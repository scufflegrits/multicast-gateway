# mcgw test machine setup

How to prepare a separate Linux machine to run the namespace test environment,
the test tools and the prototypes. The mcgw daemon does not exist yet, so this
is not an mcgw installation guide; daemon installation will be documented when
there is a daemon to install, building on
[deployment planning](../docs/mcgw-deployment.md).

## Machine requirements

| Item | Requirement |
|---|---|
| OS | Debian 13, or RHEL 9 / RHEL 10. Run on each when gathering OD-09 evidence, since kernels differ |
| Machine | A dedicated VM or lab host. Tests create network namespaces and need root; do not use a production host |
| Checkout | On local disk; a root-squashed NFS home stops root reading the scripts or writing results |
| Access | `sudo`, and internet access for packages and `git clone` |
| Kernel | Any supported kernel for these releases; record the version, as results are per kernel |
| Go | 1.22 or newer to build; 1.25.10 or newer recommended (see [Go versions](#go-versions)) |

The environment lives entirely in network namespaces prefixed `mcgw-`. It does
not change host interfaces, routes or firewall rules. Each namespace has its own
netfilter state, so host firewalld/nftables rules do not filter traffic inside it.

## Go versions

| Item | Version | Notes |
|---|---|---|
| Minimum to build | 1.22 | From `go.mod`; verified with Go 1.22.12 |
| Recommended | 1.25.10 or newer | Clears govulncheck finding GO-2026-4971 (Windows-only, not reachable on Linux) |
| Checked with | 1.27.2 | `gofmt`, `go vet`, golangci-lint and govulncheck clean |
| Debian 13 `golang-go` | 1.24.4 | Verified on a Debian 13 machine; builds, but govulncheck reports GO-2026-4971 |
| RHEL 9 `golang` | Not yet recorded | Varies by RHEL minor release; record `dnf info golang` and `go version` on the test machine |
| RHEL 10 `golang` | Not yet recorded | As for RHEL 9 |

Each OD-09 results file records the Go runtime of the prototype binary; also
record `go version` and `go env GOTOOLCHAIN GOPROXY` on each machine (step 1), so
the RHEL rows can be filled in from the first RHEL runs. These versions apply to the test tools and
prototypes only; the daemon's Go version policy is open
([OD-18](../docs/mcgw-open-decisions.md#od-18)).

## 1. Install packages

Debian 13:

```bash
sudo apt update
sudo apt install -y git golang-go iproute2 tcpdump jq python3
```

RHEL 9 or 10 (packages come from BaseOS and AppStream; the system must be registered):

```bash
sudo dnf install -y git golang iproute tcpdump jq python3
```

`timeout`, `install` and `paste` come from coreutils, which both distributions
install by default. Python 3 is only needed for the regression checks.

Check and record the Go version and settings:

```bash
go version
go env GOTOOLCHAIN GOPROXY
```

RHEL's Go package may set `GOTOOLCHAIN=local`, which turns off the automatic
download of a newer toolchain.

If it reports a version older than 1.22, install the official toolchain instead
of the distro package: download the Linux tarball from https://go.dev/dl/,
verify its checksum, extract it to `/usr/local/go`, and add `/usr/local/go/bin`
to `PATH`.

## 2. Get the code

```bash
git clone https://github.com/scufflegrits/multicast-gateway.git
cd multicast-gateway
```

If the repository is private, clone over SSH with a key added to your GitHub
account (`git clone git@github.com:scufflegrits/multicast-gateway.git`) or
authenticate with `gh auth login` first.

## 3. Build the tools

Build as your normal user, not root:

```bash
test/build.sh
```

This writes `mcsend`, `mcrecv` and `od09-isolation` to `test/bin/` (ignored by git).

## 4. Try the environment (optional)

```bash
sudo test/netns/env.sh up
sudo test/netns/env.sh status
sudo test/netns/env.sh down
```

`up` refuses to run if `mcgw-` namespaces already exist; `down` removes every
`mcgw-` namespace and stops processes still running inside them. `env.sh`
implements the IPv4 topology of the test plan's
[shared environment](../docs/mcgw-test-plan.md#shared-environment).

## 5. Run a prototype

For OD-09 socket isolation, follow
[prototypes/od09-isolation](../prototypes/od09-isolation/README.md):

```bash
sudo prototypes/od09-isolation/run-mci.sh
```

The run takes about 5 minutes; over SSH, run it inside `tmux` or `screen`. The
script removes any existing `mcgw-` environment first (including one started by
hand in step 4), creates and removes its own, and on a VALID or REVIEW run writes
a report under `prototypes/od09-isolation/results/`. It ends with exit 0 (VALID),
3 (REVIEW) or another code (INVALID, no report); see
[Run outcomes](../prototypes/od09-isolation/README.md#run-outcomes).

## 6. Return the results

Check the outcome first (`echo $?` straight after the run). Commit a VALID
report after completing its Interpretation section; commit a REVIEW report only
after investigating the reasons it lists. Never commit after an INVALID run.
Then push, or copy the file back to the main checkout:

```bash
git add prototypes/od09-isolation/results/
git commit -m "OD-09 isolation results: <os> <kernel>"
git push
```

Raw per-receiver output stays in the `/tmp/mcgw-od09.*` directory the script
prints. It is owned by your user, it is not committed, and it is lost on reboot,
so copy anything needed for investigation first.

## Troubleshooting

| Symptom | Check |
|---|---|
| `must run as root` | Run the environment and prototype scripts with `sudo` |
| `mcgw- namespaces already exist` (from `env.sh up`) | A previous environment is still present: `sudo test/netns/env.sh down`. The prototype runner removes it automatically |
| `INVALID experiment: receiver not ready` or `sender process failed` on RHEL | Possibly SELinux or a `noexec` home: run `sudo ausearch -m avc -ts recent`, then copy the binaries outside your home and pass that directory to the runner (see the [prototype guide](../prototypes/od09-isolation/README.md#run-it)) |
| `INVALID experiment` (other) | Read the message and the files in the printed raw directory (receiver `.stderr`, sender `.json.stderr`, capture `.txt.stderr`) |
| `missing tools` | Install the packages in step 1 |
| `test/bin/... missing` | Run `test/build.sh` as your normal user |
| `ip link add ... netns` fails | Record the `ip -V` output; the script needs an iproute2 that creates veth pairs directly in namespaces |
| `go: go.mod requires go >= ...` | Install a newer Go as described in step 1 |
| `undefined: min` / `undefined: max` with "note: module requires Go 1.22" | Go 1.20 or older, which ignores the `go` line; install a newer Go as described in step 1 |
| `govulncheck` reports GO-2026-4971 | Expected with Debian 13's Go 1.24.4: a Windows-only panic in `net`, fixed in Go 1.25.10, not reachable on Linux. Use Go 1.25.10 or newer to clear it |
| `govulncheck: Loading packages failed ... mismatch` | govulncheck was built with an older Go than the `go` on `PATH`; rebuild it with `go install golang.org/x/vuln/cmd/govulncheck@latest` |

## Layout

| Path | Purpose |
|---|---|
| `test/netns/` | Shared environment script and helpers, reused by future integration tests |
| `test/tools/` | `mcsend` (numbered-payload sender) and `mcrecv` (unicast listener) |
| `test/build.sh` | Builds tools and prototypes into `test/bin/` |
| `test/test_tools.py` | Process-level regression checks for the tools (loopback only) |
| `prototypes/od09-isolation/results/` | Committed OD-09 run reports |
| `prototypes/` | Throwaway experiments that produce evidence for open decisions; never imported by mcgw |

## Tool and harness completion

Receivers write one summary with `complete` and `termination`. Deadline expiry
completes the observation window; early closure or an unexpected read error is
incomplete and exits nonzero. `-ready-file PATH` writes a readiness marker after
socket setup. Per-datagram output remains optional with `-lines`.

`mcsend` exits 1 when any datagram submission fails, printing the first error to
stderr and keeping its `sent`, `errors`, `n` and `rate` summary, and exits 2 for
usage errors (for example `-size` above 65507 or an unknown `-iface`). Its success
means local submission, not receipt. Pacing never bursts to catch up after a stall.

The OD-09 runner checks individual child exits, validates summaries and positive
controls, compares every cell with kernel-semantics predictions, and includes the
OD-17 unicast, broadcast and local-origin checks. See the
[prototype guide](../prototypes/od09-isolation/README.md) for evidence rules and
unprivileged regression commands.

With Python 3 and Go installed, process-level regression checks are available:

```bash
python3 test/test_tools.py
```

They build binaries in a temporary directory, open loopback listeners, check
readiness, early termination and the reported bound port, check usage-error exit
codes, and verify a failed submission using destination port 0, which Linux
rejects before transmission. They do not create namespaces or send traffic onto
real networks.
