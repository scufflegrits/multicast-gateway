# shellcheck shell=bash
# Shared helpers for the mcgw namespace test environment. Source, do not run.

# shellcheck disable=SC2034  # used by scripts that source this file
MCGW_NAMESPACES=(mcgw-src mcgw-src2 mcgw-gw mcgw-net mcgw-dsta mcgw-dstb mcgw-dstc)

require_root() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "error: must run as root (network namespaces)" >&2
        exit 1
    fi
}

require_tools() {
    local missing=()
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if ((${#missing[@]})); then
        echo "error: missing tools: ${missing[*]} (see test/README.md)" >&2
        exit 1
    fi
}

# nsx NAMESPACE COMMAND... runs a command inside a test namespace.
nsx() {
    local ns=$1
    shift
    ip netns exec "$ns" "$@"
}

# wait_until SECONDS COMMAND... polls every 0.2 s until the command succeeds,
# for at least SECONDS. It counts attempts rather than using $SECONDS, which has
# one-second resolution and could give up almost a second early.
wait_until() {
    local tries=$(($1 * 5 + 1)) # SECONDS*5 sleeps of 0.2 s between attempts
    shift
    until "$@"; do
        ((--tries > 0)) || return 1
        sleep 0.2
    done
}

# Stop direct background children with a finite TERM grace period. Reap every
# child, including failures, before callers discard their PID ownership list.
# Callers must not pass previously reaped PIDs or unrelated processes.
stop_children() {
    local pid attempt running
    for pid in "$@"; do kill -TERM "$pid" 2>/dev/null || true; done
    for ((attempt = 0; attempt < 20; attempt++)); do
        running=0
        for pid in "$@"; do
            if kill -0 "$pid" 2>/dev/null; then running=1; fi
        done
        ((running)) || break
        sleep 0.1
    done
    for pid in "$@"; do kill -KILL "$pid" 2>/dev/null || true; done
    for pid in "$@"; do wait "$pid" 2>/dev/null || true; done
}
