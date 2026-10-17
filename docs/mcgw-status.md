# mcgw project status and next steps

**Last updated:** 2026-10-17, following commit `000c34b` and the prototype review fixes. Read this first
when picking the project back up. Update it whenever you stop for more than a day.

## Where things stand

| Area | State |
|---|---|
| Design | Architecture agreed in principle; no daemon code yet |
| Second review (`temp2.md`) | All findings F01–F22 addressed in docs and the checker; dispositions in [architecture review §7](architecture-review.md#7-second-review-dispositions). Only device/OS lab qualification (its step 7) remains |
| Test plan | [47 cases](mcgw-test-plan.md) (43 Ready, 4 Draft) plus 13 lab/qualification stubs; contract gaps G1–G7 all resolved |
| Open decisions resolved this session | OD-16 (test-build-only fault hooks), OD-17 (no static cycle rejection; warn on local sinks at route ports) |
| Open decisions added | OD-18 (daemon Go toolchain/version policy) |
| First code | Namespace test environment, `mcsend`/`mcrecv` tools and the OD-09 isolation prototype. Reviewed and hardened: readiness markers, positive controls, explicit child/summary validation and OD17-UC unicast injection. Unit/harness regressions and loopback process checks pass. **Privileged namespace experiment not yet run**: needs a separate lab machine |
| Feature backlog | [FI-01](mcgw-feature-ideas.md#fi-01) read-only browser status page (Candidate, after OD-15) |

## Next step: run the OD-09 prototype on the test machines

Do this on **each** of Debian 13, RHEL 9 and RHEL 10. Full instructions:
[test/README.md](../test/README.md).

```bash
# 1. Install packages
sudo apt install -y git golang-go iproute2 tcpdump jq       # Debian 13
sudo dnf install -y git golang iproute tcpdump jq           # RHEL 9 / 10

# 2. Record the Go versions (needed for test/README.md and OD-18)
go version
dnf info golang          # RHEL only
apt-cache policy golang-go   # Debian only

# 3. Get the code and build as a normal user
git clone https://github.com/scufflegrits/multicast-gateway.git
cd multicast-gateway
test/build.sh

# 4. Run the prototype (about 3 minutes)
sudo prototypes/od09-isolation/run-mci.sh

# 5. Optional: vulnerability scan with that machine's Go
go install golang.org/x/vuln/cmd/govulncheck@latest
~/go/bin/govulncheck ./...

# 6. Return the results
git add prototypes/od09-isolation/results/
git commit -m "OD-09 isolation results: <os> <kernel>"
git push
```

Write down, per machine, the output of step 2 and step 5, or paste it into the
results file before committing.

### If the first run fails

Two parts could not be tested before handoff:

| Symptom | Likely cause | What to capture |
|---|---|---|
| `ip link add ... netns` error from `env.sh up` | That iproute2 cannot create veth pairs directly inside namespaces | `ip -V` output and the exact error |
| Results mark IGMP evidence MISSING | tcpdump's verbose IGMP text differs from the pattern searched | The `igmp-05-*.txt` files in the raw output directory the script prints |
| Runner reports INVALID | Child failure, incomplete summary or failed positive control | Raw directory printed by cleanup; sender JSON, receiver stderr and capture stderr |
| Script hangs | A receiver did not exit | Which case was running; `sudo test/netns/env.sh down` cleans up |

Either way, bring the error output back and ask for the script to be fixed.

## After the results are back

1. Complete the Interpretation section in each results file
   (`prototypes/od09-isolation/results/`): which option set stopped
   cross-delivery in the kernel, and whether the per-datagram checks caught the rest.
2. Record the outcome in [OD-09](mcgw-open-decisions.md#od-09) "Investigation results"
   and decide OD-09.
3. Confirm in [OD-17](mcgw-open-decisions.md#od-17) that unicast reaching a
   wildcard-bound socket is rejected as `wrong_destination` (`OD17-UC` rows and
   retained unicast captures).
   If not, OD-17 reopens.
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
| Checks before committing | `python3 scripts/check-docs.py`; for Go changes also `gofmt -l .`, `go vet ./...`, `golangci-lint run ./...` |

## Resuming with Claude Code

Start a session in this repository and ask it to read `docs/mcgw-status.md`. If
results have been pushed from the test machines, `git pull` first.
