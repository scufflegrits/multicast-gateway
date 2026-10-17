# mcgw architecture review

Status: historical design review. The owner concurred with the reviewer
responses for D1–D12 and subsequently accepted the independent review fixes.
`architecture.md` is authoritative for current scope and contracts. Original
proposals below are retained as history, including superseded executive wording;
prototype choices and numeric defaults remain open. This records design
acceptance, not authorization to implement the daemon.
Online technical references are collected in Appendix A and cited by source ID.

## 1. Executive assessment

The core direction is sound: a Linux service with isolated multicast receivers,
payload-preserving forwarding, independently bounded consumers, and operational
visibility. Go is a reasonable starting implementation. The most important work
before implementation is defining the observable forwarding contract and failure
behavior. A rewrite decision should follow measurement, not precede it.

The draft currently promises more than it specifies. In particular, “delivered,”
“no silent failures,” and “loops are prevented” overstate what the proposed
mechanisms can establish. Reload, TCP buffering, socket isolation, and health
also need concrete contracts before their diagrams become implementation rules.

Recommended next step: resolve the P0 decisions below, then run small networking
and failure-injection experiments. Keep recording, protocol inspection, relay,
and broad replay-format support out of the first forwarding milestone.

### Confirmed deployment inputs

- A few separate sites; no workload measurements yet.
- Commercial WAN paths can change and have variable delay. Some sites have
  persistently high latency; others have low latency. Jitter is expected.
- No wireless links.
- Possible equipment: Cisco C8570-G2, IOS XE 17.18.x; Cisco 9300/9400,
  versions 17.18.4 / 17.15.6; Palo Alto firewalls, models/versions unspecified.
  These are deployment inputs, not a validated compatibility matrix.
- Receiving on one interface and sending through another must be supported.
  Historical clarification: separate NICs are not mandatory; same-interface operation is also supported.
- Confirmation concerns mcgw receiving and forwarding a datagram to its local
  outbound transport. It does not require proof of host egress, destination
  receipt, or processing by a destination application.
- No cooperating destination receiver or acknowledgment protocol is required.

### Proposed executive section for architecture.md

**Historical, superseded proposal:** the executive section in architecture.md
is authoritative. The original text below is retained for review history; its
conditional TCP scope is no longer current.

> mcgw is a Linux service that joins configured IPv4 and IPv6 multicast groups
> and forwards received UDP payloads to configured unicast destinations. Each
> route can serve multiple destinations. Ingress and egress can use different
> network interfaces. Deployments operate independently at separate sites.
>
> The initial release provides UDP forwarding, operational counters, route and
> sink status, configuration validation, controlled reload, and systemd
> integration. TCP forwarding provides framed datagrams to compatible clients
> if retained in the initial release. Recording, protocol inspection, and local
> status tooling are planned extensions; replay is a separate validation tool
> whose initial format support must be agreed before implementation.
>
> mcgw preserves UDP payload bytes. It creates new outbound transport packets;
> it does not preserve original IP headers, source endpoints, or multicast
> delivery semantics at the destination. It does not provide bidirectional
> discovery relay, multicast routing, WAN path selection, jitter smoothing,
> original sender-order recovery, or guaranteed destination delivery.
>
> Forwarding success means local socket acceptance: a complete UDP datagram,
> or a complete framed datagram written to a TCP socket. TCP queue admission
> is reported separately. Success does not prove that traffic left the host,
> arrived at the destination, or was processed there. Counters describe
> observable application outcomes and available kernel drop information;
> they cannot account for every packet lost before application receipt.
>
> WAN delay, reordering, outages, path MTU limits, firewall policy, and
> multicast membership infrastructure can affect service. mcgw adds no
> intentional UDP reordering or retransmission. Slow TCP clients can accumulate
> delay and lose queued frames under the configured bounded-queue policy.
> Each destination has separate outcomes; one destination's success does not
> imply another's success. Performance limits will be established through
> repeatable tests, including fan-out and degraded network conditions.

Owner response on executive scope/text: direction accepted; superseded by the executive section in architecture.md.

## 2. Decisions required before the forwarding implementation

P0 means settle the contract before building the affected path. P1 means settle
before a site pilot. P2 means defer unless a confirmed use case requires it.
Each finding includes my proposed decision and justification under “Reviewer
response,” followed by an owner response field for acceptance, revision, or
deferral. Reviewer responses below were subsequently accepted by the owner. Exact
resource and timeout defaults remain to be measured before schema freeze.

### D1 — P0: Define forwarding success and packet accounting

**Draft:** sections 2–3 and the design principles imply every packet has a
single delivery/drop outcome. Fan-out gives one input several independent
outcomes, and failures before application receipt are not fully observable.

**Failure scenario:** one datagram reaches three UDP destinations; two sends
succeed and one fails. A route-level “sent” count can conceal the failing sink.
A TCP queue accepts a frame, but the client disconnects before it is written.
Counting enqueue as forwarding would falsely report success.

**Recommendation:** define the following per configuration generation and stable
route/sink identifiers:

- Received datagrams and payload bytes at the application boundary.
- Exclusive route rejection reasons before fan-out, including truncated input.
- Per UDP destination: offers, successful whole-datagram socket submissions,
  failed submissions, queue drops if queued, and pending work.
- Per TCP client: offers, queued frames, complete frame writes, queued drops,
  and failed/abandoned frames. A partially written frame is not complete.
- A separate “no TCP clients” outcome, rather than silently treating an empty
  listener as a successful delivery.
- Kernel receive-overflow observations separately from application drops.
  Socket overflow reports do not describe all host or upstream losses. [S2]

Use “submitted” or explicitly defined “forwarded,” rather than unqualified
“delivered.” Successful send does not establish remote delivery. [S1] Aggregate
counters are operational accounting, not a durable per-packet audit trail.
Ask separately whether individual packet receipts are ever needed; do not add
per-packet logging by default.

