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

# wait_until SECONDS COMMAND... polls until the command succeeds.
wait_until() {
    local deadline=$((SECONDS + $1))
    shift
    until "$@"; do
        ((SECONDS < deadline)) || return 1
        sleep 0.2
    done
}
