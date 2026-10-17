#!/usr/bin/env bash
# Run the OD-09 socket-isolation experiment: test-plan cases T-MCI-01..05, an
# overlapping-membership variant (T-MCI-05b) and the OD-17 unicast/broadcast/
# local-origin checks, once per isolation option set, and write a report.
#
# Usage: sudo prototypes/od09-isolation/run-mci.sh [BIN_DIR]
#   BIN_DIR defaults to test/bin. Pass another directory (for example one under
#   /usr/local) where SELinux or a noexec /home blocks running test/bin.
#
# Outcomes (see README.md "Run outcomes"):
#   exit 0  VALID   every validity check passed and every cell matched its prediction
#   exit 3  REVIEW  the run is valid but a prediction or evidence check differed;
#                   the report is kept and lists the reasons; review before use
#   other   INVALID a process, summary, positive control or capture check failed;
#                   do not use the run (raw output is kept for investigation)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=../../test/netns/lib.sh
source "$repo/test/netns/lib.sh"
# shellcheck source=harness.sh
source "$here/harness.sh"
require_root
require_tools ip jq tcpdump timeout install git

bin=${1:-$repo/test/bin}
for tool in mcsend od09-isolation; do
    [[ -x $bin/$tool ]] || { echo "error: $bin/$tool missing; run test/build.sh first" >&2; exit 1; }
done

env_sh=$repo/test/netns/env.sh
raw=$(mktemp -d /tmp/mcgw-od09.XXXXXX)
pids=()

# forget_pid PID removes a reaped child so cleanup never signals a reused PID.
forget_pid() {
    local keep=() p
    for p in "${pids[@]}"; do [[ $p == "$1" ]] || keep+=("$p"); done
    pids=("${keep[@]}")
}

cleanup() {
    local rc=$?
    trap - EXIT
    trap '' INT TERM # a second Ctrl-C must not cut cleanup short and leave namespaces
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    "$env_sh" down >/dev/null 2>&1 || true
    # Let the invoking user read the raw evidence without sudo.
    if [[ -n ${SUDO_USER:-} ]]; then chown -R "$SUDO_USER": "$raw" 2>/dev/null || true; fi
    case $rc in
        0) echo "VALID run" >&2 ;;
        3) echo "REVIEW: run is valid but needs review before use; see 'Run status' in the report" >&2 ;;
        *) echo "INVALID run; do not use for design decisions" >&2 ;;
    esac
    echo "raw output: $raw (copy anything you need before reboot; /tmp is cleaned)" >&2
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The runner always starts from a clean environment: any existing mcgw-
# namespaces (for example from a manual 'env.sh up') are removed first.
"$env_sh" down >/dev/null
"$env_sh" up >/dev/null
gw_sysctls=$(nsx mcgw-gw sysctl -n net.ipv4.conf.all.rp_filter net.ipv4.conf.eth0.rp_filter \
    net.ipv4.conf.eth0.force_igmp_version | paste -sd/)

N=200          # datagrams per sender; filtering is deterministic, so volume only needs to be exact
RECV_TIME=8s   # receive window; covers readiness waits plus up to five 0.5 s sends
rows=()
mismatches=()
igmp_join_runs=0

# Each case owns its children and checks their individual exit status.
labels=()
receiver_pids=()
capture_pids=()

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

# send NS MCSEND-ARGS... sends N datagrams; the timeout bounds a stuck sender.
send_count=0
send() {
    local ns=$1 file
    shift
    send_count=$((send_count + 1))
    file=$raw/send-$send_count.json
    nsx "$ns" timeout 15 "$bin/mcsend" -n "$N" -rate 400 -size 64 "$@" \
        >"$file" 2>"$file.stderr" || { invalid "sender process failed: $file"; return 1; }
    check_sender "$file" "$N"
}

# capture IFACE FILE FILTER starts tcpdump in GW. --immediate-mode writes each
# packet at once, so stopping the capture after the traffic loses nothing.
capture() {
    local iface=$1 file=$2 filter=$3
    timeout 60 ip netns exec mcgw-gw tcpdump -l -nn --immediate-mode -i "$iface" -vv "$filter" \
        >"$file" 2>"$file.stderr" &
    local pid=$!
    pids+=("$pid")
    capture_pids+=("$pid")
    wait_until 3 grep -q 'listening on' "$file.stderr" || { invalid "capture not ready: $file"; return 1; }
}

