Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  # VM specs (keep it lightweight)
  config.vm.provider "virtualbox" do |vb|
    vb.memory = 3072
    vb.cpus = 2
  end

  # Networking
  config.vm.network "private_network", ip: "192.168.56.10"

  # Sync your repo into VM
  config.vm.synced_folder ".", "/vagrant"

  # Ansible provisioner
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "ansible/playbooks/site.yaml"
    ansible.inventory_path = "ansible/inventory/vagrant.yaml"
    ansible.limit = "vagrant"
  end
end
