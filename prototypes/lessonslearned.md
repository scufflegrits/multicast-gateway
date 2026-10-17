# Lessons learned from the prototypes

What writing, reviewing and fixing the OD-09 isolation prototype and the test
tools taught us, so the next prototype starts from here instead of rediscovering
it. Each lesson names the mistake or finding it came from. Add to this file
whenever a review or a lab run teaches something new.

Sources: the first prototype commit, the first hardening review (five findings),
and a second review by ten parallel reviewers covering bash logic, Linux socket
semantics, namespace portability, Go code, experiment design, tcpdump parsing,
test quality, operational safety, docs consistency and an end-to-end trace.

## Checklist for the next prototype

1. Write the predicted outcome of every case before writing code, from the
   kernel or protocol rules, including the cases that are expected to **leak**.
2. Give every case a positive control (the thing under test demonstrably
   happened) and, where possible, a negative control (an expected leak appears).
3. Test the exact scenario the decision is about, not a nearby one that is
   easier to set up.
4. Separate "the experiment broke" (INVALID) from "the result surprised us"
   (REVIEW) from "as predicted" (VALID), with distinct exit codes.
5. Record the effective settings read back from the system, not the requested ones.
6. Keep capture windows to the event being proved; match only the records that
   prove it.
7. Make the pure logic (parsing, classification, formatting) testable without root,
   and mutation-check those tests.
8. Run the full check list before every commit (end of this file).
9. Get an independent review before the first lab run; reviewers with different
   focus areas find different classes of problems.
10. Update the prototype README, the status file and this file in the same commit.

## Experiment design

| Lesson | Where it came from |
|---|---|
| **Positive controls are mandatory.** Zero cross-delivery means nothing if the receiver also got none of its own traffic. Assert each receiver accepted exactly its own N | First version would have reported "isolated" on a run where no traffic arrived |
| **Negative controls catch harness faults that look like success.** Predict which option sets must leak (for example a wildcard socket with `IP_MULTICAST_ALL=1`) and flag a run where they do not | Second review: an all-zero run would have read as "every option set isolates" |
| **Write predictions down and compare automatically.** A per-cell Predicted/Match column turns a wall of numbers into a short list of surprises | Second review; predictions came from the kernel-semantics reviewer |
| **A surprising result is data, not a broken run.** Prediction mismatches and missing optional evidence produce REVIEW (exit 3, report kept); only process, summary, control or capture failures produce INVALID | Second review found the old MISSING state was both "kept" and "INVALID" |
| **Test the real scenario.** OD-17 is about a sink on the gateway sending to itself; that traffic arrives through loopback and is classified `wrong_ingress`. Unicast from an external host tested a different path | Second review: the OD17-UC check proved the wrong claim |
| **Look for the layer that is really filtering.** A lone source-specific join makes the *interface* filter INCLUDE{source}, so a source-filter test passes before any socket sees the traffic. Add an overlapping any-source member (T-MCI-05b) to test the socket filter | Kernel-semantics and design reviewers, independently |
| **Know which receivers a datagram can reach.** Multicast goes to every matching socket; unicast goes to exactly one `SO_REUSEADDR` socket. Use a single socket when testing unicast | Kernel-semantics review |
| **Record effective settings.** Read `IP_MULTICAST_ALL` back with `getsockopt`, read the namespace sysctls, record tool versions and `git describe --dirty` | Design review: "default" was assumed to be 1 |
| **State what is not covered** in the report and README, so a passing run is not over-read | Design and docs reviews |
| **Exact counts beat volume** for deterministic kernel filtering; say so where the plan suggested more traffic | Docs review |

## Captures and evidence

