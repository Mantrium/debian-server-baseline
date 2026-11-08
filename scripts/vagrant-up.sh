#!/usr/bin/env bash
#
# Create and provision the Vagrant VM, then refresh the inventory variables.

set -euo pipefail

cd "$(dirname "$0")/.."

PROVIDER="${BASELINE_VM_PROVIDER:-libvirt}"

vagrant up --provider="$PROVIDER"
scripts/vagrant-inventory.sh