At a quiescent snapshot, require `received = rejected + fanout_accepted` and,
for each UDP destination, `offered = submitted + failed + dropped + pending`.
TCP accounting must include queued and in-progress frames without double
counting; asynchronous network errors are events, not automatically losses of
identifiable earlier packets. Restarts reset process-local counters.

**Acceptance:** inject numbered payloads and force one sink failure. The healthy
sink continues, and counters reconcile after draining. Exercise partial batch
sends: only the returned successful prefix counts as submitted. [S3]

**Reviewer response — accept; make this the primary contract.** I would use
`udp_submitted_packets` for successful local socket submissions, with payload
bytes counted separately. Give each configured destination a stable sink ID.
Keep configuration generation in status/events rather than an ever-growing
Prometheus label; preserve counters across unchanged-route reloads. Distinguish
submission failures from later asynchronous error observations. Publish
aggregate outcomes by default; add neither destination acknowledgments nor a
persistent per-packet journal.

**Justification:** this meets the confirmed confirmation requirement with
observable evidence and keeps one successful destination from masking another's
failure. A generation label or arbitrary client/source labels would create
unnecessary metric cardinality. Reconciliation checks should use a drained
snapshot or consistent internal snapshot, since independent live counter reads
can temporarily disagree. [S1–S3]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D2 — P0: Make outbound routing behavior explicit

**Draft:** the example permits source binding, but `interface` is described
mostly as groundwork for future multicast sinks. Separate ingress and egress
is a current requirement.

**Failure scenario:** the multicast join uses eth0 while the host's default
route sends unicast through an unintended interface. Binding a source address
alone is mistaken for enforcing a particular egress device.

**Recommendation:** define two supported modes: normal Linux route selection,
and explicitly constrained egress. Specify sink source address/port, optional
egress interface, IPv6 scope handling, required privileges, and behavior if
the interface disappears. Validate family compatibility. If cross-family
payload forwarding is supported, say so and test it; otherwise reject it.
Expose configured bindings and actual local socket endpoints in status.
Device constraint does not supply a route or override firewall policy.
Inspect host policy routing and reverse-path filtering when validating
asymmetric deployments; avoid automatically changing host sysctls. [S4, S5]

**Acceptance:** use two interfaces and competing routes in network namespaces;
verify receiver-side payloads and test interface-down and route-change behavior.
Keep privileged test setup separate from daemon privilege requirements.

**Reviewer response — accept both routing modes for v1.** Default to Linux
routing, with optional source binding and an explicit sink `egress_interface`
constraint. When configured, enforce that constraint or fail the sink visibly;
never silently fall back to another interface. Keep ingress interface selection
independent. Expose the effective local endpoint after socket setup. For the
first release, support same-family forwarding and reject cross-family sinks;
reconsider cross-family forwarding when a deployment requires it.

**Justification:** two-interface operation is a stated requirement, while host
routing remains useful for ordinary deployments. Explicit constraint semantics
prevent operators from mistaking source binding for interface enforcement.
Same-family support reduces the initial validation/MTU matrix without blocking
the confirmed use case. The exact Linux enforcement API and capabilities should
be selected in the D9 prototype, not guessed in the config contract. [S2, S4, S5]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D3 — P0: Specify buffer ownership and isolation for every consumer

**Draft:** “one shared buffer” and bounded queues do not specify who owns the
buffer after receive storage is reused. Only TCP and recording explicitly have
queue bounds; UDP and inspector isolation are asserted without a mechanism.

**Failure scenario:** a slow consumer reads bytes overwritten by the next
receive; alternatively, retained shared buffers exhaust memory. A UDP send
stall or inline inspector delays every other sink.

**Recommendation:** make accepted payloads immutable until all users release
them. Choose explicit reference ownership or bounded copies after a small
prototype. Bound every asynchronous queue by bytes and frames, cap clients,
and define total process memory limits. Give UDP destinations independent
failure/queue behavior. Inspector processing must be asynchronous or have a
strictly bounded inline cost; a plugin cannot be allowed to block indefinitely.
Counters should be cheap; logs should summarize/rate-limit repeated failures.
Replace “every error is logged” with counted outcomes plus bounded event logs.

**Acceptance:** force a slow sink and a stalled inspector; fast receivers retain
correct bytes, bounded latency, and bounded process memory. Test buffer reuse
with payload integrity checks and the implementation's race tooling.

**Reviewer response — accept; start with bounded copies.** Copy accepted
payloads into independently owned sink queue entries for the first prototype.
Use one ordered worker per UDP destination, bounded by bytes and frames; drop
the new offer when its queue is full. Do not let a failed destination stop the
others. Set an explicit total queue allocation budget and reject configurations
whose declared queue budgets exceed it. Document receive buffers, socket buffers,
and runtime overhead separately from that budget. Future inspectors use their
own bounded sample queues.

**Justification:** copying is easier to verify than shared buffer lifetimes and
allows straightforward accounting and isolation. It costs memory bandwidth, so
measure it under fan-out before committing to optimization. Replace copies with
immutable reference-counted storage only if profiling shows a material need.
A queue budget alone is not a guarantee about total resident memory. UDP
queue-full drop-new is a deliberate initial policy, not a claim that it suits
every freshness-sensitive workload.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D4 — P0: Finish the TCP contract before promising TCP compatibility

**Draft:** framing is explicitly undefined, while drop-oldest and flushing are
already promised. TCP clients connect to mcgw; it does not currently dial an
arbitrary destination TCP service.

**Failure scenario:** a high-delay or slow-reading client accumulates stale
frames. Evicting a frame after writing part of it corrupts stream framing.
A shutdown waits indefinitely for a client that stopped reading.

**Recommendation:** decide whether TCP is necessary for the first release.
If retained, define a versioned framing contract before coding: length width,
byte order, payload limit, zero-length datagrams, metadata presence, and
compatibility expectations. Provide a reference decoder/fixture. Drop only
whole frames that have not started writing. Specify a write deadline and close
the connection on an unfinished frame that cannot complete. Cap clients,
queued bytes/frames, and queue age; define disconnect and bounded shutdown
behavior. Users need a compatible framed-stream client.