| Lesson | Where it came from |
|---|---|
| **Teardown events leak into capture windows.** Closing a source-specific socket sends an IGMPv3 BLOCK record for the same source, so a loose pattern "proved" a join that was never captured. Stop the capture before the receivers close | tcpdump and end-to-end reviewers, independently |
| **Match only records that prove the claim.** Use `igmp v3 report.*gaddr G (allow\|to_in\|is_in) \{[^}]*S[ }]`; the trailing `[ }]` stops `.20` matching `.200` | tcpdump review, confirmed with synthetic pcaps |
| **Learn output formats from synthetic pcaps.** Write packets with a small Python script and decode them with `tcpdump -r file -nn -vv`, which needs no root. With `-vv`, IGMPv3 records stay on one line and UDP prints two lines per packet (IP header, then addresses) | tcpdump review |
| **Use `--immediate-mode` and stop captures explicitly.** Without it tcpdump buffers for up to about a second and loses the tail on SIGTERM | End-to-end review |
| **Readiness, not sleeps.** Wait for tcpdump's `listening on` on stderr and for a ready-marker file each receiver writes after joining | First hardening review |
| **Loopback captures may count a packet in both directions**; assert "at least" for `lo` | Kept conservative because it could not be verified without root |

## Linux and kernel facts

| Fact | Notes |
|---|---|
| `IP_MULTICAST_ALL` is 49 (not exported by Go's `syscall`); the default is 1 | With 1, a socket receives a group arriving on any interface where *some* socket joined it, whatever its bind. Binding to the group does not filter by interface; only `IP_MULTICAST_ALL=0` does |
| `struct in_pktinfo` is `{int ipi_ifindex; in_addr ipi_spec_dst; in_addr ipi_addr}` | `ipi_addr` (bytes 8–12) is the header destination; `ipi_spec_dst` is the local address. Ifindex is native-endian. Locally originated traffic reports the loopback ifindex |
| `struct ip_mreq_source` is `{multiaddr, interface, sourceaddr}` with an interface *address* | Ambiguous with unnumbered or shared addresses; the daemon should use `MCAST_JOIN_SOURCE_GROUP` (`group_source_req`, ifindex) |
| `udp_sendmsg` rejects destination port 0 with EINVAL and payloads over 65507 with EMSGSIZE, before routing | Safe ways to provoke a send failure in tests without emitting packets |
| Go enables `SO_BROADCAST` on every UDP socket by default | A test that expected EACCES for 255.255.255.255 sent two real broadcasts onto the LAN. Never use a send that might succeed as a "safe failure" |
| New network namespaces start from kernel defaults, not the host's sysctl.d values, unless `net.core.devconf_inherit_init_net=1` | Pin what matters (`rp_filter`, `force_igmp_version`) in the environment script |
| `ip link add A netns NS1 type veth peer name B netns NS2` creates both ends inside namespaces | The host's NetworkManager and udev never see them |
| `ip netns exec` executes the program directly | `$!` is the real process; signals reach it |
| A running process keeps a deleted namespace alive | `down` kills `ip netns pids` before `ip netns del` |

## Bash harness

| Lesson | Where it came from |
|---|---|
| **`$SECONDS` has one-second resolution.** A "3 s" deadline could give up after 2.2 s. Count attempts, and check the arithmetic: N attempts give N−1 sleeps | Bash and namespace reviewers; the off-by-one was caught by a new timing test |
| **Cleanup must ignore further signals.** `trap '' INT TERM` first, or a second Ctrl-C skips namespace removal | Three reviewers |
| **Wait for each PID and forget it once reaped**, so cleanup never signals a reused PID; never rely on a bare `wait` | First and second reviews |
| **Know the exit codes of wrappers.** GNU `timeout` returns 124 when it expires and 143 when it is sent SIGTERM itself; `grep -c` returns 1 for no match and 2 for errors | Verified with small experiments |
| **errexit has blind spots.** It does not fire inside `if`/`while` conditions, `||`/`&&` lists or a failing `$(...)` inside `[[ ]]` or `(( ))`; make those paths call `invalid` explicitly | Bash review |
| **Bound every child.** Senders get `timeout 15`; captures a safety `timeout 60` | Bash review |
| **Root writing into a user-owned directory is a symlink hazard.** Write the report to the private `mktemp -d` directory, refuse an existing or symlinked target, then `install -o user` it in place; use timestamped names so reruns never overwrite | Operational review |
| **Hand raw evidence back to the user.** `chown -R "$SUDO_USER"` the temporary directory at cleanup, and warn that `/tmp` is cleared on reboot | Operational and end-to-end reviews |
| **Never grant a sudo rule for a single script** that sources files or runs binaries from a user-writable checkout; it is equivalent to full root | Operational review |
| **Say when a runner destroys state**, such as removing an existing environment before starting | Docs and operational reviews |
| **ShellCheck needs `-x -P SCRIPTDIR`** and `# shellcheck source=` directives to follow sourced helpers | Repeated lint noise |

## Go tools

| Lesson | Where it came from |
|---|---|
| **Standard library only, and a low `go` directive**, so the tools build with distro Go; prove it with `GOTOOLCHAIN=go1.22.12 go test ./...` | Distro Go is 1.24 on Debian 13 and varies on RHEL |
| **`//go:build linux`** on tools that use Linux-only `syscall` APIs, so other platforms skip them instead of failing `go build ./...` | First lint review |
| **Close raw sockets on every error path.** With `syscall.Socket` use named results and a `defer` that closes on error; `net.FilePacketConn` duplicates the fd, so close the `os.File` afterwards | Go review |
| **Deterministic output.** Sort by comparing fields; `fmt.Sprint` keys collide (`"239.1.1.1",23` and `"239.1.1.12",3`) and sort numbers as text | Go review; regression test added |
| **Pacing must not burst after a stall**: reset the schedule when behind, and do not sleep after the last item | Go review |
| **Exit-code convention:** 0 success, 1 incomplete or failed work (summary still printed), 2 usage/setup; always print a summary with `complete` and `termination` | First hardening review |
| **Validate every flag** (port range, payload size, unknown interface), and print the first runtime error, not just a count | Go review |
| **Factor pure functions** (`verdict`, `pktinfo`, `sortOrigins`, `fillPayload`) so they can be tested without sockets; build control-message buffers in tests with `syscall.CmsgSpace` | Test review |
| **errcheck: check what matters, discard the rest explicitly** with `_ =` (teardown `Close`, per-line output) | First lint review |
| **govulncheck must be built with a Go at least as new as the `go` it runs**, and its findings depend on the toolchain's standard library | Lint and vulnerability review |

## Tests

| Lesson | Where it came from |
|---|---|
| **Mutation-check the tests.** Copy the code to a scratch module, break one thing, and confirm a test fails. Untested parsers and boundaries survived until this was done | Test review; now catches pktinfo, boundary and precedence mutations |
| **Test both sides of every check.** A validator tested only for rejection can be replaced by "always fail" without a test noticing | Test review (`expect_accept`) |
| **Assert why something failed**, for example `INVALID experiment` in stderr, not merely a nonzero exit, which a jq syntax error would also give | Test review |
| **Include exact boundaries** (n == max, n == max + 1) and combined failures that exercise precedence | Test review |
| **Timing tests assert lower bounds** and generous upper bounds | Caught the `wait_until` off-by-one |
| **Raw-string quoting in Python-driven shell tests is easy to get wrong**; prefer `"$2"` inside triple-quoted raw strings | One false failure in the new tests |

## Documentation

| Lesson | Where it came from |
|---|---|
| **Docs drift right after hardening.** Re-read every claim (counts, runtimes, exit codes, row types, file names) against the code after each change | Docs review found stale text from one commit earlier |
| **One definition of outcomes**, repeated consistently in the README, results README, test setup and status file | MISSING/INVALID contradiction |
| **Keep terminology distinct**: receiver = multicast receive socket; destination or sink = unicast output | Docs review |

## Checks before committing prototype or tool changes

Run from the repository root:

```bash
gofmt -l .
go vet ./...
golangci-lint run ./...
go test -race ./...
GOTOOLCHAIN=go1.22.12 go test ./...       # minimum supported Go
shellcheck -x -P SCRIPTDIR test/netns/*.sh test/build.sh prototypes/od09-isolation/*.sh
python3 prototypes/od09-isolation/test_harness.py
python3 test/test_tools.py
python3 scripts/check-docs.py
git diff --check
```
