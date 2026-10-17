# mcgw — multicast gateway

A planned Linux service that receives IPv4/IPv6 multicast UDP traffic and forwards
unchanged payloads to one or more unicast destinations. It targets Debian and RHEL
hosts or VMs at independent sites.

**Status:** agreed design direction; implementation and prototype validation
remain open. This repository contains design documents, a proposed test plan,
a network-namespace test environment with small test tools, the OD-09 socket
isolation prototype (not yet run on the lab machines) and documentation-checking
scripts. No released daemon or performance guarantee is claimed.

## Contents

- [Project overview](#project-overview)
- [Documentation](#documentation)
- [Design decisions and future ideas](#design-decisions-and-future-ideas)
- [Documentation checks](#documentation-checks)

## Project overview

| Topic | Planned behavior |
|---|---|
| Input | IPv4/IPv6 multicast UDP, with any-source or source-specific membership |
| Output | One or more unicast UDP destinations; same IP family as input |
| Interfaces | Receive and send through the same interface or separate interfaces |
| Payload | Preserve bytes and datagram boundaries |
| Failure isolation | Independent bounded queues and outcome accounting per destination |
| Operations | Interface monitoring, recovery, structured journal events, metrics and read-only status |
| Confirmation boundary | Successful forwarding means complete local UDP socket acceptance; it does not prove host egress, destination receipt or application processing |
| Network limits | No end-to-end path probes, retransmission, jitter smoothing or resequencing |

The [architecture](docs/architecture.md) defines the authoritative scope and
contracts. The [platform reference guides](docs/reference/README.md) cover IPv4
only; that narrower guide coverage does not change the planned dual-stack design.

## Documentation

| Reader / task | Document | Purpose |
|---|---|---|
| Resume work | [Status and next steps](docs/mcgw-status.md) | Where the project stands and the next actions |
| Start here | [Documentation overview](docs/README.md) | Project capabilities, limits and reading guide |
| Learn the vocabulary | [Concepts](docs/mcgw-concepts.md) | Networking concepts and diagrams for newcomers |
| Understand or implement the design | [Architecture](docs/architecture.md) | Forwarding contracts, lifecycle diagrams, rationale and validation gates |
| Resolve implementation choices | [Open decisions](docs/mcgw-open-decisions.md) | Current positions, alternatives, evidence needed and recorded resolutions |
| Plan validation before code | [Test plan](docs/mcgw-test-plan.md) | Proposed unit, integration, lab and qualification cases; traceability, blockers and contract gaps |
| Run tests and prototypes | [Test machine setup](test/README.md) | Prepare a Debian 13 or RHEL 9/10 machine and run the OD-09 prototype |
| Plan a deployment | [Deployment planning](docs/mcgw-deployment.md) | Host/network prerequisites, service integration and site qualification |
| Diagnose missing traffic | [Troubleshooting](docs/mcgw-troubleshooting.md) | Checks, retained evidence and next actions |
| Check platform details | [Platform references](docs/reference/README.md) | IPv4-only Cisco, Debian/Proxmox, RHEL/VMware and Windows guides |
| Propose optional improvements | [Feature ideas](docs/mcgw-feature-ideas.md) | Nice-to-have backlog with value, constraints and acceptance gates |
| Review design history | [Architecture review](docs/architecture-review.md) | Earlier findings, decisions, justifications and supporting sources |

Suggested starting point: Concepts → Architecture. Use the test plan alongside
implementation work, and deployment/troubleshooting documents for operational
planning.

## Design decisions and future ideas

| Question | Where it belongs |
|---|---|
| What behavior is currently agreed? | Architecture |
| What implementation choice still needs evidence or clarification? | Open decisions |
| How will an agreed contract be verified? | Test plan; proposed cases are not evidence of passed tests |
| What optional improvement might be useful later? | Feature ideas; entries do not expand v1 scope |
| What capability is deliberately outside v1? | Architecture’s deferred capabilities section |

The feature backlog currently includes a read-only browser status page, gated on
the status schema and management isolation requirements. It is an optional idea,
not a committed v1 feature.

## Documentation checks

From the repository root, run:

```bash
python3 scripts/check-docs.py
```

This checks local links, heading anchors, fenced blocks and selected Mermaid
conventions. Full Mermaid grammar and visual layout require separate rendering
and inspection.

After changing the checker, also run its regression fixtures:

```bash
python3 scripts/test_check_docs.py
```
