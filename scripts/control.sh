#!/usr/bin/env bash
# Installation du noeud controleur k3s.
set -euxo pipefail

CONTROL_IP="${CONTROL_IP:-192.168.105.11}"
NODE_NAME="${NODE_NAME:-k3s-control}"
K3S_TLS_SAN="${K3S_TLS_SAN:-192.168.1.98}"

echo "==> Attente que l'IP privee ${CONTROL_IP} soit active..."
for i in {1..30}; do
  if ip -4 addr show | grep -q "${CONTROL_IP}"; then break; fi
  sleep 2
done

echo "==> Installation de k3s server sur le controleur..."
export INSTALL_K3S_EXEC="server --node-ip=${CONTROL_IP} --node-name=${NODE_NAME} --tls-san=${K3S_TLS_SAN} --write-kubeconfig-mode=600"
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
