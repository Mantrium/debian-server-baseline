# Architecture

## 1. Purpose

`infra-server-baseline` turns a freshly installed Debian 13 (Trixie) machine
into a known-good, hardened server. It is Phase 1 of the Mantrium
infrastructure project and is deliberately generic: nothing about a particular
organisation, hostname or operator is baked into a role.

The repository has three jobs:

1. Describe the baseline as idempotent Ansible roles.
2. Reproduce a Debian 13 machine locally so the baseline can be tested.
3. Keep every operator-specific value in one Git-ignored file.

## 2. Layers

| Layer | Runs on | Responsibility |
|---|---|---|
| Controller | the operator's workstation | Holds the private key, reads `config/user.yml`, runs Ansible |
| Target | the Debian 13 server | Receives the baseline; holds no secrets from the controller |
| Vagrant | the operator's workstation | Provides a throwaway Debian 13 target for development |

Ansible always runs on the controller and connects to the target over SSH.
Nothing in this repository runs on the target outside of an Ansible task.

Vagrant is a development convenience only. Production deployment is a direct
`ansible-playbook` run against the production inventory; Vagrant is never
required there.

## 3. Configuration ownership

There is exactly one authoritative source for each value.

| Value | Owner | Notes |
|---|---|---|
| `server_hostname` | `config/user.yml` | Consumed by `os_identity` |
| `admin_username` | `config/user.yml` | Consumed by `users`, `ssh` |
| `server_timezone` | `config/user.yml` | Consumed by `os_identity` |
| `ssh_public_key_path` | `config/user.yml` | Read on the controller by `preflight` |
| Internal role variables | `roles/<role>/defaults/main.yml` | Prefixed `baseline_` |
| Connection details | `inventories/*` | Host, port, user, private key path |

Rules that follow from this:

- No role default may restate a value from `config/user.yml`.
- No inventory may restate a value from `config/user.yml` except to derive a
  connection parameter from it (the production inventory does this).
- `config/user.yml` is Git-ignored. `config/user.example.yml` is tracked and is
  the documented starting point.

`preflight` is the single gate that loads and validates the user configuration.
Every playbook runs it first, so a missing or malformed configuration fails
before any role changes the target.

## 4. Role responsibilities

Each role owns one concern and one set of files.

| Role | Owns | Changes the target |
|---|---|---|
| `preflight` | User configuration validation | No |
| `apt_upgrade` | Pending package upgrades | Yes |
| `os_identity` | Hostname, `/etc/hosts`, timezone, locale | Yes |
| `apt_sources` | `/etc/apt/sources.list.d/debian.sources` | Yes |
| `apt_maintenance` | `/etc/apt/apt.conf.d/20auto-upgrades`, upgrade review tools | Yes |
| `base_packages` | The baseline package set | Yes |
| `users` | The administrative user and its `authorized_keys` | Yes |
| `ssh` | `/etc/ssh/sshd_config.d/00-server-baseline.conf` | Yes |
| `nftables` | `/etc/nftables.conf`, `/etc/nftables.d/`, the unit drop-in | Yes |
| `journald` | `/etc/systemd/journald.conf.d/`, `/var/log/journal` | Yes |
| `logrotate` | `/etc/logrotate.d/server-baseline` | Yes |
| `service_audit` | `/var/log/server-baseline/service-audit.txt` | Report only |
| `kernel_status` | `/var/log/server-baseline/kernel-status.txt` | Report only |
| `storage_checks` | `/var/log/server-baseline/storage.txt` | Report only |
| `verification` | Assertions over the applied baseline | No |

The four reporting roles (`service_audit`, `kernel_status`, `storage_checks`,
`verification`) never change system state. They exist so that the state of a
server can be captured and checked without logging in interactively.

## 5. Playbooks

| Playbook | Purpose | Changes state |
|---|---|---|
| `bootstrap.yml` | Give Ansible a Python interpreter on a bare guest | Yes (packages only) |
| `baseline.yml` | Apply the full baseline | Yes |
| `verify.yml` | Assert the baseline is in place | No |
| `maintenance.yml` | Write the maintenance report | Report only |
| `security-audit.yml` | Write the security audit report | Report only |