TCP maintains ordered bytes through retransmission; it can trade loss for
additional waiting. Do not claim it fixes WAN jitter or keeps data fresh.
Local write completion remains the reporting boundary. [S1, S6]

**Acceptance:** test slow reads, no reads, partial writes, reconnects, queue
expiry, zero clients, and termination during a partial frame. A decoder must
never receive a malformed stream followed by purportedly valid frames.

**Reviewer response — defer TCP from the initial forwarding release.** Keep it
on the roadmap as a framed-stream listener for compatible clients, rather than
promise compatibility with generic TCP applications. Before adding it, specify
a versioned protocol and reference decoder. My starting proposal is a documented
version-1 format with a four-byte unsigned network-order payload length,
payload-only frames, explicit zero-length support, and a configured payload cap.
Do not infer future versions from payload bytes; specify version selection
before freezing the protocol.

**Justification:** no confirmed destination requires TCP, and it adds client
lifecycle, framing, slow-reader, and shutdown obligations to the critical path.
When introduced, use bounded queues with drop-oldest only for unstarted frames,
queue-age limits, and connection closure on an incomplete-frame deadline.
These are future decisions, not features to partially implement in v1. [S1, S6]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D5 — P0: Replace absolute loop prevention with a defensible boundary

**Draft:** static validation plus matching source endpoints is presented as
preventing network loops. It also conflates receiver policy with the multicast
loopback option on an outbound socket.

**Failure scenario:** another gateway reflects payloads using a different
source endpoint, or NAT changes it. Neither local check detects the cycle.
An unspecified/ephemeral bind cannot be compared as a concrete endpoint until
the socket has been assigned one. Conversely, a shared source tuple may
identify a legitimate local sender rather than a reflected packet.

**Recommendation:** reject demonstrable local configuration cycles and document
that arbitrary multi-site reflection is outside the guarantee. Define actual
socket endpoint registration, wildcard handling, reload overlap, and permitted
same-host senders. Keep local endpoint filtering as a narrowly described guard.
Do not introduce payload hashes as a universal fix: identical payloads can be
legitimate. Payload-agnostic forwarding has no reliable universal packet ID.
Multicast loopback options concern locally transmitted multicast; they do not
provide general protection for the current unicast sink path. [S11]

**Acceptance:** demonstrate direct local feedback and an external reflector
with changed source endpoints. Document what is blocked and what is not.
Also revisit “no sink bind accepted by a source filter”: unrestricted sources
must not make all legitimate local source binds invalid.

**Reviewer response — revise the guarantee and narrow the runtime guard.**
Describe v1 as preventing identified local configuration loops and detecting
specific local-source feedback. Reject provable loops, not every sink bind that
an unrestricted source filter could accept. Maintain actual local UDP endpoints
for the guard; resolve wildcard addresses against relevant local addresses and
update that set when interfaces change. Document potential false positives for
legitimate local senders and an explicit way to configure that policy.

**Justification:** the current static source-filter rule could reject ordinary
any-source routes, while the broader prevention claim cannot cover reflectors
that change source endpoints. Keep multicast/broadcast sinks deferred. Require
operators to avoid external forwarding cycles; payload hashing or opaque-payload
sequence invention would introduce new correctness problems. Treat local tuple
matching as a diagnostic guard, not a security boundary. [S11]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D6 — P0: Define what reload can guarantee after runtime failure

**Draft:** invalid config keeps old routes, but valid config is assumed to
activate successfully. Validation cannot reserve every runtime resource.

**Failure scenario:** parsing succeeds, but a new TCP listener cannot bind.
A replacement multicast socket needs the same resources as the old socket;
starting first can duplicate packets, while stopping first creates a gap.

**Recommendation:** define prepare/apply/rollback behavior and distinguish
validation success from activation success. Keep unaffected routes running.
Report desired and active configuration generations and route failures.
For changes sharing sockets/listeners, specify a controlled interruption or
safe resource reuse; do not promise lossless atomic replacement without proof.
If rollback fails, expose degraded state. Define whether a failed startup exits
or enters retry mode, and when systemd readiness is sent.

**Acceptance:** reload with an occupied port, vanished interface, and forced
join failure. Verify active config reporting, unchanged-route continuity,
rollback behavior, and absence of accidental duplicate forwarding.

**Reviewer response — accept controlled interruption for changed routes.**
Perform full validation first and prepare independent resources where safe.
Leave unchanged routes running. For conflicting replacements, stop the affected
route, activate its replacement, and attempt restoration on failure. Report
per-route active generation and any mixed/degraded result; do not report a
single successful global activation when only part applied. Reuse the same
receiver for sink-only changes where a tested dispatch swap permits it.

**Justification:** an honest, bounded interruption is preferable to an unproven
lossless reload promise. On initial startup I would fail and exit if any required
route cannot initialize, sending readiness only after all required routes are
ready. After successful startup, runtime failures should retry with capped
backoff and remain visible. Add a configurable shutdown deadline; count abandoned
queued work rather than wait indefinitely. Decide exact timeout defaults during
prototype testing, before releasing the schema.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

## 3. Decisions required before a site pilot

### D7 — P1: Separate traffic freshness, receiver readiness, and sink health

**Draft:** a route becomes Active only on its first packet; Joining has no idle
timeout. `/healthz` remains successful with stale traffic or all sinks failing.
A stale route automatically rejoins, even when the sender is simply quiet.

**Recommendation:** expose process liveness, configured receiver readiness,
traffic freshness, and per-sink state separately. Start freshness timing when
the join succeeds, even if no first packet arrives. Allow intentionally idle
routes and configure freshness expectations per route. A stale input cannot
prove membership failure. Make rejoins optional, rate-limited, and backed off;
report attempts and results. Do not change timers merely because a site's
baseline WAN latency is high. The relevant values are traffic cadence, tolerated
gaps, and where the multicast source sits relative to mcgw.

