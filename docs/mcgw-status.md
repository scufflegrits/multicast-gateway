# mcgw project status and next steps

**Last updated:** 2026-10-17, after the ten-reviewer prototype review (see `git log`). Read this first
when picking the project back up. Update it whenever you stop for more than a day.

## Where things stand

| Area | State |
|---|---|
| Design | Architecture agreed in principle; no daemon code yet |
| Second review (`temp2.md`) | All findings F01–F22 addressed in docs and the checker; dispositions in [architecture review §7](architecture-review.md#7-second-review-dispositions). Only device/OS lab qualification (its step 7) remains |
| Test plan | [47 cases](mcgw-test-plan.md) (43 Ready, 4 Draft) plus 13 lab/qualification stubs; contract gaps G1–G7 all resolved |
| Open decisions resolved this session | OD-16 (test-build-only fault hooks), OD-17 (no static cycle rejection; warn on local sinks at route ports) |
| Open decisions added | OD-18 (daemon Go toolchain/version policy) |
| First code | Namespace test environment, `mcsend`/`mcrecv` tools and the OD-09 isolation prototype. Reviewed twice (the second time by ten parallel reviewers) and hardened: readiness markers, positive controls, kernel-semantics predictions with expected-leak negative controls, T-MCI-05b overlapping membership, OD-17 unicast/broadcast/local-origin checks, VALID/REVIEW/INVALID outcomes. Go, harness and loopback regression checks pass. **Privileged namespace experiment not yet run**: needs a separate lab machine. Lessons for future prototypes: [prototypes/lessonslearned.md](../prototypes/lessonslearned.md) |
| Feature backlog | [FI-01](mcgw-feature-ideas.md#fi-01) read-only browser status page (Candidate, after OD-15) |

## Next step: run the OD-09 prototype on the test machines

Do this on **each** of Debian 13, RHEL 9 and RHEL 10. Full instructions:
[test/README.md](../test/README.md).

```bash
# 1. Install packages
sudo apt install -y git golang-go iproute2 tcpdump jq python3   # Debian 13
sudo dnf install -y git golang iproute tcpdump jq python3       # RHEL 9 / 10

# 2. Record the Go versions (needed for test/README.md and OD-18)
go version
go env GOTOOLCHAIN GOPROXY
dnf info golang          # RHEL only
apt-cache policy golang-go   # Debian only

# 3. Get the code and build as a normal user
git clone https://github.com/scufflegrits/multicast-gateway.git
cd multicast-gateway
test/build.sh

# 4. Run the prototype (about 5 minutes; over SSH use tmux or screen)
sudo prototypes/od09-isolation/run-mci.sh
echo $?   # 0 VALID, 3 REVIEW (report kept, needs review), other INVALID (no report)

# 5. Optional: vulnerability scan with that machine's Go
go install golang.org/x/vuln/cmd/govulncheck@latest
"$(go env GOPATH)"/bin/govulncheck ./...

# 6. Return the results: VALID after completing Interpretation; REVIEW only after
#    investigating its reasons; never after INVALID
git add prototypes/od09-isolation/results/
git commit -m "OD-09 isolation results: <os> <kernel>"
git push
```

Write down, per machine, the output of step 2 and step 5, or paste it into the
results file before committing.

### If the first run fails

These failure modes could not be exercised before handoff (no root on the
development machine):

| Symptom | Likely cause | What to capture |
|---|---|---|
| `ip link add ... netns` error from `env.sh up` | That iproute2 cannot create veth pairs directly inside namespaces | `ip -V` output and the exact error |
| INVALID: receiver not ready / sender process failed (RHEL) | SELinux or a `noexec` home blocking `test/bin` | `sudo ausearch -m avc -ts recent`; retry with the binaries copied outside the home directory (prototype README, "Run it") |
| INVALID (other) | Child failure, incomplete summary, failed positive control or capture | The raw directory printed at the end: sender JSON, receiver stderr and capture stderr |
| REVIEW: SSM join report missing | tcpdump's IGMP text differs from the pattern, or the join report was not sent | The `igmp-05-*.txt` files in the raw directory |
| REVIEW: cells differ from predictions | The kernel behaves differently from the documented prediction | The report's Review reasons and the matching raw JSON |

Bring the output back and ask for the scripts or predictions to be corrected.

## After the results are back

1. Complete the Interpretation section in each results file
   (`prototypes/od09-isolation/results/`): which option set stopped
   cross-delivery in the kernel, and whether the per-datagram checks caught the rest.
2. Record the outcome in [OD-09](mcgw-open-decisions.md#od-09) "Investigation results"
   and decide OD-09.
3. Record in [OD-17](mcgw-open-decisions.md#od-17) what the `OD17` rows show
   for the bind chosen under OD-09: external unicast and broadcast should be not
   delivered or rejected as `wrong_destination`, local-origin traffic not delivered
   or rejected as `wrong_ingress`. If any of it is accepted, OD-17 reopens.
4. Fill in the RHEL 9 and RHEL 10 rows of the
   [Go versions table](../test/README.md#go-versions) and add the evidence to
   [OD-18](mcgw-open-decisions.md#od-18).

## Queue after that

| Order | Item | Notes |
|---|---|---|
| 1 | Decide OD-18 (Go toolchain policy) | Needs the RHEL Go versions from above |
| 2 | OD-11 reload prototype | Needs a minimal daemon skeleton first |
| 3 | Settle numbers for OD-12 and names for OD-15 | Unblocks the most test cases (13 and 10) |
| 4 | Qualify two harness methods | `tbf` slow-sink (T-ISO-02) and netlink overflow (T-IFR-08) |
| 5 | Add a receive-overflow test | Traceability gap under OD-06 |
| 6 | Lab and qualification stubs | T-LAB-01..07, T-QUA-01..06; needs lab time |

## Notes for this workstation

| Item | Detail |
|---|---|
| Go | Debian's Go 1.24.4 is at `/usr/lib/go/bin` and is not on `PATH`; add `export PATH=/usr/lib/go/bin:$HOME/.local/bin:$PATH` to `~/.bashrc` if wanted |
| govulncheck | `~/.local/bin/govulncheck` rebuilt with Go 1.27.2; old binary kept as `govulncheck.go1.26.bak` |
| Expected govulncheck result | Clean with Go 1.27.2; with Go 1.24.4 it reports GO-2026-4971 (Windows-only, not reachable on Linux) |
| Checks before committing | `python3 scripts/check-docs.py`; for Go changes also `gofmt -l .`, `go vet ./...`, `golangci-lint run ./...`, `go test -race ./...`; for prototype or tool changes also `python3 prototypes/od09-isolation/test_harness.py`, `python3 test/test_tools.py` and `shellcheck -x -P SCRIPTDIR` on the scripts |

## Resuming with Claude Code

Start a session in this repository and ask it to read `docs/mcgw-status.md`. If
results have been pushed from the test machines, `git pull` first.
