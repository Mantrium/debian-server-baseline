#!/usr/bin/env bash
#
# Shared helpers for the integration tests.
#
# Every tests/integration/test_*.sh sources this file. Tests run on the
# controller and inspect the Vagrant guest over SSH, so they exercise the
# machine exactly as an operator would.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Connection details produced by scripts/vagrant-inventory.sh.
if [ ! -f .vagrant/vagrant-env.sh ]; then
  scripts/vagrant-inventory.sh >/dev/null
fi
# shellcheck disable=SC1091
set -a; . .vagrant/vagrant-env.sh; set +a

: "${BASELINE_VAGRANT_HOST:?BASELINE_VAGRANT_HOST is not set}"
: "${BASELINE_VAGRANT_PORT:?BASELINE_VAGRANT_PORT is not set}"
: "${BASELINE_VAGRANT_USER:?BASELINE_VAGRANT_USER is not set}"
: "${BASELINE_VAGRANT_KEY:?BASELINE_VAGRANT_KEY is not set}"

USER_CONFIG="$REPO_ROOT/config/user.yml"

baseline_failures=0
baseline_checks=0

# guest <command> - run a command on the guest as the Vagrant user.
guest() {
  ssh -i "$BASELINE_VAGRANT_KEY" \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$REPO_ROOT/.vagrant/known_hosts" \
      -o LogLevel=ERROR \
      -o ConnectTimeout=10 \
      -p "$BASELINE_VAGRANT_PORT" \
      "$BASELINE_VAGRANT_USER@$BASELINE_VAGRANT_HOST" "$@"
}

# guest_root <command> - run a command on the guest with sudo.
guest_root() {
  guest "sudo -n $*"
}

# user_config <key> - read a scalar value from config/user.yml.
user_config() {
  sed -n "s/^$1:[[:space:]]*//p" "$USER_CONFIG" | head -n 1 | sed -e 's/^"//' -e 's/"$//'
}

# user_config_resolved <key> - read a scalar from config/user.yml with any
# Jinja expression resolved. The example configuration stores the SSH key path
# as "{{ lookup('env', 'HOME') }}/.ssh/id_ed25519.pub", so the raw value is not
# a usable path.
user_config_resolved() {
  ansible localhost -c local -m debug -a "var=$1" -e "@$USER_CONFIG" 2>/dev/null |
    sed -n "s/.*\"$1\": \"\(.*\)\".*/\1/p"
}

baseline_ok() {
  baseline_checks=$((baseline_checks + 1))
  printf 'ok   %s\n' "$1"
}

baseline_fail() {
  baseline_checks=$((baseline_checks + 1))
  baseline_failures=$((baseline_failures + 1))
  printf 'FAIL %s\n' "$1"
  shift
  for line in "$@"; do
    printf '       %s\n' "$line"
  done
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then
    baseline_ok "$1"
  else
    baseline_fail "$1" "expected: $2" "actual:   $3"
  fi
}

# assert_contains <label> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) baseline_ok "$1" ;;
    *) baseline_fail "$1" "expected to contain: $3" "actual: $2" ;;
  esac
}

# assert_not_contains <label> <haystack> <needle>
assert_not_contains() {
  case "$2" in
    *"$3"*) baseline_fail "$1" "expected not to contain: $3" "actual: $2" ;;
    *) baseline_ok "$1" ;;
  esac
}

# assert_nonempty <label> <value>
assert_nonempty() {
  if [ -n "$2" ]; then
    baseline_ok "$1"
  else
    baseline_fail "$1" "value is empty"
  fi
}

# finish - print the summary and exit non-zero if anything failed.
finish() {
  printf '\n%s: %d checks, %d failed\n' "$(basename "$0")" "$baseline_checks" "$baseline_failures"
  [ "$baseline_failures" -eq 0 ]
}

# baseline_apply [extra ansible-playbook arguments] - apply playbooks/baseline.yml
# to the Vagrant guest and print the PLAY RECAP line for the host.
baseline_apply() {
  local out
  out="$(make baseline EXTRA_VARS="$*" 2>&1)" || {
    printf '%s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" | grep -E '^[a-z0-9_-]+ +: ok=' | tail -n 1
}

# guest_reboot - reboot the guest and wait until it is reachable again.
# Returns non-zero if it does not come back.
guest_reboot() {
  guest 'sudo reboot' >/dev/null 2>&1 || true

  # `sudo reboot` returns before the machine stops, so wait for it to go down
  # first; otherwise the caller's checks run against the pre-reboot system.
  for _ in $(seq 1 60); do
    guest 'true' >/dev/null 2>&1 || break
    sleep 2
  done

  for _ in $(seq 1 90); do
    if guest 'true' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# first_rule <chain> - the first rule of a chain in the baseline table, or the
# chain's closing brace when the chain has no rules.
first_rule() {
  guest_root "nft -s list chain inet $table $1" | sed -n '/type filter hook/{n;p;q}'
}
