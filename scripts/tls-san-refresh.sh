#!/usr/bin/env bash
# Regénère le certificat de l'API k3s avec TOUTES les IPs du sous-réseau LAN
# du Mac (TLS_SAN_SUBNET.1 à .254). Plus jamais d'erreur x509 si l'IP DHCP change :
# seul le champ "server" du kubeconfig client reste à mettre à jour.
#
# Usage (depuis le Mac) :
#   bash scripts/tls-san-refresh.sh
#   TLS_SAN_SUBNET=192.168.0 bash scripts/tls-san-refresh.sh
set -euo pipefail

SUBNET="${TLS_SAN_SUBNET:-192.168.1}"
CONTROL_IP="192.168.105.11"

SAN_ARGS=""
for i in $(seq 1 254); do
  SAN_ARGS="${SAN_ARGS} --tls-san=${SUBNET}.${i}"
done

echo "==> Regénération du certificat API avec les SANs ${SUBNET}.1-${SUBNET}.254"
echo "==> k3s va redémarrer (environ 30-60 s)..."
vagrant ssh k3s-control -c "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --node-ip=${CONTROL_IP} --node-name=k3s-control --flannel-iface=eth0${SAN_ARGS} --write-kubeconfig-mode=600' sh -"

echo
echo "==> Vérification des SANs du nouveau certificat :"
echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
