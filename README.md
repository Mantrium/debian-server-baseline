# debian-server-baseline

A generic, **secure server baseline setup for Debian 13 (Trixie)**, **automated with Ansible** 
and developed and tested using a local Vagrant/libvirt virtual machine.

Operator-specific values, including the hostname, user, 
timezone, and SSH key path, are defined in a Git-ignored 
`config/user.yml` file that each operator creates from the tracked example.

## What it does

|Area|Behaviour|
|---|---|
|Identity|Hostname, timezone, locale and `/etc/hosts` entry.|
|Updates|The package index is refreshed and pending upgrades are applied before anything else is configured.|
|APT|Debian 13 `deb822` sources, periodic update policy, review packages.|
|Packages|A curated base, security, maintenance, network and monitoring set.|
|Access|Administrative account in `sudo` with the operator's public key installed.|
|SSH|Key-only authentication, no root login, hardened effective configuration.|
|Firewall|nftables default-deny inbound, preserving unrelated tables.|
|Logging|Persistent journald storage and log rotation.|
|Diagnostics|Read-only service, kernel and storage reports under `/var/log/server-baseline/`.|
|Verification|An assertion role that fails the run when the baseline is not in place.|

## Requirements

On the controller:

- `ansible-core` >= 2.16, `ansible-lint`, `yamllint` (see `requirements-dev.txt`)
- the `ansible.posix` collection (see `requirements.yml`)
- `vagrant` with `vagrant-libvirt`, QEMU/KVM and libvirt for the test VM
- an SSH key pair; the public key is installed on the target

On the target: Debian 13 (Trixie).

## Quick start (local test VM)

```bash
# 1. Install the toolchain and the required collection
make tools
make collections

# 2. Create your configuration (skipped if it already exists)
cp -n config/user.example.yml config/user.yml
$EDITOR config/user.yml

# 3. Check the host, then build and provision the test VM
make check-host
make vagrant-up

# 4. Run the integration tests
make vagrant-test
```

## Production

Production is a direct `ansible-playbook` run against a Debian 13 server.
Vagrant is never involved. The full walkthrough is
[`docs/production.md`](docs/production.md); in short:

```bash
# On the controller, once
make tools
make collections
cp -n config/user.example.yml config/user.yml
$EDITOR config/user.yml

# Point the production inventory at the server
cp -n inventories/production/hosts.example.yml inventories/production/hosts.yml
cp -n inventories/production/group_vars/all.example.yml inventories/production/group_vars/all.yml
$EDITOR inventories/production/hosts.yml

# Bootstrap, apply, verify
ansible-playbook -i inventories/production/hosts.yml playbooks/bootstrap.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml
ansible-playbook -i inventories/production/hosts.yml playbooks/verify.yml
```

The first run installs your key for `admin_username` and then disables password
authentication and root login, so confirm a new SSH session works before you
close the current one. [`docs/production.md`](docs/production.md) covers the
account Ansible connects as, the provider firewall, multiple servers and
ongoing operation.

## Common commands

|Command|Purpose|
|---|---|
|`make help`|List every target.|
|`make vagrant-up`|Create and provision the Vagrant VM.|
|`make vagrant-provision`|Re-run the Ansible provisioners.|
|`make vagrant-ssh`|Open an SSH session to the VM.|
|`make vagrant-test`|Run the integration test suite.|
|`make verify`|Run `playbooks/verify.yml`.|
|`make maintenance`|Generate the maintenance report.|
|`make security-audit`|Generate the security audit report.|
|`make lint`|`ansible-lint` and `yamllint`.|
|`make syntax-check`|`--syntax-check` on every playbook.|
|`make vagrant-destroy`|Destroy the VM.|

## Documentation

|Document|Contents|
|---|---|
|[`docs/architecture.md`](docs/architecture.md)|Component responsibilities and role separation.|
|[`docs/installation.md`](docs/installation.md)|Prerequisites, bootstrap and first run.|
|[`docs/production.md`](docs/production.md)|Deploying to a real server: VPS setup, inventory, first run, ongoing operation.|
|[`docs/vagrant.md`](docs/vagrant.md)|The test environment, box provenance and environment variables.|
|[`docs/configuration.md`](docs/configuration.md)|The user configuration file and preflight validation.|
|[`docs/security.md`](docs/security.md)|SSH, firewall and audit posture.|
|[`docs/maintenance.md`](docs/maintenance.md)|Update workflow, kernel updates and reboots.|
|[`docs/recovery.md`](docs/recovery.md)|Recovering access to a locked-out host.|
|[`docs/troubleshooting.md`](docs/troubleshooting.md)|Common failures and their resolutions.|

## Licence

MIT. See `LICENSE`.
