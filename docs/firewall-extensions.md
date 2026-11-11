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

This repository creates the directories, the includes, the table and the
policies; the layer on top creates and manages the fragments:

```text
/etc/nftables.d/
│
├── 10-server-baseline.nft
│
├── input/
│   └── 50-example-service.nft
│
└── forward/
    └── 50-example-forwarding.nft
```

Rules for a fragment:

- It contains rule statements appropriate to its enclosing chain — never table
  or chain declarations. A table declaration inside a fragment is a syntax
  error, because the fragment is parsed as part of the chain body.
- A wildcard include with no matches is not an error, so the directories may be
  empty.
- The baseline preserves externally managed fragments when it reapplies: the
  directory task uses `state: directory`, which never removes files.

## 5. `baseline_firewall_block_ipv6`

|Variable|Default|Type|
|---|---|---|
|`baseline_firewall_block_ipv6`|`true`|YAML boolean|

When it is `true` (the default), the host firewall drops IPv6 at the input,
forward and output hooks. The rule is the first rule of each of the three
chains, so it precedes loopback, conntrack, invalid-state, ICMP/ICMPv6, DHCP,
the SSH allowlist, the port allowances and the input include. It carries a
`counter`, so drops are observable with
`nft list chain inet baseline_filter input`; no `log` statement is added, so
blocked IPv6 cannot fill the journal.

The value must be a YAML boolean. `preflight` rejects a string:
`-e baseline_firewall_block_ipv6=true` produces the string `"true"`, which the
`| bool` filter would accept as true while the type check rejects it, so the
same value would mean different things in different places.

## 6. The default: IPv6 is blocked

```yaml
# Block IPv6 at the host firewall. This is the role default.
baseline_firewall_block_ipv6: true
```

The role default is `true`, so a host that does not set the variable at all
blocks IPv6. Set it explicitly in `config/user.yml` to make the intent visible,
and re-run `playbooks/baseline.yml`. No reboot is needed: the table is recreated
and reloaded by the role.

## 7. Restoring dual-stack behaviour

```yaml
# Preserve the existing dual-stack firewall behaviour.
baseline_firewall_block_ipv6: false
```

Set it to `false` and re-run `playbooks/baseline.yml`. The drop rules are
removed with the rest of the table, again without a reboot.

## 8. IPv6 loopback is blocked too

The output chain drops IPv6 before any other rule, so `::1` is blocked as well.
Applications on the host must use `127.0.0.1` or an explicitly configured IPv4
address rather than `::1` while blocking is enabled, which is the default.
