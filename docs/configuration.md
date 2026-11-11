# Configuration

Every user-specific setting lives in a single Git-ignored file, `config/user.yml`.
The repository itself contains no hostname, no account name, no timezone and no
key path that belongs to a particular operator.

## The user variables

|Variable|Meaning|Example|
|---|---|---|
|`server_hostname`|The hostname applied to the target by `os_identity`. The Vagrantfile also reads it, only to abort early when the configuration is missing.|`myserver`|
|`admin_username`|The administrative account created on the target and added to `sudo`.|`admin`|
|`server_timezone`|The system timezone, as a name valid under `/usr/share/zoneinfo`.|`Etc/UTC`|
|`ssh_public_key_path`|Path **on the controller** to the public key installed for `admin_username`.|`/home/user/.ssh/id_ed25519.pub`|
|`baseline_firewall_block_ipv6`|Optional. Block IPv6 at the host firewall; see [`docs/firewall-extensions.md`](firewall-extensions.md). Must be a YAML boolean. Defaults to `false`.|`false`|

The first four variables are the only authoritative source for those values. No
role default restates them. `baseline_firewall_block_ipv6` is optional: it may
be absent from `config/user.yml`, in which case the `nftables` role default
(`false`) applies.

## Copy workflow

```bash
cp -n config/user.example.yml config/user.yml
$EDITOR config/user.yml
```

`config/user.yml` is listed in `.gitignore` and must never be committed.
`config/user.example.yml` is tracked and is the documented template.

`ssh_public_key_path` may use Jinja expressions, because the file is loaded with
`ansible.builtin.include_vars` and therefore templated. The example used by the
maintainers is:

```yaml
ssh_public_key_path: "{{ lookup('env', 'HOME') }}/.ssh/id_ed25519.pub"
```

## Where the file is read

`roles/preflight` runs first in every playbook. It:

1. checks that `config/user.yml` exists on the controller;
2. loads it with `include_vars`, so the variables land at host scope;
3. asserts that all four variables are defined and non-empty;
4. asserts that `server_hostname` is a DNS-style name and `admin_username`
   matches `^[a-z_][a-z0-9_-]*$`;
5. asserts that `baseline_firewall_block_ipv6`, when set, is a YAML boolean, and
   that it is not `true` while `baseline_firewall_enabled` is `false`;
6. asserts that `/usr/share/zoneinfo/<server_timezone>` exists on the target;
7. reads the public key, asserts it is a recognised key type, and derives the
   matching private key path by stripping a trailing `.pub`;
8. asserts that the private key exists on the controller, because the
   integration tests authenticate with it.

It publishes two facts for the later roles:

|Fact|Value|
|---|---|
|`baseline_ssh_public_key`|The full public key line, read with `lookup('file', ssh_public_key_path)`.|
|`baseline_ssh_private_key_path`|`ssh_public_key_path` with a trailing `.pub` removed.|

## Preflight failure modes

|Situation|Result|
|---|---|
|`config/user.yml` absent|Fails with the `cp config/user.example.yml config/user.yml` instruction.|
|A required variable missing or empty|Fails naming the variable and the file.|
|`server_hostname` or `admin_username` malformed|Fails with the accepted pattern.|
|`server_timezone` not present under `/usr/share/zoneinfo`|Fails naming the timezone.|
|`baseline_firewall_block_ipv6` not a YAML boolean|Fails naming the variable, its type and the accepted forms.|
|`baseline_firewall_block_ipv6: true` with `baseline_firewall_enabled: false`|Fails explaining that the firewall is not configured, so the blocking would not be enforced.|
|Public key missing, empty, a directory, or not a recognised key type|Fails with the key path.|
|Matching private key absent|Fails naming the private key path.|

## Firewall IPv6 blocking

`baseline_firewall_block_ipv6` is the one optional user variable. It is a YAML
boolean and defaults to `false`; see
[`docs/firewall-extensions.md`](firewall-extensions.md) for the full reference.

```yaml
# Preserve the existing dual-stack firewall behaviour.
baseline_firewall_block_ipv6: false
```

```yaml
# Block IPv6 at the host firewall.
baseline_firewall_block_ipv6: true
```

Set it in `config/user.yml` and re-run `playbooks/baseline.yml`; no reboot is
needed in either direction. On the command line, use a YAML file
(`-e @file.yml`) or the JSON form `-e '{"baseline_firewall_block_ipv6": true}'`,
because `-e baseline_firewall_block_ipv6=true` produces the string `"true"`,
which preflight rejects.

## Related variables

`BASELINE_SSH_PORT` (Vagrant) and `baseline_ssh_port` (the `ssh` and `nftables`
roles) must agree when the SSH port is changed; see
[`docs/vagrant.md`](vagrant.md) and [`docs/security.md`](security.md).

The `BASELINE_VM_*` environment variables select the Vagrant box, size and
provider; see [`docs/vagrant.md`](vagrant.md).

The production inventory derives its connection user and private key from
`config/user.yml` with `lookup('template', ...)`. It renders the file rather
than reading it raw, so a Jinja expression such as `lookup('env', 'HOME')` in
`ssh_public_key_path` is resolved before the value is used as a connection
parameter; connection variables are not templated recursively. Ansible must be
run from the repository root when using it.
