#!/usr/bin/env bash
#
# Assert the baseline_firewall_block_ipv6 switch.
#
# The role default blocks IPv6, so the test starts from the shipped default,
# turns blocking off to exercise the IPv6 paths, turns it back on to prove the
# drop, and turns it off again to prove the change is reversible without a
# reboot.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

table=baseline_filter
block_fixture=tests/fixtures/firewall-block-ipv6.yml
allow_fixture=tests/fixtures/firewall-allow-ipv6.yml
invalid_fixture=tests/fixtures/firewall-block-ipv6-invalid.yml
contradiction_fixture=tests/fixtures/firewall-block-ipv6-disabled-firewall.yml

probe_ns=baseline-probe
probe_host_if=baseline-probe0
probe_ns_if=baseline-probe1
probe_host_addr=2001:db8:1::1
probe_ns_addr=2001:db8:1::2

router_ns=baseline-router
router_host_if=baseline-rtr0
router_ns_if=baseline-rtr1
router_host_addr=2001:db8:2::1
router_ns_addr=2001:db8:2::2

forward_fragment=/etc/nftables.d/forward/90-baseline-probe.nft

# The kernel IPv6 configuration, captured before anything is applied.
sysctl_before="$(guest 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6 /proc/sys/net/ipv6/conf/default/disable_ipv6 /proc/sys/net/ipv6/conf/all/forwarding')"
forwarding_before="$(guest 'cat /proc/sys/net/ipv6/conf/all/forwarding')"
cmdline_before="$(guest 'cat /proc/cmdline')"
sysctl_files_before="$(guest_root 'ls /etc/sysctl.d/')"

cleanup() {
  guest_root "rm -f $forward_fragment" >/dev/null 2>&1
  guest_root "ip netns del $probe_ns" >/dev/null 2>&1
  guest_root "ip netns del $router_ns" >/dev/null 2>&1
  guest_root "ip link del $probe_host_if" >/dev/null 2>&1
  guest_root "ip link del $router_host_if" >/dev/null 2>&1
  guest_root "sysctl -q -w net.ipv6.conf.all.forwarding=${forwarding_before:-0}" >/dev/null 2>&1
  guest_root 'nft -f /etc/nftables.conf' >/dev/null 2>&1
}
trap cleanup EXIT

# assert_blocked <label> - the IPv6 drop is the first rule of all three chains.
assert_blocked() {
  for chain in input forward output; do
    rule="$(first_rule "$chain")"
    assert_contains "$1: the $chain chain drops IPv6 first" "$rule" "meta nfproto ipv6"
    assert_contains "$1: the $chain IPv6 rule drops" "$rule" "drop"
  done
}

# assert_not_blocked <label> - no chain carries an IPv6 drop rule.
assert_not_blocked() {
  for chain in input forward output; do
    assert_not_contains "$1: the $chain chain has no IPv6 drop rule" \
      "$(guest_root "nft -s list chain inet $table $chain")" "meta nfproto ipv6"
  done
}

# probe_up - create the probe namespace and its veth pair.
probe_up() {
  guest_root "ip netns add $probe_ns"
  guest_root "ip link add $probe_host_if type veth peer name $probe_ns_if"
  guest_root "ip link set $probe_ns_if netns $probe_ns"
  guest_root "ip addr add $probe_host_addr/64 dev $probe_host_if"
  guest_root "ip link set $probe_host_if up"
  guest_root "ip netns exec $probe_ns ip addr add $probe_ns_addr/64 dev $probe_ns_if"
  guest_root "ip netns exec $probe_ns ip link set $probe_ns_if up"
  guest_root "ip netns exec $probe_ns ip link set lo up"
  # Duplicate address detection has to finish before the addresses are usable.
  sleep 2
}

# router_up - create the second namespace and route between the two.
router_up() {
  guest_root "ip netns add $router_ns"
  guest_root "ip link add $router_host_if type veth peer name $router_ns_if"
  guest_root "ip link set $router_ns_if netns $router_ns"
  guest_root "ip addr add $router_host_addr/64 dev $router_host_if"
  guest_root "ip link set $router_host_if up"
  guest_root "ip netns exec $router_ns ip addr add $router_ns_addr/64 dev $router_ns_if"
  guest_root "ip netns exec $router_ns ip link set $router_ns_if up"
  guest_root "ip netns exec $router_ns ip link set lo up"
  guest_root "ip netns exec $probe_ns ip -6 route add 2001:db8:2::/64 via $probe_host_addr"
  guest_root "ip netns exec $router_ns ip -6 route add 2001:db8:1::/64 via $router_host_addr"
  guest_root 'sysctl -q -w net.ipv6.conf.all.forwarding=1'
  # Duplicate address detection has to finish before the addresses are usable.
  sleep 2
}