**Acceptance:** quiet sender, never-active route, failed sink with healthy
input, interface loss, and restored traffic all yield distinguishable status.
Verify watchdog work reflects useful daemon progress, not just a timer thread.

**Reviewer response — accept separate health dimensions; disable automatic
stale-triggered rejoin by default.** Define `/healthz` as process/control-loop
liveness and `/readyz` as required receiver/sink initialization readiness. Report
traffic freshness independently, disabled unless an operator sets an expected
traffic interval. UDP sink readiness means local setup succeeded; last submission
and recent errors remain separate evidence, with remote reachability unknown.
Expose never-seen traffic explicitly.

**Justification:** silence is valid for event-driven feeds and cannot diagnose a
lost join. Restarting or rejoining because a sender is quiet adds disruption
without evidence. Recover known socket/interface failures with bounded backoff;
keep stale-based rejoin an explicit opt-in recovery experiment. Neither endpoint
should imply destination delivery. For future TCP, zero clients is a distinct
state whose effect on readiness requires an explicit policy.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D8 — P1: Define WAN behavior, MTU policy, and overload policy

The draft's “no reordering” should mean mcgw preserves the observed receive
order within each route/sink where packets survive. WAN traffic can already be
out of order. mcgw cannot infer original order for arbitrary payloads.
RTP gaps need bounded sequence tracking by source/SSRC, distinguishing reordered,
duplicate, late, and provisionally missing packets. Wraparound and restart must
be handled. RTP jitter uses sender timing information; one-way path latency is
not generally measurable from an opaque payload. [S7]

A 9000-byte accepted payload may not fit the outbound WAN path. Specify
`max_datagram` as UDP payload bytes, truncation handling, and fragmentation/PMTU
policy for both families. Count oversized/truncated input without forwarding
partial payloads. Count outbound size failures separately. IPv4 and IPv6 header
budgets differ, and encapsulation can reduce usable path MTU. [S8, S9]

High latency alone does not establish congestion. Available capacity, offered
rate, loss, and queueing matter. Fan-out multiplies traffic: 100 Mbps received
with four UDP destinations is roughly 400 Mbps payload output. Bounded buffering
cannot sustain an overloaded WAN. Define UDP drop/pacing policy and ownership of
capacity planning; avoid unlimited retries or catch-up bursts after outages.
UDP congestion guidance is relevant even on provisioned commercial links. [S10]
No acknowledgment protocol is proposed here; it would add traffic and a new
protocol without meeting a confirmed requirement.

**Acceptance:** emulate several delay/loss/reordering profiles, path changes,
smaller MTUs, and an egress bottleneck. Values are experiment inputs, not claimed
site measurements. Verify payload integrity, accounting, queue age, memory, and
fast-sink isolation. mcgw adds no intentional UDP reorder buffer.

**Reviewer response — accept transparent, bounded UDP forwarding.** Preserve
observed per-route order among surviving offers to each destination. Add no
reordering, retransmission, or outage backlog. Drop expired unstarted queue
entries using monotonic age, and count queue-full, expired, oversize, truncated,
and send-size failures distinctly. Use PMTU-aware sends and do not deliberately
fragment or split an application datagram to make it fit. Verify the chosen
IPv4/IPv6 socket settings in the prototype. Keep the input payload limit separate
from any destination size constraint.

**Justification:** opaque payloads cannot safely be resequenced or split, and
stale catch-up traffic can worsen an outage recovery. A 9000-byte receive ceiling
must not advertise WAN compatibility. Require an operator-declared capacity plan
before sustained deployment; offer explicit per-sink rate limits with counted
drops if needed, but do not call fixed pacing adaptive congestion control.
Select queue age/rate defaults from tests and site needs rather than inventing
workload figures. [S7–S10]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D9 — P1: Prove IPv4/IPv6 socket isolation and clarify address validation

**Draft:** IPv4-specific socket options appear in a family-neutral diagram.
One group/port/interface tuple is assumed isolated without a testable socket
recipe. The SSM validation rule needs a precise IPv6 prefix definition rather than
the shorthand `ff3x::`, with a clear distinction between address scope and
source-specific membership.

**Recommendation:** specify bind/reuse policy, membership interface, destination
and interface ancillary-data checks, any-source/SSM APIs, and family-specific
options. Do not imply an IPv4 option establishes IPv6 behavior. Distinguish SSM
membership from a userspace source allow-list. Normalize interface names and
address aliases before duplicate checks. Define link-local zones, mapped IPv4
addresses, listener wildcard conflicts, and scoped multicast validation. [S4,
S11] Reject TCP/metrics address conflicts when they cannot coexist, rather than
merely warning. Directed broadcast rejection depends on prefix/routing context;
rejecting every address ending in `.255` is not valid general validation.

**Acceptance:** different groups on the same port, the same group on different
interfaces, unrelated local joins, wrong-interface injection, and SSM source
mismatch for both families. Run against the selected Debian/RHEL kernels.

**Reviewer response — accept; make the socket prototype a release gate.**
Require family-specific membership setup plus verification of destination group
and ingress interface on received datagrams. Specify socket reuse only as needed
for tested isolation; do not assume socket reuse load-balances multicast; test co-bound delivery and reload duplication explicitly.
Test both ASM and SSM on named Debian/RHEL versions before declaring them
supported. Canonicalize addresses/interfaces before comparing duplicate routes,
and reject listener conflicts that cannot bind together.

**Justification:** logical route keys do not by themselves isolate kernel socket
delivery. Ancillary-data checks provide an additional application boundary,
while membership filtering and receive-overflow measurements remain necessary
for load behavior. Reject unsupported scope/address combinations explicitly;
do not silently weaken an SSM request into ASM plus a userspace filter. Address
classification and socket behavior belong in black-box tests, not only parser
unit tests. [S4, S11]

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D10 — P1: Replace the performance promise with a benchmark envelope

