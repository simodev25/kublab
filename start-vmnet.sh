#!/usr/bin/env bash
# Démarre le daemon socket_vmnet (réseau privé du cluster k3s(.
#
# À exécuter UNE fois ( en root(, AVANT `vagrant up` :
#   sudo bash start-vmnet.sh
#
# Le daemon tourne en avant-plan — gardez le terminal ouvert,
# ou relancez-le avec : sudo bash start-vmnet.sh &
set -euxo pipefail

exec /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
  --vmnet-gateway=192.168.105.1 \
  --vmnet-dhcp-end=192.168.105.100 \
  /opt/homebrew/var/run/socket_vmnet