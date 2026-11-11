#!/usr/bin/env bash
#
# Assert the nftables input and forward extension points.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

table=baseline_filter
input_dir=/etc/nftables.d/input
forward_dir=/etc/nftables.d/forward
input_fragment="$input_dir/90-baseline-probe.nft"
forward_fragment="$forward_dir/90-baseline-probe.nft"
input_marker=192.0.2.123
forward_marker=192.0.2.124

cleanup() {
  guest_root "rm -f $input_fragment $forward_fragment" >/dev/null 2>&1
  guest_root 'nft -f /etc/nftables.conf' >/dev/null 2>&1
}
trap cleanup EXIT

# line_of <text> <literal> - the first line number containing the literal.
line_of() {
  printf '%s\n' "$1" | grep -nF "$2" | head -n 1 | cut -d: -f1
}

for dir in "$input_dir" "$forward_dir"; do
  assert_eq "$dir exists" "0" "$(guest_root "test -d $dir; echo \$?")"
  assert_eq "$dir is root:root 0755" "root:root 755" \
    "$(guest_root "stat -c '%U:%G %a' $dir")"
done

# The includes must sit inside their chains, not at the top level.
rendered="$(guest_root "cat /etc/nftables.d/10-server-baseline.nft")"
input_chain="$(line_of "$rendered" 'chain input {')"
input_include="$(line_of "$rendered" "include \"$input_dir/*.nft\"")"
forward_chain="$(line_of "$rendered" 'chain forward {')"
forward_include="$(line_of "$rendered" "include \"$forward_dir/*.nft\"")"
output_chain="$(line_of "$rendered" 'chain output {')"

assert_eq "the input include is inside the input chain" "yes" \
  "$([ -n "$input_include" ] && [ "$input_include" -gt "$input_chain" ] \
     && [ "$input_include" -lt "$forward_chain" ] && echo yes || echo no)"
assert_eq "the forward include is inside the forward chain" "yes" \
  "$([ -n "$forward_include" ] && [ "$forward_include" -gt "$forward_chain" ] \
     && [ "$forward_include" -lt "$output_chain" ] && echo yes || echo no)"

# An empty drop-in directory is accepted.
assert_eq "empty extension directories validate" "0" \
  "$(guest_root 'nft -c -f /etc/nftables.conf >/dev/null 2>&1; echo $?')"

# A fragment contributes rules to the enclosing chain.
guest "printf '%s\n' 'ip saddr $input_marker tcp dport 9 accept' | sudo -n tee $input_fragment >/dev/null"
guest "printf '%s\n' 'ip saddr $forward_marker ip daddr 192.0.2.125 accept' | sudo -n tee $forward_fragment >/dev/null"

assert_eq "the fragments validate" "0" \
  "$(guest_root 'nft -c -f /etc/nftables.conf >/dev/null 2>&1; echo $?')"

guest_root 'nft -f /etc/nftables.conf'
assert_contains "the input fragment rule is active in the input chain" \
  "$(guest_root "nft -s list chain inet $table input")" "$input_marker"
assert_contains "the forward fragment rule is active in the forward chain" \
  "$(guest_root "nft -s list chain inet $table forward")" "$forward_marker"
assert_not_contains "the input fragment rule is not in the forward chain" \
  "$(guest_root "nft -s list chain inet $table forward")" "$input_marker"

# A re-apply of the baseline preserves the externally managed fragments.
baseline_apply >/dev/null
assert_eq "the fragment file survives a re-apply" "0" \
  "$(guest_root "test -f $input_fragment; echo \$?")"
assert_contains "the input fragment rule survives a re-apply" \
  "$(guest_root "nft -s list chain inet $table input")" "$input_marker"

# A restart of the nftables service keeps the rule active.
guest_root 'systemctl restart nftables'
assert_contains "the input fragment rule survives a service restart" \
  "$(guest_root "nft -s list chain inet $table input")" "$input_marker"

# A reboot loads it again.
ready=0
guest_reboot && ready=1
assert_eq "the guest is reachable after the reboot" "1" "$ready"
assert_contains "the input fragment rule survives a reboot" \
  "$(guest_root "nft -s list chain inet $table input")" "$input_marker"

# Removing the fragment removes the rule.
guest_root "rm -f $input_fragment $forward_fragment"
guest_root 'nft -f /etc/nftables.conf'
assert_not_contains "the input fragment rule is removed" \
  "$(guest_root "nft -s list chain inet $table input")" "$input_marker"
assert_not_contains "the forward fragment rule is removed" \
  "$(guest_root "nft -s list chain inet $table forward")" "$forward_marker"

finish