“1 Gbps / 100k packets per second” needs clarification: simultaneous targets
imply approximately 1250 payload bytes per packet if Gbps counts payload bytes.
Neither a CPU count nor aggregate input alone defines resource demand.

**Recommendation:** retain these as provisional targets, then specify packet
size distribution, group count, fan-out, TCP clients, enabled features, VM CPU
model, memory, kernel, NIC, test duration, and egress capacity. Measure CPU,
memory, allocation/GC behavior, receive overflow, sink losses, and receive-to-
submission latency percentiles. Include bursts and idle routes alongside steady
traffic. Require zero unexplained loss in a declared healthy test envelope;
expected policy drops under overload remain visible. Instrumentation and log
volume belong in that envelope.

A Go failure should trigger profiling and correction of routing, socket, queue,
or allocation bottlenecks before considering Rust. A rewrite does not fix an
oversubscribed link or a faulty success contract.

**Acceptance:** publish reproducible results for one sink, several sinks, a slow
TCP client, and all required first-release features. Generator/receiver loss
must be distinguished from mcgw application losses.

**Reviewer response — retain the numbers as an aspirational benchmark case,
not a release-wide guarantee.** Use 1 Gbps of UDP payload at 100k packets/s as
one precisely described case, then test smaller datagrams, increasing fan-out,
more groups, bursts, and idle routes separately. Start with UDP-only Go results
on a fully identified 2-vCPU VM. Record generator and receiver evidence alongside
mcgw counters, and publish both healthy limits and overload behavior.

**Justification:** there are no measured site requirements yet, so a universal
zero-drop promise would be arbitrary. Input throughput can conceal output
saturation. Set a numeric local forwarding latency criterion before the release
benchmark, once prototype measurements and operational needs inform it. Do not
use WAN end-to-end delay as mcgw processing latency. Consider Rust only after
profiling establishes that a Go-specific limitation prevents an agreed target.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

### D11 — P1: Document the host and network deployment boundary

mcgw is an application receiver/sender, not a multicast router. Ordinary
multicast reception plus unicast transmission should not require enabling host
IP forwarding. Specify required service privileges and narrowly scoped
capabilities after choosing socket APIs. Protect the local API with filesystem
permissions; decide who can reach TCP and metrics listeners. A wildcard TCP
listener exposes forwarded data to any client permitted by network policy.

For each site, record ingress VLAN/interface, multicast sources/groups,
IGMP/MLD membership and querier behavior, routed multicast dependencies if any,
unicast routes, firewall rules, return routing for TCP, and path MTU. Confirm
actual Palo Alto details later. Test the stated Cisco software combinations in
the lab rather than asserting support from model names alone. No vendor-specific
compatibility or defect conclusion is made in this review.

**Acceptance:** a deployment checklist and one representative site test establish
joins, payload receipt, source/egress selection, firewall behavior, route changes,
and recovery after interface/network interruption.

**Reviewer response — accept a small deployment contract for every site.**
Run as a dedicated service account and add only capabilities demonstrated to be
needed by the selected APIs. Bind metrics/status to loopback by default; allow
an explicit management address for external scraping. Do not expose an
unauthenticated management API on the WAN. Keep host routes, multicast network
configuration, and firewall policy operator-managed, with effective settings
recorded in the deployment checklist.

**Justification:** deployments depend on network and host configuration that the
daemon should not silently rewrite. Start qualification with one representative
lab topology using the specified Cisco platforms/software; add each site's
actual firewall and routing differences before its pilot. Record tested
combinations rather than claim blanket vendor support. This keeps deployment
repeatable without requiring a central controller or destination receiver.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

## 4. Scope and document consistency

### D12 — P1/P2: Choose one first-release feature list

Sections 1–6 show recording, inspector, status CLI, and API as normal behavior;
section 8 defers them to v1.x, and section 7 omits the status commands. Readers
cannot tell what an initial install actually provides.

**Recommendation:** agree on a release table and use it consistently in every
diagram, example, and executive paragraph. First forwarding milestone: config,
IPv4/IPv6 receiving, UDP sinks, outcome metrics/status, lifecycle management,
and integration tests. Decide TCP explicitly under D4. Keep a small replay tool
if needed for testing; full pcapng/link-type support need not gate forwarding.
Retain a minimal operational status path even if the richer local API is later.

For later recording, define captured metadata, timestamp origin, link type,
checksums/synthetic headers, and whether capture represents received or filtered
traffic. Define disk-full/permission failures, retention scope, crash recovery,
and whether “written” means buffered write or durable sync. Recording is not
literally replay's inverse if original network headers were never captured.

For replay, specify offline behavior: it should not accidentally join live groups,
collide with daemon listeners, or mix live input into replay results. Define
ambiguous group/port matches across interfaces, malformed/truncated captures,
fragments, speed validation, and timestamp regressions. A dry run must not bind
forwarding listeners, send packets, or create recording output.

TCP framing, metric names, config schema, and lifecycle behavior should become
small language-neutral contracts first. Do not design unused sink fields solely
to support speculative future features. Add future capabilities behind explicit
schema changes once their behavior is understood.

**Reviewer response — choose a UDP-first v1 and defer the rest explicitly.**
Include IPv4/IPv6 ASM and SSM receiving, unicast UDP sinks, explicit egress,
source/size filtering, bounded queues, local-loop guards, outcome metrics,
minimal route/sink status, validation, controlled reload, systemd lifecycle,
and black-box tests. Provide minimal read-only status over the same protected
HTTP listener as metrics, rather than require a Unix API and CLI in the first
milestone. Define its small JSON contract before implementation.

