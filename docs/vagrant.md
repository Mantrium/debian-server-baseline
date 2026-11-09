# Vagrant environment

Vagrant exists only for local development and integration testing. Production
never uses it; see [`docs/production.md`](production.md) for the production
path.

## Host prerequisites

The development host is assumed to be Arch Linux (the maintainers use Omarchy).
Install the packages and add your user to the `libvirt` group:

```bash
sudo pacman -S --needed vagrant libvirt qemu-base qemu-system-x86 qemu-img make git
sudo usermod -aG libvirt "$USER"
# log out and back in so the group membership takes effect
```

Then install the Vagrant provider plugin and the Ansible toolchain:

```bash
vagrant plugin install vagrant-libvirt
make tools        # install the toolchain with uv
make collections  # ansible-galaxy collection install -r requirements.yml
```

`make check-host` reports every requirement and installs nothing.

### Firewall

libvirt NATs guest traffic through the host, so the host firewall must forward
packets coming from the libvirt bridge. A firewall that drops forwarded packets
leaves the guest without internet access, and every `apt` task in the baseline
then fails with `Failed to update apt cache`.

ICMP is usually still allowed, so the signature is a guest that can
`ping 1.1.1.1` but cannot reach an HTTP mirror.

With `ufw`:

```bash
uplink=$(ip route show default | awk '{print $5; exit}')
sudo ufw route allow in on virbr0 out on "$uplink"
sudo ufw route allow in on virbr1 out on "$uplink"
```

Alternatively, set `DEFAULT_FORWARD_POLICY="ACCEPT"` in `/etc/default/ufw` and
run `sudo ufw reload`.

## Box selection

The environment uses `cloud-image/debian-13`, pinned to a specific version.

|Property|Value|
|---|---|
|Box|`cloud-image/debian-13`|
|Version|`20260914.2601.0`|
|Provider|`libvirt`, architecture `amd64`|
|Provenance|Derived from the official Debian cloud image by `alchemy-solutions/vagrant-cloud-images`, which verifies the upstream `sha512` checksum at build time.|
|Upstream image|`debian-13-genericcloud-amd64.qcow2`, virtual size 3.0 GiB, published by the Debian cloud team.|
|Base disk|The box build resizes the disk to 10 GiB, so `machine_virtual_size` grows it to the configured size.|

The box injects a `vagrant` user (password `vagrant`, NOPASSWD sudo, the
standard Vagrant insecure key) through cloud-init with
`datasource_list: [NoCloud, None]`. That is what makes `vagrant ssh` work out of
the box, and it is deliberately independent of the administrative account the
baseline creates.

## Virtual machine specification

|Resource|Default|Environment variable|
|---|---|---|
|OS|Debian 13 (Trixie)|`BASELINE_VM_BOX` / `BASELINE_VM_BOX_VERSION`|
|Architecture|amd64|—|
|CPU|2 vCPU|`BASELINE_VM_CPUS`|
|RAM|4096 MiB|`BASELINE_VM_MEMORY`|
|Disk|30 GB|`BASELINE_VM_DISK`|
|Provider|libvirt (KVM/QEMU)|`BASELINE_VM_PROVIDER`|
|Networking|Provider-managed NAT|—|
|SSH|Vagrant-managed|`BASELINE_SSH_PORT`|
|Provisioning|Ansible remote provisioner|—|
|Python|Python 3 + `python3-apt`|—|

Copy `.env.example` to `.env` to override any of them; the Makefile sources
`.env` automatically.

No fixed LAN subnet is required: the VM address is assigned by the
provider-managed NAT network and discovered after boot.

## Commands

```bash
make vagrant-up         # create, provision and refresh the inventory
make vagrant-provision  # re-run both Ansible provisioners
make vagrant-ssh        # interactive shell
make vagrant-reload     # reboot
make vagrant-status     # show status
make vagrant-destroy    # destroy the VM
make vagrant-test       # run tests/integration/test_*.sh
```

Equivalent raw commands: `vagrant up --provider=libvirt`, `vagrant provision`,
`vagrant ssh`, `vagrant reload`, `vagrant status`, `vagrant destroy`.

## Provisioning order

`vagrant up` runs two Ansible provisioners, in this order:

1. `playbooks/bootstrap.yml` — ensures `python3` and `python3-apt` exist. It
   uses `raw` and no fact gathering so it works on a host without Python.
2. `playbooks/baseline.yml` — the baseline itself.

## Inventory mechanism

`vagrant-libvirt` connects straight to the VM address on the provider-managed
network, so the address is only known after boot. `scripts/vagrant-inventory.sh`
reads `vagrant ssh-config` and writes `.vagrant/vagrant-env.sh`:

```sh
export BASELINE_VAGRANT_HOST='192.168.121.x'
export BASELINE_VAGRANT_PORT='22'
export BASELINE_VAGRANT_USER='vagrant'
export BASELINE_VAGRANT_KEY='/abs/path/.vagrant/machines/main/libvirt/private_key'
```

`inventories/vagrant/hosts.yml` reads those variables, so the checked-in
inventory stays static. Every Ansible target in the Makefile sources the file
and passes `-i inventories/vagrant/hosts.yml`, which is what keeps the
production inventory from being selected by accident.

## Recreating the machine

```bash
make vagrant-destroy
make vagrant-up
make vagrant-test
```

A destroyed and recreated VM is the clean-installation test: the administrative
SSH key must be read from `config/user.yml` and installed automatically.
