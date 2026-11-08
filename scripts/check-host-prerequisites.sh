#!/usr/bin/env bash
#
# Report whether this development host can build and test the baseline.
#
# Read-only: this script installs nothing and changes nothing. It prints one
# line per requirement and exits non-zero if a required item is missing.

set -uo pipefail

missing=0

ok()   { printf '  %-34s OK\n' "$1"; }
bad()  { printf '  %-34s MISSING  %s\n' "$1" "${2:-}"; missing=$((missing + 1)); }
note() { printf '  %-34s %s\n' "$1" "$2"; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "== Required commands =="
for cmd in vagrant virsh qemu-system-x86_64 qemu-img make git uv \
           ansible-playbook ansible-galaxy ansible-lint yamllint; do
  if have "$cmd"; then ok "$cmd"; else bad "$cmd"; fi
done

echo
echo "== Vagrant =="
if have vagrant; then
  note "vagrant version" "$(vagrant --version 2>/dev/null)"
  if vagrant plugin list 2>/dev/null | grep -q '^vagrant-libvirt '; then
    ok "vagrant-libvirt plugin"
  else
    bad "vagrant-libvirt plugin" "vagrant plugin install vagrant-libvirt"
  fi
else
  bad "vagrant"
fi

echo
echo "== libvirt =="
if have virsh; then
  if virsh -c qemu:///system nodeinfo >/dev/null 2>&1; then
    ok "qemu:///system reachable"
  else
    bad "qemu:///system reachable" "add this user to the 'libvirt' group and re-login"
  fi
  if virsh -c qemu:///system net-list --all 2>/dev/null | grep -q .; then
    ok "libvirt networks"
  else
    note "libvirt networks" "none defined yet; vagrant-libvirt creates one on first up"
  fi
else
  bad "virsh"
fi

echo
echo "== SSH key pair =="
for f in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"; do
  if [ -f "$f" ]; then ok "$f"; else bad "$f" "ssh-keygen -t ed25519"; fi
done

echo
echo "== Disk space =="
avail_kb=$(df -Pk /var/lib/libvirt 2>/dev/null | awk 'NR==2 {print $4}')
if [ -z "${avail_kb:-}" ]; then
  avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
fi
avail_gb=$((avail_kb / 1024 / 1024))
if [ "$avail_gb" -ge 40 ]; then
  ok "free space (${avail_gb} GiB)"
else
  bad "free space (${avail_gb} GiB)" "at least 40 GiB recommended"
fi

echo
echo "== Host packages (Arch Linux names) =="
cat <<'EOF'
  vagrant libvirt qemu-base qemu-system-x86 qemu-img make git
  Install with: sudo pacman -S --needed vagrant libvirt qemu-base qemu-system-x86 qemu-img make git
  Then:         sudo usermod -aG libvirt "$USER"   (log out and back in)
EOF

echo
if [ "$missing" -eq 0 ]; then
  echo "All prerequisites satisfied."
  exit 0
fi
echo "$missing prerequisite(s) missing."
exit 1
