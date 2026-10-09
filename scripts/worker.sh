#!/usr/bin/env bash
# Installation d'un noeud worker k3s connecte au controleur.
set -euxo pipefail

CONTROL_IP="${CONTROL_IP:-192.168.105.11}"
AGENT_IP="${AGENT_IP:-192.168.105.12}"
NODE_NAME="${NODE_NAME:-k3s-worker1}"
SSH_KEY="/home/vagrant/.ssh/k3s-control_key"

chmod 600 "${SSH_KEY}"

echo "==> Attente que l'IP privee ${AGENT_IP} soit active..."
for i in {1..30}; do
  if ip -4 addr show | grep -q "${AGENT_IP}"; then break; fi
  sleep 2
done

echo "==> Recuperation du token k3s depuis ${CONTROL_IP}..."
NODE_TOKEN=""
for i in {1..60}; do
  NODE_TOKEN=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   -i "${SSH_KEY}" vagrant@"${CONTROL_IP}" \
                   "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null || true)
  if [ -n "${NODE_TOKEN}" ]; then
    echo "==> Token recupere OK"
    break
  fi
  sleep 5
done

if [ -z "${NODE_TOKEN}" ]; then
  echo "ERREUR : impossible de recuperer le token k3s depuis ${CONTROL_IP}" >&2
  echo "Verifiez que k3s-control est bien demarre et joignable." >&2
  exit 1
fi

echo "==> Installation de k3s agent sur le worker..."
export K3S_URL="https://${CONTROL_IP}:6443"
export K3S_TOKEN="${NODE_TOKEN}"
export INSTALL_K3S_EXEC="agent --node-ip=${AGENT_IP} --node-name=${NODE_NAME}"
curl -sfL https://get.k3s.io | sh -

echo "==> Worker configure. Node pret dans quelques dizaines de secondes."