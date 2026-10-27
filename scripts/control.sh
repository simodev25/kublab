#!/usr/bin/env bash
# Installation du noeud controleur k3s.
set -euxo pipefail

CONTROL_IP="${CONTROL_IP:-192.168.105.11}"
NODE_NAME="${NODE_NAME:-k3s-control}"
# Certificat API : inclut TOUTES les IPs du sous-reseau LAN du Mac
# (TLS_SAN_SUBNET.1 a .254), pour survivre aux changements d'IP DHCP.
# Ajustez TLS_SAN_SUBNET si votre LAN utilise une autre plage.
TLS_SAN_SUBNET="${TLS_SAN_SUBNET:-192.168.1}"
# Nom mDNS du Mac : se met a jour tout seul si l'IP du Mac change.
TLS_SAN_DNS="${TLS_SAN_DNS:-$(scutil --get LocalHostName).local}"

SAN_ARGS=""
for i in $(seq 1 254); do
  SAN_ARGS="${SAN_ARGS} --tls-san=${TLS_SAN_SUBNET}.${i}"
done
SAN_ARGS="${SAN_ARGS} --tls-san=${TLS_SAN_DNS}"

echo "==> Attente que l'IP privee ${CONTROL_IP} soit active..."
for i in {1..30}; do
  if ip -4 addr show | grep -q "${CONTROL_IP}"; then break; fi
  sleep 2
done

echo "==> Installation de k3s server sur le controleur..."
PRIVATE_IFACE="$(ip -o -4 addr show | awk -v ip="$CONTROL_IP" 'split($4, a, "/") && a[1] == ip {print $2; exit}')"
PRIVATE_IFACE="${PRIVATE_IFACE%%@*}"
[ -n "$PRIVATE_IFACE" ] || { echo "IP privee $CONTROL_IP introuvable" >&2; exit 1; }
export INSTALL_K3S_EXEC="server --node-ip=${CONTROL_IP} --node-name=${NODE_NAME} --flannel-iface=${PRIVATE_IFACE}${SAN_ARGS} --write-kubeconfig-mode=600"
curl -sfL https://get.k3s.io | sh -

echo "==> Attente que l'API k3s reponde..."
for i in {1..60}; do
  if sudo /usr/local/bin/k3s kubectl get --raw='/readyz' >/dev/null 2>&1; then
    echo "==> Cluster pret !"
    break
  fi
  sleep 5
done

echo
echo "====================  TOKEN K3S  ===================="
sudo cat /var/lib/rancher/k3s/server/node-token
echo "============================================================="
echo
echo "Kubeconfig disponible:"
echo "  vagrant ssh k3s-control -c 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.yaml"