# ping6 <prefix> <target> - 0 when the IPv6 ping succeeds. The first packet can
# be lost while neighbour discovery completes, so the ping is retried; a
# blocked path fails every attempt.
ping6() {
  local attempt
  for attempt in 1 2 3; do
    if guest_root "$1 ping -6 -c 1 -W 2 $2 >/dev/null 2>&1"; then
      printf '0\n'
      return 0
    fi
    sleep 1
  done
  printf '1\n'
  return 0
}

# --- the shipped default blocks IPv6 -------------------------------------
baseline_apply >/dev/null
assert_blocked "default"
assert_contains "the ICMPv6 rule is preserved" \
  "$(guest_root "nft -s list chain inet $table input")" "meta l4proto ipv6-icmp accept"
assert_contains "the IPv6 SSH allowlist is preserved" \
  "$(guest_root "nft -s list chain inet $table input")" "ip6 saddr ::/0 tcp dport 22 accept"
assert_contains "the IPv4 SSH allowlist is preserved" \
  "$(guest_root "nft -s list chain inet $table input")" "ip saddr 0.0.0.0/0 tcp dport 22 accept"
assert_contains "the input IPv6 rule has a counter" \
  "$(guest_root "nft list chain inet $table input")" "meta nfproto ipv6 counter packets"
assert_eq "IPv6 loopback is blocked" "1" "$(guest_root 'ping -6 -c 1 -W 2 ::1 >/dev/null 2>&1; echo $?')"
assert_eq "IPv4 loopback works" "0" "$(guest_root 'ping -4 -c 1 -W 2 127.0.0.1 >/dev/null 2>&1; echo $?')"

# --- disabled: IPv6 works again ------------------------------------------
baseline_apply "-e @$allow_fixture" >/dev/null
assert_not_blocked "disabled"
probe_up
assert_eq "input path: the namespace reaches the host over IPv6" "0" \
  "$(ping6 "ip netns exec $probe_ns" "$probe_host_addr")"
assert_eq "output path: the host reaches the namespace over IPv6" "0" \
  "$(ping6 "" "$probe_ns_addr")"

# --- enabled: packet-level filtering -------------------------------------
baseline_apply "-e @$block_fixture" >/dev/null
assert_blocked "enabled"
assert_contains "the ICMPv6 rule is still rendered" \
  "$(guest_root "nft -s list chain inet $table input")" "meta l4proto ipv6-icmp accept"
assert_contains "the IPv6 SSH allowlist is still rendered" \
  "$(guest_root "nft -s list chain inet $table input")" "ip6 saddr ::/0 tcp dport 22 accept"

counter_before="$(guest_root "nft list chain inet $table input" | sed -n 's/.*meta nfproto ipv6 counter packets \([0-9]*\).*/\1/p')"
assert_eq "input path: the namespace no longer reaches the host" "1" \
  "$(ping6 "ip netns exec $probe_ns" "$probe_host_addr")"
assert_eq "output path: the host no longer reaches the namespace" "1" \
  "$(ping6 "" "$probe_ns_addr")"
counter_after="$(guest_root "nft list chain inet $table input" | sed -n 's/.*meta nfproto ipv6 counter packets \([0-9]*\).*/\1/p')"
if [ -n "$counter_before" ] && [ -n "$counter_after" ] && [ "$counter_after" -gt "$counter_before" ]; then
  baseline_ok "the input IPv6 drop counter increased"
else
  baseline_fail "the input IPv6 drop counter increased" \
    "before: ${counter_before:-none}" "after:  ${counter_after:-none}"
fi

# --- forward path --------------------------------------------------------
router_up
guest "printf '%s\n' 'ip6 saddr 2001:db8:1::/64 ip6 daddr 2001:db8:2::/64 accept' \
  | sudo -n tee $forward_fragment >/dev/null"
guest_root 'nft -f /etc/nftables.conf'
assert_eq "forward path: the IPv6 drop precedes the forward fragment" "1" \
  "$(ping6 "ip netns exec $probe_ns" "$router_ns_addr")"

