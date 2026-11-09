# Installation

## What you need

### The controller

Ansible runs on your workstation, not on the server. You need:

| Requirement | Why |
|---|---|
| `ansible-core` >= 2.16 | Runs the playbooks |
| `ansible.posix` collection | Provides `ansible.posix.authorized_key` |
| `ansible-lint`, `yamllint` | Optional; used by `make lint` |
| An SSH key pair | The public key is installed on the server |
| `git` | To clone the repository |

Install the Python toolchain and the collection:

```bash
make tools        # install the toolchain with uv
make collections  # ansible-galaxy collection install -r requirements.yml
```

`make tools` reads `requirements-dev.txt` and runs `uv tool install` once per
entry. Without `uv`, install the same three tools with `pipx`:

```bash
pipx install ansible-core
pipx install ansible-lint
pipx install yamllint
```

A plain `pip install --user` is refused on distributions that mark Python as
externally managed, which includes Arch and Debian 12 and later. Use `pipx` or a
virtualenv there.

### The server

- Debian 13 (Trixie), amd64 or arm64.
- A reachable SSH service.
- An account that can become root. The baseline creates the administrative
  account itself, so the account you first connect with only needs `sudo`.
- Python 3. `playbooks/bootstrap.yml` installs `python3` and `python3-apt` if
  they are missing, so a minimal image works.

### The development host (optional)

Only needed for the Vagrant test environment. See `docs/vagrant.md`; the short
version is:

```bash
sudo pacman -S --needed vagrant libvirt qemu-base qemu-system-x86 qemu-img make git
sudo usermod -aG libvirt "$USER"
vagrant plugin install vagrant-libvirt
```

`make check-host` reports every requirement and installs nothing.

## Configure the baseline

```bash
cp -n config/user.example.yml config/user.yml
$EDITOR config/user.yml
```

| Variable | Meaning |
|---|---|
| `server_hostname` | The hostname applied to the server |
| `admin_username` | The administrative account to create |
| `server_timezone` | The system timezone |
| `ssh_public_key_path` | Path on the controller to the public key to install |

`config/user.yml` is Git-ignored and must never be committed. See
`docs/configuration.md` for the validation the baseline performs on it.

## Prepare the production inventory

The end-to-end walkthrough for a real server, including the account Ansible
connects as and the provider firewall, is `docs/production.md`. The inventory
itself is:

```bash
cp -n inventories/production/hosts.example.yml inventories/production/hosts.yml
cp -n inventories/production/group_vars/all.example.yml inventories/production/group_vars/all.yml
$EDITOR inventories/production/hosts.yml
```

Both files are Git-ignored. `hosts.yml` holds the address of each server;
`all.yml` derives the SSH user and private key from `config/user.yml`, so run
Ansible from the repository root.

## First run

```bash
# Give Ansible a Python interpreter on a bare server (skip if Python 3 exists)
ansible-playbook -i inventories/production/hosts.yml playbooks/bootstrap.yml

# Apply the baseline
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml

# Confirm it is in place
ansible-playbook -i inventories/production/hosts.yml playbooks/verify.yml
```

`baseline.yml` starts by refreshing the package index and applying pending
upgrades, then configures the server. It is idempotent: running it again
immediately reports no changes. A later run may apply upgrades that Debian
published in the meantime, which is the intended behaviour.

## What the first run does to your access

The baseline creates `admin_username`, installs your public key for it, and
disables password authentication and root login over SSH. Your existing keys are
preserved, and the account you connected with is not modified.

Before the SSH daemon is hardened, `users` has already created the
administrative account and installed the key, so there is always a working way
in. If you are unsure, keep a second session open until you have confirmed that
`ssh -i <private key> <admin_username>@<host>` works.

## Testing before production

The repository ships a Vagrant environment that reproduces Debian 13 locally:

```bash
make vagrant-up
make vagrant-test
```

See `docs/vagrant.md`. Production deployment is a direct `ansible-playbook` run;
Vagrant is never required there.

## Uninstalling

The baseline has no uninstaller: it configures a server rather than installing a
product. To revert a specific change, see `docs/recovery.md`.
