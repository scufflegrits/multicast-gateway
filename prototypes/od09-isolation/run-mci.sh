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
source "$here/harness.sh"
require_root
require_tools ip jq tcpdump timeout

bin=${1:-$repo/test/bin}
for tool in mcsend od09-isolation; do
    [[ -x $bin/$tool ]] || { echo "error: $bin/$tool missing; run test/build.sh first" >&2; exit 1; }
done

env_sh=$repo/test/netns/env.sh
raw=$(mktemp -d /tmp/mcgw-od09.XXXXXX)
pids=()
cleanup() {
    local rc=$?
    trap - EXIT
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    "$env_sh" down >/dev/null 2>&1 || true
    if ((rc != 0)); then echo "INVALID run; do not use for design decisions" >&2; fi
    echo "raw output: $raw" >&2
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$env_sh" down >/dev/null
"$env_sh" up >/dev/null

N=200
RECV_TIME=5s
rows=()

# Each case owns its children and checks their individual exit status.
labels=()
receiver_pids=()
capture_pid=
recv() {
    local label=$1
    shift
    ip netns exec mcgw-gw "$bin/od09-isolation" -name "$label" -duration "$RECV_TIME" \
        -ready-file "$raw/$label.ready" "$@" >"$raw/$label.json" 2>"$raw/$label.stderr" &
    local pid=$!
    pids+=("$pid")
    labels+=("$label")
    receiver_pids+=("$pid")
    wait_until 3 test -f "$raw/$label.ready" || { invalid "receiver not ready: $label"; return 1; }
}

send_count=0
send() {
    local ns=$1 file
    shift
    send_count=$((send_count + 1))
    file=$raw/send-$send_count.json
    nsx "$ns" "$bin/mcsend" -n "$N" -rate 400 -size 64 -iface s0 "$@" >"$file" || {
        invalid "sender process failed: $file"; return 1;
    }
    check_sender "$file" "$N"
}

capture() {
    local file=$1
    shift
    timeout 7 ip netns exec mcgw-gw tcpdump -lnni eth0 -vv "$@" >"$file" 2>"$file.stderr" &
    capture_pid=$!
    pids+=("$capture_pid")
    wait_until 3 grep -q 'listening on' "$file.stderr" || { invalid "capture not ready: $file"; return 1; }
}

finish_case() {
    local i
    for i in "${!labels[@]}"; do
        wait_receiver "${receiver_pids[$i]}" "$raw/${labels[$i]}.json"
    done
    if [[ -n $capture_pid ]]; then wait_capture "$capture_pid"; fi
    labels=()
    receiver_pids=()
    capture_pid=
    pids=()
}

# row CASE LABEL appends a summary row for one receiver's output
row() {
    local case=$1 label=$2 f=$raw/$2.json
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
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 239.1.1.2:3000 -from 192.168.10.20
    finish_case
    expect_accept "$raw/R1-01-$tag.json" "$N"
    expect_accept "$raw/R2-01-$tag.json" "$N"
    row T-MCI-01 "R1-01-$tag"
    row T-MCI-01 "R2-01-$tag"

    # T-MCI-02: same group on two interfaces
    recv "R1-02-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "R2-02-$tag" -group 239.1.1.1 -iface eth2 "${opts[@]}"
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src2 -to 239.1.1.1:3000 -from 192.168.11.20
    finish_case
    expect_accept "$raw/R1-02-$tag.json" "$N"
    expect_accept "$raw/R2-02-$tag.json" "$N"
    row T-MCI-02 "R1-02-$tag"
    row T-MCI-02 "R2-02-$tag"

    # T-MCI-03: unrelated host join on the same port (unrelated app uses kernel defaults)
    recv "R1-03-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-03-$tag" -group 239.9.9.9 -iface eth0 -bind wildcard -mcall default
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 239.9.9.9:3000 -from 192.168.10.20
    finish_case
    expect_accept "$raw/R1-03-$tag.json" "$N"
    expect_accept "$raw/U-03-$tag.json" "$N"
    row T-MCI-03 "U-03-$tag"
    row T-MCI-03 "R1-03-$tag"

    # T-MCI-04: wrong-interface injection (unrelated app joined the group on eth2)
    recv "R1-04-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-04-$tag" -group 239.1.1.1 -iface eth2 -bind wildcard -mcall default
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src2 -to 239.1.1.1:3000 -from 192.168.11.20
    finish_case
    expect_accept "$raw/R1-04-$tag.json" "$N"
    expect_accept "$raw/U-04-$tag.json" "$N"
    row T-MCI-04 "U-04-$tag"
    row T-MCI-04 "R1-04-$tag"

    # T-MCI-05: source-specific membership excludes other sources
    # Verify both sources in a separate window: an ASM membership during the
    # SSM capture would change the interface's aggregate IGMP source filter.
    recv "C-05-$tag" -group 232.1.1.1 -iface eth0 -bind group -mcall 0
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.21
    finish_case
    expect_accept "$raw/C-05-$tag.json" "$((2 * N))"
    row T-MCI-05-control "C-05-$tag"
    capture "$raw/igmp-05-$tag.txt" igmp
    recv "R3-05-$tag" -group 232.1.1.1 -iface eth0 -source 192.168.10.20 "${opts[@]}"
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 232.1.1.1:3000 -from 192.168.10.21
    finish_case
    expect_accept "$raw/R3-05-$tag.json" "$N"
    row T-MCI-05 "R3-05-$tag"

    # Dedicated OD-17 check: one receive socket, avoiding unicast reuse ambiguity.
    capture "$raw/unicast-$tag.txt" 'udp and dst host 192.168.10.1 and dst port 3000'
    recv "R-UC-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    send mcgw-src -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 192.168.10.1:3000 -from 192.168.10.20
    finish_case
    expect_accept "$raw/R-UC-$tag.json" "$N"
    [[ $(count_matches ' > 192\.168\.10\.1\.3000:' "$raw/unicast-$tag.txt") == "$N" ]] || {
        invalid "unicast injection not fully observed: $tag"; return 1;
    }
    local rejected=0
    [[ $bind == wildcard ]] && rejected=$N
    jq -e --argjson n "$rejected" '(.verdicts.wrong_destination // 0) == $n' "$raw/R-UC-$tag.json" >/dev/null || {
        invalid "unexpected unicast rejection count: $tag"; return 1;
    }
    row OD17-UC "R-UC-$tag"
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
igmp_v3=0
igmp_src=0
for file in "$raw"/igmp-05-*.txt; do
    matches=$(count_matches 'v3 report' "$file")
    if ((matches > 0)); then igmp_v3=$((igmp_v3 + 1)); fi
    matches=$(count_matches '232\.1\.1\.1.*192\.168\.10\.20' "$file")
    if ((matches > 0)); then igmp_src=$((igmp_src + 1)); fi
done
igmp_status=complete
if ((igmp_v3 != 4 || igmp_src != 4)); then igmp_status="MISSING — SSM wire evidence needs investigation"; fi
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
    echo "| IGMP evidence | $igmp_status |"
    echo "| Datagrams per sender | $N |"
    echo "| IGMPv3 report seen (T-MCI-05) | $igmp_v3 of 4 runs; with source 192.168.10.20: $igmp_src of 4 |"
    echo
    echo "\`foreign delivered\` counts datagrams the kernel delivered to the socket that do not"
    echo "belong to the route (other group, other interface, or other source for T-MCI-05)."
    echo "Rows are usable only with the recorded positive controls and successful sender summaries."
    echo "Zero foreign delivery with those controls supports kernel suppression for this run."
    echo "Missing IGMP evidence prevents completing the SSM wire qualification."
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

if [[ $igmp_status != complete ]]; then
    invalid "SSM wire evidence missing; report retained at $out"
fi