# --- IPv4 regression while blocking is enabled ---------------------------
assert_eq "IPv4 loopback still works" "0" "$(guest_root 'ping -4 -c 1 -W 2 127.0.0.1 >/dev/null 2>&1; echo $?')"
ipv4_addrs="$(guest 'ip -4 addr show scope global | grep -c inet' || true)"
assert_eq "the guest still has an IPv4 address" "yes" \
  "$([ "${ipv4_addrs:-0}" -gt 0 ] && echo yes || echo no)"
assert_contains "the DHCP client rule is preserved" \
  "$(guest_root "nft -s list chain inet $table input")" "udp sport 67 udp dport 68 accept"
if make verify EXTRA_VARS="-e @$block_fixture" >/dev/null 2>&1; then
  baseline_ok "make verify succeeds while IPv6 is blocked"
else
  baseline_fail "make verify succeeds while IPv6 is blocked"
fi

# --- reversibility, no reboot --------------------------------------------
baseline_apply "-e @$allow_fixture" >/dev/null
assert_not_blocked "disabled again"
assert_contains "the forward fragment rule survives the toggle" \
  "$(guest_root "nft -s list chain inet $table forward")" "2001:db8:1::/64"
assert_eq "input path: IPv6 works again" "0" \
  "$(ping6 "ip netns exec $probe_ns" "$probe_host_addr")"
assert_eq "output path: IPv6 works again" "0" \
  "$(ping6 "" "$probe_ns_addr")"
assert_eq "forward path: IPv6 works again" "0" \
  "$(ping6 "ip netns exec $probe_ns" "$router_ns_addr")"

# The forward-path probe enabled IPv6 forwarding; put the guest back the way
# it was, so the 9.7 snapshot comparison below is meaningful.
guest_root "sysctl -q -w net.ipv6.conf.all.forwarding=${forwarding_before:-0}"

# --- 9.7 kernel and Vagrant preservation ---------------------------------
assert_eq "the kernel IPv6 sysctls are unchanged" "$sysctl_before" \
  "$(guest 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6 /proc/sys/net/ipv6/conf/default/disable_ipv6 /proc/sys/net/ipv6/conf/all/forwarding')"
assert_eq "the kernel command line is unchanged" "$cmdline_before" "$(guest 'cat /proc/cmdline')"
assert_eq "no IPv6-disablement sysctl file was added" "$sysctl_files_before" \
  "$(guest_root 'ls /etc/sysctl.d/')"
assert_eq "the kernel IPv6 stack is enabled" "0" \
  "$(guest 'cat /proc/sys/net/ipv6/conf/all/disable_ipv6')"
assert_eq "the kernel IPv6 interface table is present" "0" \
  "$(guest 'test -f /proc/net/if_inet6; echo $?')"
assert_contains "the loopback IPv6 address is intact" \
  "$(guest 'ip -6 addr show dev lo')" "inet6 ::1/128"
assert_contains "the link-local IPv6 address is intact" \
  "$(guest 'ip -6 addr show')" "inet6 fe80::"
assert_not_contains "the kernel command line has no ipv6.disable" "$cmdline_before" "ipv6.disable"
assert_eq "no GRUB file disables IPv6" "" \
  "$(guest_root "grep -rls 'ipv6.disable' /etc/default/grub /etc/default/grub.d /boot/grub/grub.cfg 2>/dev/null")"
if git diff --quiet -- Vagrantfile; then
  baseline_ok "the Vagrantfile is unchanged"
else
  baseline_fail "the Vagrantfile is unchanged"
fi

# --- configuration validation --------------------------------------------
if invalid_out="$(ansible-playbook -i inventories/vagrant/hosts.yml \
    playbooks/baseline.yml -e "@$invalid_fixture" 2>&1)"; then
  baseline_fail "a non-boolean baseline_firewall_block_ipv6 is rejected"
else
  assert_contains "the rejection names the variable" "$invalid_out" \
    "baseline_firewall_block_ipv6"
fi

if contradiction_out="$(ansible-playbook -i inventories/vagrant/hosts.yml \
    playbooks/baseline.yml -e "@$contradiction_fixture" 2>&1)"; then
  baseline_fail "blocking with the firewall disabled is rejected"
else
  assert_contains "the rejection explains the contradiction" "$contradiction_out" \
    "baseline_firewall_enabled"
fi

finish
