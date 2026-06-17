# Vagrant runs ansible-playbook from this directory (the project root), but the
# playbooks/roles assume the `ansible/` dir as the working context. Point ansible
# at the right config and roles via absolute paths so resolution is independent of cwd.
ENV["ANSIBLE_CONFIG"]     = File.expand_path("ansible/ansible.cfg", __dir__)
ENV["ANSIBLE_ROLES_PATH"] = File.expand_path("ansible/roles", __dir__)

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

  # Phase 1: initial server setup (runs as the default `vagrant` user).
  # Creates the deploy user, installs the SSH key, hardens SSH.
  config.vm.provision "bootstrap", type: "ansible" do |ansible|
    ansible.playbook          = "ansible/playbooks/bootstrap.yaml"
    ansible.compatibility_mode = "2.0"
  end

  # Phase 2: main deploy — docker, firewall, ssh, services.
  # Still connects as `vagrant` (passwordless sudo via become); needs the vault password.
  config.vm.provision "main", type: "ansible" do |ansible|
    ansible.playbook           = "ansible/playbooks/main.yaml"
    ansible.vault_password_file = ".vault_pass"
    ansible.compatibility_mode = "2.0"
  end
end
