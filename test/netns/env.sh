#!/usr/bin/env bash
# Create, inspect or remove the test plan's shared environment (ENV).
# Everything lives in network namespaces prefixed mcgw-; host interfaces,
# routes and firewall rules are not touched.
#
# Usage: sudo test/netns/env.sh up | down | status
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/lib.sh"

# veth NS1 IF1 NS2 IF2 creates a veth pair directly inside two namespaces.
veth() {
    ip link add "$2" netns "$1" type veth peer name "$4" netns "$3"
    ip -n "$1" link set "$2" up
    ip -n "$3" link set "$4" up
}

addr() { ip -n "$1" addr add "$3" dev "$2"; }

up() {
    local listing
    # Enumeration failure is not evidence that creating the environment is safe.
    listing=$(ip netns list) || return 1
    if grep -q '^mcgw-' <<< "$listing"; then
        echo "error: mcgw- namespaces already exist; run '$0 down' first" >&2
        exit 1
    fi
    for ns in "${MCGW_NAMESPACES[@]}"; do
        ip netns add "$ns"
        ip -n "$ns" link set lo up
    done

    # Ingress: SRC -> GW eth0, SRC2 -> GW eth2
    veth mcgw-src s0 mcgw-gw eth0
    veth mcgw-src2 s0 mcgw-gw eth2
    addr mcgw-src s0 192.168.10.20/24
    addr mcgw-src s0 192.168.10.21/24
    addr mcgw-src2 s0 192.168.11.20/24
    addr mcgw-gw eth0 192.168.10.1/24
    addr mcgw-gw eth2 192.168.11.1/24
    for ns in mcgw-src mcgw-src2; do
        ip -n "$ns" route add 239.0.0.0/8 dev s0
        ip -n "$ns" route add 232.0.0.0/8 dev s0
    done

    # Egress: GW eth1 and destinations on bridge br0 in NET (no snooping, no querier)
    ip -n mcgw-net link add br0 type bridge mcast_snooping 0
    ip -n mcgw-net link set br0 up
    veth mcgw-gw eth1 mcgw-net p-gw
    veth mcgw-dsta eth0 mcgw-net p-dsta
    veth mcgw-dstb eth0 mcgw-net p-dstb
    veth mcgw-dstc eth0 mcgw-net p-dstc
    for port in p-gw p-dsta p-dstb p-dstc; do
        ip -n mcgw-net link set "$port" master br0
    done
    addr mcgw-gw eth1 10.0.20.1/24
    addr mcgw-dsta eth0 10.0.20.5/24
    addr mcgw-dstb eth0 10.0.20.6/24
    addr mcgw-dstc eth0 10.0.20.7/24

    # Constrained-egress path: GW eth3 -> DST_B eth1
    veth mcgw-gw eth3 mcgw-dstb eth1
    addr mcgw-gw eth3 10.0.30.1/24
    addr mcgw-dstb eth1 10.0.30.6/24

    # Pin GW settings so results do not depend on distro defaults or on values a
    # host with net.core.devconf_inherit_init_net=1 would pass into new namespaces:
    # loose reverse-path filtering, and IGMPv3 so source-specific joins are visible
    # on the wire (the test plan's "GW forced to IGMPv3").
    for key in all default eth0 eth1 eth2 eth3; do
        nsx mcgw-gw sysctl -qw "net.ipv4.conf.$key.rp_filter=2"
        nsx mcgw-gw sysctl -qw "net.ipv4.conf.$key.force_igmp_version=3"
    done
    echo "ENV up: ${MCGW_NAMESPACES[*]}"
}

# down removes every mcgw- namespace (including stray ones from older layouts,
# which would otherwise make 'up' refuse forever) after stopping processes left
# inside, since a running process keeps a deleted namespace alive.
stop_namespace_processes() {
    local ns=$1 listing pid attempt
    local -a members=()
    listing=$(ip netns pids "$ns") || return 1
    mapfile -t members < <(printf '%s\n' "$listing")
    for pid in "${members[@]}"; do
        [[ -z $pid ]] || kill -TERM "$pid" 2>/dev/null || true
    done
    # Do not delete the name while surviving processes still pin the namespace.
    # Re-read membership to include children forked during the grace period.
    for ((attempt = 0; attempt < 40; attempt++)); do
        listing=$(ip netns pids "$ns") || return 1
        [[ -n $listing ]] || return 0
        if ((attempt == 20)); then
            mapfile -t members < <(printf '%s\n' "$listing")
            for pid in "${members[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
        fi
        sleep 0.1
    done
    echo "error: processes remain in $ns after TERM/KILL; namespace retained" >&2
    return 1
}

down() {
    local ns listing failed=0
    # A failed enumeration must never be mistaken for an empty environment.
    listing=$(ip netns list) || return 1
    while read -r ns _; do
        [[ $ns == mcgw-* ]] || continue
        if ! stop_namespace_processes "$ns"; then
            echo "error: could not stop processes in $ns; namespace retained" >&2
            failed=1
            continue
        fi
        if ! ip netns del "$ns"; then
            echo "error: could not delete namespace $ns" >&2
            failed=1
        fi
    done <<< "$listing"
    ((failed == 0)) || return 1
    echo "ENV down"
}

status() {
    local listing ns
    # Use one checked snapshot: an ip failure must not look like an absent ENV.
    listing=$(ip netns list) || return 1
    grep '^mcgw-' <<< "$listing" || { echo "ENV not present"; return 0; }
    for ns in "${MCGW_NAMESPACES[@]}"; do
        grep -q "^$ns\b" <<< "$listing" || continue
        echo "== $ns"
        ip -n "$ns" -br addr show | grep -v '^lo ' || true
    done
    echo "== mcgw-gw rp_filter and force_igmp_version"
    nsx mcgw-gw sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.eth0.rp_filter \
        net.ipv4.conf.eth0.force_igmp_version 2>/dev/null || true
}

# Keep dispatch separate so unprivileged tests can replace only the lock and
# namespace commands while exercising the real lifecycle functions.
main() {
    require_root
    require_tools ip sysctl flock
    case "${1:-}" in
        up) lock_environment /run/mcgw-test.lock || return 1; up ;;
        down) lock_environment /run/mcgw-test.lock || return 1; down ;;
        status) status ;;
        *) echo "usage: $0 up | down | status" >&2; exit 2 ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
