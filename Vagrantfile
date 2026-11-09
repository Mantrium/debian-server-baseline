# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Local development and integration-testing environment for the Debian 13
# server baseline. Production never uses Vagrant.
#
# Every user-specific value comes from config/user.yml; every machine sizing
# value comes from the environment (see .env.example).

require 'yaml'

PROJECT_ROOT = File.dirname(__FILE__)
USER_CONFIG  = File.join(PROJECT_ROOT, 'config', 'user.yml')

unless File.exist?(USER_CONFIG)
  abort <<~MSG
    ERROR: #{USER_CONFIG} is missing.

    Copy the example configuration and edit it for your environment:

        cp config/user.example.yml config/user.yml

    See docs/configuration.md for details.
  MSG
end

user_config = YAML.load_file(USER_CONFIG) || {}
server_hostname = user_config['server_hostname'].to_s.strip
if server_hostname.empty?
  abort "ERROR: server_hostname is not set in #{USER_CONFIG}"
end

vm_name    = ENV.fetch('BASELINE_VM_NAME', 'main')
vm_box     = ENV.fetch('BASELINE_VM_BOX', 'cloud-image/debian-13')
vm_box_ver = ENV.fetch('BASELINE_VM_BOX_VERSION', '20260914.2601.0')
vm_cpus    = ENV.fetch('BASELINE_VM_CPUS', '2').to_i
vm_memory  = ENV.fetch('BASELINE_VM_MEMORY', '4096').to_i
vm_disk    = ENV.fetch('BASELINE_VM_DISK', '30').to_i
ssh_port   = ENV.fetch('BASELINE_SSH_PORT', '22').to_i

Vagrant.configure('2') do |config|
  config.vagrant.plugins = 'vagrant-libvirt'

  config.vm.define vm_name do |vm|
    vm.vm.box          = vm_box
    vm.vm.box_version  = vm_box_ver
    vm.vm.boot_timeout = 600

    # The os_identity role owns the hostname and /etc/hosts.
    #
    # Vagrant's Debian capability writes only the first label of vm.hostname
    # (name.split(".", 2)[0]) and re-applies it on every `up` and `reload`, so
    # an FQDN such as server.example.com would silently become server and
    # would revert after a reboot. Disabling the modification keeps one owner.
    vm.vm.allow_hosts_modification = false

    # The repository is not shared into the guest; Ansible runs from the host.
    vm.vm.synced_folder '.', '/vagrant', disabled: true

    # Vagrant's own SSH access (user "vagrant", insecure key) is deliberately
    # independent of the server's administrative SSH configuration.
    vm.ssh.port = ssh_port

    vm.vm.provider :libvirt do |libvirt|
      libvirt.driver               = 'kvm'
      libvirt.uri                  = 'qemu:///system'
      libvirt.cpus                 = vm_cpus
      libvirt.memory               = vm_memory
      libvirt.machine_virtual_size = vm_disk
      libvirt.cpu_mode             = 'host-passthrough'
    end

    vm.vm.provision 'ansible' do |ansible|
      ansible.playbook           = 'playbooks/bootstrap.yml'
      ansible.become             = true
      ansible.compatibility_mode = '2.0'
    end

    vm.vm.provision 'ansible' do |ansible|
      ansible.playbook           = 'playbooks/baseline.yml'
      ansible.become             = true
      ansible.compatibility_mode = '2.0'
    end
  end
end
