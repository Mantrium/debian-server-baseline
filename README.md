# infra-server-baseline

A generic, publicly reusable **Debian 13 (Trixie) server baseline**, managed by
Ansible and developed against a local Vagrant/libvirt virtual machine.

The repository is deliberately free of any operator-specific value: hostname,
administrative account, timezone and SSH key path all come from a Git-ignored
`config/user.yml` that each operator creates from the tracked example.

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

## Quick start

```bash
# 1. Install the toolchain and the required collection
make tools
make collections

# 2. Create your configuration
cp config/user.example.yml config/user.yml
$EDITOR config/user.yml

# 3. Check the host, then build and provision the test VM
make check-host
make vagrant-up

# 4. Run the integration tests
make vagrant-test
```

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
|`docs/architecture.md`|Component responsibilities and role separation.|
|`docs/installation.md`|Prerequisites, bootstrap and first run.|
|`docs/vagrant.md`|The test environment, box provenance and environment variables.|
|`docs/configuration.md`|The user configuration file and preflight validation.|
|`docs/security.md`|SSH, firewall and audit posture.|
|`docs/maintenance.md`|Update workflow, kernel updates and reboots.|
|`docs/recovery.md`|Recovering access to a locked-out host.|
|`docs/troubleshooting.md`|Common failures and their resolutions.|

## Licence

MIT. See `LICENSE`.
