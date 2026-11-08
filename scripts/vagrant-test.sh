#!/usr/bin/env bash
#
# Run every tests/integration/test_*.sh against the Vagrant VM.
#
# Each test script is self-contained and exits non-zero on failure. The runner
# reports a per-file summary and exits non-zero if any test failed.

set -uo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .vagrant/vagrant-env.sh ]; then
  scripts/vagrant-inventory.sh
fi

# shellcheck disable=SC1091
set -a; . .vagrant/vagrant-env.sh; set +a

shopt -s nullglob
tests=(tests/integration/test_*.sh)

if [ ${#tests[@]} -eq 0 ]; then
  echo "No tests found in tests/integration/." >&2
  exit 1
fi

passed=0
failed=0
failed_names=()

for t in "${tests[@]}"; do
  printf '\n===== %s =====\n' "$t"
  if bash "$t"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_names+=("$t")
  fi
done

printf '\n===== summary =====\n'
printf 'passed: %d\n' "$passed"
printf 'failed: %d\n' "$failed"
for n in "${failed_names[@]:-}"; do
  [ -n "$n" ] && printf '  FAILED %s\n' "$n"
done

[ "$failed" -eq 0 ]
