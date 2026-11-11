#!/usr/bin/env bash
#
# Assert that the baseline survives a reboot.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

admin="$(user_config admin_username)"
public_key="$(user_config_resolved ssh_public_key_path)"
private_key="${public_key%.pub}"

before_boot="$(guest 'cat /proc/sys/kernel/random/boot_id')"

ready=0
guest_reboot && ready=1
assert_eq "the guest is reachable after the reboot" "1" "$ready"

after_boot="$(guest 'cat /proc/sys/kernel/random/boot_id')"
assert_eq "the guest actually rebooted" "different" \
  "$([ -n "$before_boot" ] && [ "$before_boot" != "$after_boot" ] && echo different || echo same)"

login="$(ssh -i "$private_key" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "$BASELINE_VAGRANT_PORT" \
  "$admin@$BASELINE_VAGRANT_HOST" 'echo key-auth-ok' 2>&1)"
assert_contains "key authentication still works" "$login" "key-auth-ok"

assert_eq "the hostname persists" "$(user_config server_hostname)" "$(guest 'hostnamectl --static')"
assert_eq "the timezone persists" "$(user_config server_timezone)" \
  "$(guest 'timedatectl show --property=Timezone --value')"

firewall="$(guest_root 'nft list table inet baseline_filter')"
assert_contains "the firewall table persists" "$firewall" "policy drop"
assert_eq "the firewall service is enabled" "enabled" "$(guest 'systemctl is-enabled nftables')"

sshd="$(guest_root 'sshd -T')"
assert_contains "the SSH hardening persists" "$sshd" "permitrootlogin no"
assert_contains "MaxAuthTries persists" "$sshd" "maxauthtries 3"

assert_nonempty "the journal directory persists" \
  "$(guest_root 'find /var/log/journal -mindepth 1 -maxdepth 1 -type d')"
boots="$(guest_root 'journalctl --list-boots' | grep -cE '^[[:space:]]*-?[0-9]+ ')"
if [ "${boots:-0}" -ge 2 ]; then
  baseline_ok "the journal lists at least two boots"
else
  baseline_fail "the journal lists at least two boots" "found ${boots:-0}"
fi

assert_contains "no unit failed" "$(guest 'systemctl --failed --no-pager --plain')" "0 loaded units listed"

finish
