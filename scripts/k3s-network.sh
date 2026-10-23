#!/usr/bin/env bash
# A executer dans une VM : sudo bash k3s-network.sh IP_PRIVEE SERVICE_K3S
# Choisir le reseau prive pour VXLAN, jamais le NAT QEMU commun aux 3 VM.
set -euo pipefail

NODE_IP="${1:?IP privee manquante}"
SERVICE="${2:?Service k3s ou k3s-agent manquant}"
[ "$(id -u)" -eq 0 ] || { echo "Execution root requise." >&2; exit 1; }
case "$SERVICE" in k3s|k3s-agent) ;; *) echo "Service invalide." >&2; exit 1 ;; esac

PRIVATE_IFACE="$(ip -o -4 addr show | awk -v ip="$NODE_IP" 'split($4, a, "/") && a[1] == ip {print $2; exit}')"
PRIVATE_IFACE="${PRIVATE_IFACE%%@*}"
[ -n "$PRIVATE_IFACE" ] || { echo "IP privee $NODE_IP absente : verifiez cloud-init/socket_vmnet." >&2; exit 1; }

mkdir -p /etc/rancher/k3s/config.yaml.d
CONFIG=/etc/rancher/k3s/config.yaml.d/20-kublab-network.yaml
CONTENT="flannel-iface: ${PRIVATE_IFACE}"
if [ -f "$CONFIG" ] && [ "$(cat "$CONFIG")" = "$CONTENT" ]; then
  echo "==> Flannel deja configure sur $PRIVATE_IFACE pour $NODE_IP"
else
  if [ -e "$CONFIG" ]; then cp -p "$CONFIG" "${CONFIG}.bak.$(date +%s)"; fi
  printf '%s\n' "$CONTENT" > "$CONFIG"
  chmod 600 "$CONFIG"
  echo "==> Flannel configure sur $PRIVATE_IFACE pour $NODE_IP ; redemarrage de $SERVICE"
  systemctl restart "$SERVICE"
fi
