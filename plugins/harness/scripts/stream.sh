#!/bin/bash
# Host half of a harness work stream: one Docker container per GitHub issue, running a
# headless stream lead (claude -p) with the full harness inside. The container's only
# channels back are the PR and the bind-mounted run dir (result.json, status).
#
#   stream.sh build                       build the image for this project (once per CLI/plugin version)
#   stream.sh launch --issue N --slug s [--budget USD] [--max-turns N] [--model m] [--effort e]
#                    [--brief path] [--relaunch]
#   stream.sh status                      every stream's status, container state and PR
#   stream.sh collect <id> [--wait]       print result.json; --wait blocks until the run ends
#   stream.sh followup <id> "<message>"   resume the stream's session with a new message
#   stream.sh stop <id>                   SIGINT (ends the run, result recorded), then docker stop after the grace period
#   stream.sh prune                       remove containers whose PR is merged or closed; keep the rest
#
# Config comes from the project's .claude/harness.env (STREAM_* keys, read literally,
# never sourced; see templates/harness.env.example). Secrets come from two 0600 files
# outside the repo, passed with --env-file:
#   ~/.config/claude-harness/containers.env            CLAUDE_CODE_OAUTH_TOKEN (claude setup-token)
#   ~/.config/<PROJECT_NAME>-harness/containers.env    GH_TOKEN (fine-grained PAT on this one repo)
# A run dir is <STREAM_RUNS_DIR>/<issue>-<slug>/ under the project; <id> is <issue>-<slug>.
set -u

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd -P)}"
cd "$PROJECT_DIR" || exit 2
[ -f .claude/harness.env ] || { echo "stream: no .claude/harness.env in $PROJECT_DIR (run /harness:harness-init)" >&2; exit 2; }

die() { echo "stream: $*" >&2; exit 1; }

# --- Read config literally; never `source` a repo-controlled file (same reader as the hooks) ---
harness_env_value() {
  local key="$1" line val=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    while [ "${line# }" != "$line" ] || [ "${line#$'\t'}" != "$line" ]; do
      line="${line# }"; line="${line#$'\t'}"
    done
    case "$line" in "$key="*) ;; *) continue ;; esac
    val="${line#$key=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
  done < .claude/harness.env
  printf '%s' "$val"
}
cfg() { local v; v="$(harness_env_value "$1")"; printf '%s' "${v:-${2:-}}"; }

PROJECT_NAME=$(cfg PROJECT_NAME "$(basename "$PROJECT_DIR")")
RUNS_DIR=$(cfg STREAM_RUNS_DIR ".claude/streams")
REPO=$(cfg STREAM_REPO "")
BASE_IMAGE=$(cfg STREAM_BASE_IMAGE "node:20")
CLI_VERSION=$(cfg STREAM_CLAUDE_VERSION "latest")   # a pin is for reproducing a problem, not the default
default_setup=""; [ -f package-lock.json ] && default_setup="npm ci"
SETUP_COMMAND=$(cfg STREAM_SETUP_COMMAND "$default_setup")
MAX_CONCURRENT=$(cfg STREAM_MAX_CONCURRENT 3)
MEMORY=$(cfg STREAM_MEMORY 6g)
CPUS=$(cfg STREAM_CPUS 3)
BUDGET=$(cfg STREAM_MAX_BUDGET_USD "")
MAX_TURNS=$(cfg STREAM_MAX_TURNS "")
MODEL=$(cfg STREAM_MODEL "opus")   # a stream lead is a judgment role: strongest model by default
EFFORT=$(cfg STREAM_EFFORT "")
STOP_GRACE=$(cfg STREAM_STOP_GRACE_SECS 300)
FIREWALL=$(cfg STREAM_FIREWALL 1)
EXTRA_EGRESS=$(cfg STREAM_EXTRA_EGRESS "")
MCP_CONFIG=$(cfg STREAM_MCP_CONFIG "")
COLLECT_TIMEOUT=$(cfg STREAM_COLLECT_TIMEOUT_SECS 28800)

