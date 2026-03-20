#!/bin/bash
# Run all contagent tests and report overall results

set -uo pipefail

PASS=0
FAIL=0

for f in "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"/test-*.sh; do
  echo "--- $(basename "$f") ---"
  if bash "$f" "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  echo ""
done

echo "Test files: $((PASS + FAIL)) total, ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
