# mcgw — multicast gateway

A planned Linux service for forwarding IPv4/IPv6 multicast UDP payloads to one
or more unicast destinations. Design and prototype gates remain open; no released
implementation or performance guarantee is claimed.

| Reader | Start here |
|---|---|
| New to the project | [Project overview and documentation guide](docs/README.md) |
| New to networking | [Concepts](docs/mcgw-concepts.md) |
| Implementing mcgw | [Architecture](docs/architecture.md) and [open decisions](docs/mcgw-open-decisions.md) |
| Deploying or operating | [Deployment planning](docs/mcgw-deployment.md) and [troubleshooting](docs/mcgw-troubleshooting.md) |
| Reviewing design history | [Architecture review](docs/architecture-review.md) |

Successful forwarding means local UDP socket acceptance, not destination receipt.
See the architecture for authoritative scope and guarantees.
