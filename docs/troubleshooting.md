# Troubleshooting

## `make check-host` reports a missing prerequisite

Install what it lists. On Arch Linux:

```bash
sudo pacman -S --needed vagrant libvirt qemu-base qemu-system-x86 qemu-img make git
sudo usermod -aG libvirt "$USER"
# log out and back in
vagrant plugin install vagrant-libvirt
make tools
make collections
```

## `apt` tasks fail with `Failed to update apt cache`

The guest has no internet access. libvirt NATs guest traffic through the host,
so the host firewall must forward packets from the libvirt bridge. With `ufw`
active and the default forward policy of `DROP`, forwarded ICMP is still
accepted but forwarded TCP is dropped, so the guest can `ping 1.1.1.1` yet
cannot reach an HTTP mirror.

```bash
uplink=$(ip route show default | awk '{print $5; exit}')
sudo ufw route allow in on virbr0 out on "$uplink"
sudo ufw route allow in on virbr1 out on "$uplink"
```

`make check-host` detects this combination and prints the same fix.

## `config/user.yml is missing`

```bash
cp config/user.example.yml config/user.yml
$EDITOR config/user.yml
```

The baseline never falls back to hardcoded values, so every playbook fails until
the file exists.

## `Required variable 'x' is missing or empty in config/user.yml`

The file exists but is incomplete. Compare it with `config/user.example.yml`;
all four variables are required.

## `server_timezone 'x' is not a valid timezone on this host`

The value must name a file under `/usr/share/zoneinfo`. Use `Etc/UTC` or a name
such as `Europe/Berlin`.

## `SSH public key is missing or invalid`

`ssh_public_key_path` must point at a readable, non-empty public key file on the
controller, and the matching private key must exist next to it. The Mantrium
configuration resolves the path with `lookup('env', 'HOME')`, so Ansible must be
run from the repository root.

## `Matching private key ... not found`

The private key is expected next to the public key, with the `.pub` suffix
removed. Either restore it or point `ssh_public_key_path` at a key pair that
exists.

## `ansible-inventory` cannot resolve the production inventory

The production `group_vars/all.yml` reads `config/user.yml` with
`lookup('file', ...)`, which is relative to the working directory. Run Ansible
from the repository root.

## `vagrant up` fails with `ignoring_virtual_size_too_small`

The box disk is already at least as large as `BASELINE_VM_DISK`. The warning is
harmless; check the actual size with `df -hT /` on the guest.

## `vagrant up` cannot find the box

```bash
vagrant box add cloud-image/debian-13 --provider libvirt
```

The version is pinned by `BASELINE_VM_BOX_VERSION`; set it to a version that
exists, or unset it to take the latest.

## The VM has no IP address

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-start vagrant-libvirt
```

`vagrant reload` re-attaches the interface.

## `make vagrant-test` fails on `test_apt.sh` with pending upgrades

`test_apt.sh` asserts that nothing is left to upgrade, which is what
`apt_upgrade` guarantees. If Debian publishes an update between provisioning and
the test run, re-run `make vagrant-provision` and then the test.

## `sshd -T` does not show the baseline values

Check that the drop-in exists and that nothing with a lower number overrides it:

```bash
ls -l /etc/ssh/sshd_config.d/
grep -n '^Include' /etc/ssh/sshd_config
```

sshd uses the first value it sees, and `sshd_config.d/*.conf` is included in
lexical order, so `00-server-baseline.conf` wins.

## `nft list table inet baseline_filter` fails

```bash
systemctl status nftables
nft -c -f /etc/nftables.conf
```

A syntax error in a drop-in under `/etc/nftables.d/` stops the whole file from
loading. The role validates the file with `nft -c -f` before starting the
service.

## `make verify` fails

The failure message names the check. Each one maps to a role:

| Check | Role |
|---|---|
| Operating system, hostname, timezone, locale | `os_identity` |
| Administrative user and key | `users` |
| SSH configuration | `ssh` |
| Firewall | `nftables` |
| Journal, log rotation | `journald`, `logrotate` |
| Packages | `base_packages` |
| APT | `apt_sources`, `apt_maintenance` |
| Reports | `service_audit`, `kernel_status`, `storage_checks` |

Re-run `make vagrant-provision` and then `make verify`.

## `make lint` fails

`ansible-lint` and `yamllint` both run. `yamllint` reads `.yamllint`, which
sets a 120 character line limit; wrap long Jinja expressions with a folded
scalar (`>-`), which preserves the value's type.
