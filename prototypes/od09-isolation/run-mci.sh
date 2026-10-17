#!/usr/bin/env bash
# Run test-plan cases T-MCI-01..05 (IPv4) against the OD-09 prototype for each
# isolation option set, and write a results summary for OD-09.
#
# Usage: sudo prototypes/od09-isolation/run-mci.sh [BIN_DIR]
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=../../test/netns/lib.sh
source "$repo/test/netns/lib.sh"
require_root
require_tools ip jq tcpdump timeout

bin=${1:-$repo/test/bin}
for tool in mcsend od09-isolation; do
    [[ -x $bin/$tool ]] || { echo "error: $bin/$tool missing; run test/build.sh first" >&2; exit 1; }
done

env_sh=$repo/test/netns/env.sh
raw=$(mktemp -d /tmp/mcgw-od09.XXXXXX)
trap '"$env_sh" down >/dev/null 2>&1 || true' EXIT
"$env_sh" down >/dev/null
"$env_sh" up >/dev/null

N=200
RECV_TIME=5s
rows=()

# recv LABEL ARGS... starts a prototype receiver in GW, output to $raw/LABEL.json
recv() {
    local label=$1
    shift
    nsx mcgw-gw "$bin/od09-isolation" -name "$label" -duration "$RECV_TIME" "$@" >"$raw/$label.json" &
}

# send NS ARGS... sends N datagrams with mcsend inside NS
send() {
    local ns=$1
    shift
    nsx "$ns" "$bin/mcsend" -n "$N" -rate 400 -size 64 -iface s0 "$@" >>"$raw/send.log"
}

# row CASE LABEL appends a summary row for one receiver's output
row() {
    local case=$1 label=$2 f=$raw/$2.json
    [[ -s $f ]] || { rows+=("| $case | $label | error: no output | | | | | |"); return; }
    rows+=("$(jq -r --arg c "$case" '
        "| \($c) | \(.name) | \(.options.bind) | \(.options.mcall) | \(.received) | \(.verdicts.accept // 0) | \(.foreign_delivered) | " +
        ([.verdicts | to_entries[] | select(.key != "accept") | "\(.key)=\(.value)"] | join(", ")) + " |"
    ' "$f")")
}

run_case() {
    local bind=$1 mcall=$2 tag="${1}-${2}"
    local opts=(-bind "$bind" -mcall "$mcall")

    # T-MCI-01: same port, different groups
    recv "R1-01-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "R2-01-$tag" -group 239.1.1.2 -iface eth0 "${opts[@]}"
    sleep 1
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 239.1.1.2:3000 -from 192.168.10.20
    wait
    row T-MCI-01 "R1-01-$tag"
    row T-MCI-01 "R2-01-$tag"

    # T-MCI-02: same group on two interfaces
    recv "R1-02-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "R2-02-$tag" -group 239.1.1.1 -iface eth2 "${opts[@]}"
    sleep 1
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src2 -to 239.1.1.1:3000 -from 192.168.11.20
    wait
    row T-MCI-02 "R1-02-$tag"
    row T-MCI-02 "R2-02-$tag"

    # T-MCI-03: unrelated host join on the same port (unrelated app uses kernel defaults)
    recv "R1-03-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-03-$tag" -group 239.9.9.9 -iface eth0 -bind wildcard -mcall default
    sleep 1
    send mcgw-src -to 239.9.9.9:3000 -from 192.168.10.20
    wait
    row T-MCI-03 "R1-03-$tag"

    # T-MCI-04: wrong-interface injection (unrelated app joined the group on eth2)
    recv "R1-04-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-04-$tag" -group 239.1.1.1 -iface eth2 -bind wildcard -mcall default
    sleep 1
    send mcgw-src2 -to 239.1.1.1:3000 -from 192.168.11.20
    wait
    row T-MCI-04 "R1-04-$tag"

    # T-MCI-05: source-specific membership excludes other sources
    timeout 6 ip netns exec mcgw-gw tcpdump -lni eth0 -vv igmp >"$raw/igmp-05-$tag.txt" 2>&1 &
    recv "R3-05-$tag" -group 232.1.1.1 -iface eth0 -source 192.168.10.20 "${opts[@]}"
    sleep 1
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.21
    wait
    row T-MCI-05 "R3-05-$tag"
}

for bind in group wildcard; do
    for mcall in default 0; do
        echo "running bind=$bind mcall=$mcall"
        run_case "$bind" "$mcall"
    done
done

. /etc/os-release
kernel=$(uname -r)
out=$here/results/$(date +%F)-${ID}${VERSION_ID:-}-${kernel}.md
igmp_v3=$(grep -l 'v3 report' "$raw"/igmp-05-*.txt 2>/dev/null | wc -l)
igmp_src=$(grep -l '232.1.1.1.*192.168.10.20' "$raw"/igmp-05-*.txt 2>/dev/null | wc -l)
{
    echo "# OD-09 isolation run — $PRETTY_NAME, kernel $kernel"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Date | $(date -u +'%F %H:%M UTC') |"
    echo "| OS | $PRETTY_NAME |"
    echo "| Kernel | $kernel |"
    echo "| iproute2 | $(ip -V | head -1) |"
    echo "| Prototype Go | $(jq -r '.go' "$raw"/R1-01-group-default.json 2>/dev/null) |"
    echo "| Repository commit | $(git -c safe.directory="$repo" -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown) |"
    echo "| Datagrams per sender | $N |"
    echo "| IGMPv3 report seen (T-MCI-05) | $igmp_v3 of 4 runs; with source 192.168.10.20: $igmp_src of 4 |"
    echo
    echo "\`foreign delivered\` counts datagrams the kernel delivered to the socket that do not"
    echo "belong to the route (other group, other interface, or other source for T-MCI-05)."
    echo "Zero means the kernel suppressed them; otherwise the per-datagram checks rejected them."
    echo
    echo "| Case | Receiver | Bind | IP_MULTICAST_ALL | Received | Accepted | Foreign delivered | Rejections |"
    echo "|---|---|---|---|---|---|---|---|"
    printf '%s\n' "${rows[@]}"
    echo
    echo "## Interpretation"
    echo
    echo "To be completed by the reviewer: which option set prevents cross-delivery in the kernel,"
    echo "and whether the per-datagram checks caught everything else. Record the outcome in OD-09."
} >"$out"
if [[ -n ${SUDO_USER:-} ]]; then
    chown "$SUDO_USER": "$out"
fi
echo "results: $out"
echo "raw output: $raw"
