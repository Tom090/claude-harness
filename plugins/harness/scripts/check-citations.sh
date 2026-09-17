#!/bin/bash
# Checks that every `§ <Heading>` citation of a rules file inside the plugin resolves to
# a real heading in that file, and that no retired role is still referenced. Cheap to
# run; run it from verify-gates and whenever rules/ headings change.
#
# Usage: check-citations.sh [plugin-root]   (defaults to the directory above this script)
# Exit 0 when clean, 1 with one line per unresolved citation or stale reference.

set -u
plugin_root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
rules_dir="$plugin_root/rules"
retired_roles="wave-lead"
status=0

[ -d "$rules_dir" ] || { echo "check-citations: no rules dir at $rules_dir" >&2; exit 1; }

# Citations may wrap across lines, so each file is flattened to one line first. A
# citation is a rules filename followed within a few words by § and the heading text,
# which runs until the first punctuation that cannot be part of a heading.
files=$(find "$plugin_root" -type f \( -name '*.md' -o -name '*.template' -o -name '*.sh' -o -name '*.json' \) \
        -not -path "$rules_dir/*" | sort)

for f in $files; do
  flat=$(tr '\n' ' ' < "$f" | tr -s ' ')
  printf '%s' "$flat" | grep -oE '[a-z-]+\.md`[^`§]{0,40}§ *[^.,;:()`—]+' | while IFS= read -r cite; do
    rules_file=$(printf '%s' "$cite" | grep -oE '^[a-z-]+\.md')
    heading=$(printf '%s' "$cite" | sed -E 's/^.*§ *//; s/ +$//')
    target="$rules_dir/$rules_file"
    if [ ! -f "$target" ]; then
      echo "UNRESOLVED ${f#$plugin_root/}: cites $rules_file, which is not in rules/"
      continue
    fi
    found=0
    while IFS= read -r h; do
      # The citation text may run past the heading into the sentence; the heading must
      # match as a whole-word prefix of it.
      case "$heading" in
        "$h"|"$h "*) found=1; break ;;
      esac
    done < <(grep -E '^#+ ' "$target" | sed -E 's/^#+ +//')
    [ "$found" -eq 1 ] || echo "UNRESOLVED ${f#$plugin_root/}: § $heading (in $rules_file)"
  done
done | tee /dev/stderr | grep -q . && status=1

for role in $retired_roles; do
  hits=$(grep -rn --include='*.md' --include='*.template' --include='*.sh' --include='*.json' \
           --exclude=check-citations.sh \
           "$role" "$plugin_root" || true)
  if [ -n "$hits" ]; then
    echo "STALE role '$role' still referenced:" >&2
    printf '%s\n' "$hits" | sed "s|$plugin_root/||" >&2
    status=1
  fi
done

[ "$status" -eq 0 ] && echo "check-citations: OK"
exit "$status"
