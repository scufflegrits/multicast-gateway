# OD-09 isolation results

One file per run, written by `../run-mci.sh` and named
`<date>-<time>-<os><version>-<kernel>.md` (local time; never overwritten).

Each file records:
- the run status (VALID or REVIEW, with reasons for REVIEW)
- the date in UTC, the OS and kernel, and the iproute2 and tcpdump versions
- the prototype's Go runtime version and the repository commit (`-dirty` marks local changes)
- the gateway `rp_filter` and `force_igmp_version` values, and the socket options used
- the traffic volume and the number of T-MCI-05 captures containing the IGMPv3 join record
- one row per receiver per option set, with the prediction and whether it matched

INVALID runs write no file here. See
[Run outcomes](../README.md#run-outcomes).

Commit a VALID file after completing its Interpretation section. Commit a REVIEW
file only after investigating its reasons and recording them in Interpretation.
Then summarize the outcome in
[OD-09](../../../docs/mcgw-open-decisions.md#od-09).

No runs recorded yet.
