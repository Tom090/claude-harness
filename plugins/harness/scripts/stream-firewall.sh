#!/bin/bash
# Default-deny egress for a stream container. Adapted from anthropics/claude-code
# .devcontainer/init-firewall.sh: keeps Docker's embedded DNS, allows GitHub's published
# ranges plus the hosts Claude Code needs (code.claude.com/docs/en/network-config), and
# rejects everything else. Runs as root via the single sudoers line the image grants.
#
# $1 (optional): space-separated extra hostnames to allow (a project whose setup command
# pulls from elsewhere, e.g. a private registry); the entrypoint passes STREAM_EXTRA_EGRESS.
set -euo pipefail
EXTRA="${1:-}"
IFS=$'\n\t'

DOCKER_DNS_RULES=$(iptables-save -t nat 2>/dev/null | grep "127\.0\.0\.11" || true)

iptables -F; iptables -X
iptables -t nat -F; iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --max-time 20 https://api.github.com/meta)
if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: could not fetch GitHub IP ranges"; exit 1
fi
while read -r cidr; do
    [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] || { echo "ERROR: bad CIDR $cidr"; exit 1; }
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

domains="api.anthropic.com claude.ai platform.claude.com registry.npmjs.org $EXTRA"
for domain in $(printf '%s' "$domains" | tr ' ' '\n' | grep -v '^$'); do
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    [ -n "$ips" ] || { echo "ERROR: failed to resolve $domain"; exit 1; }
    while read -r ip; do
        [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { echo "ERROR: bad IP $ip for $domain"; exit 1; }
        ipset add allowed-domains "$ip" 2>/dev/null || true
        echo "allow $domain $ip"
    done < <(echo "$ips")
done

HOST_IP=$(ip route | grep default | cut -d" " -f3)
[ -n "$HOST_IP" ] || { echo "ERROR: no default route"; exit 1; }
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

if curl --connect-timeout 5 -s https://example.com >/dev/null 2>&1; then
    echo "ERROR: firewall verification failed: example.com reachable"; exit 1
fi
if ! curl --connect-timeout 5 -s https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: firewall verification failed: api.github.com unreachable"; exit 1
fi
echo "Firewall active: GitHub, Anthropic, npm registry${EXTRA:+, $EXTRA}; everything else rejected"