IMAGE="harness-stream:${PROJECT_NAME}"   # one tag per project; `build` replaces it, `status` shows its CLI version
SHARED_ENV="$HOME/.config/claude-harness/containers.env"
PROJECT_ENV="$HOME/.config/${PROJECT_NAME}-harness/containers.env"

cname() { printf 'hs-%s-%s' "$PROJECT_NAME" "$1"; }
rundir() { printf '%s/%s/%s' "$PROJECT_DIR" "$RUNS_DIR" "$1"; }
read_status() { cut -d' ' -f1 "$(rundir "$1")/status" 2>/dev/null; }
is_active() { case "$(read_status "$1")" in launched|running|followup) return 0 ;; esac; return 1; }
container_state() { docker inspect -f '{{.State.Status}}' "$(cname "$1")" 2>/dev/null || printf -- '-'; }
list_ids() { [ -d "$PROJECT_DIR/$RUNS_DIR" ] || return 0; ls -1 "$PROJECT_DIR/$RUNS_DIR" 2>/dev/null | grep -E '^[0-9]+-[a-z0-9-]+$' | sort -n; }
active_count() { local n=0 id; for id in $(list_ids); do is_active "$id" && n=$((n+1)); done; printf '%s' "$n"; }
docker_up() { docker info >/dev/null 2>&1 || die "Docker is not running (open -a Docker, then retry)"; }

check_env_file() {   # <file> <required key>
  local f="$1" key="$2" mode
  [ -f "$f" ] || die "missing $f (must contain $key=...; see templates/harness.env.example § STREAM_)"
  mode=$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f" 2>/dev/null)
  case "$mode" in 600|400) ;; *) die "$f must be mode 0600 (is $mode)" ;; esac
  grep -q "^${key}=" "$f" || die "$f has no ${key}= line"
  grep -q "^ANTHROPIC_API_KEY=" "$f" && die "$f sets ANTHROPIC_API_KEY; it would override the OAuth token in -p mode. Remove it."
  return 0
}

image_cli() { docker run --rm --entrypoint cat "$IMAGE" /opt/claude-harness/.cli-version 2>/dev/null || printf -- '-'; }

cmd_build() {
  docker_up
  echo "stream: building $IMAGE from $BASE_IMAGE with Claude Code $CLI_VERSION (context: $PLUGIN)"
  docker build --pull -f "$PLUGIN/templates/docker/Dockerfile.stream" \
    --build-arg "NODE_IMAGE=$BASE_IMAGE" --build-arg "CLAUDE_CODE_VERSION=$CLI_VERSION" \
    -t "$IMAGE" "$PLUGIN" || die "build failed"
  echo "stream: built $IMAGE with Claude Code $(image_cli). Rebuild whenever you want a newer CLI or plugin inside streams."
}

