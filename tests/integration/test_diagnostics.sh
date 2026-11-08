#!/usr/bin/env bash
#
# Assert the service, kernel and storage reports.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

report_dir=/var/log/server-baseline
hostname="$(user_config server_hostname)"

assert_eq "the report directory exists" "0" \
  "$(guest_root "test -d $report_dir; echo \$?")"

for report in service-audit kernel-status storage; do
  path="$report_dir/$report.txt"
  assert_eq "$report.txt exists" "0" "$(guest_root "test -f $path; echo \$?")"
  assert_eq "$report.txt is 0640" "640" "$(guest_root "stat -c '%a' $path")"
  assert_eq "$report.txt is owned by root" "root:root" "$(guest_root "stat -c '%U:%G' $path")"
  assert_nonempty "$report.txt is not empty" "$(guest_root "cat $path")"
done

audit="$(guest_root "cat $report_dir/service-audit.txt")"
assert_contains "the service audit lists running services" "$audit" "## Running services"
assert_contains "the service audit lists enabled units" "$audit" "## Enabled unit files"
assert_contains "the service audit lists failed units" "$audit" "## Failed units"
assert_contains "the service audit lists listeners" "$audit" "## Listening sockets"
assert_contains "the service audit names the host" "$audit" "$hostname"
assert_contains "the service audit shows sshd listening" "$audit" "sshd"

kernel="$(guest_root "cat $report_dir/kernel-status.txt")"
assert_contains "the kernel report lists the running kernel" "$kernel" "## Running kernel"
assert_contains "the kernel report lists kernel packages" "$kernel" "## Installed kernel packages"
assert_contains "the kernel report lists pending upgrades" "$kernel" "## Pending kernel upgrades"
assert_contains "the kernel report lists pending restarts" "$kernel" "## Pending service restarts"
assert_contains "the kernel report states the reboot requirement" "$kernel" "## Reboot required"
assert_contains "the kernel report names the running kernel" "$kernel" "$(guest 'uname -r')"

storage="$(guest_root "cat $report_dir/storage.txt")"
assert_contains "the storage report lists block devices" "$storage" "## Block devices"
assert_contains "the storage report lists the mount table" "$storage" "## Mount table"
assert_contains "the storage report lists filesystem usage" "$storage" "## Filesystem usage"
assert_contains "the storage report lists filesystem identifiers" "$storage" "## Filesystem identifiers"
assert_contains "the storage report lists full filesystems" "$storage" "percent"
assert_contains "the storage report shows the root filesystem" "$storage" "/dev/vda1"

assert_contains "no unit failed" "$(guest 'systemctl --failed --no-pager --plain')" "0 loaded units listed"

# The reporting roles must not change system state.
before_units="$(guest 'systemctl list-unit-files --state=enabled --no-pager --plain')"
before_failed="$(guest 'systemctl --failed --no-pager --plain')"
if make vagrant-provision >/dev/null 2>&1; then
  baseline_ok "re-provisioning succeeds"
else
  baseline_fail "re-provisioning succeeds"
fi
assert_eq "the enabled unit set is unchanged" "$before_units" \
  "$(guest 'systemctl list-unit-files --state=enabled --no-pager --plain')"
assert_eq "the failed unit set is unchanged" "$before_failed" \
  "$(guest 'systemctl --failed --no-pager --plain')"

finish
