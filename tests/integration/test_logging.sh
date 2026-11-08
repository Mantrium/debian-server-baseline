#!/usr/bin/env bash
#
# Assert persistent system logging and log rotation.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

assert_eq "/var/log/journal exists" "0" \
  "$(guest_root 'test -d /var/log/journal; echo $?')"
assert_nonempty "/var/log/journal holds a machine-id directory" \
  "$(guest_root 'find /var/log/journal -mindepth 1 -maxdepth 1 -type d')"

assert_contains "the journal reports its disk usage" \
  "$(guest_root 'journalctl --disk-usage')" "take up"

effective="$(guest_root 'systemd-analyze cat-config systemd/journald.conf')"
assert_contains "the journal is persistent" "$effective" "Storage=persistent"
assert_contains "the journal is compressed" "$effective" "Compress=yes"
assert_contains "the journal size is bounded" "$effective" "SystemMaxUse=500M"
assert_contains "the journal keeps free space" "$effective" "SystemKeepFree=1G"
assert_contains "the journal retention is bounded" "$effective" "MaxRetentionSec=1month"

assert_eq "the journal verifies" "0" "$(guest_root 'journalctl --verify >/dev/null 2>&1; echo $?')"
assert_contains "the journal records at least one boot" \
  "$(guest_root 'journalctl --list-boots')" "BOOT ID"

assert_eq "logrotate.timer is enabled" "enabled" "$(guest 'systemctl is-enabled logrotate.timer')"
assert_eq "logrotate.timer is active" "active" "$(guest 'systemctl is-active logrotate.timer')"

rotation="$(guest 'cat /etc/logrotate.d/server-baseline')"
assert_contains "the baseline reports are rotated" "$rotation" "/var/log/server-baseline/*.txt"
assert_contains "rotation keeps 8 generations" "$rotation" "rotate 8"
assert_contains "rotation compresses" "$rotation" "compress"

assert_eq "the logrotate configuration is valid" "0" \
  "$(guest_root 'logrotate --debug /etc/logrotate.conf >/dev/null 2>&1; echo $?')"

finish
