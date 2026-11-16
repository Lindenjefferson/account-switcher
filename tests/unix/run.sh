#!/usr/bin/env bash
# Runs every tests/unix/*.test.sh. Usage: tests/unix/run.sh   (or: bash tests/unix/run.sh)
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
status=0
for t in *.test.sh; do
    bash "$t" || status=1
done
[ $status -eq 0 ] && echo "ALL OK" || echo "THERE WERE FAILURES" >&2
exit $status
