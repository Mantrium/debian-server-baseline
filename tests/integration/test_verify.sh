#!/usr/bin/env bash
#
# Assert the integrated verification, maintenance and audit playbooks.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

report_dir=/var/log/server-baseline

if make verify >/dev/null 2>&1; then
  baseline_ok "make verify succeeds"
else
  baseline_fail "make verify succeeds"
fi

if make maintenance >/dev/null 2>&1; then
  baseline_ok "make maintenance succeeds"
else
  baseline_fail "make maintenance succeeds"
fi

if make security-audit >/dev/null 2>&1; then
  baseline_ok "make security-audit succeeds"
else
  baseline_fail "make security-audit succeeds"
fi

for report in maintenance-report security-audit; do
  path="$report_dir/$report.txt"
  assert_eq "$report.txt exists" "0" "$(guest_root "test -f $path; echo \$?")"
  assert_eq "$report.txt is 0640" "640" "$(guest_root "stat -c '%a' $path")"
  assert_nonempty "$report.txt is not empty" "$(guest_root "cat $path")"
done

maintenance="$(guest_root "cat $report_dir/maintenance-report.txt")"
assert_contains "the maintenance report lists pending upgrades" "$maintenance" "## Pending upgrades"
assert_contains "the maintenance report lists critical updates" "$maintenance" "## Critical updates"
assert_contains "the maintenance report lists security support" "$maintenance" "## Security support"
assert_contains "the maintenance report lists pending restarts" "$maintenance" "## Pending service restarts"
assert_contains "the maintenance report states the reboot requirement" "$maintenance" "## Reboot required"

audit="$(guest_root "cat $report_dir/security-audit.txt")"
assert_contains "the audit lists the SSH configuration" "$audit" "## SSH configuration"
assert_contains "the audit lists the firewall ruleset" "$audit" "## Firewall ruleset"
assert_contains "the audit lists enabled units" "$audit" "## Enabled unit files"
assert_contains "the audit lists listening sockets" "$audit" "## Listening sockets"
assert_contains "the audit lists security support" "$audit" "## Security support"
assert_contains "the audit lists the running kernel" "$audit" "## Running kernel"
assert_contains "the audit shows the hardened SSH configuration" "$audit" "permitrootlogin no"
assert_contains "the audit shows the firewall table" "$audit" "table inet baseline_filter"

finish
