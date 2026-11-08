#!/usr/bin/env bash
#
# Destroy the Vagrant VM and the generated inventory variables.

set -euo pipefail

cd "$(dirname "$0")/.."

vagrant destroy -f
rm -f .vagrant/vagrant-env.sh
