# OD-09 isolation prototype

Throwaway experiment for [OD-09](../../docs/mcgw-open-decisions.md#od-09): which
IPv4 socket options and per-datagram checks keep one route's multicast receiver
from seeing other groups, other interfaces or other sources. It also gathers the
evidence [OD-17](../../docs/mcgw-open-decisions.md#od-17) relies on. It is not mcgw
code, and the daemon must not import it. Machine setup is in
[test/README.md](../../test/README.md).

## What it runs

`run-mci.sh` builds the shared namespace environment and runs every case once
for each option set:

| Option | Values | Meaning |
|---|---|---|
| Bind | `group`, `wildcard` | Bind the receive socket to the group address or to `0.0.0.0` |
| `IP_MULTICAST_ALL` | `default` (kernel default, 1), `0` | Whether the socket receives groups joined by other sockets on the host |

| Case | What it checks | Receivers |
|---|---|---|
| T-MCI-01 | Same port, different groups | `R1`, `R2` |
| T-MCI-02 | Same group on two interfaces | `R1` (eth0), `R2` (eth2) |
| T-MCI-03 | Another application joined a different group on the same port | `R1`, unrelated `U` |
| T-MCI-04 | Traffic for the group arriving on the wrong interface | `R1` (eth0), unrelated `U` (eth2) |
| T-MCI-05-control | Both sources reach 232.1.1.1 (any-source receiver) | `C` |
| T-MCI-05 | Source-specific join alone; IGMPv3 join report captured | `R3` |
| T-MCI-05b | Source-specific join while another application holds an any-source join | `R3`, unrelated `U` |
| OD17 | External unicast, broadcast and local-origin unicast (gateway address and loopback) to the receive port | one receiver |

Receiver names are `<role>-<case>-<bind>-<mcall>`, for example `R1-01-group-default`.
`U` receivers always use a wildcard bind and kernel defaults, like a naive
application; `C` always uses a group bind with `IP_MULTICAST_ALL=0`. Their rows show
those fixed options, not the option set under test.

Every socket sets `SO_REUSEADDR` (so several receivers can share port 3000) and
`IP_PKTINFO` (so each datagram reports its header destination and arrival
interface). The effective `IP_MULTICAST_ALL` is read back from the kernel and
shown in each row. Each received datagram gets one verdict using the
architecture §4 rejection precedence: `truncated`, `wrong_ingress`,
`wrong_destination`, `oversize`, `source_filtered`, otherwise `accept`.

T-MCI-05 alone exercises only the interface-level source filter (the interface
becomes INCLUDE{.20}, so .21 never reaches a socket). T-MCI-05b adds an
any-source member, which switches the interface filter to EXCLUDE{}, so only the
socket's own source filter can keep .21 out. That is the case a real gateway with
overlapping members faces.

## Run it

```bash
test/build.sh                                  # as your normal user
sudo prototypes/od09-isolation/run-mci.sh      # about 5 minutes; use tmux/screen over SSH
```

The runner removes any existing `mcgw-` namespaces before starting. Where SELinux
or a `noexec` home directory stops `test/bin` from running, copy the binaries
elsewhere and pass that directory:

```bash
sudo install -d /usr/local/libexec/mcgw-test
sudo install -m 0755 test/bin/* /usr/local/libexec/mcgw-test/
sudo prototypes/od09-isolation/run-mci.sh /usr/local/libexec/mcgw-test
```

Do not grant a sudo rule for this script alone: it sources files and runs
binaries from your checkout, so such a rule is equivalent to full root.

## Run outcomes

| Exit | Outcome | Report | Use |
|---|---|---|---|
| 0 | **VALID** | Written, `Run status: VALID` | Complete the Interpretation section, then commit |
| 3 | **REVIEW** | Written, `Run status: REVIEW` with the reasons | Valid run with something unexpected; investigate the listed reasons and record them in Interpretation before committing |
| other | **INVALID** | Not written | Do not use; bring back the raw directory |

**INVALID** means the experiment itself failed:
- a receiver was not ready in time, or failed or ended early
- a summary was missing or malformed
- a sender did not submit all datagrams
- a positive control failed (a receiver did not accept exactly its own traffic)
- a capture failed or did not see the injected unicast and broadcast

**REVIEW** means the run worked but either:
- a cell's foreign delivery or effective `IP_MULTICAST_ALL` differed from the prediction below, or
- the T-MCI-05 IGMP capture did not contain the join record for 192.168.10.20.

The report file is named `results/<date>-<time>-<os><version>-<kernel>.md`. It is
never overwritten, and it refuses to replace a symlink. Raw JSON, readiness markers,
stderr and captures stay in the printed `/tmp/mcgw-od09.*` directory, owned by the
invoking user. Copy anything you need before a reboot, because `/tmp` is cleaned.

## Predictions

Expected `Foreign` per receiver, from Linux socket delivery rules
(`__udp_is_mcast_sock`). With `IP_MULTICAST_ALL=1` a socket receives a group
arriving on any interface where some socket joined it, whatever its bind. A
wildcard socket also receives other groups on its port. `IP_MULTICAST_ALL=0`
limits delivery to the socket's own (group, interface) memberships. N = 200.

| Receiver | group / default | group / 0 | wildcard / default | wildcard / 0 |
|---|---|---|---|---|
| T-MCI-01 R1, R2 | 0 | 0 | N (`wrong_destination`) | 0 |
| T-MCI-02 R1, R2 | N (`wrong_ingress`) | 0 | N (`wrong_ingress`) | 0 |
| T-MCI-03 R1 | 0 | 0 | N (`wrong_destination`) | 0 |
| T-MCI-04 R1 | N (`wrong_ingress`) | 0 | N (`wrong_ingress`) | 0 |
| T-MCI-03 / -04 U | N | N | N | N |
| C, T-MCI-05 R3, T-MCI-05b R3 and U | 0 | 0 | 0 | 0 |
| OD17 | 0 (not delivered) | 0 | 4N: 2N `wrong_destination`, 2N `wrong_ingress` | 4N |

The cells with expected leaks are the negative controls: if they show 0, the run
reports REVIEW rather than being read as "every option set isolates".

## Reading the report

| Column | Meaning |
|---|---|
| Received | Datagrams the kernel delivered to this socket |
| Accepted | Datagrams that passed every check |
| Foreign | Delivered datagrams that are not the receiver's own traffic: other group, other interface, other source, or (OD17) unicast, broadcast and local-origin traffic |
| Predicted | Expected Foreign from the table above |
| Match | `yes`, or `NO` when Foreign or the effective `IP_MULTICAST_ALL` differs from the prediction |
| Rejections | Every non-accept verdict with its count |

Zero foreign delivery supports kernel suppression only together with the
positive controls, which the runner enforces. Nonzero foreign delivery with
matching rejections shows the per-datagram boundary working instead; it does not
show kernel suppression.

## Differences from the test plan

- **Volume:** 200 datagrams per sender instead of the plan's 500–1000. Kernel filtering is deterministic, so exact counts matter more than volume.
- **Extra positive controls:** T-MCI-03 and T-MCI-04 add own traffic for R1 and validate the unrelated receivers.
- **Additions:** T-MCI-05b and the OD17 checks.
- **Not covered:**
  - the T-MCI-05 `check-config` rejection (there is no daemon yet)
  - interface binding (`SO_BINDTODEVICE`)
  - operation without `SO_REUSEADDR`
  - permitted local senders
  - IGMPv2 querier compatibility
  - source-specific joins outside 232/8
  - IPv6 (T-MCI-06)
- **Network side:** the namespaces have no querier or snooping, so the run says nothing about network-side IGMP behavior.

## Regression checks

These checks do not create namespaces and need no root. Run them from the
repository root:

```bash
go test ./...
python3 prototypes/od09-isolation/test_harness.py
python3 test/test_tools.py
```

They cover:
- rejection precedence and size boundaries
- `IP_PKTINFO` parsing and deterministic result ordering
- receive termination and summary validation
- positive-control and sender counts, and capture exit codes
- the IGMP join pattern, which matches only join records, never leave records
- the prediction checks, report rows and `wait_until` timing

Privileged Debian/RHEL runs are still required to establish actual kernel behavior.

## After the runs

1. Complete each results file's Interpretation section.
2. Record the outcome in OD-09 "Investigation results", with links to the files.
3. Record in OD-17 what the OD17 rows show for the bind chosen under OD-09.
