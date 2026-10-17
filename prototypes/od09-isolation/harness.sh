# shellcheck shell=bash
# Validation helpers shared by the runner and unprivileged regression checks.
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
    # GNU timeout returns 124 when the planned capture window ends.
    [[ $rc == 0 || $rc == 124 ]] || { invalid "capture failed (exit $rc)"; return 1; }
}
