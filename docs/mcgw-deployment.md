# mcgw deployment planning

**Status:** pre-implementation guidance. No installable daemon, supported OS matrix,
or production systemd unit is claimed here. Read-only checks are usable on hosts
with the relevant tools; service/HTTP checks require implemented mcgw features.
Current policy is defined in [architecture](architecture.md); unresolved choices
are tracked in [open decisions](mcgw-open-decisions.md).

## Contents

- [Host and network prerequisites](#host-and-network-prerequisites)
- [Service lifecycle contract](#service-lifecycle-contract)
- [Access and hardening](#access-and-hardening)
- [Logging and collection](#logging-and-collection)
- [Qualification and acceptance](#qualification-and-acceptance)
- [Sources](#sources)

## Host and network prerequisites

| Area | Record / verify | Failure it helps explain |
|---|---|---|
| OS | Debian/RHEL release, kernel, systemd, security policy, network namespace | API/version or permission mismatch |
| Interfaces | Name/index, addresses, administrative/carrier state, ingress VLAN and egress policy | Wrong join, missing bind address, recreated interface |
| Routing | Permitted unicast route/source, policy rules, asymmetric return paths | Wrong egress, missing route; interface up does not prove remote reachability |
| IPv4 reverse-path filtering | Inspect both `net.ipv4.conf.all.rp_filter` and ingress-interface value; the effective mode is the maximum numeric value (0 disabled, 1 strict, 2 loose), so 2 on either is loose even if the other is 1 | Source-validation drops before mcgw even when a capture sees input; do not automatically disable it [S5] |
| Firewall | Permit intended multicast UDP, necessary IGMP/ICMPv6 membership traffic, outbound UDP, and useful ICMP error feedback | Input loss, membership expiry, PMTU black holes; never assume a universal distro/zone policy |
| Membership infrastructure | Record querier, snooping, router source/group ranges, and effective IGMP/MLD versions | Join succeeds locally but network distribution fails or ages out |
| Source-specific membership | Verify IGMPv3 for IPv4 / MLDv2 for IPv6 where source-specific reporting is needed; inspect version-forcing settings and router support | Older compatibility behavior cannot provide equivalent source selection [S16] |
| Routed multicast | Sender TTL/hop limit, routed group reachability and any ASM rendezvous configuration | Traffic cannot cross the required network boundary; no universal sender TTL is assumed |
| Receive buffers | Requested and effective `SO_RCVBUF`, `net.core.rmem_max`, receive-overflow evidence | Request may be capped without yielding requested capacity; Linux reports doubled buffer accounting [S2] |
| Membership limits | Inspect applicable `igmp_max_memberships`, `igmp_max_msf`, `mld_max_msf` and group/source demand | Resource exhaustion; meanings differ by setting and kernel [S5] |
| Capacity | Input packet/byte rates, bursts, fan-out, shared WAN headroom, queue policy | Valid traffic or hostile traffic overwhelms an output |
| Time | Host time synchronization and incident timestamps | Misleading cross-site correlation; internal queue ages use monotonic time |

mcgw reports available effective settings and failures; warning/failure thresholds
remain OD-06/OD-10 decisions. Operators own sysctl, routing and firewall changes.
Do not infer authentication from source filtering or use membership snooping as
an access-control substitute.

## Service lifecycle contract

A reference unit will be written after OD-01/OD-02/OD-10/OD-11 resolve. A unit
with invented timeout/capability values would imply unsupported decisions.

| Concern | Required contract / validation |
|---|---|
| Startup | Invalid config fails. Required local initialization currently must succeed before readiness; bounded waiting versus degraded startup remains open |
| Required components | Define all-required versus explicit optional policy before schema freeze; do not assume a `required` field exists |
| Ordering | Evaluate `Wants=`/`After=network-online.target`; online-target completion is not proof all configured interfaces are usable |
| Notify | Baseline `Type=notify`; match `NotifyAccess` to sender process; send initial `READY=1` only when startup contract is met [S15] |
| Watchdog | Set `WatchdogSec` only after implementing its protocol; share meaningful progress evidence with liveness, including idle operation |
| Preflight | Evaluate `ExecStartPre` validation as the service user; it cannot reserve resources or eliminate startup races |
| Reload | Serialize/coalesce or reject concurrent requests; report applied, rolled-back, and degraded outcomes. Plain `kill -HUP` does not give synchronous activation success |
| Version compatibility | `Type=notify-reload` is version-dependent (introduced in systemd 253); otherwise choose and test a compatible completion mechanism [S15] |
| Notifications | Implement appropriate reload/stopping notifications for the chosen protocol; do not copy notify-reload fields into a baseline unit without checking requirements |
| Shutdown | Stop intake, bound drain/cancellation, count abandonment; systemd stop timeout must exceed internal shutdown deadline plus cleanup margin |
| Restart | Choose `Restart=on-failure`, restart delay/start-limit policy with boot/failure tests; avoid a silent restart storm |
| Config updates | Prefer atomic replacement over editing the active file in place; validate as the service identity; invalid reload preserves old config |

Rollback can restore configuration/resources, not payloads already discarded.
Systemd readiness and HTTP readiness are related but separate interfaces; define
which transitions each consumer observes.

## Access and hardening

| Boundary | Position / investigation |
|---|---|
| Ingress trust | mcgw does not authenticate publishers; spoofed source addresses may pass an allow-list. Network controls and capacity planning are required; mandatory ceilings remain OD-03 |
| Fan-out | One accepted input can cause many output copies; account for both accidental and intentional amplification |
| Local API | Loopback HTTP is accessible to other permitted processes/users on that host; v1 is not a per-user authorization boundary |
| External API | Explicit binding plus operator access controls/proxy; no built-in authentication/TLS promise |
| Privileges | Dedicated service identity; verify APIs on selected vendor kernels before choosing capabilities. Privileged local port binds and device enforcement may need different permissions |
| Sandbox | Evaluate `NoNewPrivileges`, read-only filesystem restrictions, address-family limits including netlink and notification sockets, file limits and service memory limits |
| SELinux | Keep enforcing policy during RHEL qualification; determine labels/permissions with evidence. Do not recommend disabling SELinux or assume one universal service domain |
| Memory | Queue budget is not total RSS; service memory limits need measured overhead/headroom. Runtime memory tuning is not a substitute for ownership bounds |
| Redundancy | No built-in v1 HA. Do not introduce duplicate-producing overlapping instances without an explicit deployment decision; active/standby design is OD-13 |

## Logging and collection

| Item | Acceptance |
|---|---|
| Transport | Structured JSON inside journal MESSAGE; no separate log file |
| Severity | Currently JSON-only; `journalctl -p err` is not a reliable JSON-severity filter. Native priority mapping remains OD-08 |
| Collection | Parse message JSON, preserve host/config/route/sink identity, test outage and recovery alerts |
| Volume | Bound repeated events; inspect journal/service/collector rate limits and retention; suppressed/lost records are possible |
| Isolation | Blocked or broken log output must not stall forwarding or interface recovery; test it and check the overflow/write-failure counters ([architecture §5](architecture.md#journal-events-and-siem-integration)) |
| Privacy | Bound diagnostic captures and retain payloads only as needed |

## Qualification and acceptance

Individual test cases, including the namespace harness, are in the
[test plan](mcgw-test-plan.md).

| Test group | Evidence required |
|---|---|
| Representative lab | Specified Cisco router/switch software and actual firewall configuration; then each site's differences |
| Network isolation | Multiple groups sharing ports, unrelated host joins, wrong-interface injection, source mismatches, membership-version compatibility |
| Data integrity | Empty/max/oversize payloads, truncation and accounting; per-sink independence |
| Resource failures | Receive overflow, constrained buffers, stalled output, output MTU failures, unavailable interface |
| Lifecycle | Late boot interface/address, delete/recreate, reload conflicts, partial preparation cleanup, shutdown and notification completion |
| Reproducibility | Planned network-namespace/veth fixture harness, impairment via `tc netem`, scripted link changes, race checks and config fuzzing; test netlink reconciliation/event loss |
| Packaging | Record binary/config/unit paths and Debian/RHEL installation conventions when implemented; no deb/rpm support claim yet |

## Sources

Primary references are indexed in the [review research appendix](architecture-review.md#appendix-a--online-research-sources):
S2 (socket buffers), S5 (sysctls), S15 (systemd service), S16 (SSM membership),
and S17 (systemd execution/logging). They describe mechanisms, not qualification
of a specific release, vendor topology, security policy, or default setting.
