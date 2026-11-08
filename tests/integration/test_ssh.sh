#!/usr/bin/env bash
#
# Assert the SSH daemon hardening.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

admin="$(user_config admin_username)"
public_key="$(user_config_resolved ssh_public_key_path)"
private_key="${public_key%.pub}"

effective="$(guest_root 'sshd -T')"

assert_contains "root login is disabled" "$effective" "permitrootlogin no"
assert_contains "public key authentication is enabled" "$effective" "pubkeyauthentication yes"
assert_contains "password authentication is disabled" "$effective" "passwordauthentication no"
assert_contains "keyboard-interactive authentication is disabled" \
  "$effective" "kbdinteractiveauthentication no"
assert_contains "empty passwords are refused" "$effective" "permitemptypasswords no"
assert_contains "X11 forwarding is disabled" "$effective" "x11forwarding no"
assert_contains "MaxAuthTries is 3" "$effective" "maxauthtries 3"
assert_contains "LoginGraceTime is 30" "$effective" "logingracetime 30"

assert_eq "the configuration file is valid" "0" "$(guest_root 'sshd -t; echo $?')"

# Key authentication must still work.
key_login="$(ssh -i "$private_key" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -p "$BASELINE_VAGRANT_PORT" \
  "$admin@$BASELINE_VAGRANT_HOST" 'echo key-auth-ok' 2>&1)"
assert_contains "key authentication as $admin works" "$key_login" "key-auth-ok"

# Password authentication must not.
password_login="$(ssh \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "$BASELINE_VAGRANT_PORT" \
  "$admin@$BASELINE_VAGRANT_HOST" true 2>&1)"
assert_contains "password authentication is refused" "$password_login" "Permission denied"

# Root login must not.
root_login="$(ssh \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "$BASELINE_VAGRANT_PORT" \
  "root@$BASELINE_VAGRANT_HOST" true 2>&1)"
assert_contains "root login is refused" "$root_login" "Permission denied"

# Vagrant's own access must be untouched.
assert_eq "vagrant ssh still works" "0" \
  "$(vagrant ssh -c 'true' >/dev/null 2>&1; echo $?)"

finish
