# Recovery

## Before you need this

Two things make recovery possible:

- The baseline never touches the `vagrant` account in the Vagrant environment,
  and never touches `root` anywhere. Its own SSH hardening only affects the
  account named by `admin_username`.
- The firewall accepts the configured SSH port, so a mistake in another rule
  cannot lock you out of SSH.

## Lost SSH access

### Vagrant environment

`vagrant ssh` uses Vagrant's own account and key, which the baseline does not
modify:

```bash
vagrant ssh
```

If Vagrant's SSH is also broken, use the serial console. The libvirt domain is
named `<project-directory>_<BASELINE_VM_NAME>`, so list it first:

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system console debian-server-baseline_main
# log in as vagrant / vagrant, exit with Ctrl-]
```

### Production

Use the provider's out-of-band console (KVM, IPMI, a rescue system). Log in as
`root` or as the administrative user through the console, then diagnose:

```bash
systemctl status ssh
sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication)'
journalctl -u ssh -n 50
```

The most common cause is a firewall rule that does not accept the SSH port.
Check:

```bash
nft list table inet baseline_filter
```

## Firewall recovery

If the firewall is blocking you, remove only the baseline table from the
console:

```bash
nft destroy table inet baseline_filter
```

That leaves every other table intact. Re-apply the baseline table with:

```bash
nft -f /etc/nftables.d/10-server-baseline.nft
```

To disable the firewall permanently, set `baseline_firewall_enabled: false` and
re-run `baseline.yml`.

## SSH recovery

The baseline's SSH configuration lives in one file:

```bash
rm /etc/ssh/sshd_config.d/00-server-baseline.conf
systemctl reload ssh
```

That restores whatever the rest of the configuration says. To re-apply the
baseline, re-run `baseline.yml`.

If a broken configuration was written, `sshd -t` fails and the handler refuses
to reload, so the running daemon keeps the previous configuration. Fix the file
and re-run.

## Rebuilding a server

The baseline is designed to be re-applied:

```bash
ansible-playbook -i inventories/production/hosts.yml playbooks/baseline.yml
```

Every role is idempotent, so re-running is safe. To start from scratch, destroy
the machine and provision it again; nothing in the baseline depends on state
that only exists on a previously configured host.

## Vagrant environment recovery

```bash
make vagrant-destroy
make vagrant-up
```

`make vagrant-destroy` removes the domain and its disk. The box stays in the
local Vagrant cache, so recreating is fast.

If `vagrant up` fails while attaching a network, `virsh -c qemu:///system
net-list --all` shows the defined networks; a stale one can be removed with
`virsh -c qemu:///system net-undefine <name>`.

## Secrets

`config/user.yml` is Git-ignored and holds no secrets: it names a hostname, a
username, a timezone and the path to a public key. The private key never leaves
the controller.

If a private key is compromised, generate a new pair, point
`ssh_public_key_path` at the new public key, re-run `baseline.yml`, and remove
the old key from `/home/<admin_username>/.ssh/authorized_keys` by hand — the
baseline preserves existing keys by design.