cmd_launch() {
  local issue="" slug="" brief="" relaunch=0 budget="$BUDGET" max_turns="$MAX_TURNS" model="$MODEL" effort="$EFFORT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --slug) slug="$2"; shift 2 ;;
      --brief) brief="$2"; shift 2 ;;
      --budget) budget="$2"; shift 2 ;;
      --max-turns) max_turns="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --effort) effort="$2"; shift 2 ;;
      --relaunch) relaunch=1; shift ;;
      *) die "launch: unknown argument $1" ;;
    esac
  done
  [[ "$issue" =~ ^[0-9]+$ ]] || die "launch: --issue must be a number"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "launch: --slug must be lowercase [a-z0-9-]"
  local id="$issue-$slug" branch="feat/$issue-$slug" dir name
  dir="$(rundir "$id")"; name="$(cname "$id")"

  docker_up
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image $IMAGE not built; run: stream.sh build"
  check_env_file "$SHARED_ENV" CLAUDE_CODE_OAUTH_TOKEN
  check_env_file "$PROJECT_ENV" GH_TOKEN
  [ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  [ -n "$REPO" ] || die "STREAM_REPO unset and gh cannot tell the repo; set STREAM_REPO=\"owner/name\" in harness.env"

  local n; n=$(active_count)
  [ "$n" -lt "$MAX_CONCURRENT" ] || die "$n streams active; STREAM_MAX_CONCURRENT=$MAX_CONCURRENT. Collect or stop one first."
  is_active "$id" && die "stream $id is already $(read_status "$id")"
  if docker container inspect "$name" >/dev/null 2>&1; then
    if [ "$relaunch" -eq 1 ]; then   # not active (checked above): idle after done/failed, or exited
      docker rm -f "$name" >/dev/null && echo "stream: removed container $name ($(read_status "$id"))"
    else
      die "container $name exists ($(container_state "$id"); status: $(read_status "$id")). stream.sh prune after its PR merges, or pass --relaunch to archive the run and replace it."
    fi
  fi
  if [ -f "$dir/result.json" ] || [ -f "$dir/stream.jsonl" ]; then
    [ "$relaunch" -eq 1 ] || die "stream $id has a previous run in $dir; pass --relaunch to archive it and start again"
    local arch="$dir/attempt-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$arch"
    for f in stream.jsonl result.json status session token container prompt.md followup.md setup.log firewall.log entrypoint.log stderr.log owner-questions.md; do
      [ -e "$dir/$f" ] && mv "$dir/$f" "$arch/"
    done
    echo "stream: archived previous run to $arch"
  fi
  mkdir -p "$dir"
  if [ -n "$brief" ]; then cp "$brief" "$dir/brief.md" || die "cannot read brief $brief"; fi
  [ -s "$dir/brief.md" ] || die "no brief: write $dir/brief.md (or pass --brief path)"

  local open_pr; open_pr=$(gh pr list --state open --head "$branch" --json number -q '.[].number' 2>/dev/null)
  [ -z "$open_pr" ] || die "PR #$open_pr is already open on $branch"
  local istate; istate=$(gh issue view "$issue" --json state -q .state 2>/dev/null)
  [ "$istate" = "OPEN" ] || die "issue #$issue is not open (state: ${istate:-unknown}); issues are the queue"

  local session token
  session=$(uuidgen | tr 'A-Z' 'a-z')
  token=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8)
  local gname gemail; gname=$(git config user.name); gemail=$(git config user.email)

  local envs=(
    -e "STREAM_ID=$id" -e "STREAM_ISSUE=$issue" -e "STREAM_SLUG=$slug" -e "STREAM_BRANCH=$branch"
    -e "STREAM_REPO=$REPO" -e "STREAM_SESSION_ID=$session" -e "STREAM_TOKEN=$token"
    -e "STREAM_SETUP_COMMAND=$SETUP_COMMAND" -e "STREAM_MAX_BUDGET_USD=$budget" -e "STREAM_MAX_TURNS=$max_turns"
    -e "STREAM_MODEL=$model" -e "STREAM_EFFORT=$effort" -e "STREAM_FIREWALL=$FIREWALL"
    -e "STREAM_EXTRA_EGRESS=$EXTRA_EGRESS" -e "STREAM_MCP_CONFIG=$MCP_CONFIG"
    -e "GIT_AUTHOR_NAME=$gname" -e "GIT_AUTHOR_EMAIL=$gemail" -e "GIT_COMMITTER_NAME=$gname" -e "GIT_COMMITTER_EMAIL=$gemail"
  )
  printf 'launched\n' > "$dir/status"
  printf '%s\n' "$session" > "$dir/session"
  printf '%s\n' "$token" > "$dir/token"
  printf '%s\n' "$name" > "$dir/container"
  date -u +%FT%TZ > "$dir/launched_at"
  rm -f "$dir/result.json"

  if ! docker run -d --init --name "$name" \
      --label "claude-harness.project=$PROJECT_NAME" --label "claude-harness.stream=$id" --label "claude-harness.issue=$issue" \
      --memory "$MEMORY" --cpus "$CPUS" --cap-add NET_ADMIN --cap-add NET_RAW \
      --env-file "$SHARED_ENV" --env-file "$PROJECT_ENV" "${envs[@]}" \
      -v "$dir:/run/stream" -v harness-npm-cache:/home/node/.npm \
      "$IMAGE" >/dev/null; then
    printf 'failed launch\n' > "$dir/status"; die "docker run failed"
  fi
  cat <<EOT
