#!/usr/bin/env bash
# Build the test tools and prototypes into test/bin. Run as a normal user.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $(id -u) -eq 0 ]]; then
    echo "warning: building as root leaves root-owned Go caches; prefer a normal user" >&2
fi
command -v go >/dev/null || { echo "error: go not found (see test/README.md)" >&2; exit 1; }
mkdir -p "$repo/test/bin"
cd "$repo"
go build -o "$repo/test/bin/" ./test/tools/... ./prototypes/...
ls -1 "$repo/test/bin"
