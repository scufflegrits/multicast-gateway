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
    jq -se '
        def count: type == "number" and . >= 0 and . == floor;
        def own($o): .dst == $o.group and .ifindex == $o.ifindex and
            ($o.source == "" or .src == $o.source);
        length == 1 and (.[0] |
        .tool == "od09-isolation" and .complete == true and .termination == "deadline" and
        (.name | type == "string") and (.go | type == "string") and
        (.received | count) and (.foreign_delivered | count) and
        (.options | type == "object") and
        (.options.group | type == "string") and (.options.source | type == "string") and
        (.options.iface | type == "string") and
        (.options.ifindex | count and . > 0) and
        (.options.port | count and . > 0 and . <= 65535) and
        (.options.bind == "group" or .options.bind == "wildcard") and
        (.options.mcall == "default" or .options.mcall == "0" or .options.mcall == "1") and
        (.options.mcall_effective == 0 or .options.mcall_effective == 1) and
        (.verdicts | type == "object") and
        (.verdicts | to_entries | all(.[];
            (.value | count) and (.key == "accept" or .key == "truncated" or
            .key == "wrong_ingress" or .key == "wrong_destination" or
            .key == "oversize" or .key == "source_filtered"))) and
        (.origins | type == "array") and
        (.origins | all(.[]; (.count | count and . > 0) and
            (.dst | type == "string") and (.src | type == "string") and
            (.ifindex | count) and (.verdict | type == "string"))) and
        (.received == ([.verdicts[]] | add // 0)) and
        (.received == ([.origins[].count] | add // 0)) and
        (.options as $o | .foreign_delivered ==
            ([.origins[] | select(own($o) | not) | .count] | add // 0)) and
        (.options as $o | all(.origins[]; .verdict != "accept" or own($o))) and
        (. as $r | all(.origins[]; $r.verdicts[.verdict] != null)) and
        (. as $r | .verdicts | to_entries | all(.[]; . as $v |
            $v.value == ([$r.origins[] | select(.verdict == $v.key) | .count] | add // 0))))' "$file" >/dev/null || {
        invalid "missing, malformed or incomplete receiver summary: $file"; return 1;
    }
}

expect_accept() {
    local file=$1 expected=$2
    jq -e --argjson n "$expected" '(.verdicts.accept // 0) == $n' "$file" >/dev/null || {
        invalid "positive control failed: $file (expected $expected accepted)"; return 1;
    }
}

# Aggregate accepted counts cannot prove both ASM control sources arrived: a
# duplicate from one source could hide the other's absence. Check each source.
expect_accept_source() {
    local file=$1 source=$2 expected=$3
    jq -e --arg source "$source" --argjson n "$expected" '
        ([.origins[] | select(.verdict == "accept" and .src == $source) |
            .count] | add // 0) == $n' "$file" >/dev/null || {
        invalid "positive control failed: $file (expected $expected accepted from $source)"; return 1;
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

# Compare rejection reasons as well as totals: a wrong reason is evidence to
# review, even when the aggregate foreign count happens to match.
rejections_match() {
    jq -e --argjson expected "$2" '
        def nonzero: with_entries(select(.value != 0));
        (.verdicts | del(.accept) | nonzero) == ($expected | nonzero)' "$1" >/dev/null
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
    # stop_captures verifies that capture is alive before requesting shutdown.
    # 143 is intentional SIGTERM; 124/137 are safety limits, not complete evidence.
    [[ $rc == 0 || $rc == 143 ]] || { invalid "capture failed (exit $rc)"; return 1; }
}
