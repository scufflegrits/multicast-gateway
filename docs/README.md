# mcgw — multicast gateway

mcgw is a planned Linux service that receives multicast UDP traffic and forwards
unchanged payloads to configured unicast receivers. It lets an existing multicast
feed reach systems on other networks without requiring those systems to join
the original multicast group.

**Status:** design agreed in principle; implementation and prototype validation
remain open. Features below describe the intended v1, not a released product.

## Project overview

| Topic | Overview |
|---|---|
| Input | IPv4 or IPv6 multicast; any-source or source-specific membership |
| Output | One or more unicast UDP receivers per configured feed; same IP family as input |
| Interfaces | Receive and send through one interface or separate interfaces |
| Payloads | Preserve bytes and datagram boundaries; no application-protocol translation |
| Example uses | Simulation, sensor/telemetry, and video feeds whose receivers understand the original payload |
| Deployment | Independent Debian/RHEL hosts or VMs at separate sites |
| Implementation direction | Go first; measure performance before considering alternatives |

## Intended v1 capabilities

All capabilities below are design requirements subject to the architecture's
prototype/OS qualification gates; none is a tested-support claim.

| Capability | Purpose |
|---|---|
| Configured routes and sinks | Select multicast inputs and independent unicast outputs |
| Source and size filtering | Reject unwanted senders or unacceptable datagrams with counted reasons |
| Bounded per-destination queues | Isolate slow/failed outputs and make overload drops visible |
| Source binding and optional egress constraint | Control local output endpoints and, when required, the outgoing interface |
| Local forwarding accounting | Report receives, rejections, submissions, failures, and drops per relevant route/output |
| Interface monitoring and recovery | Detect relevant local network changes, expose failures, and reinitialize affected resources |
| Metrics and read-only status | Separate liveness, local readiness, and traffic freshness |
| Journal events | Record structured outage/recovery events for host collectors and SIEM alerting |
| Local-loop guards | Reject provable local cycles and detect configured local-source feedback; no universal multi-site loop guarantee |
| Service lifecycle | Validate configuration, apply controlled reloads, shut down within a deadline, and integrate with systemd |

## Guarantees and limits

| Question | Answer |
|---|---|
| Does it work with one receiver? | Yes; additional receivers are optional |
| What does successful forwarding mean? | Linux accepted a complete outbound UDP datagram into the local socket path |
| Does it test the destination before sending? | No; it checks local forwarding conditions and relies on Linux routing |
| Does it confirm destination receipt or processing? | No; local submission is the confirmation boundary |
| Does it fix WAN delay, loss, or reordering? | No; it preserves observed order among surviving datagrams per route/output |
| Can queues absorb an unlimited outage? | No; queue limits, expiry, and unavailable-output handling produce counted drops |
| Is it a multicast router or discovery relay? | No; v1 receives and sends as an application, with one-way forwarding |
| Are performance figures guaranteed? | No; the architecture defines provisional benchmark cases and validation gates |
| What is deferred? | TCP, recording, protocol inspection, production replay, cross-family forwarding, multicast/broadcast outputs, and bidirectional relay; see architecture for the complete deferred list |

## Documentation

Newcomers → Concepts; implementers → Architecture and Open decisions;
operators → Deployment planning and Troubleshooting. ASM, SSM, SIEM and other
terms are explained in Concepts and the architecture acronym appendix.

| Document | Purpose |
|---|---|
| [Concepts](mcgw-concepts.md) | Explain the vocabulary, network behavior, and forwarding-confirmation boundary before reading the architecture |
| [Architecture](architecture.md) | Define scope, behavior, guarantees, design rationale, diagnostic evidence, and open validation choices |
| [Troubleshooting](mcgw-troubleshooting.md) | Walk operators through symptoms, checks, evidence, and next actions |
| [Platform references](reference/README.md) | IPv4-only supporting Cisco, Debian/Proxmox, RHEL/VMware and Windows guides; scope, evidence and qualification limits are explicit |
| [Deployment planning](mcgw-deployment.md) | Host/network prerequisites, lifecycle integration, hardening, logging collection, and site qualification |
| [Open decisions](mcgw-open-decisions.md) | Track unresolved proposals, current positions, alternatives, evidence needed, decision gates, and resolutions |
| [Feature ideas](mcgw-feature-ideas.md) | Nice-to-have backlog: optional improvements, their value, constraints and gates; not v1 scope |
| [Architecture review](architecture-review.md) | Preserve review history, accepted recommendations, justifications, and research sources; architecture.md is authoritative for current decisions |

**Suggested reading order:** Concepts → Architecture → Troubleshooting as needed.
Use the architecture review for decision history and supporting sources.

The documents describe the planned design. Diagnostic fields and commands that
depend on mcgw functionality are subject to implementation; see each document's
status and limitations.

Documentation maintenance: run `python3 scripts/check-docs.py` from the repository
root to check local links and diagram structure; review rendered diagrams separately.
After changing the checker, run `python3 scripts/test_check_docs.py`.
