# Configuration

Every user-specific setting lives in a single Git-ignored file, `config/user.yml`.
The repository itself contains no hostname, no account name, no timezone and no
key path that belongs to a particular operator.

## The four variables

|Variable|Meaning|Example|
|---|---|---|
|`server_hostname`|The hostname applied to the target by `os_identity`. The Vagrantfile also reads it, only to abort early when the configuration is missing.|`myserver`|
|`admin_username`|The administrative account created on the target and added to `sudo`.|`admin`|
|`server_timezone`|The system timezone, as a name valid under `/usr/share/zoneinfo`.|`Etc/UTC`|
|`ssh_public_key_path`|Path **on the controller** to the public key installed for `admin_username`.|`/home/user/.ssh/id_ed25519.pub`|

These four variables are the only authoritative source for those values. No role
default restates them.

## Copy workflow

```bash
cp config/user.example.yml config/user.yml
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
5. asserts that `/usr/share/zoneinfo/<server_timezone>` exists on the target;
6. reads the public key, asserts it is a recognised key type, and derives the
   matching private key path by stripping a trailing `.pub`;
7. asserts that the private key exists on the controller, because the
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
|Public key missing, empty, a directory, or not a recognised key type|Fails with the key path.|
|Matching private key absent|Fails naming the private key path.|

## Related variables

`BASELINE_SSH_PORT` (Vagrant) and `baseline_ssh_port` (the `ssh` and `nftables`
roles) must agree when the SSH port is changed; see `docs/vagrant.md` and
`docs/security.md`.

The `BASELINE_VM_*` environment variables select the Vagrant box, size and
provider; see `docs/vagrant.md`.

The production inventory derives its connection user and private key from
`config/user.yml` with `lookup('file', 'config/user.yml')`, so Ansible must be
run from the repository root when using it.
