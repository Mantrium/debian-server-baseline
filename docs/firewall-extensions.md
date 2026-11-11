# Firewall extensions and the IPv6 policy

The `nftables` role owns one table and two extension directories. A layer on top
of the baseline adds rules by dropping `.nft` fragments into those directories,
and an operator can switch the host to an IPv4-only firewall policy with one
YAML boolean.

## 1. The modular architecture

`/etc/nftables.conf` is reduced to an include of `/etc/nftables.d/*.nft`, and
`10-server-baseline.nft` defines the single `inet baseline_filter` table. That
table includes the two extension directories from inside its input and forward
chains:

```text
/etc/nftables.conf
└── include "/etc/nftables.d/*.nft"
    └── 10-server-baseline.nft
        └── table inet baseline_filter
            ├── chain input   → include "/etc/nftables.d/input/*.nft"
            ├── chain forward → include "/etc/nftables.d/forward/*.nft"
            └── chain output
```

Nothing ever flushes the whole ruleset. The baseline table is destroyed and
recreated on every run, so the file is idempotent, and tables created by other
tools or providers survive.

## 2. The input extension directory

`/etc/nftables.d/input/`, created by the role as `root:root 0755`, is included
as the last statement of the input chain. Fragments therefore add rules *after*
the baseline's own accept rules and can never bypass the default-drop policy:
the baseline's accepts are evaluated first, and anything a fragment does not
accept still falls through to `policy drop`.

## 3. The forward extension directory

`/etc/nftables.d/forward/`, created by the role as `root:root 0755`, is included
as the last statement of the forward chain. The forward chain keeps its
configurable default-drop policy (`baseline_firewall_forward_policy`) and now
drops invalid and accepts established/related connections before the include, so
a fragment only has to accept the initiating direction of the traffic it wants
to forward.

## 4. How a layer on top consumes them

Phase 1 (this repository) creates the directories, the includes, the table, the
policies and the optional IPv6 drop rules. Phase 2 creates and manages the
fragments:

```text
/etc/nftables.d/
│
├── 10-server-baseline.nft
│
├── input/
│   └── 50-incus-host-services.nft
│
└── forward/
    └── 50-incus-ovn.nft
```

Rules for a fragment:

- It contains rule statements appropriate to its enclosing chain — never table
  or chain declarations. A table declaration inside a fragment is a syntax
  error, because the fragment is parsed as part of the chain body.
- A wildcard include with no matches is not an error, so the directories may be
  empty.
- Phase 1 preserves externally managed fragments when it reapplies the baseline:
  the directory task uses `state: directory`, which never removes files.

Phase 1 contains no Incus or OVN configuration. The actual Phase 2 rules must be
determined by testing the final OVN topology and packet paths.

## 5. `baseline_firewall_block_ipv6`

|Variable|Default|Type|
|---|---|---|
|`baseline_firewall_block_ipv6`|`false`|YAML boolean|

When it is `true`, the host firewall drops IPv6 at the input, forward and output
hooks. The rule is the first rule of each of the three chains, so it precedes
loopback, conntrack, invalid-state, ICMP/ICMPv6, DHCP, the SSH allowlist, the
port allowances and the input include. It carries a `counter`, so drops are
observable with `nft list chain inet baseline_filter input`; no `log` statement
is added, so blocked IPv6 cannot fill the journal.

The value must be a YAML boolean. `preflight` rejects a string, because
`-e baseline_firewall_block_ipv6=true` produces the string `"true"`, which would
silently be truthy in one place and false in another.

## 6. Enabling it

```yaml
# Block IPv6 at the host firewall.
baseline_firewall_block_ipv6: true
```

Set it in `config/user.yml` and re-run `playbooks/baseline.yml`. No reboot is
needed: the table is recreated and reloaded by the role.

## 7. Restoring normal behaviour

```yaml
# Preserve the existing dual-stack firewall behaviour.
baseline_firewall_block_ipv6: false
```

Set it back to `false` and re-run `playbooks/baseline.yml`. The drop rules are
removed with the rest of the table, again without a reboot.

## 8. Firewall blocking versus kernel-level disablement

This is a firewall policy, not a kernel change. With
`baseline_firewall_block_ipv6: true`:

- IPv6 is dropped at the input, forward and output hooks of the host firewall;
- provider-assigned IPv6 addresses are **not** removed, and `ip -6 addr show`
  still lists them;
- `net.ipv6.conf.*` is **not** changed, and no IPv6-disablement sysctl file is
  added under `/etc/sysctl.d/`;
- GRUB and the kernel command line are **not** touched, so `ipv6.disable=1` is
  never added;
- the kernel IPv6 stack stays enabled, and `/proc/net/if_inet6` stays present.

The kernel IPv6 stack, the sysctls, GRUB, the kernel command line, the provider
network configuration and the Vagrantfile are all out of scope for this feature.

## 9. Why Vagrant and the Linux IPv6 configuration are unchanged

The feature is a firewall policy, so the Vagrantfile, the libvirt networking and
the guest's IPv6 stack are untouched. The integration test asserts this: it
compares the IPv6 sysctls, the kernel command line and the contents of
`/etc/sysctl.d/` before and after the toggle, and checks that `git diff` reports
no change to the Vagrantfile.

## 10. Why OVN still needs its own IPv4-only policy

OVN can switch traffic inside its logical datapath without every packet
traversing the host's ordinary nftables IP forwarding chain, so host firewall
rules are not a substitute for OVN ACLs. A layer on top must configure
IPv4-only OVN networks and deny IPv6 within tenant networking; blocking IPv6 at
the host firewall does not cover the logical datapath.

## 11. IPv6 loopback is blocked too

The output chain drops IPv6 before any other rule, so `::1` is blocked as well.
Applications on the host must use `127.0.0.1` or an explicitly configured IPv4
address rather than `::1` while blocking is enabled.
