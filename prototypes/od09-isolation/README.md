# OD-09 isolation prototype

Throwaway experiment for [OD-09](../../docs/mcgw-open-decisions.md#od-09): which
IPv4 socket options and per-datagram checks keep one route's multicast receiver
from seeing other groups, other interfaces or other sources. It is not mcgw code,
and the daemon must not import it. Machine setup is in
[test/README.md](../../test/README.md).

## What it runs

`run-mci.sh` runs test-plan cases
[T-MCI-01 to T-MCI-05](../../docs/mcgw-test-plan.md#mci--multicast-isolation)
in the shared namespace environment, once for each option set:

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
sudo prototypes/od09-isolation/run-mci.sh      # about 2 minutes
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

A `Foreign delivered` of 0 means the kernel kept unrelated traffic away from the
socket. A nonzero value with matching rejections means the per-datagram checks
caught it instead. OD-09 needs both facts per kernel: the architecture requires
kernel suppression with the checks as a second boundary.

Expected own traffic per receiver is 200 datagrams (400 for T-MCI-05, of which
200 are from the wrong source).

## After the runs

1. Complete each results file's Interpretation section.
2. Record the outcome in OD-09 "Investigation results", with links to the files.
3. Note in OD-17 whether unicast reaching a wildcard-bound socket was rejected as
   assumed (T-MCI-01 and T-MCI-03 show the destination check working).

IPv6 (T-MCI-06) is not covered yet.
