# shellcheck shell=bash
# Validation helpers shared by the runner and the unprivileged regression checks
# in test_harness.py. Functions that guard experiment validity call invalid();
# prediction checks only return a status, because a prediction mismatch is data
# for human review, not a broken run.

# IGMPv3 join evidence for T-MCI-05: a report record that adds 192.168.10.20 to
# 232.1.1.1 (ALLOW, TO_IN or IS_IN). Leave records (BLOCK, TO_IN {}) and other
# addresses such as 192.168.10.200 deliberately do not match.
# shellcheck disable=SC2034  # used by run-mci.sh
IGMP_JOIN_RE='igmp v3 report.*gaddr 232\.1\.1\.1 (allow|to_in|is_in) \{[^}]*192\.168\.10\.20[ }]'

invalid() { echo "INVALID experiment: $*" >&2; return 1; }

wait_receiver() {
    local pid=$1 file=$2
    wait "$pid" || { invalid "receiver failed: $file"; return 1; }
    jq -se 'length == 1 and (.[0] | .tool == "od09-isolation" and
        .complete == true and .termination == "deadline" and
        (.received | type == "number") and (.verdicts | type == "object") and
        (.received == ([.verdicts[]] | add // 0)))' "$file" >/dev/null || {
        invalid "missing, malformed or incomplete receiver summary: $file"; return 1;
    }
}

expect_accept() {
    local file=$1 expected=$2
    jq -e --argjson n "$expected" '(.verdicts.accept // 0) == $n' "$file" >/dev/null || {
        invalid "positive control failed: $file (expected $expected accepted)"; return 1;
    }
}

check_sender() {
    local file=$1 expected=$2
    jq -se --argjson n "$expected" 'length == 1 and
        (.[0] | .tool == "mcsend" and .sent == $n and .errors == 0)' "$file" >/dev/null || {
        invalid "sender did not submit all datagrams: $file"; return 1;
    }
}

# foreign_matches FILE N succeeds when the receiver's foreign delivery equals the
# prediction N. Mismatches are reported for review rather than invalidating the run.
foreign_matches() {
    local file=$1 predicted=$2
    jq -e --argjson n "$predicted" '.foreign_delivered == $n' "$file" >/dev/null
}

# mcall_matches FILE succeeds when the effective IP_MULTICAST_ALL read back from
# the kernel is what the requested setting implies ("default" is 1 on Linux).
mcall_matches() {
    jq -e '(if .options.mcall == "default" then 1 else (.options.mcall | tonumber) end)
        == .options.mcall_effective' "$1" >/dev/null
}

# row_text CASE FILE PREDICTED MATCH prints one markdown table row for the report.
row_text() {
    local case=$1 file=$2 predicted=$3 match=$4
    jq -r --arg c "$case" --arg p "$predicted" --arg m "$match" '
        "| \($c) | \(.name) | \(.options.bind) | \(.options.mcall) (\(.options.mcall_effective)) | " +
        "\(.received) | \(.verdicts.accept // 0) | \(.foreign_delivered) | \($p) | \($m) | " +
        ([.verdicts | to_entries[] | select(.key != "accept") | "\(.key)=\(.value)"] | join(", ")) + " |"
    ' "$file"
}

# No matches is data; unreadable evidence is an experiment failure.
count_matches() {
    local pattern=$1 file=$2 rc
    if grep -cE "$pattern" "$file"; then
        return 0
    else
        rc=$?
        [[ $rc == 1 ]] && return 0
        return "$rc"
    fi
}

wait_capture() {
    local pid=$1 rc=0
    wait "$pid" || rc=$?
    # 0: tcpdump exited itself; 124: GNU timeout safety limit reached;
    # 143: the runner stopped the capture with SIGTERM after the traffic window.
    [[ $rc == 0 || $rc == 124 || $rc == 143 ]] || { invalid "capture failed (exit $rc)"; return 1; }
}
