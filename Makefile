SHELL := /bin/bash

-include .env
export

PROVIDER          ?= libvirt
VAGRANT_INVENTORY := inventories/vagrant/hosts.yml
VAGRANT_ENV       := .vagrant/vagrant-env.sh

ANSIBLE_PLAYBOOK := ansible-playbook
ANSIBLE_LINT     := ansible-lint
YAMLLINT         := yamllint

.PHONY: help tools collections check-host vagrant-up vagrant-provision \
        vagrant-ssh vagrant-reload vagrant-status vagrant-destroy vagrant-test \
        bootstrap baseline syntax-check lint test verify maintenance security-audit clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  %-20s %s\n", $$1, $$2}'

tools: ## Install the tools listed in requirements-dev.txt with uv
	@for tool in $$(grep -vE '^[[:space:]]*(#|$$)' requirements-dev.txt); do \
		echo "uv tool install $$tool"; \
		uv tool install "$$tool" || exit 1; \
	done

collections: ## Install the required Ansible collections
	ansible-galaxy collection install -r requirements.yml

check-host: ## Report missing host prerequisites (installs nothing)
	scripts/check-host-prerequisites.sh

vagrant-up: ## Create and provision the Vagrant VM
	scripts/vagrant-up.sh

vagrant-provision: ## Re-run the Ansible provisioners
	vagrant provision

vagrant-ssh: ## Open an SSH session to the VM
	vagrant ssh

vagrant-reload: ## Reboot the VM
	vagrant reload

vagrant-status: ## Show VM status
	vagrant status

vagrant-destroy: ## Destroy the VM
	scripts/vagrant-destroy.sh

vagrant-test: ## Run the integration test suite against the VM
	scripts/vagrant-test.sh

bootstrap: ## Run playbooks/bootstrap.yml against the Vagrant VM
	@test -f $(VAGRANT_ENV) || scripts/vagrant-inventory.sh
	set -a; . $(VAGRANT_ENV); set +a; $(ANSIBLE_PLAYBOOK) -i $(VAGRANT_INVENTORY) playbooks/bootstrap.yml

baseline: ## Run playbooks/baseline.yml against the Vagrant VM (EXTRA_VARS=...)
	@test -f $(VAGRANT_ENV) || scripts/vagrant-inventory.sh
	set -a; . $(VAGRANT_ENV); set +a; $(ANSIBLE_PLAYBOOK) -i $(VAGRANT_INVENTORY) playbooks/baseline.yml $(EXTRA_VARS)

syntax-check: ## ansible-playbook --syntax-check on every playbook
	@for p in playbooks/*.yml; do echo "== $$p"; $(ANSIBLE_PLAYBOOK) --syntax-check -i $(VAGRANT_INVENTORY) "$$p" || exit 1; done

lint: ## ansible-lint and yamllint
	$(ANSIBLE_LINT)
	$(YAMLLINT) .

test: ## Run the integration test suite against the Vagrant VM
	scripts/vagrant-test.sh

verify: ## Run playbooks/verify.yml against the Vagrant VM (EXTRA_VARS=...)
	@test -f $(VAGRANT_ENV) || scripts/vagrant-inventory.sh
	set -a; . $(VAGRANT_ENV); set +a; $(ANSIBLE_PLAYBOOK) -i $(VAGRANT_INVENTORY) playbooks/verify.yml $(EXTRA_VARS)

maintenance: ## Generate the maintenance report
	@test -f $(VAGRANT_ENV) || scripts/vagrant-inventory.sh
	set -a; . $(VAGRANT_ENV); set +a; $(ANSIBLE_PLAYBOOK) -i $(VAGRANT_INVENTORY) playbooks/maintenance.yml

security-audit: ## Generate the security audit report
	@test -f $(VAGRANT_ENV) || scripts/vagrant-inventory.sh
	set -a; . $(VAGRANT_ENV); set +a; $(ANSIBLE_PLAYBOOK) -i $(VAGRANT_INVENTORY) playbooks/security-audit.yml

clean: ## Remove generated local state
	rm -f $(VAGRANT_ENV)
