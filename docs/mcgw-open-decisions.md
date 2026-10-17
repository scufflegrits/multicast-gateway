# mcgw open decisions

**Status:** decision register, 2026-10-16. This records unresolved implementation
choices and proposals needing evidence. It does not authorize implementation or
replace the agreed [architecture](architecture.md).

## How to use this register

| Rule | Meaning |
|---|---|
| Current position applies | Investigating an alternative does not suspend the accepted design |
| Stable IDs | Refer to decisions by OD number across documents and changes |
| Evidence before resolution | Record test results, measurements, sources, and owner clarification as appropriate |
| Resolution | Record chosen option, rationale, date, and authoritative document changes |
| Preserve history | Retain resolved entries; do not delete rejected alternatives |
| Nice-to-haves | Optional improvements v1 can ship without go in the [feature ideas backlog](mcgw-feature-ideas.md), not here |
| Sources | `temp.md` is a review input, not verified authority; validate technical claims using primary sources and selected deployment versions |

| Status | Meaning |
|---|---|
| Open | Needs a decision or evidence; investigation not yet recorded |
| Investigating | Active work is underway, with results tracked in the entry |
| Deferred | Revisit only when the stated requirement/gate arises |
| Resolved | Outcome and rationale recorded and authoritative documents updated |

## Decision index