Defer TCP, recording/rotation, RTP inspection, richer local API/CLI, relay,
multicast/broadcast sinks, and production replay breadth. Use a test-only UDP
fixture sender initially; if a standalone replay command is needed next, begin
with an explicitly limited classic-pcap format and reject unsupported inputs.
Do not advertise the current full replay contract as implemented v1 scope.

**Justification:** this covers the confirmed forwarding and visibility needs
while concentrating testing on packet correctness and site behavior. The removed
features remain useful extensions, but none has a confirmed first deployment
requirement. Update the proposed executive text and all diagrams to this release
table only after owner acceptance; its present conditional TCP wording remains
a review placeholder.

Owner response: concurred with the reviewer response; see architecture.md for the current contract.

## 5. Ordered action plan

| Step | Concrete output | Completion condition |
|---|---|---|
| 1. Owner reviews this document | Responses on D1–D12 and proposed executive text | Accepted, revised, or deferred decisions are explicit |
| 2. Update the architecture | Agreed executive section, release table, corrected guarantees and diagrams | No conflicting feature scope or undefined success claims |
| 3. Write minimal contracts | Accounting, config/egress, queue ownership, lifecycle, TCP framing if retained | Each P0 decision has observable acceptance behavior |
| 4. Run focused prototypes | Socket isolation, two-interface egress, slow-sink isolation, reload conflicts | Results recorded; failed assumptions revise the design |
| 5. Build forwarding milestone | Small working daemon and black-box integration suite | Required IPv4/IPv6 paths pass outcome and failure tests |
| 6. Benchmark and pilot | Reproducible performance report and site checklist | Measured limits and deployment dependencies are documented |
| 7. Extend by priority | Recording, inspection, fuller replay/API | Each extension preserves forwarding isolation and accounting |

Steps 1–2 are complete for the accepted design and subsequent documentation
updates. Steps 3–7 remain future implementation/validation work; unresolved
contracts are tracked in mcgw-open-decisions.md. This is not an implementation
completion claim.
No workload numbers are required to make the contract decisions. Site inventory
and a small traffic sample can refine the benchmark envelope later.

## 6. Follow-up review dispositions

Source: repository-root `temp.md`, reviewing commit `03a3443`. The owner accepted
the follow-up assessment: document agreed clarifications and investigate proposals
without silently replacing accepted policies. IDs below correspond to that input;
the summary/top-issue tables and suggested work order repeat these findings.

**Addressed means given a disposition, not proven or implemented.** Documented
changes are complete; tracked/deferred entries require the linked evidence/gate.
`temp.md` is left unchanged as the original input. Its severity labels and
technical assertions are not adopted automatically.

### Accepted independent-review record

| Accepted finding | Documentation result |
|---|---|
| Bounded sends and original sink ownership | Send deadlines/cancellation, no retargeting, bounded drain/abandonment |
| Reload overlap and counter continuity | All simultaneous resource generations budgeted; unchanged counters survive reload |
| Management boundary | No built-in HTTP auth/TLS; external controls and loopback trust limits |
| Test boundaries | Empty/max/oversize datagrams and interface deletion/recreation |
| Presentation/traceability | Provisional metric names, repeated-route illustration, legend meanings, TCP listener direction, terminology, recorded concurrence |
| Additional owner decisions | rtnetlink monitoring and SIEM events; separate-NIC support without a separate-NIC requirement; draw-first guidance and layperson docs |

### Finding-by-finding disposition