`bootstrap.yml` deliberately uses `raw` and disables fact gathering: it must
work on a machine that has no Python yet. It installs `python3` and
`python3-apt` and nothing else.

## 6. Execution order

`baseline.yml` applies roles in this order, and the order is load-bearing:

1. `preflight` — validate the configuration.
2. `apt_upgrade` — refresh the package index and apply pending upgrades, so
   that every later role configures a patched system.
3. `os_identity` — hostname, timezone, locale. Installs `locales` and `tzdata`
   itself because it runs before `base_packages`.
4. `apt_sources` — point APT at the intended repositories.
5. `apt_maintenance` — periodic APT maintenance and the upgrade review tools.
6. `base_packages` — install the baseline package set.
7. `users` — create the administrative user and install the public key.
8. `ssh` — harden the SSH daemon.
9. `nftables` — firewall.
10. `journald` — persistent logging.
11. `logrotate` — rotate the baseline reports.
12. `service_audit`, `kernel_status`, `storage_checks` — write reports.
13. `verification` — assert the result.

`preflight` runs before `apt_upgrade` because it only reads the controller: a
missing or malformed `config/user.yml` should stop the run before the target is
touched at all.

`users` runs before `ssh` so that the administrative account and its key exist
before the daemon is hardened. `ssh` runs before `nftables` so that a firewall
mistake cannot lock the operator out of an unhardened daemon.

## 7. Fixed paths

| Path | Owner |
|---|---|
| `/etc/apt/sources.list.d/debian.sources` | `apt_sources` |
| `/etc/apt/apt.conf.d/20auto-upgrades` | `apt_maintenance` |
| `/etc/ssh/sshd_config.d/00-server-baseline.conf` | `ssh` |
| `/etc/nftables.conf`, `/etc/nftables.d/10-server-baseline.nft` | `nftables` |
| `/etc/systemd/system/nftables.service.d/10-server-baseline.conf` | `nftables` |
| `/etc/systemd/journald.conf.d/10-server-baseline.conf` | `journald` |
| `/var/log/journal` | `journald` |
| `/etc/logrotate.d/server-baseline` | `logrotate` |
| `/var/log/server-baseline/` | the reporting roles |

Every file the baseline writes is either a drop-in under a `.d/` directory or a
file whose name identifies this repository. The baseline does not rewrite
distribution-owned files in place, so a Debian package upgrade cannot silently
revert the baseline and the baseline cannot silently revert a package upgrade.

## 8. Reports

Reports are written to `/var/log/server-baseline/` as plain text, mode
`0640 root:root`:

| File | Producer |
|---|---|
| `service-audit.txt` | `service_audit` |
| `kernel-status.txt` | `kernel_status` |
| `storage.txt` | `storage_checks` |
| `maintenance-report.txt` | `maintenance.yml` |
| `security-audit.txt` | `security-audit.yml` |

Reports are regenerated on every run. They are the intended input for a human
reviewing a server, and for the integration tests.

## 9. Boundary with `infra-hosting-platform`

This repository stops at a hardened, observable, generic Debian 13 host. It
does not install or configure any hosting workload.

`infra-hosting-platform` (Phase 2) is a separate repository that builds on this
baseline. It owns everything specific to hosting: web servers, databases,
container runtimes, TLS material, application deployment and per-tenant
configuration.

The interface between the two is the baseline itself:

- `infra-hosting-platform` may assume the baseline roles have run.
- It may add roles; it must not modify baseline roles.
- It must not depend on any value that is not either in `config/user.yml` or
  produced by a baseline role.

Keeping the boundary here means the baseline stays reusable by anyone, and the
hosting platform can evolve without re-testing the baseline.

## 10. Design rules

- **Idempotent.** A second run reports no changes. Every task that writes a file
  uses a template or a module that compares content.
- **Explicit.** No task depends on an implicit default that is not written down
  in a role default.
- **Reversible.** Every change is a file the operator can inspect, and the
  documentation records how to undo it.
- **Minimal.** No dependency is added unless a role needs it.
- **Testable.** Every role has an integration test that runs against the
  Vagrant machine.
