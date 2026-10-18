# Resumed scheduled prototype review

Completed 2026-10-17 against baseline `8bfb958`. This finishes the interrupted
scheduled code review; it does not qualify the prototype on the lab platforms.
Scope: the throwaway OD-09 prototype, shared test tools, namespace environment,
evidence rules, regression checks and related documentation. No daemon work.

## Confirmed findings and resolutions

| ID | Severity | Finding | Resolution and regression evidence |
|---|---|---|---|
| R1 | High | Cleanup could fail after installing a report marked VALID/REVIEW, leaving a usable-looking report for an INVALID run | Teardown must succeed before publication; successful teardown is not repeated by EXIT. Tests cover success, failure, retained raw draft and no published report on failure |
| R2 | Medium | SSM any-source controls accepted 400 packets from .20 and none from .21 because only the combined total was checked | C-05 and U-05b require exactly N accepted from each source. Harness tests cover N/N, missing source, duplication and imbalance |
| R3 | Medium | A report named the current checkout without identifying stale or custom executables used for measurements | Run private snapshots; retain original paths, SHA256 hashes and available Go build metadata. Distinguish harness revision from executable source revisions. Tests verify preserved bytes after original replacement and a custom executable evidence parent containing spaces |
| R4 | Medium | A failed namespace listing allowed startup and made status report an absent environment | Check listing status before creation or absence claims; status uses one snapshot. Four mocked enumeration regressions |
| R5 | Medium | Concurrent runners could delete each other's shared namespaces | Runner lifetime and standalone environment mutations share `/run/mcgw-test.lock`; child commands reuse the inherited lock. Tests prove exclusion, inherited reuse and release |
| R6 | Medium | The output existence check and subsequent install could race, overwriting a newly created destination | Stage on the output filesystem, then link atomically without replacement. Tests cover existing files, symlinks, a racing destination and staging cleanup |

Final review caught an execution-location regression in R3: snapshots originally
required executable `/tmp`, undermining the custom BIN_DIR workaround. The runner
now accepts `[BIN_DIR [EVIDENCE_PARENT]]`; documentation shows a permitted
`/usr/local/libexec` parent. The mocked-main regression exercises that path.

## Independent reviewer coverage

| Reviewer | Coverage and result |
|---|---|
| Go | Socket ownership, ancillary parsing, rejection precedence, flags, signals, readiness, deadlines, pacing and toolchain portability. No new confirmed Go defect |
| Shell | Child exits, cleanup, namespace lifecycle, error propagation, enumeration, concurrent runs and publication. Confirmed R1/R4/R5/R6 |
| Evidence | Positive controls, ASM/SSM overlap, unicast/broadcast/local-origin validity, captures, prediction/report consistency and retained evidence. Confirmed R1/R2/R3 |
| Final integration | Independently reviewed fixes and documentation, ran all 35 mock regressions, found the executable-directory regression above and approved its correction. No unresolved confirmed finding |

## Validation

Temporary Go/lint caches were used. No system tool or dependency was installed or
upgraded. All commands were run from the repository root.

| Check | Result |
|---|---|
| `gofmt -l .` | Pass, no output |
| `go test ./...`, `go vet ./...`, `go test -race ./...` | Pass with Go 1.24.4 on Linux amd64 |
| `GOTOOLCHAIN=go1.22.12 go test ./...` | Pass with cached minimum toolchain |
| `golangci-lint run ./...` | Pass, 0 issues (2.14.0); writable temporary lint cache |
| `shellcheck -x -P SCRIPTDIR test/netns/*.sh test/build.sh prototypes/od09-isolation/*.sh` | Pass (0.10.0) |
| `python3 prototypes/od09-isolation/test_harness.py` | Pass, 16 tests |
| `python3 prototypes/od09-isolation/test_runner.py` | Pass, 15 tests |
| `python3 test/netns/test_env.py` | Pass, 4 tests; mocks only |
| `python3 test/test_tools.py` | Pass, 8 loopback process tests in the primary session. A reviewer's separate sandbox denied sockets; its failed run is not counted as passing |
| `python3 scripts/check-docs.py`, `python3 scripts/test_check_docs.py` | Pass, local documentation checks and 8 checker regressions. Full Mermaid rendering is not covered |
| `git diff --check` | Pass |
| `govulncheck ./...` | Advisory remains, exit 3: GO-2026-4971 in Go 1.24.4 `net`, with a `mcsend` → `net.ResolveUDPAddr` trace. Scanner v1.9.0 also lists 5 imported-package and 54 module advisories without called symbols. This is not a clean scan |

The existing GO-2026-4971 advisory concerns a Windows panic, fixed in Go 1.25.10.
No toolchain update was made to hide it. The module minimum remains Go 1.22;
daemon toolchain policy remains OD-18.

## Remaining platform qualification

Run the real privileged experiment on dedicated Debian 13, RHEL 9 and RHEL 10
machines following the [prototype guide](README.md) and [test setup](../../test/README.md).
Record exact kernel/toolchain versions, ASM/SSM delivery and predicted leaks,
IGMP joins, OD17 inputs and rejections, loopback capture multiplicity, namespace
creation/teardown and SELinux/noexec behavior. Investigate REVIEW rows before
using them. No privileged multicast experiment or host networking change was
performed during this review, and no OD-09 platform result is claimed.

After evidence returns, complete report interpretations and update OD-09/OD-17
and the RHEL toolchain rows for OD-18. A passing code review cannot settle them.

## Advisory reference

The vulnerability scanner supplied the primary advisory
[GO-2026-4971](https://pkg.go.dev/vuln/GO-2026-4971). No online research was used to
change the experiment's existing kernel predictions.