stop_captures() {
    local pid
    ((${#capture_pids[@]})) || return 0
    sleep 0.5 # let the last packets of the window arrive
    for pid in "${capture_pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for pid in "${capture_pids[@]}"; do
        wait_capture "$pid"
        forget_pid "$pid"
    done
    capture_pids=()
}

finish_case() {
    local i
    for i in "${!labels[@]}"; do
        wait_receiver "${receiver_pids[$i]}" "$raw/${labels[$i]}.json"
        forget_pid "${receiver_pids[$i]}"
    done
    stop_captures
    labels=()
    receiver_pids=()
}

# result CASE LABEL PREDICTED adds a report row and compares the receiver's
# foreign delivery with the kernel-semantics prediction (README "Predictions").
result() {
    local case=$1 label=$2 predicted=$3 f=$raw/$2.json match=yes
    if ! foreign_matches "$f" "$predicted"; then
        match=NO
        mismatches+=("$case $label: foreign delivery $(jq .foreign_delivered "$f"), predicted $predicted")
    fi
    if ! mcall_matches "$f"; then
        match=NO
        mismatches+=("$case $label: effective IP_MULTICAST_ALL differs from the requested setting")
    fi
    rows+=("$(row_text "$case" "$f" "$predicted" "$match")")
}

run_case() {
    local bind=$1 mcall=$2 tag="${1}-${2}"
    local opts=(-bind "$bind" -mcall "$mcall")
    # Predicted leaks (kernel __udp_is_mcast_sock): with IP_MULTICAST_ALL=1 a socket
    # receives a group arriving on an interface where another socket joined it,
    # whatever the bind; a wildcard socket also receives other groups on the port.
    # IP_MULTICAST_ALL=0 limits delivery to the socket's own (group, interface).
    local leak_iface=0 leak_group=0
    [[ $mcall == default ]] && leak_iface=$N
    [[ $mcall == default && $bind == wildcard ]] && leak_group=$N

    # T-MCI-01: same port, different groups
    recv "R1-01-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "R2-01-$tag" -group 239.1.1.2 -iface eth0 "${opts[@]}"
    send mcgw-src -iface s0 -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -iface s0 -to 239.1.1.2:3000 -from 192.168.10.20
    finish_case
    expect_accept "$raw/R1-01-$tag.json" "$N"
    expect_accept "$raw/R2-01-$tag.json" "$N"
    result T-MCI-01 "R1-01-$tag" "$leak_group"
    result T-MCI-01 "R2-01-$tag" "$leak_group"

    # T-MCI-02: same group on two interfaces
    recv "R1-02-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "R2-02-$tag" -group 239.1.1.1 -iface eth2 "${opts[@]}"
    send mcgw-src -iface s0 -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src2 -iface s0 -to 239.1.1.1:3000 -from 192.168.11.20
    finish_case
    expect_accept "$raw/R1-02-$tag.json" "$N"
    expect_accept "$raw/R2-02-$tag.json" "$N"
    result T-MCI-02 "R1-02-$tag" "$leak_iface"
    result T-MCI-02 "R2-02-$tag" "$leak_iface"

    # T-MCI-03: unrelated host join on the same port. The unrelated receiver U
    # always uses kernel defaults and a wildcard bind, like a naive application,
    # so it also receives R1's group (its own foreign delivery is always N).
    recv "R1-03-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-03-$tag" -group 239.9.9.9 -iface eth0 -bind wildcard -mcall default
    send mcgw-src -iface s0 -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -iface s0 -to 239.9.9.9:3000 -from 192.168.10.20
    finish_case
    expect_accept "$raw/R1-03-$tag.json" "$N"
    expect_accept "$raw/U-03-$tag.json" "$N"
    result T-MCI-03 "U-03-$tag" "$N"
    result T-MCI-03 "R1-03-$tag" "$leak_group"

    # T-MCI-04: wrong-interface injection (unrelated receiver joined the group on eth2)
    recv "R1-04-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    recv "U-04-$tag" -group 239.1.1.1 -iface eth2 -bind wildcard -mcall default
    send mcgw-src -iface s0 -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src2 -iface s0 -to 239.1.1.1:3000 -from 192.168.11.20
    finish_case
    expect_accept "$raw/R1-04-$tag.json" "$N"
    expect_accept "$raw/U-04-$tag.json" "$N"
    result T-MCI-04 "U-04-$tag" "$N"
    result T-MCI-04 "R1-04-$tag" "$leak_iface"

    # T-MCI-05 control: an any-source receiver proves both sources reach 232.1.1.1.
    recv "C-05-$tag" -group 232.1.1.1 -iface eth0 -bind group -mcall 0
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.21
    finish_case
    expect_accept "$raw/C-05-$tag.json" "$((2 * N))"
    result T-MCI-05-control "C-05-$tag" 0

    # T-MCI-05: source-specific membership alone. The interface filter becomes
    # INCLUDE{.20}, so .21 is dropped before any socket. The IGMP capture runs only
    # across the join and the traffic and stops before the receiver closes, so the
    # leave report (BLOCK) is not in the evidence.
    capture eth0 "$raw/igmp-05-$tag.txt" igmp
    recv "R3-05-$tag" -group 232.1.1.1 -iface eth0 -source 192.168.10.20 "${opts[@]}"
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.21
    stop_captures
    finish_case
    expect_accept "$raw/R3-05-$tag.json" "$N"
    result T-MCI-05 "R3-05-$tag" 0
    if (($(count_matches "$IGMP_JOIN_RE" "$raw/igmp-05-$tag.txt") > 0)); then
        igmp_join_runs=$((igmp_join_runs + 1))
    fi

    # T-MCI-05b: the same source-specific receiver while an unrelated any-source
    # member exists. The interface filter is then EXCLUDE{}, so .21 reaches the
    # host and only the socket's own source filter can keep it out.
    recv "R3-05b-$tag" -group 232.1.1.1 -iface eth0 -source 192.168.10.20 "${opts[@]}"
    recv "U-05b-$tag" -group 232.1.1.1 -iface eth0 -bind wildcard -mcall default
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -iface s0 -to 232.1.1.1:3000 -from 192.168.10.21
    finish_case
    expect_accept "$raw/R3-05b-$tag.json" "$N"
    expect_accept "$raw/U-05b-$tag.json" "$((2 * N))"
    result T-MCI-05b "R3-05b-$tag" 0
    result T-MCI-05b "U-05b-$tag" 0

    # OD-17: one receive socket (unicast goes to only one SO_REUSEADDR socket).
    # External unicast and broadcast arrive on eth0; local-origin unicast (a sink on
    # the gateway sending to its own address or loopback) arrives on lo. A wildcard
    # socket is predicted to receive all four (destination or ingress mismatch); a
    # group-bound socket none. Captures prove the traffic reached the gateway.
    capture eth0 "$raw/od17-eth0-$tag.txt" \
        'udp and dst port 3000 and (dst host 192.168.10.1 or dst host 192.168.10.255)'
    capture lo "$raw/od17-lo-$tag.txt" 'udp and dst port 3000'
    recv "R-OD17-$tag" -group 239.1.1.1 -iface eth0 "${opts[@]}"
    send mcgw-src -iface s0 -to 239.1.1.1:3000 -from 192.168.10.20
    send mcgw-src -to 192.168.10.1:3000 -from 192.168.10.20
    send mcgw-src -to 192.168.10.255:3000 -from 192.168.10.20 # Go sets SO_BROADCAST by default
    send mcgw-gw -to 192.168.10.1:3000
    send mcgw-gw -to 127.0.0.1:3000
    stop_captures
    finish_case
    expect_accept "$raw/R-OD17-$tag.json" "$N"
    [[ $(count_matches ' > 192\.168\.10\.(1|255)\.3000:' "$raw/od17-eth0-$tag.txt") == "$((2 * N))" ]] || {
        invalid "external unicast/broadcast not fully observed on eth0: $tag"; return 1;
    }
    # Loopback traffic is counted as "at least", since a loopback capture can show a
    # packet in both directions on some kernels.
    (($(count_matches ' > (192\.168\.10\.1|127\.0\.0\.1)\.3000:' "$raw/od17-lo-$tag.txt") >= 2 * N)) || {
        invalid "local-origin unicast not observed on lo: $tag"; return 1;
    }
    local od17=0
    [[ $bind == wildcard ]] && od17=$((4 * N))
    result OD17 "R-OD17-$tag" "$od17"
}

for bind in group wildcard; do
    for mcall in default 0; do
        echo "running bind=$bind mcall=$mcall"
        run_case "$bind" "$mcall"
    done
done

# Run status: VALID, or REVIEW with reasons. INVALID never reaches this point.
reasons=()
if ((igmp_join_runs != 4)); then
    reasons+=("SSM join report (ALLOW/TO_IN with source 192.168.10.20) found in $igmp_join_runs of 4 captures; inspect the igmp-05-*.txt files")
fi
if ((${#mismatches[@]})); then
    reasons+=("${#mismatches[@]} check(s) differ from the kernel-semantics predictions")
fi
status=VALID
((${#reasons[@]} == 0)) || status=REVIEW

. /etc/os-release
kernel=$(uname -r)
report=$raw/report.md
{
    echo "# OD-09 isolation run — $PRETTY_NAME, kernel $kernel"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Run status | **$status** |"
    echo "| Date | $(date -u +'%F %H:%M:%S UTC') |"
    echo "| OS | $PRETTY_NAME |"
    echo "| Kernel | $kernel |"
    echo "| iproute2 | $(ip -V | head -1) |"
    echo "| tcpdump | $(tcpdump --version 2>&1 | head -1) |"
    echo "| Prototype Go runtime | $(jq -er '.go' "$raw"/R1-01-group-default.json 2>/dev/null || echo unknown) |"
    echo "| Repository commit | $(git -c safe.directory="$repo" -C "$repo" describe --always --dirty 2>/dev/null || echo unknown) |"
    echo "| GW rp_filter all/eth0, force_igmp_version eth0 | $gw_sysctls |"
    echo "| Socket options on every receiver | SO_REUSEADDR=1, IP_PKTINFO=1; ASM join IP_ADD_MEMBERSHIP (ip_mreqn ifindex); SSM join IP_ADD_SOURCE_MEMBERSHIP (interface address) |"
    echo "| Volume | $N datagrams per sender at 400/s, 64-byte payloads (test plan examples use 500-1000; filtering is deterministic, counts must be exact) |"
    echo "| SSM join reports seen (T-MCI-05) | $igmp_join_runs of 4 captures |"
    echo
    if [[ $status == REVIEW ]]; then
        echo "## Review reasons"
        echo
        printf -- '- %s\n' "${reasons[@]}"
        if ((${#mismatches[@]})); then printf -- '  - %s\n' "${mismatches[@]}"; fi
        echo
    fi
    echo "## Results"
    echo
    echo "Received counts every datagram the kernel delivered to the socket. Foreign counts"
    echo "delivered datagrams that are not the receiver's own traffic (other group, other"
    echo "interface, other source, or unicast/broadcast/local-origin for OD17); zero means the"
    echo "kernel kept them away. Predicted is the foreign count expected from Linux socket"
    echo "semantics. IP_MULTICAST_ALL shows the requested setting and, in brackets, the value"
    echo "read back from the kernel. Rejections lists every non-accept verdict."
    echo "U- and C- receivers use fixed options (shown in their row), not the option set under test."
    echo
    echo "| Case | Receiver | Bind | IP_MULTICAST_ALL | Received | Accepted | Foreign | Predicted | Match | Rejections |"
    echo "|---|---|---|---|---|---|---|---|---|---|"
    printf '%s\n' "${rows[@]}"
    echo
    echo "## Not covered by this run"
    echo
    echo "- Interface binding (SO_BINDTODEVICE) as a separate option dimension"
    echo "- Running without SO_REUSEADDR (bind-conflict behavior of the chosen option set)"
    echo "- T-MCI-05 check-config rejection (no daemon yet), permitted local senders,"
    echo "  IGMPv2 querier compatibility, source-specific joins outside 232/8, IPv6 (T-MCI-06)"
    echo "- Network-side IGMP/snooping behavior: the namespaces have no querier or snooping"
    echo
    echo "## Interpretation"
    echo
    echo "To be completed by the reviewer before using this run for OD-09/OD-17:"
    echo
    echo "1. For each option set, classify each case as kernel-suppressed (Foreign 0),"
    echo "   rejected by the per-datagram checks (Foreign > 0 with matching rejections) or leaked."
    echo "2. Explain every Match = NO row, using the raw JSON and captures."
    echo "3. Confirm from the igmp-05 captures that the join record for 192.168.10.20 is present."
    echo "4. Name the option set chosen for mcgw and the accounting boundary it implies:"
    echo "   what the kernel suppresses (not counted by mcgw) and what mcgw rejects (counted)."
    echo "5. For OD-17, state the OD17 rows for the chosen bind: which verdicts unicast,"
    echo "   broadcast and local-origin traffic received, or that none was delivered."
    echo "6. Compare with the runs on the other distributions and record differences."
} >"$report"

# Copy the report into the user-owned results directory without following a
# planted symlink and without overwriting an earlier run.
out=$here/results/$(date +%F-%H%M%S)-${ID}${VERSION_ID:-}-${kernel}.md
if [[ -e $out || -L $out ]]; then invalid "refusing to overwrite existing $out"; fi
owner=()
if [[ -n ${SUDO_USER:-} ]]; then owner=(-o "$SUDO_USER" -g "$(id -gn "$SUDO_USER")"); fi
install -m 0644 "${owner[@]}" "$report" "$out"
echo "results: $out ($status)"

[[ $status == VALID ]] || exit 3
