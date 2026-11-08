#!/usr/bin/env bash
#
# Assert the nftables firewall.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

table="baseline_filter"
admin="$(user_config admin_username)"
public_key="$(user_config_resolved ssh_public_key_path)"
private_key="${public_key%.pub}"

assert_eq "nftables is enabled" "enabled" "$(guest 'systemctl is-enabled nftables')"
assert_eq "nftables is active" "active" "$(guest 'systemctl is-active nftables')"

listing="$(guest_root "nft list table inet $table")"
assert_contains "the baseline table exists" "$listing" "table inet $table"
assert_contains "the input chain drops by default" "$listing" "policy drop"
assert_contains "the forward chain drops by default" "$listing" "policy drop"
assert_contains "the output chain accepts by default" "$listing" "policy accept"
assert_contains "the SSH port is accepted" "$listing" "tcp dport 22 accept"
assert_contains "loopback is accepted" "$listing" 'iif "lo" accept'
assert_contains "established connections are accepted" "$listing" "ct state established,related accept"
assert_contains "ICMP is accepted" "$listing" "meta l4proto icmp accept"

# The entry point must not flush the whole ruleset. The comments mention the
# phrase, so only an active directive counts.
entrypoint="$(guest 'cat /etc/nftables.conf')"
assert_eq "the entry point does not flush the ruleset" "" \
  "$(guest "grep -E '^[[:space:]]*flush ruleset' /etc/nftables.conf")"
assert_contains "the entry point includes the drop-ins" "$entrypoint" 'include "/etc/nftables.d/*.nft"'

# The unit must not flush the whole ruleset when it stops.
unit="$(guest 'cat /etc/systemd/system/nftables.service.d/10-server-baseline.conf')"
assert_contains "the unit stops only the baseline table" "$unit" "destroy table inet $table"
assert_eq "the unit does not flush the ruleset" "" \
  "$(guest "grep -E '^[[:space:]]*ExecStop=.*flush ruleset' /etc/systemd/system/nftables.service.d/10-server-baseline.conf")"

# A pre-existing unrelated table must survive a re-apply of the baseline table.
guest_root 'nft add table inet unrelated_probe' >/dev/null 2>&1
guest_root 'nft -f /etc/nftables.d/10-server-baseline.nft' >/dev/null 2>&1
assert_contains "an unrelated table survives a re-apply" \
  "$(guest_root 'nft list tables')" "table inet unrelated_probe"
guest_root 'nft delete table inet unrelated_probe' >/dev/null 2>&1

# SSH must still work through the firewall.
login="$(ssh -i "$private_key" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
  -o LogLevel=ERROR \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -p "$BASELINE_VAGRANT_PORT" \
  "$admin@$BASELINE_VAGRANT_HOST" 'echo ssh-through-firewall-ok' 2>&1)"
assert_contains "SSH works through the firewall" "$login" "ssh-through-firewall-ok"

finish