| Finding IDs | Disposition | Location / follow-up | Rationale / action |
|---|---|---|---|
| N1, D-3 | Documented; API validation open | Architecture receive-path contract; OD-09 | Require unrelated-delivery suppression plus ancillary validation; qualify exact family controls. No unverified Go API claim adopted. |
| N2, O3 | Documented | Deployment prerequisites; troubleshooting host checks | Ingress firewall and effective IPv4 rp_filter checks included; no universal RHEL default asserted. |
| N3 | Documented; schema open | Architecture config; deployment; OD-09 | Separate source membership and allow-list; source-specific example uses 232/8; verify versions/infrastructure. No universal PIM/RP requirement inferred from an address alone. |
| N4 | Qualified; tracked | Architecture WAN policy; deployment; OD-04 | Enforce current no-deliberate-fragmentation policy with tested settings; defaults are not the contract. Missing ICMP may conceal downstream drops. Fragmentation option not adopted. |
| N5, O5 | Documented; thresholds open | Deployment prerequisites; OD-06/OD-10 | Requested/effective buffers, queue caps, overflow and membership limits; no universal numeric default or automatic sysctl change. |
| N6 | Documented; vendor claim not adopted | Troubleshooting other symptoms; deployment | Investigate querier/snooping age-out; exact timer and Cat9k defaults must be verified against deployed versions/configuration. |
| N7 | Qualified; tracked | OD-06 | Distinguish per-datagram read storage from socket queue; evaluate returned lengths/flags. A 65535-byte read buffer is not declared the only valid design. |
| N8 | Clarified | Architecture receive-path contract; historical D9 wording | Do not assume reuse balances multicast; test duplicate co-delivery under actual bind/membership arrangement. |
| N9 | Documented | Deployment prerequisites; concepts and troubleshooting | Inspect sender TTL/hop limit for routed ingress; no universal sender default. |
| D-1 | Trust boundary documented; rate policy open | Architecture trust table; deployment; OD-03 | No publisher authentication; address filtering is spoofable; fan-out capacity/access controls required. Mandatory default ceiling not adopted. |
| D-2, O2 | Tracked; current policy retained | Architecture health table; deployment lifecycle; OD-01/OD-02 | Fail-start remains current; bounded initialization waiting/degraded startup require evidence. Network-online ordering alone is insufficient. |
| D-4 | Qualified; tracked | OD-05; troubleshooting errors | Connected/unconnected/error-queue/retry contract open. Linux UDP errors are not exclusive to connected sockets; no unconditional one-retry rule. |
| D-5 | Documented; future design deferred | Architecture trust/availability; deployment; OD-13 | No built-in HA; overlapping gateways can duplicate. No automatic prohibition/VRRP implementation choice without deployment decision. |
| D-6, D-7 | Tracked | OD-07; architecture benchmark | Evaluate pooling and batching through measurement; neither per-packet syscall failure nor mandatory slabs is established. |
| D-8 | Qualified; tracked | Architecture receive-path contract; OD-09 | Membership filtering required; extra kernel filters need evidence and separate accounting. Kernel drops cannot simultaneously count as application-received rejections. |
| D-9, O12 | Documented; protocol open | Deployment lifecycle; OD-11 | Atomic file replacement, reload serialization, identity and irrecoverable discarded payloads addressed; no invented completion API. |
| D-10 | Deferred | OD-14 | DSCP/output hop limits need a confirmed QoS/path requirement; not silently added to v1. |
| D-11 | Documented; not implemented | Deployment qualification | netns/veth, impairments, race/fuzz and event-loss tests planned; no runnable harness claimed. |
| O1 | Contract documented; unit pending | Deployment lifecycle; OD-01/OD-11 | Notify/watchdog/preflight/stop/reload completion and version compatibility recorded. Reference unit waits for unresolved policy/defaults. |
| O4 | Qualified; tracked | Deployment access; OD-10 | Minimum capabilities depend on chosen API and qualified vendor kernel; no automatic CAP_NET_ADMIN or unverified blanket capability rule. |
| O6, O7 | Documented; qualification open | Deployment access; OD-10 | Sandbox/SELinux qualification required; no disabling enforcement or assumed universal domain. Final settings remain evidence-dependent. |
| O8 | Tracked | Deployment logging; OD-08 | JSON severity limitation retained; native priority alternatives and rate-limit tests recorded, not adopted implicitly. |
| O9 | Documented | Architecture trust boundary; deployment | Loopback is not local per-user authorization. Unix-socket API remains deferred. |
| O10 | Partly documented; conventions open | Architecture health; OD-15 | HTTP 200/503 specified; metric conventions and port registration verification remain pre-schema tasks. |
| O11 | Documented | Deployment lifecycle | Watchdog and HTTP liveness share meaningful progress evidence; idle service remains healthy. |
| X1, X7 | Corrected | Architecture queue/accounting tables | Use datagram/entry and queue-full rejection; do not imply v1 drop-oldest. |
| X2, X9 | Corrected | Architecture outcome diagram; troubleshooting | Add sink_unavailable and abandoned paths; reason tokens marked illustrative pending metric schema. |
| X3, X4, X5 | Clarified | Architecture terminology table; concepts; guide | Define ingress receiver, destination receiver and sink; unavailable is component state and unready is readiness consequence. Plain-language output synonyms remain intentional in primer. |
| X6 | Corrected | Review status/action plan and this section | Completed documentation stages and accepted independent-review changes recorded. |
| X8 | Corrected | Documentation README | Add local-loop capability and clarify deferred examples are not exhaustive; link authoritative scope. |
| X10 | Clarified historically | Review confirmed inputs | Separate NIC operation must be supported, not required for every deployment. |
| X11, E2 | Corrected | Architecture/concepts/troubleshooting legends | Common color roles; diagnostic arrows are progression, not packets. Labels retain context-specific meaning. |
| X12 | Corrected | Architecture acronym appendix | Add RFC and pcap/pcapng; TB explicitly remains a diagram direction keyword. |
| T1, T2 | Documented | Troubleshooting read-only checks | Concrete host checks and planned status/metrics/health commands; namespaces, prerequisites and authority limits explained. |
| T3 | Corrected | Troubleshooting endpoints/evidence | List provisional route rejection and sink outcomes consistently, including wrong destination/ingress. |
| T4, T5, T6 | Documented | Troubleshooting ingress diagram and symptom table | Additional symptoms, host pre-socket drops, membership evidence, offload/capture caveats and bounded captures. |
| E1 | Clarified | Concepts overview/transport definitions | Opening diagram terms flagged as explained below; expand UDP/TCP before comparison. Avoid disruptive reordering without reader evidence. |
| E3 | Viewer limitation documented | Architecture legend note | HTML cell fills depend on renderer; text labels are fallback. User-requested swatches retained; visual validation still open. |
| E4 | Retained with rationale | Diagram conventions below | Repeated init/classes preserve standalone portability; shared source/config tooling deferred until warranted. |
| E5 | Retained with rationale | Docs guide and architecture authority | Short guarantee summaries are useful to distinct audiences; architecture authoritative, consistency checks required. |
| E6 | Validation added | Documentation validation script | Local anchors/links checked including numbered headings; section renumbering must update links. |
| E7 | Corrected | Review executive proposal introduction | Superseded notice precedes historical quote. |
| E8 | Corrected | Concepts health section | Remote reachability moved outside observed-health table. |
| E9 | Documented | Root README; documentation guide | Role-based entry points and concept terminology pointer. |
| Editorial low-priority list | Corrected or intentionally retained | Concepts and troubleshooting | Two-copy example aligned; send result branches added; PMTU pronoun clarified; IPv4/IPv6 endpoint notation examples remain distinct by design. Tables preferred per owner; long rows divided by symptom/check sections. |
| Traceability D1/D4 | Carried forward | Architecture deferred TCP row | Reference decoder, client/queue caps, queue age, no-client outcome, bounded shutdown and unstarted-frame policy restored; four-byte framing remains proposal. |
| Traceability D7/D8/D9 | Documented; implementation details open | Architecture health/queues/receive; OD-02/OD-09 | Current readiness intentional, monotonic age explicit, independent filtering and full isolation tests restored. |
| Lost content / workload examples | Documented or scoped | README; deployment qualification/lifecycle | Sensor/simulation/video examples and fixture/packaging planning retained; replay and discovery support not restored as v1 promises. |
| Untraced additions | Recorded; report corrected | Independent-review record below; architecture monitoring sources | Monitoring, SIEM, bounded sends, unavailable drops and overlap budget were owner-approved. S12–S14 were already cited; uncited claim rejected. |
| README capability qualification | Clarified | Documentation README status and capability introduction | Intended capabilities remain subject to prototype gates; not claimed tested support. |

