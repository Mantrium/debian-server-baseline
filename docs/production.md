# Production deployment

Vagrant is a development tool. A production server is a Debian 13 machine you
already have - a cloud VPS, a dedicated host, or a virtual machine at a hosting
provider - reached over SSH and configured by `ansible-playbook` from your
workstation. Nothing from this repository is installed on the server; the only
prerequisite is Python 3, which `bootstrap.yml` provides.

[`docs/installation.md`](installation.md) covers the controller requirements
and the meaning of every configuration variable. This document is the
end-to-end walkthrough.

## Before you start

| You need | Notes |
|---|---|
| A Debian 13 (Trixie) server | amd64 or arm64. Any provider that offers a Debian 13 image. |
| SSH access as an account that can become root | See [The account Ansible connects as](#the-account-ansible-connects-as). |
| Your SSH key pair on the controller | The public key is installed on the server; the private key never leaves the controller. |
| The repository and toolchain on the controller | `make tools` and `make collections`; see [`docs/installation.md`](installation.md). |

## 1. Create the server

1. Choose Debian 13 (Trixie) as the image.
2. Add your public key (`~/.ssh/id_ed25519.pub`) at creation time, so the
   provider installs it for its default account.
3. Note the server's address.
4. In the provider's firewall or security group, allow TCP 22 from the address
   you manage from. The baseline's own firewall is a second layer, not a
   replacement for this one.

Debian cloud images ship a `debian` account with passwordless `sudo`. That is
the account the baseline expects by default.

## 2. Configure the baseline

```bash
cp -n config/user.example.yml config/user.yml
$EDITOR config/user.yml
```

| Variable | Production value |
|---|---|
| `server_hostname` | The server's hostname, for example `web1.example.com`. It is written to `/etc/hostname` and `/etc/hosts`. It does not have to resolve in DNS, but it should match the A record if you publish one. |
| `admin_username` | The account the baseline creates and installs your key for. It must be the account Ansible connects as; see below. |
| `server_timezone` | For example `Etc/UTC`. |
| `ssh_public_key_path` | The public key on the controller. The matching private key is derived by stripping `.pub`, and both must exist. |

### The account Ansible connects as

The production inventory sets `ansible_user` to `admin_username`. That account
must already exist and be able to become root, because the connection is made
before any role runs.

- On a Debian cloud image, `admin_username: debian` works as-is.
- If your provider only gives you `root`, either create the administrative
  account first, or set `ansible_user: root` on the host in `hosts.yml` for the
  first run. The baseline creates the administrative account and installs the
  key before it disables root login, so later runs use `admin_username`.

If `sudo` on the server asks for a password, add `--ask-become-pass` to every
`ansible-playbook` command.

## 3. Create the production inventory

```bash
cp -n inventories/production/hosts.example.yml inventories/production/hosts.yml
cp -n inventories/production/group_vars/all.example.yml inventories/production/group_vars/all.yml
$EDITOR inventories/production/hosts.yml
```

`hosts.yml` holds the address of each server:

```yaml
all:
  children:
    production:
      hosts:
        baseline-01:
          ansible_host: 203.0.113.10
```

`group_vars/all.yml` derives the connection user and private key from
`config/user.yml`, so run Ansible from the repository root. Both files are
Git-ignored.

## 4. First run

```bash
# 1. Give Ansible a Python interpreter (skip if Python 3 is already installed)
ansible-playbook -i inventories/production/hosts.yml playbooks/bootstrap.yml

# 2. Apply the baseline
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml

# 3. Confirm it is in place
ansible-playbook -i inventories/production/hosts.yml playbooks/verify.yml
```

`bootstrap.yml` changes nothing when the image already has `python3` and
`python3-apt`.

`baseline.yml` refreshes the package index, applies pending upgrades, then
configures the server. It is idempotent: a second run immediately afterwards
reports no changes.

### Keep a session open

The first run installs your key for `admin_username`, then disables password
authentication and root login. Before you close your current session, confirm
the new one works:

```bash
ssh -i <private key> <admin_username>@<address>
```

## 5. What the first run changed

| Area | Effect |
|---|---|
| Identity | `/etc/hostname`, `/etc/hosts`, timezone and locale. |
| Updates | Index refreshed, pending upgrades applied. |
| APT | Debian 13 `deb822` sources and the periodic update policy. |
| Packages | Base, security, maintenance, network and monitoring sets. |
| Access | `admin_username` in `sudo`, your key in `authorized_keys`. |
| SSH | Key-only authentication, no root login, `sshd -T` matches the baseline. |
| Firewall | nftables default-deny inbound; SSH and ICMP accepted. |
| Logging | Persistent journald storage and log rotation. |
| Reports | `/var/log/server-baseline/`: `service-audit.txt`, `kernel-status.txt`, `storage.txt`, `maintenance-report.txt`, `security-audit.txt`. |

The baseline does not remove cloud-init or provider agents, and it does not
touch the provider's firewall.

## 6. Ongoing operation

```bash
# Apply updates and re-assert the baseline
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml

# Reports only, no changes
ansible-playbook -i inventories/production/hosts.yml playbooks/maintenance.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/security-audit.yml
```

`maintenance.yml` reports whether a reboot is required. A kernel update needs
one; see [`docs/maintenance.md`](maintenance.md).

`make verify`, `make maintenance` and `make security-audit` target the Vagrant
VM. Against production, use the `ansible-playbook` commands above.

## 7. Multiple servers

`config/user.yml` holds one `server_hostname`, so a single run gives every host
the same hostname. For several servers with distinct hostnames, add each host
to `hosts.yml`, then run once per host and override the hostname:

```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml \
  --limit web1 -e server_hostname=web1.example.com
```

`admin_username`, `server_timezone` and the key are shared by every host.

## 8. Recovery

If SSH stops working, use the provider's out-of-band console or rescue system;
see [`docs/recovery.md`](recovery.md).

## Checklist

- [ ] Debian 13 server reachable over SSH
- [ ] Provider firewall allows the SSH port
- [ ] `config/user.yml` created and edited
- [ ] `inventories/production/hosts.yml` and `group_vars/all.yml` created
- [ ] `bootstrap.yml` run
- [ ] `baseline.yml` run
- [ ] `verify.yml` passes
- [ ] A new SSH session as `admin_username` with the private key works