| ID | Question | Gate | Status |
|---|---|---|---|
| [OD-01](#od-01) | Startup behavior | Before lifecycle implementation | Open |
| [OD-02](#od-02) | Required components and readiness scope | Before config/status implementation | Open |
| [OD-03](#od-03) | Rate ceilings and ingress trust | Before sustained pilot; earlier if policy affects v1 schema | Open |
| [OD-04](#od-04) | PMTU enforcement and fragmentation alternatives | Before send-path implementation | Open |
| [OD-05](#od-05) | UDP socket errors and finite retry policy | Before send-path implementation | Open |
| [OD-06](#od-06) | Receive storage, truncation, and effective socket buffers | Before receive-path implementation | Open |
| [OD-07](#od-07) | Allocation strategy and batching | Before release benchmark; prototype before data-path freeze | Open |
| [OD-08](#od-08) | Journal severity and SIEM ingestion | Before operational logging contract / pilot | Open |
| [OD-09](#od-09) | Multicast isolation and source-selection schema | Before receive/config implementation | Open |
| [OD-10](#od-10) | Egress enforcement and deployment permissions | Before output socket implementation | Open |
| [OD-11](#od-11) | Reload serialization and resource transitions | Before lifecycle implementation | Open |
| [OD-12](#od-12) | Queue, timer, and benchmark defaults | Before schema freeze / release benchmark | Open |
| [OD-13](#od-13) | High availability and duplicate traffic | Before any redundant-site deployment | Deferred |
| [OD-14](#od-14) | Output QoS and hop-limit controls | Confirmed site requirement | Deferred |
| [OD-15](#od-15) | Metrics names and port qualification | Before observability schema freeze | Open |

## OD-01

**Startup behavior**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before lifecycle implementation |
| Current position | Invalid configuration fails startup. Under the accepted design, failure to initialize a required component also fails startup; runtime failures recover with bounded backoff. |
| Options and tradeoffs | Keep fail-start with bounded initialization retries; or start degraded and distinguish process readiness from forwarding readiness. Degraded startup changes the accepted policy. |
| Evidence needed | Late interface/address arrival, unavailable egress, boot without carrier, systemd start timeout/restart limits; verify useful diagnostics without indefinite waiting or restart storms. |
| Context | Architecture §5; review D6 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-02

**Required components and readiness scope**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before config/status implementation |
| Current position | Readiness reflects current local usability of required receivers/sinks, independently of liveness and traffic freshness. “Required” has no frozen configuration definition. Interim rule: every configured ingress receiver and sink is required for aggregate readiness ([architecture §5](architecture.md#health-and-status)); an optional-component policy remains an open alternative. |
| Options and tradeoffs | Treat all configured components as required; or add explicit per-route/per-sink required policy. Optional outputs improve partial-service reporting but add policy complexity. |
| Evidence needed | Define defaults, aggregate HTTP status codes, partial failures, optional-component events, and startup interaction with OD-01. A failed sink must not stop healthy sinks. |
| Context | Architecture §5; review D7 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-03

**Rate ceilings and ingress trust**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before sustained pilot; earlier if policy affects v1 schema |
| Current position | Queues are bounded. Per-sink pacing is conditional, not mandatory; no numeric default ceiling is accepted. Input payloads and source addresses are not authenticated by mcgw. |
| Options and tradeoffs | Operator capacity plan alone; configurable route/sink ceilings; or mandatory default limits. Limits can protect capacity but also drop valid bursts; source allow-lists do not authenticate senders. |
| Evidence needed | Declare ingress trust boundary, fan-out amplification budget, peak packet/byte rates, burst allowance, enforcement point, and counted-drop semantics. Validate network access controls independently. |
| Context | Architecture §§4, 8–9; review D8; temp.md D-1 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-04

**PMTU enforcement and fragmentation alternatives**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before send-path implementation |
| Current position | PMTU-aware output with no deliberate fragmentation or payload splitting. Count locally reported size failures; local acceptance does not prove passage through the WAN. |
| Options and tradeoffs | Select family-specific socket settings that enforce the current policy. Operator-selectable fragmentation is an alternative proposal, not an accepted v1 capability. |
| Evidence needed | IPv4/IPv6 tests with small local/path MTUs, route changes, and missing ICMP feedback. Verify no deliberate fragmentation and honest accounting when a downstream drop is unobservable. |
| Context | Architecture §§4, 8; review D8; temp.md N4 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-05

**UDP socket errors and finite retry policy**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before send-path implementation |
| Current position | Sends are bounded/cancellable. Only accepted whole datagrams count as submitted; asynchronous errors do not retroactively identify an earlier lost packet. |
| Options and tradeoffs | Connected versus unconnected output sockets; separate error-queue processing; immediate terminal failure versus bounded retry for selected errors. No unconditional retry-on-ECONNREFUSED rule is accepted. |
| Evidence needed | Inject local/transient errors and delayed ICMP errors; verify ordering, no duplicate submission, finite completion, and exactly-once terminal offer accounting. |
| Context | Architecture §§3–4, 8; temp.md D-4 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-06

**Receive storage, truncation, and effective socket buffers**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before receive-path implementation |
| Current position | Never forward truncated input. The illustrative receive-queue request is not an established default. Per-datagram read storage and the kernel socket receive queue are different resources. |
| Options and tradeoffs | Full supported-datagram read storage versus limit-sized storage with explicit returned-length/flag handling; define oversize/truncated precedence. Compare requested/effective socket queues and choose warning/failure policy. |
| Evidence needed | Test empty, maximum, oversize, truncated input, ancillary-data truncation, clamped queue requests, and overflow reporting on selected kernels. Do not assume a universal sysctl default or require extra privilege without evidence. |
| Context | Architecture §§4, 6, 8; temp.md N5, N7 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-07

**Allocation strategy and batching**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before release benchmark; prototype before data-path freeze |
| Current position | Start with bounded sink-owned copies. Shared storage, preallocated rings/slabs, and particular batching APIs are not mandatory designs. |
| Options and tradeoffs | Compare bounded pooled copies, simpler allocation, and shared immutable ownership if needed; compare single and batched I/O. Trade throughput against latency, memory, and ownership complexity. |
| Evidence needed | Measure fan-out integrity, allocations, garbage collection, local latency, CPU and memory at the declared benchmark envelope. Verify partial-batch accounting and ordering. |
| Context | Architecture §§3, 8; review D3, D10; temp.md D-6, D-7 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-08

**Journal severity and SIEM ingestion**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before operational logging contract / pilot |
| Current position | Structured JSON goes to stdout/stderr and journal MESSAGE. JSON severity currently does not imply native journal PRIORITY. SIEM parsing is external. |
| Options and tradeoffs | Keep JSON-only severity with explicit collector rules; add systemd-recognized priority prefixes; or use native journal submission. Preserve structured payload parsing across the selected approach. |
| Evidence needed | Test journalctl severity filters, collector JSON parsing, outage/recovery correlation, rate limits/suppression, journal unavailability, and blocked/broken stdout/stderr (logging isolation, architecture §5). Freeze event fields and priority mapping. |
| Context | Architecture §5; temp.md O8 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-09

**Multicast isolation and source-selection schema**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before receive/config implementation |
| Current position | Per-route isolation, IPv4/IPv6 ASM/SSM support, and source filtering are required. Exact socket APIs and the schema separating membership source from application allow-lists remain open. |
| Options and tradeoffs | Prototype group/interface binding, multicast-all controls and ancillary validation under family-specific rules. Preserve isolated route behavior; a different demultiplexing implementation needs explicit rationale. Distinguish SSM range classification from source-specific joins outside those ranges. |
| Evidence needed | Test same-port groups, same-group interfaces, unrelated host joins, wrong-interface injection, source mismatch, permitted local senders, and network membership-version compatibility. Record supported kernels/APIs. |
| Context | Architecture §§3, 6, 8; review D9; temp.md N1, N3, D-3 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-10

**Egress enforcement and deployment permissions**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before output socket implementation |
| Current position | Normal Linux routing or enforced interface constraint; no silent fallback. Dedicated service account and only demonstrated capabilities; host routes/firewalls/sysctls remain operator-managed. |
| Options and tradeoffs | Choose supported Linux egress APIs and minimum capabilities after OS qualification. Establish systemd restrictions, SELinux position, effective buffer checks, and management-access trust boundary. |
| Evidence needed | Competing routes, interface delete/recreate, privilege-denied behavior, source binding, management exposure, and rtnetlink subscriptions under the actual service sandbox. |
| Context | Architecture §§5–6, 8–9; review D2, D11; temp.md O4–O9 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-11

**Reload serialization and resource transitions**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before lifecycle implementation |
| Current position | Unchanged routes continue; changed resources may be interrupted; rollback is best effort. Offers retain original sink identity; overlap fits the allocation budget. Discarded payloads cannot be recovered by rollback. |
| Options and tradeoffs | Serialize and coalesce reload requests or reject concurrent requests visibly. Define requests before startup readiness, changed-instance criteria, bounded old-instance drain, and safe dispatch swaps. |
| Evidence needed | Repeated SIGHUP, half-written/replaced config, failed preparation/rollback, near-budget overlap, sink destination changes, no-op counter continuity, and cleanup of prepared resources. |
| Context | Architecture §§3–5, 8; review D6; temp.md D-9, O12 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-12

**Queue, timer, and benchmark defaults**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before schema freeze / release benchmark |
| Current position | Queues have byte/count/age bounds; deadlines/backoff are finite. Example values are not defaults. Performance is a measured envelope, not a universal guarantee. |
| Options and tradeoffs | Select per-sink bounds, total budget, monotonic age/deadlines, backoff and shutdown durations, logging queue size and flush deadline, and management connection/timeout limits; choose benchmark duration and numeric local-latency target. |
| Evidence needed | Burst and bottleneck tests, idle routes, failures, shutdown, wall-clock changes, identified VM/OS/NIC, generator/receiver loss separation, and realistic fan-out. |
| Context | Architecture §8; review D8, D10 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-13

**High availability and duplicate traffic**

| Field | Record |
|---|---|
| Status | Deferred |
| Decision gate | Before any redundant-site deployment |
| Current position | No built-in HA mechanism is specified for v1. Independent gateways and arbitrary payloads provide no universal deduplication guarantee. |
| Options and tradeoffs | State single-instance availability limits; investigate operator-managed active/standby if needed. Active/active can duplicate traffic and requires an explicit receiver/deployment contract; no keepalived/VRRP design is accepted. |
| Evidence needed | Confirmed availability requirement, failover ownership/fencing, duplicate/loss tolerance, membership recovery, source endpoint continuity, and split-brain tests. |
| Context | Architecture scope; temp.md D-5 |
| Investigation results | Not yet recorded |
| Resolution | Pending; current position remains in force |

## OD-14

**Output QoS and hop-limit controls**

| Field | Record |
|---|---|
| Status | Deferred |
| Decision gate | Confirmed site QoS/path requirement |
| Current position | No per-sink DSCP or TTL/hop-limit configuration is promised for v1 |
| Options and tradeoffs | Add controls where a measured network policy requires them; more config and validation versus operational utility |
| Evidence needed | Traffic-class policy, required values, OS/API behavior and interoperability tests |
| Resolution | Pending; do not infer defaults from inbound headers |

## OD-15

**Metrics names and listener-port qualification**

| Field | Record |
|---|---|
| Status | Open |
| Decision gate | Before observability schema freeze |
| Current position | Counter/reason names illustrative; HTTP listener 127.0.0.1:9310 is the agreed proposed default |
| Options and tradeoffs | Follow Prometheus naming conventions (mcgw prefix, counter totals, units) and verify port allocation/coexistence before freezing |
| Evidence needed | Official Prometheus conventions/port registry check; bounded label and reset tests; status/HTTP fixtures; stalled-client and concurrent-scrape fault injection during traffic, reload and recovery |
| Resolution | Pending; no claim of exclusive registered port ownership |

## Deferred feature design

TCP framing/client policy, recording, RTP inspection, production replay,
multicast/broadcast sinks, cross-family forwarding, and relay remain governed by
the architecture's [deferred capability table](architecture.md#10-deferred-capabilities).
Create individual decision entries when a feature is proposed for development;
its appearance on that list is not approval to implement it.

## Related documents

| Document | Responsibility |
|---|---|
| [Architecture](architecture.md) | Current agreed design and behavioral contracts |
| [Architecture review](architecture-review.md) | Historical findings, accepted recommendations, and supporting sources |
| [Documentation guide](README.md) | Reader navigation and project overview |
