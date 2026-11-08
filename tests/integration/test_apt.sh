#!/usr/bin/env bash
#
# Assert the APT repository and maintenance configuration.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

sources_file=/etc/apt/sources.list.d/debian.sources
sources="$(guest "cat $sources_file")"

assert_contains "debian.sources declares the Debian URI" \
  "$sources" "URIs: https://deb.debian.org/debian"
assert_contains "debian.sources declares the security URI" \
  "$sources" "URIs: https://security.debian.org/debian-security"
assert_contains "debian.sources declares the release suites" \
  "$sources" "Suites: trixie trixie-updates"
assert_contains "debian.sources declares the security suite" \
  "$sources" "Suites: trixie-security"
assert_contains "debian.sources declares the components" \
  "$sources" "Components: main non-free-firmware"
assert_contains "debian.sources pins the signing key" \
  "$sources" "Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp"
assert_not_contains "debian.sources does not use a mirrorlist" "$sources" "mirror+file:"

assert_eq "the superseded security sources file is absent" "" \
  "$(guest 'ls /etc/apt/sources.list.d/debian-security.sources 2>/dev/null')"

assert_eq "apt-get update succeeds" "0" \
  "$(guest_root 'apt-get update >/dev/null 2>&1; echo $?')"

policy="$(guest 'apt-cache policy')"
assert_contains "the trixie suite is available" "$policy" "trixie/main"
assert_contains "the trixie-updates suite is available" "$policy" "trixie-updates/main"
assert_contains "the trixie-security suite is available" "$policy" "trixie-security/main"

periodic="$(guest 'cat /etc/apt/apt.conf.d/20auto-upgrades')"
assert_contains "the package index is refreshed periodically" \
  "$periodic" 'APT::Periodic::Update-Package-Lists "1";'
assert_contains "upgrades are not downloaded automatically" \
  "$periodic" 'APT::Periodic::Download-Upgradeable-Packages "0";'
assert_contains "upgrades are not applied automatically" \
  "$periodic" 'APT::Periodic::Unattended-Upgrade "0";'
assert_contains "the package cache is cleaned periodically" \
  "$periodic" 'APT::Periodic::AutocleanInterval "7";'

for pkg in apt-listchanges apt-listbugs debian-security-support needrestart; do
  assert_eq "$pkg is installed" "install ok installed" \
    "$(guest "dpkg-query -W -f='\${Status}' $pkg 2>/dev/null")"
done

# apt_upgrade runs before every other role, so a freshly provisioned server has
# nothing left to upgrade.
assert_eq "no package upgrades are pending" "0" \
  "$(guest 'apt-get -s upgrade 2>/dev/null | grep -c "^Inst "')"

finish
