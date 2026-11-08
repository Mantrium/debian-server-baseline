#!/usr/bin/env bash
#
# Assert the baseline package set is installed and its tools are usable.

# shellcheck source=tests/integration/lib.sh
. "$(dirname "$0")/lib.sh"

packages="sudo openssh-server ca-certificates curl wget git jq rsync neovim
python3 python3-apt locales tzdata nftables apt-listchanges apt-listbugs
debian-security-support needrestart iproute2 iputils-ping bind9-dnsutils
tcpdump lsof ethtool btop iftop sysstat logrotate"

for pkg in $packages; do
  assert_eq "$pkg is installed" "install ok installed" \
    "$(guest "dpkg-query -W -f='\${Status}' $pkg 2>/dev/null")"
done

for cmd in git nvim jq ss ping dig tcpdump lsof ethtool btop iftop sar; do
  # ethtool and iftop live in /usr/sbin, which is not on a non-root PATH.
  assert_eq "$cmd is executable" "ok" \
    "$(guest "PATH=\$PATH:/usr/sbin:/sbin command -v $cmd >/dev/null 2>&1 && echo ok || echo missing")"
done

finish
