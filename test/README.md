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
| Access | `sudo`, and internet access for packages and `git clone` |
| Kernel | Any supported kernel for these releases; record the version, as results are per kernel |
| Go | 1.22 or newer (distro packages are expected to qualify; check with `go version`) |

The environment lives entirely in network namespaces prefixed `mcgw-`. It does
not change host interfaces, routes or firewall rules. Each namespace has its own
netfilter state, so host firewalld/nftables rules do not filter traffic inside it.

## 1. Install packages

Debian 13:

```bash
sudo apt update
sudo apt install -y git golang-go iproute2 tcpdump jq
```

RHEL 9 or 10 (packages come from BaseOS and AppStream; the system must be registered):

```bash
sudo dnf install -y git golang iproute tcpdump jq
```

Check the Go version:

```bash
go version
```

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

`up` refuses to run if `mcgw-` namespaces already exist; `down` removes them
all. The topology matches the test plan's
[shared environment](../docs/mcgw-test-plan.md#shared-environment).

## 5. Run a prototype

For OD-09 socket isolation, follow
[prototypes/od09-isolation](../prototypes/od09-isolation/README.md):

```bash
sudo prototypes/od09-isolation/run-mci.sh
```

The script creates and removes the environment itself and writes a results
summary under `prototypes/od09-isolation/results/`.

## 6. Return the results

Commit the results file and push, or copy it back to the main checkout:

```bash
git add prototypes/od09-isolation/results/
git commit -m "OD-09 isolation results: <os> <kernel>"
git push
```

Raw per-receiver output stays in the `/tmp/mcgw-od09.*` directory the script
prints; it is not committed.

## Troubleshooting

| Symptom | Check |
|---|---|
| `must run as root` | Run the environment and prototype scripts with `sudo` |
| `mcgw- namespaces already exist` | A previous run was interrupted: `sudo test/netns/env.sh down` |
| `missing tools` | Install the packages in step 1 |
| `test/bin/... missing` | Run `test/build.sh` as your normal user |
| `ip link add ... netns` fails | Record the `ip -V` output; the script needs an iproute2 that creates veth pairs directly in namespaces |
| `go: go.mod requires go >= ...` | Install a newer Go as described in step 1 |

## Layout

| Path | Purpose |
|---|---|
| `test/netns/` | Shared environment script and helpers, reused by future integration tests |
| `test/tools/` | `mcsend` (numbered-payload sender) and `mcrecv` (unicast listener) |
| `test/build.sh` | Builds tools and prototypes into `test/bin/` |
| `prototypes/` | Throwaway experiments that produce evidence for open decisions; never imported by mcgw |
