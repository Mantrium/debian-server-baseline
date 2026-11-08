#!/usr/bin/env bash
#
# Assert the administrative account and its SSH key.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

admin="$(user_config admin_username)"
assert_nonempty "admin_username is configured" "$admin"

assert_eq "$admin exists" "0" "$(guest "id -u $admin >/dev/null 2>&1; echo \$?")"
assert_eq "$admin's shell" "/bin/bash" "$(guest "getent passwd $admin | cut -d: -f7")"
assert_eq "$admin's home directory" "/home/$admin" "$(guest "getent passwd $admin | cut -d: -f6")"
assert_contains "$admin is in the sudo group" "$(guest "id -nG $admin")" "sudo"

assert_eq "the SSH directory is 0700" "700" \
  "$(guest_root "stat -c '%a' /home/$admin/.ssh")"
assert_eq "authorized_keys is 0600" "600" \
  "$(guest_root "stat -c '%a' /home/$admin/.ssh/authorized_keys")"
assert_eq "authorized_keys is owned by $admin" "$admin:$admin" \
  "$(guest_root "stat -c '%U:%G' /home/$admin/.ssh/authorized_keys")"

public_key="$(user_config_resolved ssh_public_key_path)"
assert_nonempty "the configured public key path resolves" "$public_key"

expected_fingerprint="$(ssh-keygen -lf "$public_key" 2>/dev/null | awk '{print $2}')"
assert_nonempty "the configured public key has a fingerprint" "$expected_fingerprint"
assert_contains "the configured public key is installed" \
  "$(guest_root "ssh-keygen -lf /home/$admin/.ssh/authorized_keys 2>/dev/null | awk '{print \$2}'")" \
  "$expected_fingerprint"

# Log in the way an operator would, using the matching private key.
private_key="${public_key%.pub}"
login="$(ssh -i "$private_key" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -p "$BASELINE_VAGRANT_PORT" \
  "$admin@$BASELINE_VAGRANT_HOST" 'id -un; sudo -n true && echo sudo-ok' 2>&1)"
assert_contains "SSH login as $admin succeeds" "$login" "$admin"
assert_contains "passwordless sudo works for $admin" "$login" "sudo-ok"

assert_eq "the vagrant account is preserved" "0" \
  "$(guest 'id -u vagrant >/dev/null 2>&1; echo $?')"

finish