### Diagram and document conventions

| Convention | Rationale |
|---|---|
| TB diagrams, named CSS colors | Owner-selected readability convention; label meaning must not depend on color |
| Repeated self-contained Mermaid setup | Portable individual blocks; changes must be synchronized across documents |
| Architecture owns behavior | Primer/README/runbook may summarize but cannot change a guarantee |
| Link/structure checks | Run `python3 scripts/check-docs.py`; rendered appearance still needs viewer verification |

## Appendix A — Online research sources

Accessed 2026-10-16. These primary technical references support Linux/transport
behavior, not vendor interoperability certification. Recommendations and failure
scenarios are this review's engineering judgments. No online vendor compatibility
research was used. Search results included other material; only the sources
listed here informed the critique. The initially attempted legacy
`IPPROTO_IP.7.html` URL was inaccessible; the linked current socket-option
reference below was used instead.

| ID | Source | Relevance |
|---|---|---|
| S1 | [Linux send(2)](https://man7.org/linux/man-pages/man2/sendto.2.html) | Local send success, errors, and limits of delivery claims |
| S2 | [Linux socket(7)](https://man7.org/linux/man-pages/man7/socket.7.html) | Receive overflow observations, buffer limits, device binding |
| S3 | [Linux sendmmsg(2)](https://man7.org/linux/man-pages/man2/sendmmsg.2.html) | Partial batch completion and error reporting |
| S4 | [Linux ipv6(7)](https://man7.org/linux/man-pages/man7/ipv6.7.html) | IPv6 scope IDs, address families, shared port space |
| S5 | [Linux kernel IP sysctl documentation](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html) | Reverse-path filtering and routing considerations |
| S6 | [Linux tcp(7)](https://man7.org/linux/man-pages/man7/tcp.7.html) | TCP transport behavior and buffering |
| S7 | [RFC 3550: RTP](https://www.rfc-editor.org/rfc/rfc3550.html) | Sequence validation and interarrival jitter definitions |
| S8 | [Linux udp(7)](https://man7.org/linux/man-pages/man7/udp.7.html) | UDP PMTU behavior and asynchronous errors |
| S9 | [Linux recv(2)](https://man7.org/linux/man-pages/man2/recvmsg.2.html) | Datagram truncation detection and receive semantics |
| S10 | [RFC 8085: UDP Usage Guidelines](https://www.rfc-editor.org/rfc/rfc8085.html) | Congestion, message sizing, and fragmentation considerations |
| S11 | [Linux IPv4 socket options](https://man7.org/linux/man-pages/man2/IPPROTO_IP.2const.html) and [Linux ip(7)](https://man7.org/linux/man-pages/man7/ip.7.html) | Multicast membership/loopback options and IPv4 addressing |
| S12 | [Linux rtnetlink(7)](https://man7.org/linux/man-pages/man7/rtnetlink.7.html) | Kernel link, address, and route messages for interface monitoring |
| S13 | [Debian rtnetlink(7)](https://manpages.debian.org/trixie/manpages/rtnetlink.7.en.html) | Debian documentation of the Linux routing socket API |
| S14 | [Red Hat Enterprise Linux networking guide](https://docs.redhat.com/en-us/documentation/red_hat_enterprise_linux/7/pdf/networking_guide/Red_Hat_Enterprise_Linux-7-Networking_Guide-en-US.pdf) | RHEL use of rtnetlink; availability evidence, not qualification of the deployment release |
| S15 | [systemd.service(5)](https://man7.org/linux/man-pages/man5/systemd.service.5.html) | Notification, reload protocol versioning, lifecycle and timeout semantics |
| S16 | [RFC 4604](https://www.rfc-editor.org/info/rfc4604/) and [RFC 4607](https://www.rfc-editor.org/info/rfc4607/) | Source-specific membership protocols and SSM address/service semantics |
| S17 | [systemd.exec(5)](https://man7.org/linux/man-pages/man5/systemd.exec.5.html) | Service execution restrictions and logging/priority mechanisms |
| S18 | [ip-monitor(8)](https://man7.org/linux/man-pages/man8/ip-monitor.8.html) | Read-only link/address/route observation |
| S19 | [ss(8)](https://man7.org/linux/man-pages/man8/ss.8.html) | Socket memory/process diagnostics |
| S20 | [ip-maddress(8)](https://man7.org/linux/man-pages/man8/ip-maddress.8.html) | Interface membership listing; not per-application proof |
| S21 | [nstat(8)](https://man7.org/linux/man-pages/man8/nstat.8.html) | Host network counter snapshots |
| S22 | [tcpdump(8)](https://man7.org/linux/man-pages/man8/tcpdump.8.html) | Capture interfaces, filters, limits and capture-loss observations |
| S23 | [CSS Color named colors](https://www.w3.org/TR/css-color/#named-colors) | Diagram named-color palette terminology |
| S24 | [Debian ip(7)](https://manpages.debian.org/trixie/manpages/ip.7.en.html) and [Linux IPv6 UAPI header](https://github.com/torvalds/linux/blob/master/include/uapi/linux/in6.h) | Family-specific multicast-all option references; header presence is not runtime qualification |

The interface monitoring/outage policy and SIEM event schema are project design
choices. These references establish the kernel mechanism; they do not establish
remote delivery, lossless event collection, or a tested service permission set.

Other online material inspected during verification:

- [POSIX send(3p)](https://www.man7.org/linux/man-pages/man3/send.3p.html):
  corroborates that send completion does not guarantee message delivery.
- [Linux kernel IP sysctl v6.11](https://www.kernel.org/doc/html/v6.11/networking/ip-sysctl.html):
  versioned reference inspected before selecting the current documentation.
