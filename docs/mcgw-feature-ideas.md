# mcgw feature ideas

**Status:** nice-to-have backlog, started 2026-10-17. Entries record ideas worth
keeping, not commitments. Nothing here changes v1 scope, authorizes
implementation, or overrides the [architecture](architecture.md).

## How to use this backlog

| Register | What belongs there |
|---|---|
| This backlog | Optional improvements that v1 can ship without; value, constraints and prerequisites |
| [Open decisions](mcgw-open-decisions.md) | Unresolved choices that affect the accepted v1 design |
| [Architecture §10](architecture.md#10-deferred-capabilities) | Capabilities deliberately excluded from v1 that need substantial design before adding |

| Rule | Meaning |
|---|---|
| Stable IDs | Refer to ideas by FI number; never reuse a number |
| Must or nice-to-have | If v1 cannot meet its contracts without it, it is not an idea: raise an open decision instead |
| Gates | Record what must exist first (schemas, contracts, qualification); an idea cannot bypass a decision gate |
| Promotion | When accepted, update the authoritative document, record the link and date here, and set status Accepted |
| Preserve history | Keep declined ideas with the reason; do not delete entries |

| Status | Meaning |
|---|---|
| Idea | Recorded; not evaluated |
| Candidate | Evaluated as worthwhile; waiting on its gate |
| Accepted | Moved into the architecture or a release plan; link recorded |
| Declined | Not pursued; reason recorded |

## Idea index

| ID | Idea | Gate | Status |
|---|---|---|---|
| [FI-01](#fi-01) | Read-only browser status page | After status JSON schema freeze (OD-15) | Candidate |

## FI-01

**Read-only browser status page**

| Field | Record |
|---|---|
| Status | Candidate |
| Classification | Nice-to-have, not v1. The planned `/healthz`, `/readyz`, `/metrics` and `/status` endpoints, journal events and SIEM collection already cover operational needs; a page adds a human view, not a capability |
| Gate | After the `/status` JSON schema is frozen ([OD-15](mcgw-open-decisions.md#od-15)); a page built on provisional fields would churn with them |
| Related | Architecture §10 "Rich CLI / watch / interfaces"; management access and isolation contracts in [architecture §5](architecture.md#health-and-status) |
| Recorded | 2026-10-17 |

### Why it is not required

| Concern | Detail |
|---|---|
| Scope | v1 is UDP-first; richer APIs and the management CLI are already deferred |
| Security | v1 has no built-in HTTP authentication/TLS and binds to loopback by default. A useful page invites external binding, which requires operator-provided access controls; any state-changing form would raise the risk sharply |
| Isolation | Auto-refreshing pages are persistent management clients. The connection, timeout, response-size and snapshot-isolation bounds apply to the page as to any other client |

### Low-risk shape

- One static, read-only page served by the existing listener, rendering the
  `/status` JSON with a slow refresh.
- No write actions and no new data sources beyond existing endpoints.
- Alternative needing no daemon change: a standalone HTML file that reads
  `/status`.

### Proposed content

| Area | Content |
|---|---|
| Summary banner | Overall readiness and the reason when unready (which required component failed); process health, uptime, configuration generation |
| Routes (ingress) | Group/source, ingress interface, membership state, freshness (never seen / fresh / stale, time since last datagram), receive rate, rejection counts by reason |
| Sinks (egress) | Destination, egress interface and actual local source IP/port, state, counters (submitted, failed, `queue_full`, `expired`, `abandoned`), queue occupancy against its budget |
| Reload state | Desired versus active generation per route; any mixed-generation or rollback outcome |
| Interfaces | Link/address state of the interfaces mcgw uses; recent down/up transitions |
| Recent events | Last N outage/recovery events and suppressed-event summaries (the same records sent to the journal) |
| Boundary notice | Permanent text: ready means local sockets are usable, not that destinations received data |

### Excluded

| Item | Reason |
|---|---|
| Configuration editing or reload triggers | State changes need authentication and an API contract v1 does not provide |
| Payload previews | Sensor contents and privacy; payloads are opaque to mcgw |
| Packet captures | Belong to bounded operator tooling ([troubleshooting](mcgw-troubleshooting.md#retained-evidence-captures)) |
| Anything needing authentication to be safe | Out of scope while v1 has no built-in authentication |

| Field | Record |
|---|---|
| Evidence needed before acceptance | Frozen status schema; slow-client/refresh fault injection showing no forwarding impact; decision on serving it from the daemon versus a standalone file |
| Resolution | Pending |
