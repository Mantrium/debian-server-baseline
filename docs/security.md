# Security

## What the baseline enforces

| Area | Setting |
|---|---|
| SSH root login | Disabled |
| SSH password authentication | Disabled |
| SSH keyboard-interactive authentication | Disabled |
| SSH empty passwords | Refused |
| SSH X11 forwarding | Disabled |
| SSH `MaxAuthTries` | 3 |
| SSH `LoginGraceTime` | 30 |
| Firewall input policy | `drop` |
| Firewall forward policy | `drop` |
| Firewall output policy | `accept` |
| Unattended upgrades | Disabled; `apt_upgrade` applies them at the start of each run (see `docs/maintenance.md`) |
| Journal | Persistent, bounded |

## SSH

`ssh` writes one drop-in, `/etc/ssh/sshd_config.d/00-server-baseline.conf`. The
`00-` prefix is load-bearing: Debian's `sshd_config` includes
`sshd_config.d/*.conf` first and sshd uses the first value it sees, so this file
wins over any other drop-in, including the cloud image's `50-cloud-init.conf`.

The template is validated with `sshd -t -f` before it is written, and the
handler validates the whole configuration with `sshd -t` before reloading. A
broken configuration can therefore never be activated.

`PermitRootLogin no` disables root login over SSH entirely. Administrative work
is done through the account named by `admin_username`, which is in the `sudo`
group.

### Keys

The operator's public key is read from `ssh_public_key_path` on the controller
and installed with `ansible.posix.authorized_key` and `exclusive: false`, so
keys already present on the server are preserved. The private key never leaves
the controller.

To rotate a key, replace the file `ssh_public_key_path` points at and re-run
`baseline.yml`. The old key stays in `authorized_keys`; remove it by hand if it
should no longer be accepted.

### Changing the SSH port

`baseline_ssh_port` (role `ssh`) and `BASELINE_SSH_PORT` (Vagrant) must be
changed together, and the new port must be reachable through the firewall —
`nftables` opens `baseline_firewall_ssh_port`, which defaults to
`baseline_ssh_port`.

## Firewall

`nftables` writes one table, `inet baseline_filter`, in
`/etc/nftables.d/10-server-baseline.nft`, and reduces `/etc/nftables.conf` to an
include of that directory. Nothing ever flushes the whole ruleset, so tables
created by other tools or providers survive.

The table is destroyed and recreated on every run, which makes the file
idempotent without touching anything else. A unit drop-in replaces Debian's
`ExecStop`, which runs `nft flush ruleset`, with a statement that removes only
the baseline table.

The input chain drops by default, drops packets in the `invalid` conntrack
state, and accepts:

- loopback traffic;
- established and related connections;
- ICMP and ICMPv6;
- the DHCP client exchange;
- the configured SSH port, from the CIDRs in
  `baseline_firewall_ssh_ipv4_cidrs` and `baseline_firewall_ssh_ipv6_cidrs`.

To open more ports, set `baseline_firewall_tcp_ports` or
`baseline_firewall_udp_ports`. To restrict SSH to a management network, narrow
`baseline_firewall_ssh_ipv4_cidrs`.

To disable the firewall entirely, set `baseline_firewall_enabled: false`; the
role then only warns and leaves the target's ruleset alone.

## Auditing

`make security-audit` writes `/var/log/server-baseline/security-audit.txt`:

| Section | Contents |
|---|---|
| SSH configuration | The effective `sshd -T` output |
| Firewall ruleset | The complete `nft list ruleset` output |
| Enabled unit files | Every enabled systemd unit |
| Listening sockets | `ss -tulpn` |
| Security support | `debian-security-support --check` |
| Running kernel | `uname -r` |

`baseline.yml` also writes `service-audit.txt`, which lists running and failed
units and listening sockets, and `kernel-status.txt`, which lists the running
and installed kernels, pending kernel upgrades and pending service restarts.

## What the baseline does not do

- It does not configure fail2ban, an intrusion detection system or a log
  shipper. Those belong to a hosting platform layered on top of the baseline.
- It does not manage TLS material or application secrets.
- It does not apply upgrades unattended. `apt_upgrade` applies them at the start
  of each `baseline.yml` run, which is a deliberate, observable moment.
- It does not disable the `vagrant` account. That account exists only in the
  Vagrant environment and is not created on a production server.
