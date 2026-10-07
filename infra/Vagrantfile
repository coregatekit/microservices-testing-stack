# -*- mode: ruby -*-
# vi: set ft=ruby :

BOX             = "bento/ubuntu-24.04"
NETWORK_PREFIX  = "192.168.56" # Default range host-only

NODES = [
  { name: "k3s-server", ip: "#{NETWORK_PREFIX}.10", cpus: 2, memory: 4096 },
  { name: "k3s-agent1", ip: "#{NETWORK_PREFIX}.11", cpus: 2, memory: 2048 },
  { name: "k3s-agent2", ip: "#{NETWORK_PREFIX}.12", cpus: 2, memory: 2048 },
]

# create /etc/hosts entries

HOSTS_ENTRIES = NODES.map { |n| "#{n[:ip]} #{n[:name]}" }.join("\n")

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.box = BOX
  config.vm.box_check_update = false

  # disable share folder, let's Ansible config this
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |node|
    config.vm.define node[:name] do |n|
      n.vm.hostname = node[:name]
      n.vm.network "private_network", ip: node[:ip]

      n.vm.provider "virtualbox" do |vb|
        vb.name         = node[:name]
        vb.cpus         = node[:cpus]
        vb.memory       = node[:memory]
        vb.linked_clone = true # clone from base disk
      end

      # provision base image only
      n.vm.provision "shell", inline: <<-SHELL
        sed -i '/k3s-/d' /etc/hosts
        cat >> /etc/hosts <<EOF
#{HOSTS_ENTRIES}
EOF
      SHELL
    end
  end
end