stream: launched $id
  container  $name
  session    $session
  token      $token
  run dir    $dir
  branch     $branch on $REPO
Next: background  bash $PLUGIN/scripts/stream.sh collect $id --wait
      background  bash $PLUGIN/scripts/wave-watchdog.sh $dir/stream.jsonl
EOT
}

cmd_status() {
  local id st cs rs pr
  printf '%-28s %-16s %-10s %-12s %s\n' ID STATUS CONTAINER STATE PR
  for id in $(list_ids); do
    st=$(cat "$(rundir "$id")/status" 2>/dev/null || echo '-')
    cs=$(container_state "$id")
    rs=$(jq -r '.state // "-"' "$(rundir "$id")/result.json" 2>/dev/null || echo '-')
    pr=$(jq -r '.pr_url // "-"' "$(rundir "$id")/result.json" 2>/dev/null || echo '-')
    printf '%-28s %-16s %-10s %-12s %s\n' "$id" "$st" "$cs" "$rs" "$pr"
  done
  echo "active: $(active_count)/$MAX_CONCURRENT  image: $IMAGE (Claude Code $(image_cli); host $(claude --version 2>/dev/null | awk '{print $1}'))"
}

cmd_collect() {
  local id="${1:-}" wait=0; [ -n "$id" ] || die "collect: <id> required"
  [ "${2:-}" = "--wait" ] && wait=1
  local dir; dir="$(rundir "$id")"; [ -d "$dir" ] || die "no run dir $dir"
  local waited=0
  while is_active "$id"; do
    [ "$wait" -eq 1 ] || { echo "stream $id is $(read_status "$id") (container $(container_state "$id")); pass --wait to block"; return 7; }
    [ "$(container_state "$id")" = "running" ] || { echo "stream $id: container $(container_state "$id") while status says $(read_status "$id")" >&2; printf 'failed container-gone\n' > "$dir/status"; break; }
    [ "$waited" -lt "$COLLECT_TIMEOUT" ] || { echo "stream $id: still $(read_status "$id") after ${COLLECT_TIMEOUT}s; use stream.sh stop or wait again" >&2; return 5; }
    sleep 30; waited=$((waited+30))
  done
  local st; st=$(read_status "$id")
  echo "stream $id: status $(cat "$dir/status" 2>/dev/null)"
  if [ -f "$dir/result.json" ]; then
    jq . "$dir/result.json"
    local tok rtok; tok=$(cat "$dir/token" 2>/dev/null); rtok=$(jq -r '.token // ""' "$dir/result.json")
    if [ "$st" = "done" ] && [ -n "$tok" ] && [ "$rtok" != "$tok" ]; then
      echo "WARNING: result token '$rtok' does not match the brief's token '$tok'; treat as unverified" >&2
      return 6
    fi
  else
    echo "no result.json (see $dir/entrypoint.log, stderr.log)" >&2
  fi
  case "$st" in
    done) case "$(jq -r '.state // ""' "$dir/result.json" 2>/dev/null)" in
            done) return 0 ;; needs_owner) echo "owner questions: $dir/owner-questions.md"; return 3 ;; blocked) return 4 ;; *) return 1 ;;
          esac ;;
    stopped) return 2 ;;
    *) echo "postmortem transcript: docker cp $(cname "$id"):/home/node/.claude/projects/-workspace/$(cat "$dir/session" 2>/dev/null).jsonl $dir/transcript.jsonl" >&2; return 1 ;;
  esac
}

