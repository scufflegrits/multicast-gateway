# OD-09 isolation prototype

Throwaway experiment for [OD-09](../../docs/mcgw-open-decisions.md#od-09): which
IPv4 socket options and per-datagram checks keep one route's multicast receiver
from seeing other groups, other interfaces or other sources. It is not mcgw code,
and the daemon must not import it. Machine setup is in
[test/README.md](../../test/README.md).

## What it runs

`run-mci.sh` runs test-plan cases
[T-MCI-01 to T-MCI-05](../../docs/mcgw-test-plan.md#mci--multicast-isolation)
and a dedicated OD-17 unicast-injection check in the shared namespace
environment, once for each option set:

| Option | Values | Meaning |
|---|---|---|
| Bind | `group`, `wildcard` | Bind the receive socket to the group address or to `0.0.0.0` |
| `IP_MULTICAST_ALL` | `default` (kernel default, 1), `0` | Whether the socket receives groups joined by other sockets on the host |

Every socket also sets `SO_REUSEADDR` (so several receivers can share port
3000) and `IP_PKTINFO` (so each datagram reports its header destination and
arrival interface). T-MCI-03 and T-MCI-04 add an "unrelated" receiver that
always uses kernel defaults and a wildcard bind, like a naive application.

Each received datagram gets one verdict using the architecture §4 rejection
precedence: `truncated`, then `wrong_ingress` / `wrong_destination`, then
`oversize`, then `source_filtered`, otherwise `accept`.

## Run it

```bash
test/build.sh                                  # as your normal user
sudo prototypes/od09-isolation/run-mci.sh      # about 3 minutes
```

The script writes `results/<date>-<os><version>-<kernel>.md` and prints the raw
output directory. Run it on Debian 13 and on RHEL 9/10.

## Reading the results

| Column | Meaning |
|---|---|
| Received | Datagrams the kernel delivered to this socket |
| Accepted | Datagrams that passed every check |
| Foreign delivered | Delivered datagrams that do not belong to the route: other group, other interface, or (T-MCI-05) other source |
| Rejections | Verdict counts for the foreign datagrams |

| Evidence requirement | How it is checked |
|---|---|
| Receiver ready | Each receiver writes a unique `-ready-file` marker after socket setup; the runner waits with a deadline |
| Full observation window | Every receiver must exit successfully with `complete: true` and `termination: deadline` |
| Sender succeeded | Every sender must exit successfully and report `sent: 200`, `errors: 0` |
| Own traffic delivered | Every route receiver must accept exactly 200 multicast datagrams |
| Foreign traffic delivered to the environment | T-MCI-03/04 also validate and report the unrelated receiver's 200 own datagrams |
| Both SSM sources work | A separate ASM control window must receive all 400 datagrams before the SSM window; the ASM socket is closed before recording SSM reports |
| SSM isolation | The SSM receiver must accept only the 200 allowed-source datagrams; foreign delivery/rejection counts remain visible |
| Unicast injection | `OD17-UC` captures 200 datagrams addressed to the gateway's local unicast address and port; the sole wildcard-bound receiver must reject all 200 as `wrong_destination`; a group-bound receiver receives none of them |
| Capture process | Must start listening before traffic; exit 0 or planned timeout 124 is expected; other exit codes invalidate the run |

Zero foreign delivery supports kernel suppression only when the positive controls
succeed. Nonzero foreign delivery with matching rejections demonstrates the
per-datagram boundary instead. The latter does not establish kernel suppression.

Missing, malformed or incomplete summaries, failed processes and failed positive
controls produce a nonzero runner exit and an explicit **INVALID** message. Raw
JSON, readiness markers, stderr and captures remain in the printed temporary
directory for investigation. Do not use an invalid run to resolve OD-09/OD-17.

A capture with no matching IGMP report records zero rather than aborting report
generation. Missing IGMPv3/source evidence is marked **MISSING** in the report;
the runner exits nonzero after saving the report, and SSM wire qualification
stays incomplete until investigated. The text matching is
an evidence aid, not a substitute for reviewing the capture.

Signals end a receiver early with `complete: false`, `termination: closed` and
nonzero exit. Unexpected read failures use `termination: read_error`, retain a
stderr diagnostic and also exit nonzero. Only expiration of the requested
observation window sets `complete: true`.

## Regression checks

These checks do not create namespaces or send packets:

```bash
go test ./...
python3 prototypes/od09-isolation/test_harness.py
```

They cover rejection precedence, unicast destination checks, receive termination,
child failures, summary validation, positive-control counts, missing IGMP matches
and capture timeout handling. Privileged Debian/RHEL runs are still required to
establish actual kernel behavior.

## After the runs

1. Complete each results file's Interpretation section.
2. Record the outcome in OD-09 "Investigation results", with links to the files.
3. Note in OD-17 whether unicast reaching a wildcard-bound socket was rejected as
   assumed, using the dedicated `OD17-UC` rows and retained unicast captures.

IPv6 (T-MCI-06) is not covered yet.
