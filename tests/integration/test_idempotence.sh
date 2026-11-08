#!/usr/bin/env bash
#
# Assert that a second provisioning run changes nothing.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

# provision - run the full baseline and return the last PLAY RECAP line.
provision() {
  make vagrant-provision 2>&1 | grep -E '^[a-z0-9_-]+ +: ok=' | tail -n 1
}

first="$(provision)"
second="$(provision)"

assert_nonempty "the first run reports a recap" "$first"
assert_nonempty "the second run reports a recap" "$second"

second_changed="$(printf '%s\n' "$second" | sed -n 's/.*changed=\([0-9]*\).*/\1/p')"
assert_eq "the second run changes nothing" "0" "${second_changed:-missing}"

finish
