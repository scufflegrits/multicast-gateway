# mcgw test plan

**Status:** first pass, 2026-10-17. Test cases are written before code, in
language-neutral pseudocode. They do not change the [architecture](architecture.md),
which stays authoritative, and nothing here has been run.

## Contents

- [Rules](#rules)
- [Test levels](#test-levels)
- [Shared environment](#shared-environment)
- [Case template](#case-template)
- [ACC — Accounting and datagram limits](#acc--accounting-and-datagram-limits)
- [ISO — Sink isolation](#iso--sink-isolation)
- [MCI — Multicast isolation](#mci--multicast-isolation)
- [IFR — Interface recovery](#ifr--interface-recovery)
- [RLD — Reload and shutdown](#rld--reload-and-shutdown)
- [OBS — Health, logging and HTTP](#obs--health-logging-and-http)
- [LIFE and LOOP — Startup, validation and local loops](#life-and-loop--startup-validation-and-local-loops)
- [Lab and qualification stubs](#lab-and-qualification-stubs)
- [Traceability](#traceability)
- [Blocker summary](#blocker-summary)
- [Contract gaps found](#contract-gaps-found)

## Rules

| Rule | Meaning |
|---|---|
| Architecture is authoritative | Each case cites the contract it checks and does not restate or extend it |
| Observable evidence | Integration and lab cases check only counters, `/status`, `/readyz`, `/healthz`, journal events, captures, received datagrams and exit codes |
| Provisional names | `counter(sink, queue_full)` and similar labels are placeholders until the metrics contract is frozen (OD-15) |
| Undecided numbers | Written as named parameters (`QUEUE_LIMIT`, `MAX_AGE`); the case lists the deciding OD under Blocked by |
| Ambiguity | A contract that cannot be turned into an observable expectation is listed under [Contract gaps found](#contract-gaps-found), never settled inside a test |
| Stable IDs | Never reuse an ID; retire cases with a reason instead of deleting them |

| Status | Meaning |
|---|---|
| Draft | Intent recorded; not fully specified |
| Ready | Fully specified; implementable once its blockers resolve |
| Automated | Implemented as a test |
| Passed | Passed on a recorded build, environment and date |

## Test levels

| Level | Environment | Scope |
|---|---|---|
| Unit | `go test`, no network | Component interfaces: config validation, accounting arithmetic, queue expiry/ordering, address classification |
| Integration | Network namespaces and veth links on one Linux host, as planned in [deployment qualification](mcgw-deployment.md#qualification-and-acceptance) | Real multicast and UDP through the daemon; no hardware |
| Lab | Proxmox VMs, VLAN 2601, Cisco switches | Querier/snooping, two-NIC path, impairments, SIEM, benchmarks |
| Qualification | Selected OS, switch and Windows builds | Reference-guide commands and platform claims |

Unit cases call component interfaces and may use test doubles; they are written
alongside the code and are not enumerated here unless an integration case cannot
reach the behavior.

## Shared environment

Integration cases reuse one topology, `ENV`. Addresses follow the architecture's
configuration example.

```text
ENV
  netns SRC:  s0 192.168.10.20/24, .21/24 (secondary)   <-veth->  GW eth0 192.168.10.1/24
  netns SRC2: s0 192.168.11.20/24                        <-veth->  GW eth2 192.168.11.1/24
  netns NET:  bridge br0
                GW eth1   10.0.20.1/24  (egress, default route for 10.0.20.0/24)
                DST_A     10.0.20.5/24
                DST_B     10.0.20.6/24
                DST_C     10.0.20.7/24
  GW eth3 10.0.30.1/24  <-veth->  DST_B second address 10.0.30.6 (constrained-egress path)
  SRC, SRC2: route 239.0.0.0/8 and 232.0.0.0/8 via s0
  mcgw runs in GW with stdout/stderr on a harness-controlled pipe
  NOTIFY_SOCKET points at a harness socket that records systemd notifications

ENV6 = ENV with ff15::1:6969 ingress and 2001:db8:20::/64 egress addresses
```

Helper vocabulary used by the cases:

| Helper | Meaning |
|---|---|
| `send(ns, to, n, size, rate, from)` | Send `n` UDP datagrams; payload = sequence number, send timestamp, fixed pattern padded to `size` |
| `received(ns, port)` | Datagrams captured by a listening socket: sequence, bytes, source IP/port |
| `counter(scope, name)` | Metric value for a route or sink (provisional names) |
| `status(path)` | Field from `/status` JSON |
| `readyz()`, `healthz()` | HTTP status code from a fresh client |
| `events(name)` | Parsed JSON records with `event == name` from the harness pipe |
| `wire(iface, filter)` | Bounded capture in the relevant namespace |
| `link(iface, up|down)`, `addr(iface, add|del, a)` | Interface changes |
| `reload(cfg)`, `term()` | Replace config and send SIGHUP; send SIGTERM |
| `notified()` | Messages received on the harness notify socket |
| `wait_until(cond, T)` | Poll until true or fail after `T` |

## Case template

```text
T-XXX-NN  Title
Checks:   architecture section / contract row (or OD)
Level:    Unit | Integration | Lab | Qualification
Blocked:  ODs that set a parameter or decide the behavior (or "none")
Status:   Draft | Ready | Automated | Passed (build, env, date)

SETUP   environment and starting state
ACTION  what the test does
EXPECT  observable results only
```

## ACC — Accounting and datagram limits

```text
T-ACC-01  Whole datagram forwarded unchanged and counted
Checks:   §4 accounting contract; route/sink equations
Level:    Integration (ENV)
Blocked:  OD-15
Status:   Ready

SETUP   route R1 = 239.1.1.1:3000 on eth0; sink A -> 10.0.20.5:3000
ACTION  send(SRC, 239.1.1.1:3000, n=1000, size=1250, rate=1000/s)
EXPECT  received(DST_A, 3000) has 1000 datagrams, payloads byte-identical, sequence ascending
        counter(R1, received) == 1000; counter(R1, rejected) == 0
        counter(A, offered) == counter(A, submitted) == 1000
        counter(A, submitted_bytes) == 1000 * 1250
```

```text
T-ACC-02  Source allow-list rejection counted once
Checks:   §4 route equation; §6 config source_allow; §5 rejection reasons
Level:    Integration (ENV)
Blocked:  OD-09 (schema names), OD-15
Status:   Ready

SETUP   R1 with source_allow [192.168.10.20]; sink A
ACTION  send(SRC, 239.1.1.1:3000, n=500, from=192.168.10.20)
        send(SRC, 239.1.1.1:3000, n=300, from=192.168.10.21)
EXPECT  DST_A receives exactly the 500 datagrams from .20
        counter(R1, rejected{source_filtered}) == 300
        variant: 50 datagrams from .21 with size MAX_DATAGRAM + 1 count as oversize only
          (precedence, §4), never also as source_filtered
        counter(R1, received) == counter(R1, rejected) + counter(R1, fanout_accepted)
```

```text
T-ACC-03  Datagram size boundaries
Checks:   §4 empty UDP payload row; WAN/packet-size "too large / truncated"
Level:    Integration (ENV)
Blocked:  OD-06; MAX_DATAGRAM from OD-12
Status:   Ready

SETUP   R1, sink A, max_datagram = MAX_DATAGRAM
ACTION  send sizes [0, 1, MAX_DATAGRAM - 1, MAX_DATAGRAM, MAX_DATAGRAM + 1], 10 each
EXPECT  DST_A receives 10 each of sizes 0 .. MAX_DATAGRAM, byte-identical
        size 0: packet counts +10, payload bytes +0, one queue frame each
        size MAX_DATAGRAM + 1: none forwarded, no partial payload anywhere,
          counter(R1, rejected{oversize}) == 10 (truncated is reserved for ancillary data;
          unit-level case, as it cannot be triggered from outside)
```

```text
T-ACC-04  Accounting equations hold under mixed outcomes
Checks:   §4 "At a drained or consistent snapshot"; terminal outcome exactly once
Level:    Integration (ENV)
Blocked:  OD-12 (QUEUE_LIMIT, MAX_AGE), OD-15
Status:   Ready

SETUP   R1 with source_allow; sinks A (healthy) and B (slow, see T-ISO-02 setup)
ACTION  mixed traffic: allowed and disallowed sources, burst above B's drain rate
        stop traffic; wait until pending == 0 for every sink
EXPECT  route:  received == rejected + fanout_accepted
        each sink: offered == submitted + failed + dropped + pending (pending == 0)
        dropped == sum over reasons; no reason counted for a submitted offer
        repeat the check on 20 snapshots taken during traffic: equations hold in each
```

```text
T-ACC-05  Path-size failure is counted, not fragmented
Checks:   §4 WAN/packet-size "exceeds known outbound path budget"
Level:    Integration (ENV with NET mtu 1280 on br0 path)
Blocked:  OD-04
Status:   Draft

SETUP   GW eth1 mtu 1280; sink A
ACTION  send datagrams of 1200 and 1400 payload bytes
EXPECT  wire(eth1): no IPv4 fragments and no IPv6 fragment headers from GW
        1400-byte offers end as counted local size failures; 1200-byte offers submitted
        repeat with ICMP "fragmentation needed" blocked downstream: submissions are
          not revised into invented failures (local acceptance only)
```

```text
T-ACC-06  Asynchronous ICMP error is not attributed to a packet
Checks:   §4 "Async network error"; OD-05 current position
Level:    Integration (ENV)
Blocked:  OD-05
Status:   Ready

SETUP   sink B -> 10.0.20.6:3000 with no listener in DST_B (ICMP port unreachable)
ACTION  send 100 datagrams
EXPECT  counter(B, submitted) counts every locally accepted datagram
        any asynchronous error appears as a separate event/counter
        no offer's terminal outcome changes after it was counted submitted
        sink A unaffected
```

```text
T-ACC-07  Partial send batches counted exactly
Checks:   §3 "Send batches"
Level:    Unit (send-path component with injected short batch results)
Blocked:  OD-07 (batching chosen at all)
Status:   Draft

ACTION  injected batch send returns k of n entries accepted, then an error
EXPECT  exactly k submitted; remaining n-k retried within deadline or counted once
        order of surviving datagrams preserved
```

## ISO — Sink isolation

```text
T-ISO-01  One unavailable sink does not affect healthy sinks
Checks:   §3 Isolation; §5 "Ingress usable, constrained egress down"
Level:    Integration (ENV)
Blocked:  OD-15
Status:   Ready

SETUP   R1; sink A -> 10.0.20.5:3000; sink B -> 10.0.30.6:3000 egress_interface eth3
        link(eth3, down)
ACTION  send(SRC, 239.1.1.1:3000, n=1000, rate=1000/s)
EXPECT  DST_A receives 1000, order preserved, no added delay versus a run without B
        counter(B, dropped{sink_unavailable}) == 1000; counter(B, submitted) == 0
        readyz() == 503 (OD-02 interim rule: B is required); healthz() == 200
        events(sink_unavailable) for B: one per transition, not per datagram
```

```text
T-ISO-02  Slow sink fills its queue without delaying others
Checks:   §3 Bounds, Queue full, Isolation
Level:    Integration (ENV)
Blocked:  OD-12 (QUEUE_LIMIT), OD-15; harness method to qualify
Status:   Ready

SETUP   sinks A (eth1) and B (eth3); on GW eth3:
          tc qdisc add dev eth3 root tbf rate 1mbit burst 4k latency 2s
ACTION  send 20000 datagrams of 1250 bytes at 5000/s
EXPECT  DST_A receives all 20000 in order
        counter(B, dropped{queue_full}) > 0; B's queue occupancy never exceeds QUEUE_LIMIT
        A's receive-to-submit latency percentiles within TOL of a baseline run without B
```

```text
T-ISO-03  Unstarted entries expire by monotonic age
Checks:   §3 Bounds (age), Expired
Level:    Integration (ENV)
Blocked:  OD-12 (MAX_AGE)
Status:   Ready

SETUP   as T-ISO-02 with max age MAX_AGE
ACTION  sustained overload of B; step the wall clock forward and back by 1 h mid-run
EXPECT  counter(B, dropped{expired}) > 0
        every datagram received at DST_B: receive_time - send_time <= MAX_AGE + TOL
        wall-clock steps cause no burst of expiries or stuck entries
```

```text
T-ISO-04  Per-sink order preserved among surviving datagrams
Checks:   §3 Ordering
Level:    Integration (ENV)
Blocked:  none
Status:   Ready

SETUP   as T-ISO-02
ACTION  send 50000 numbered datagrams
EXPECT  for each sink, received sequence numbers are strictly increasing (gaps allowed)
```

```text
T-ISO-05  Pending offers stay with their original sink instance
Checks:   §3 Offer identity, Replacement / removal; §4 "Changed / removed sink"
Level:    Integration (ENV)
Blocked:  OD-11, OD-12
Status:   Ready

SETUP   sink B -> 10.0.30.6:3000 slowed as T-ISO-02 so its queue is non-empty
ACTION  reload(cfg with B -> 10.0.20.7:3000) while traffic continues
EXPECT  DST_C (10.0.20.7) receives no datagram whose sequence was offered before the reload
        old B instance: drained or abandoned offers counted once
        replacement reported separately in status/events; any reused metric ID shows an
          explicit reset
```

## MCI — Multicast isolation

These cases are the evidence for [OD-09](mcgw-open-decisions.md#od-09). Record,
per kernel, whether unwanted datagrams were suppressed by the kernel or rejected
by mcgw, because those are accounted differently (§6 receive-path contract).

```text
T-MCI-01  Same port, different groups
Checks:   §6 receive-path "Multicast cross-delivery", "Acceptance tests"
Level:    Integration (ENV)
Blocked:  OD-09
Status:   Ready

SETUP   R1 = 239.1.1.1:3000 eth0 -> sink A; R2 = 239.1.1.2:3000 eth0 -> sink B (eth1 path, 10.0.20.6)
ACTION  send 1000 to each group from SRC
EXPECT  DST_A receives only R1 datagrams; DST_B only R2 datagrams
        record counter(R*, rejected{wrong_destination}) (expected 0 if kernel suppression works)
```

```text
T-MCI-02  Same group on two interfaces
Checks:   §6 receive-path "Acceptance tests"
Level:    Integration (ENV)
Blocked:  OD-09
Status:   Ready

SETUP   R1 = 239.1.1.1:3000 eth0 -> sink A; R2 = 239.1.1.1:3000 eth2 -> sink B
ACTION  SRC sends 1000 via eth0 path; SRC2 sends 1000 via eth2 path
EXPECT  A receives only SRC's datagrams; B only SRC2's
        record counter(R*, rejected{wrong_ingress})
```

```text
T-MCI-03  Unrelated host join on the same port is not delivered
Checks:   §6 receive-path "unrelated host joins"
Level:    Integration (ENV)
Blocked:  OD-09
Status:   Ready

SETUP   R1 = 239.1.1.1:3000 eth0 -> sink A
        separate process in GW joins 239.9.9.9 on eth0 and binds port 3000
ACTION  send 1000 to 239.9.9.9:3000
EXPECT  DST_A receives nothing; counter(R1, fanout_accepted) unchanged
```

```text
T-MCI-04  Wrong-interface injection rejected
Checks:   §6 receive-path "wrong-interface injection"
Level:    Integration (ENV)
Blocked:  OD-09
Status:   Ready

SETUP   R1 = 239.1.1.1:3000 eth0 -> sink A; unrelated process joins 239.1.1.1 on eth2
ACTION  SRC2 sends 1000 to 239.1.1.1:3000 into eth2
EXPECT  DST_A receives nothing; any delivery to mcgw is counted rejected{wrong_ingress}
```

```text
T-MCI-05  Source-specific membership excludes other sources
Checks:   §6 validation "SSM", "Source controls"; config membership_source
Level:    Integration (ENV, GW forced to IGMPv3)
Blocked:  OD-09
Status:   Ready

SETUP   R3 = 232.1.1.1:3000 eth0, membership_source 192.168.10.20 -> sink A
ACTION  send 500 from .20 and 500 from .21
EXPECT  wire(eth0, igmp): IGMPv3 report includes source 192.168.10.20 for 232.1.1.1
        DST_A receives only the .20 datagrams
        config with 232.1.1.1 and no membership_source is rejected by check-config
```

```text
T-MCI-06  IPv6 isolation equivalents
Checks:   §6 receive-path (IPV6_MULTICAST_ALL where available); OD-09
Level:    Integration (ENV6)
Blocked:  OD-09
Status:   Draft

ACTION  repeat T-MCI-01 .. T-MCI-05 with IPv6 groups, MLDv2, and an ff3x::/32 SSM group
EXPECT  same isolation results; record kernel versions and controls used
```

## IFR — Interface recovery

```text
T-IFR-01  Constrained egress down then up
Checks:   §5 interface table: constrained egress down, new offers, interface restored
Level:    Integration (ENV)
Blocked:  OD-15
Status:   Ready

SETUP   sinks A (eth1) and B (eth3 constrained); steady traffic 1000/s
ACTION  link(eth3, down) for 10 s, then link(eth3, up)
EXPECT  during outage: A continues; B unready; new B offers counted sink_unavailable
        after up: B ready only after revalidation; DST_B receives again
        events: one outage and one recovery for B, recovery after local revalidation
        healthz() == 200 throughout
```

```text
T-IFR-02  Queued offers abandoned on known egress loss
Checks:   §5 "Queued offers on known egress loss"; §3 Send bounds
Level:    Integration (ENV)
Blocked:  OD-12 (SEND_DEADLINE)
Status:   Ready

SETUP   B slowed as T-ISO-02 so its queue holds entries
ACTION  link(eth3, down)
EXPECT  queued B offers counted as drops exactly once within SEND_DEADLINE + TOL
        offers already accepted by the socket stay counted submitted
```

```text
T-IFR-03  Ingress down then up restores membership
Checks:   §5 "Ingress unavailable"
Level:    Integration (ENV)
Blocked:  none
Status:   Ready

SETUP   R1 on eth0; traffic 1000/s
ACTION  link(eth0, down) for 10 s, then up
EXPECT  R1 unready during outage; event reported; healthz() == 200
        after up: wire(eth0, igmp) shows a membership report; forwarding resumes
        no rejections or drops are invented for the gap
```

```text
T-IFR-04  Bound source address removed and restored
Checks:   §5 "Address removal / interface recreation"
Level:    Integration (ENV)
Blocked:  none
Status:   Ready

SETUP   sink B bind 10.0.30.1:8930 egress_interface eth3
ACTION  addr(eth3, del, 10.0.30.1); wait; addr(eth3, add, 10.0.30.1)
EXPECT  B unavailable while the address is absent; recovers after re-add
        received(DST_B) source endpoint is 10.0.30.1:8930 after recovery
```

```text
T-IFR-05  Interface deleted and recreated under the same name
Checks:   §5 "Address removal / interface recreation"; §8 interface-state contract
Level:    Integration (ENV)
Blocked:  OD-10
Status:   Ready

ACTION  delete GW eth3; recreate eth3 (new ifindex) with the same address
EXPECT  B re-resolves the interface; status shows the new index; forwarding resumes
        no datagrams leave via another interface meanwhile
```

```text
T-IFR-06  Explicit egress constraint never falls back
Checks:   §5 "Explicit egress constraint"; §6 validation "Egress"
Level:    Integration (ENV)
Blocked:  OD-10
Status:   Ready

SETUP   B -> 10.0.30.6:3000 egress_interface eth3; add GW route 10.0.30.0/24 via eth1 (metric 100)
ACTION  link(eth3, down); send traffic
EXPECT  wire(eth1): no datagrams to 10.0.30.6 from mcgw; B counted sink_unavailable
```

```text
T-IFR-07  Unconstrained sink survives NIC loss with an alternative route
Checks:   §5 "Normal Linux routing"
Level:    Integration (ENV)
Blocked:  OD-10
Status:   Ready

SETUP   sink D -> 10.0.30.6:3000 without constraint; routes via eth3 (metric 10) and eth1 (metric 100)
ACTION  link(eth3, down)
EXPECT  D remains usable and continues via eth1; no sink_unavailable for D
```

```text
T-IFR-08  Monitor resynchronizes after notification loss
Checks:   §5 "Monitoring startup / event loss"
Level:    Integration (ENV)
Blocked:  harness method to qualify (forcing netlink overflow)
Status:   Draft

ACTION  burst thousands of address add/delete events on a dummy interface while
        toggling eth3
EXPECT  status exposes monitoring degradation if overflow occurs, then resync
        final component states match actual interface state
```

## RLD — Reload and shutdown

These cases are the evidence for [OD-11](mcgw-open-decisions.md#od-11).

```text
T-RLD-01  No-op reload preserves counters
Checks:   §4 "Reload counters"
Level:    Integration (ENV)
Blocked:  OD-15
Status:   Ready

ACTION  traffic running; reload(same cfg) 10 times
EXPECT  counters monotonic across reloads; no reset; no forwarding gap at DST_A
```

```text
T-RLD-02  Invalid reload keeps the active configuration
Checks:   §5 reload diagram "Full validation succeeds? No"
Level:    Integration (ENV)
Blocked:  none
Status:   Ready

ACTION  reload(cfg with an unknown key and an invalid address)
EXPECT  errors reported; active generation unchanged; DST_A sees no gap
```

```text
T-RLD-03  Preparation failure over budget is rejected before activation
Checks:   §5 reload diagram preparation branch; §3 "Reload memory"
Level:    Integration (ENV)
Blocked:  OD-11, OD-12 (ALLOC_BUDGET)
Status:   Ready

SETUP   active config near ALLOC_BUDGET
ACTION  reload(cfg whose live + prepared overlap exceeds ALLOC_BUDGET)
EXPECT  reload rejected and reported; active generation unchanged
        no new memberships on the wire; no new sockets (ss) remain after rejection
        forwarding uninterrupted
```

```text
T-RLD-04  Changed route interrupted, unchanged route continues
Checks:   §5 reload diagram "Apply changes"; design decision D6
Level:    Integration (ENV)
Blocked:  OD-11
Status:   Ready

SETUP   R1 -> A and R2 -> B, both with traffic
ACTION  reload(cfg changing R2's port only)
EXPECT  R1: no gap at DST_A, counters preserved
        R2: interruption reported with outcome; resumes on the new port
```

```text
T-RLD-05  Activation failure triggers reported rollback
Checks:   §5 reload diagram "Activation succeeds? No"; "Runtime" validation row
Level:    Integration (ENV)
Blocked:  OD-11
Status:   Ready

SETUP   another process holds 10.0.20.1:8931
ACTION  reload(cfg adding a sink bound to 10.0.20.1:8931)
EXPECT  activation failure reported; rollback attempted; status shows restored or
        degraded state and any mixed generations explicitly
```

```text
T-RLD-06  Repeated SIGHUP and half-written config
Checks:   §5 reload; OD-11 evidence
Level:    Integration (ENV)
Blocked:  OD-11
Status:   Ready

ACTION  20 SIGHUPs within 1 s while the config file is alternately half-written and
        atomically replaced
EXPECT  reloads serialized; final active generation == last valid file; no crash;
        unchanged-route counters preserved
```

```text
T-RLD-07  SIGTERM drains within the shutdown deadline
Checks:   §5 reload diagram TERM branch
Level:    Integration (ENV)
Blocked:  OD-12 (SHUTDOWN_DEADLINE)
Status:   Ready

SETUP   B slowed so its queue is non-empty
ACTION  term()
EXPECT  process exits within SHUTDOWN_DEADLINE + TOL
        abandoned offers counted in the final summary
        wire(eth0, igmp): leave/report change for the groups; sockets closed
```

## OBS — Health, logging and HTTP

```text
T-OBS-01  Liveness, readiness and freshness are independent
Checks:   §5 health table (/healthz, /readyz, freshness disabled, state versus readiness)
Level:    Integration (ENV)
Blocked:  OD-02, OD-15
Status:   Ready

ACTION  (a) all sinks usable, no traffic   (b) link(eth3, down)   (c) sender silent for 10 min
EXPECT  (a) healthz 200, readyz 200   (b) healthz 200, readyz 503 naming B
        (c) readiness unchanged by silence; no restart; watchdog notifications continue
```

```text
T-OBS-02  Freshness transitions
Checks:   §5 health table "Freshness enabled"
Level:    Integration (ENV)
Blocked:  OD-12 (FRESH_WINDOW)
Status:   Ready

SETUP   R1 with freshness expectation FRESH_WINDOW
ACTION  start mcgw with no traffic; send traffic; stop for 2 x FRESH_WINDOW
EXPECT  status(R1.freshness): never_seen -> fresh -> stale; readiness unaffected
```

```text
T-OBS-03  Outage events bounded during flapping
Checks:   §5 journal "Flapping"; accounting "Logs ... rate-limited"
Level:    Integration (ENV)
Blocked:  OD-08 (summary format), OD-12 (TRANSITION_LIMIT, SUMMARY_INTERVAL)
Status:   Ready

ACTION  toggle eth3 50 times in 10 s while sending 10000 datagrams
EXPECT  transition records for B <= TRANSITION_LIMIT per SUMMARY_INTERVAL
        each interval with suppression ends with one summary carrying the suppressed count
        no per-dropped-datagram records
```

```text
T-OBS-04  Outage event emitted with idle input
Checks:   §5 journal "Outage"
Level:    Integration (ENV)
Blocked:  OD-08
Status:   Ready

ACTION  no traffic; link(eth3, down)
EXPECT  events(sink_unavailable) for B within EVENT_LATENCY; fields include event,
        severity, reason, interface, route, sink, destination, old/new state, generation
```

```text
T-OBS-05  Blocked log output does not stall forwarding or recovery
Checks:   §5 journal "Logging isolation", "Overflow and failure", "Record integrity"
Level:    Integration (ENV)
Blocked:  OD-08, OD-12 (LOG_QUEUE)
Status:   Ready

ACTION  harness stops reading the stdout pipe; traffic 1000/s; toggle eth3 down/up
        resume reading after 60 s
EXPECT  DST_A throughput and latency within TOL of baseline
        B recovers after eth3 up despite blocked output
        overflow counter increments; a summary record appears after reading resumes
        every record read is one complete JSON line
```

```text
T-OBS-06  Broken log output does not stop the daemon
Checks:   §5 journal "Overflow and failure"
Level:    Integration (ENV)
Blocked:  OD-08
Status:   Ready

ACTION  harness closes the read end of the stdout pipe
EXPECT  process keeps running (no exit on SIGPIPE); forwarding continues
        write-failure counter increments
```

```text
T-OBS-07  Stalled HTTP clients are bounded
Checks:   §5 health table "Management bounds", "Snapshot isolation"
Level:    Integration (ENV)
Blocked:  OD-12, OD-15 (MAX_CONN, HEADER_TIMEOUT)
Status:   Ready

ACTION  open MAX_CONN + 10 connections sending partial request headers, never finishing;
        meanwhile run traffic, a reload, and an eth3 down/up
EXPECT  forwarding, reload and recovery complete within baseline + TOL
        stalled connections closed after HEADER_TIMEOUT + TOL
        connections over the limit are refused or queued within bounds
```

```text
T-OBS-08  Concurrent scrapes return consistent snapshots
Checks:   §5 "Snapshot isolation"; §4 consistent-snapshot equations
Level:    Integration (ENV)
Blocked:  OD-15
Status:   Ready

ACTION  50 parallel loops fetching /metrics and /status during traffic and reloads
EXPECT  forwarding latency within TOL of baseline; daemon memory bounded
        within each /status snapshot the accounting equations hold
```

## LIFE and LOOP — Startup, validation and local loops

```text
T-LIFE-01  check-config reports every error and touches nothing
Checks:   §6 CLI check-config; validation table
Level:    Integration (ENV) plus unit cases per validation row
Blocked:  OD-09 (schema), OD-12 (ranges)
Status:   Ready

ACTION  mcgw check-config -c bad.yaml, where bad.yaml contains: unknown key, family
        mismatch, broadcast destination (directed and limited), duplicate
        group:port:ingress, SSM group without membership_source, queue budget over
        the allocation budget
EXPECT  exit status nonzero; one error per problem with file:line
        wire(eth0, igmp) shows no joins; no sockets opened
```

```text
T-LIFE-02  Fail-start when a required component cannot initialize
Checks:   §5 startup diagram; OD-01 current position
Level:    Integration (ENV)
Blocked:  OD-01
Status:   Ready

SETUP   sink B constrained to eth3; eth3 absent at start
ACTION  mcgw run
EXPECT  exits nonzero with a diagnostic naming B; notified() contains no READY=1
```

```text
T-LIFE-03  READY and watchdog notifications
Checks:   §5 startup diagram "Notify READY=1"; watchdog progress note
Level:    Integration (ENV)
Blocked:  none
Status:   Ready

ACTION  mcgw run with WATCHDOG_USEC set; leave idle 5 x watchdog interval
EXPECT  READY=1 only after all required resources initialized
        WATCHDOG=1 continues while idle
```

```text
T-LOOP-01  Provable local cycle rejected on load and reload
Checks:   §6 local-loop guard "Static"
Level:    Unit and Integration
Blocked:  gap G6 (definition of a provable local cycle)
Status:   Draft
```

```text
T-LOOP-02  Feedback from a local sink endpoint rejected at runtime
Checks:   §6 local-loop guard "Runtime"
Level:    Integration (ENV)
Blocked:  guard policy (pre-implementation contract)
Status:   Ready

SETUP   sink B bind 10.0.30.1:8930; SRC also holds 10.0.30.1 on s0
ACTION  SRC sends to 239.1.1.1:3000 from 10.0.30.1:8930
EXPECT  nothing forwarded; counter(R1, rejected{self_loop}) == count sent
```

## Lab and qualification stubs

Intent only; each is expanded when lab time is scheduled. Sources point to the
existing checklists.

| ID | Level | Intent | Source |
|---|---|---|---|
| T-LAB-01 | Lab | Membership survives querier/snooping behavior on VLAN 2601 across query intervals | Arch §9 Multicast; Debian/Cisco guides |
| T-LAB-02 | Lab | Two-NIC payload integrity and source selection under route changes | Arch §9 Two-NIC path |
| T-LAB-03 | Lab | Delay, loss, reordering, small MTU and bottleneck separated from local outcomes | Arch §9 Impairments; OD-04 |
| T-LAB-04 | Lab | SIEM parses JSON, alerts on outage/recovery and summaries, including idle input | Arch §9 SIEM; OD-08 |
| T-LAB-05 | Lab | Capacity plan: rates, bursts, fan-out and egress headroom | Arch §9 Capacity plan; OD-03 |
| T-LAB-06 | Lab | Benchmark envelope on an identified 2-vCPU VM | Arch §8 benchmark envelope; OD-07, OD-12 |
| T-LAB-07 | Lab | Service sandbox: dedicated account, demonstrated capabilities, rtnetlink subscription | Deployment; OD-10 |
| T-QUA-01 | Qualification | Debian/Proxmox bridge MDB, VLAN and nftables commands on PVE 9 | Debian guide; `temp2.md` step 7 |
| T-QUA-02 | Qualification | Windows firewall profile save/restore and drop logging on the target build | Windows guide §10; F05 |
| T-QUA-03 | Qualification | RSPAN destination session, and the VM transport-VLAN extension | Cisco guide §7.2; F07 |
| T-QUA-04 | Qualification | Runbook retained captures, tshark decoding and IPv6 commands | Troubleshooting; F13–F15 |
| T-QUA-05 | Qualification | Render every Mermaid diagram in the target viewers | Architecture review conventions |
| T-QUA-06 | Qualification | Cisco snooping/querier commands on the actual switch images | Cisco guide; C1–C3 |

## Traceability

| Contract area | Tests | Gap |
|---|---|---|
| §3 queue: ownership, bounds, queue full, expiry, ordering | T-ISO-02, T-ISO-03, T-ISO-04 | Ownership (immutable copies) is unit-level only |
| §3 isolation | T-ISO-01, T-ISO-02 | — |
| §3 send batches and bounds | T-ACC-07, T-IFR-02 | — |
| §3 offer identity, replacement, reload memory | T-ISO-05, T-RLD-03 | — |
| §4 accounting equations and outcomes | T-ACC-01, T-ACC-02, T-ACC-04, T-OBS-08 | — |
| §4 empty payload, oversize, truncation | T-ACC-03 | Ancillary truncation is unit-level only |
| §4 async errors | T-ACC-06 | — |
| §4 path-size policy | T-ACC-05, T-LAB-03 | — |
| §5 startup and readiness notification | T-LIFE-02, T-LIFE-03 | — |
| §5 interface monitoring | T-IFR-01 .. T-IFR-08 | — |
| §5 reload and shutdown | T-RLD-01 .. T-RLD-07 | G3 |
| §5 health, readiness, freshness | T-OBS-01, T-OBS-02 | — |
| §5 management bounds and snapshot isolation | T-OBS-07, T-OBS-08 | — |
| §5 journal events and logging isolation | T-OBS-03 .. T-OBS-06, T-LAB-04 | — |
| §6 validation and CLI | T-LIFE-01, T-MCI-05 | — |
| §6 receive path and multicast isolation | T-MCI-01 .. T-MCI-06 | — |
| §6 local-loop guard | T-LOOP-01, T-LOOP-02 | G6 |
| §6 trust and amplification (OD-03) | T-LAB-05 | No integration case until rate policy exists |
| Kernel receive overflow observations (OD-06) | — | No case yet: needs an overflow-inducing harness and the reporting decision |
| Service sandbox and privileges (OD-10) | T-LAB-07 | Integration case possible once the unit file exists |
| Management external binding | — | Operator-controlled; covered by the pilot checklist |
| HA (OD-13), output QoS (OD-14) | — | Deferred by decision |

## Blocker summary

Counts the Blocked by entries of the integration and unit cases above. Higher
counts suggest which decisions to resolve first.

| Decision | Cases blocked | Notes |
|---|---|---|
| OD-12 | 13 | Supplies parameters only; cases are fully written with placeholders |
| OD-15 | 10 | Supplies names only; cases are fully written |
| OD-09 | 8 | Decides socket APIs and schema; the MCI results are its evidence |
| OD-11 | 5 | Decides reload serialization and transitions |
| OD-08 | 4 | Logging transport and event fields |
| OD-10 | 3 | Egress enforcement and permissions |
| OD-01, OD-02, OD-04, OD-05, OD-06, OD-07 | 1 each | OD-01/OD-02 current positions are used meanwhile |
| Contract gaps and harness methods | 4 | G6, guard policy, and two harness methods to qualify |

46 cases in total: 41 Ready and 5 Draft; 13 lab and qualification stubs are
listed separately. OD-12 and OD-15 block the most cases
but only supply numbers and names, so the first decisions that change test
behavior are OD-09 and OD-11.

## Contract gaps found

Found while writing cases. Open gaps need an owner decision; resolved gaps keep
their row with the location of the resolution.

| ID | Gap | Affected cases | Status / home |
|---|---|---|---|
| G1 | Rejection precedence: when a datagram fails several checks (e.g. disallowed source and oversize), which single exclusive reason is counted is not defined | T-ACC-02, T-ACC-04 | Resolved 2026-10-17: architecture §4 "Rejection precedence" |
| G2 | `oversize` and `truncated` are both rejection reasons but their difference (configured limit versus read-buffer truncation) is not defined | T-ACC-03 | Resolved 2026-10-17: architecture §4 "Oversize versus truncated"; noted in OD-06 |
| G3 | What `/readyz` reports while a changed route is interrupted during reload is not specified | T-RLD-04, T-RLD-05 | Open: OD-02 / OD-11 |
| G4 | Freshness windows are an optional config field, but no decision owns their default or bounds | T-OBS-02 | Resolved 2026-10-17: values owned by OD-12 |
| G5 | "Bounded transition logs" has no definition of the bound or summary interval | T-OBS-03 | Resolved 2026-10-17: limit shape in architecture §5 "Flapping"; values OD-12, summary format OD-08 |
| G6 | "Provable local configuration cycle" is not defined: routes receive multicast and sinks send unicast, so the configurations that count as a provable cycle need examples | T-LOOP-01 | Open: architecture §6 local-loop guard |
| G7 | Some behavior (control-loop stall for `/healthz` 503, partial batches, netlink overflow) cannot be triggered from outside; whether test-only fault-injection hooks are allowed is undecided | T-ACC-07, T-IFR-08, `/healthz` 503 path | Open: new OD or implementation guideline |
