# -*- mode: ruby -*-
# vi: set ft=ruby :

# ---------------------------------------------------------------------------
# Cluster k3s — 1 contrôleur + 2 workers, sur QEMU (plugin vagrant-qemu(
#
# Réseau privé (backend :socket_vmnet, sans sudo une fois le daemon lancé(:
#   Contrôleur  : 192.168.105.11
#   Worker 1    :	192.168.105.12
#   Worker 2    :	192.168.105.13
#
# Prérequis (à faire une fois(:
#   1. /opt/homebrew/bin/brew install qemu socket_vmnet
#   2. vagrant plugin install vagrant-qemu
#   3. vagrant box add perk/ubuntu-2204-arm64 --provider libvirt
#      (la metadata interne de la box est étiquetée libvirt — même si l'API la
#       propose aussi pour qemu. Le plugin sait importer ce format v1(.
#   4. sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
#          --vmnet-gateway=192.168.105.1 \
#          --vmnet-dhcp-end=192.168.105.100 \
#          /opt/homebrew/var/run/socket_vmnet
#
# Démarrage (toujours en séquentiel(:
#   vagrant up --provider qemu --no-parallel
# ---------------------------------------------------------------------------

CONTROL_IP = "192.168.105.11"
WORKER_IPS  = ["192.168.105.12", "192.168.105.13"]

# La box publique est enregistrée sous le provider « libvirt ». On pointe
# explicitement son box.img (format v1, importé par le plugin) afin que
# `--provider qemu` l'utilise. (Glob tolérant la version + l'arch de la box.)
BOX_IMAGES = Dir.glob(File.expand_path(
  "~/.vagrant.d/boxes/perk-VAGRANTSLASH-ubuntu-2204-arm64/*/arm64/*/box.img"
)).sort
BOX_IMG = BOX_IMAGES.last
if BOX_IMG.nil?
  abort("Box introuvable. Lancez d'abord:\n  vagrant box add perk/ubuntu-2204-arm64 --provider libvirt")
end

# Clé privée du contrôleur, générée par Vagrant au premier up ( copiée dans
# chaque worker pour que l'agent k3s puisse lire le token sur le contrôleur.

CONTROL_KEY = ".vagrant/machines/k3s-control/qemu/private_key"

Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-2204-arm64"

  # Évite le prompt SMB (nécessite mot de passe+ — la box est un cloud image,
  # le dossier du projet n'est pas nécessaire dans les VM..
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Auth SSH: user « vagrant » + clé (générée par Vagrant au premier boot);
  # PAS de mot de passe ( un password configuré ferait échouer l'auth(.
  config.ssh.username = "vagrant"
  config.vm.boot_timeout = 600

  # -----------------------------------------------------------------
  # Contrôleur (control-plane k3s(
  # -----------------------------------------------------------------
  config.vm.define "k3s-control" do |c|
    c.vm.hostname = "k3s-control"

    # IP privée sur le réseau des nœuds + exposition de l'API k8s vers le Mac
    c.vm.network "private_network", ip: CONTROL_IP
    c.vm.network "forwarded_port", guest: 6443, host: 6443, host_ip: "0.0.0.0"

    c.vm.provider "qemu" do |qe|
      qe.image_path = BOX_IMG
      qe.memory = "2G"
      qe.smp = "2"
      qe.advanced_network = true
      qe.net_mode = :socket_vmnet
      qe.ssh_auto_correct = true
    end

    c.vm.provision "shell", path: "scripts/control.sh", env: {"CONTROL_IP" => CONTROL_IP, "NODE_NAME" => "k3s-control"}
  end

  # -----------------------------------------------------------------
  # Workers
  # -----------------------------------------------------------------
  WORKER_IPS.each_with_index do |ip, i|
    name = "k3s-worker#{i+1}"
    config.vm.define name do |c|
      c.vm.hostname = name

      c.vm.network "private_network", ip: ip

      c.vm.provider "qemu" do |qe|
        qe.image_path = BOX_IMG
        qe.memory = "2G"
        qe.smp = "2"
        qe.advanced_network = true
        qe.net_mode = :socket_vmnet
        qe.ssh_auto_correct = true
      end

      # Clé privée du contrôleur, copiée dans le worker ( la clé publique
      # correspondante est en authorized_keys sur le contrôleur( → le worker peut
      # s'y connecter pour lire le token k3s.
      c.vm.provision "file", source: CONTROL_KEY, destination: "/home/vagrant/.ssh/k3s-control_key"
      c.vm.provision "shell", path: "scripts/worker.sh", env: {"CONTROL_IP" => CONTROL_IP, "AGENT_IP" => ip, "NODE_NAME" => name}
    end
  end
end