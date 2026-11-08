#!/usr/bin/env bash
#
# Assert the host identity established by the os_identity role.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

expected_hostname="$(user_config server_hostname)"
expected_timezone="$(user_config server_timezone)"

assert_nonempty "server_hostname is configured" "$expected_hostname"
assert_nonempty "server_timezone is configured" "$expected_timezone"

assert_eq "static hostname" "$expected_hostname" "$(guest 'hostnamectl --static')"
assert_eq "transient hostname" "$expected_hostname" "$(guest hostname)"
assert_eq "/etc/hostname" "$expected_hostname" "$(guest 'cat /etc/hostname')"

assert_eq "timezone" "$expected_timezone" "$(guest 'timedatectl show --property=Timezone --value')"

assert_contains "/etc/hosts maps the hostname to 127.0.1.1" \
  "$(guest "grep -E '^127\.0\.1\.1[[:space:]]' /etc/hosts")" \
  "127.0.1.1 $expected_hostname"

assert_contains "en_US.UTF-8 is generated" "$(guest 'locale -a')" "en_US.utf8"
assert_contains "en_US.UTF-8 is enabled in /etc/locale.gen" \
  "$(guest "grep -E '^en_US\.UTF-8[[:space:]]' /etc/locale.gen")" \
  "en_US.UTF-8 UTF-8"
assert_eq "LANG is selected" "en_US.UTF-8" \
  "$(guest "grep -E '^LANG=' /etc/default/locale | cut -d= -f2")"

finish