cmd_followup() {
  local id="${1:-}" text="${2:-}"
  [ -n "$id" ] && [ -n "$text" ] || die "followup: <id> \"<message>\" required"
  local dir name; dir="$(rundir "$id")"; name="$(cname "$id")"
  [ "$(container_state "$id")" = "running" ] || die "container $name is $(container_state "$id"); a stopped stream cannot be resumed (launch --relaunch)"
  is_active "$id" && die "stream $id is still $(read_status "$id")"
  printf 'followup\n' > "$dir/status"
  docker exec -d -u node "$name" /opt/claude-harness/scripts/stream-entrypoint.sh followup "$text" || die "docker exec failed"
  echo "stream: follow-up sent to $id; collect with: stream.sh collect $id --wait"
}

cmd_stop() {
  local id="${1:-}"; [ -n "$id" ] || die "stop: <id> required"
  local name dir; name="$(cname "$id")"; dir="$(rundir "$id")"
  [ "$(container_state "$id")" = "running" ] || { echo "stream $id: container $(container_state "$id"); nothing to stop"; return 0; }
  if ! is_active "$id"; then echo "stream $id is $(read_status "$id"); container left idling for follow-ups (prune removes it after merge)"; return 0; fi
  echo "stream: sending SIGINT to $id (ends the run within seconds; the result event records the interruption); grace ${STOP_GRACE}s"
  : > "$dir/interrupted"
  if ! docker exec "$name" bash -c '[ -f /run/stream/claude.pid ] && kill -INT "$(cat /run/stream/claude.pid)"' 2>/dev/null; then
    docker kill -s INT "$name" >/dev/null 2>&1 || true
  fi
  local waited=0
  while is_active "$id" && [ "$waited" -lt "$STOP_GRACE" ]; do sleep 5; waited=$((waited+5)); done
  if is_active "$id"; then
    echo "stream: still running after ${STOP_GRACE}s; docker stop (SIGTERM drops the turn)"
    docker stop -t 20 "$name" >/dev/null 2>&1 || true
    sleep 2
    is_active "$id" && printf 'stopped killed\n' > "$dir/status"
  fi
  echo "stream $id: status $(cat "$dir/status" 2>/dev/null); container $(container_state "$id")"
}

cmd_prune() {
  docker_up
  local id name pr state removed=0
  for id in $(list_ids); do
    name="$(cname "$id")"
    docker container inspect "$name" >/dev/null 2>&1 || continue
    if is_active "$id"; then echo "keep   $id: $(read_status "$id")"; continue; fi
    pr=$(jq -r '.pr_url // ""' "$(rundir "$id")/result.json" 2>/dev/null)
    if [ -z "$pr" ]; then echo "keep   $id: no PR recorded (remove by hand: docker rm -f $name)"; continue; fi
    state=$(gh pr view "$pr" --json state -q .state 2>/dev/null)
    case "$state" in
      MERGED|CLOSED) docker rm -f "$name" >/dev/null && { echo "pruned $id: PR $state ($pr); run dir kept"; removed=$((removed+1)); } ;;
      *) echo "keep   $id: PR ${state:-unknown} ($pr)" ;;
    esac
  done
  echo "pruned $removed container(s)"
}

case "${1:-help}" in
  build) shift; cmd_build "$@" ;;
  launch) shift; cmd_launch "$@" ;;
  status) shift; cmd_status "$@" ;;
  collect) shift; cmd_collect "$@" ;;
  followup) shift; cmd_followup "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  prune) shift; cmd_prune "$@" ;;
  help|-h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand $1 (build|launch|status|collect|followup|stop|prune)" ;;
esac
