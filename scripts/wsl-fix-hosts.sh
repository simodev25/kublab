#!/usr/bin/env bash
# A executer DANS WSL : resout le nom mDNS du Mac via Windows (qui, lui, fait
# du mDNS) et met a jour /etc/hosts de WSL. A relancer si l'IP du Mac change.
#
# Usage :
#   bash wsl-fix-hosts.sh [nom-du-Mac]
#   (defaut : MacBook-Pro.local)
set -euo pipefail

HOST="${1:-MacBook-Pro.local}"
command -v powershell.exe >/dev/null || { echo "powershell.exe introuvable : executez ce script dans WSL." >&2; exit 1; }

echo "==> Resolution de $HOST via Windows (mDNS)..."
IP="$(powershell.exe -NoProfile -Command "(Resolve-DnsName -Name '$HOST' -Type A -ErrorAction Stop).IPAddress" 2>/dev/null | tr -d '\r' | head -1 || true)"
if ! [[ "${IP:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERREUR : Windows n'a pas resolu $HOST." >&2
  echo "Verifiez depuis PowerShell : Resolve-DnsName $HOST" >&2
  exit 1
fi
echo "==> $HOST = $IP"

# Remplacer ou ajouter l'entree dans /etc/hosts.
sudo sed -i "/^[0-9.]*[[:space:]]${HOST//./\\.}\$/d" /etc/hosts
echo "$IP $HOST" | sudo tee -a /etc/hosts > /dev/null
echo "==> /etc/hosts mis a jour."

getent hosts "$HOST" && echo "==> Resolution OK dans WSL."
kubectl get nodes
