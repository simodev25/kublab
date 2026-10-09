#!/usr/bin/env bash
# Configure kubectl dans WSL pour acceder au cluster heberge sur le Mac.
set -euo pipefail
umask 077

SOURCE="./kubeconfig.yaml"
MAC_IP="192.168.1.98"
VERSION="v1.36.5"
INSTALL=false
PERSIST=false
WORK_DIR=""

usage() {
  cat <<'EOF'
Usage : bash client-wsl.sh [options]

  --kubeconfig FICHIER  Kubeconfig copie depuis le Mac, defaut ./kubeconfig.yaml
  --ip ADRESSE         IP ou nom DNS du Mac, defaut 192.168.1.98
  --install            Installer kubectl s'il est absent, dans ~/.local/bin
  --version VERSION    Version a installer, defaut v1.36.5
  --persist            Configurer PATH et KUBECONFIG dans ~/.bashrc
  --help               Afficher cette aide

Exemple dans WSL :
  bash client-wsl.sh --kubeconfig /mnt/c/Users/USER/Downloads/kubeconfig.yaml --install --persist

Le script conserve ~/.kube/config, sauvegarde un ancien kublab.yaml,
verifie le checksum de kubectl et teste l'acces HTTPS au cluster.
N'utilisez qu'un kubeconfig provenant d'une source de confiance.
EOF
}

die() { echo "ERREUR : $*" >&2; exit 1; }
cleanup() {
  if [ -n "$WORK_DIR" ]; then rm -rf -- "$WORK_DIR"; fi
}
trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kubeconfig|--ip|--version)
      [ "$#" -ge 2 ] || die "Valeur manquante pour $1"
      case "$1" in
        --kubeconfig) SOURCE="$2" ;;
        --ip) MAC_IP="$2" ;;
        --version) VERSION="$2" ;;
      esac
      shift 2
      ;;
    --install) INSTALL=true; shift ;;
    --persist) PERSIST=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Option inconnue : $1. Utilisez --help." ;;
  esac
done

[ "$(uname -s)" = Linux ] || die "Executez ce script dans WSL, pas sur le Mac."
[ -s "$SOURCE" ] || die "Kubeconfig absent ou vide : $SOURCE. Generez-le avec make kubeconfig sur le Mac puis copiez-le sous Windows."
[[ "$MAC_IP" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || die "Adresse invalide : indiquez une IP IPv4 ou un nom DNS, sans https:// ni port."
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version invalide, exemple : v1.36.5"

export PATH="$HOME/.local/bin:$PATH"
if ! command -v kubectl >/dev/null 2>&1; then
  if ! "$INSTALL"; then
    if [ -t 0 ]; then
      read -r -p "kubectl est absent. L'installer dans ~/.local/bin ? [o/N] " answer
      case "$answer" in o|O|oui|y|Y|yes) INSTALL=true ;; esac
    fi
    "$INSTALL" || die "kubectl absent. Relancez avec --install."
  fi
  command -v curl >/dev/null 2>&1 || die "Installez curl et les certificats : sudo apt-get update && sudo apt-get install -y curl ca-certificates"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum absent : installez coreutils."
  case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "Architecture non prise en charge : $(uname -m)" ;;
  esac
  WORK_DIR="$(mktemp -d)"
  URL="https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl"
  echo "==> Installation de kubectl ${VERSION} pour Linux ${ARCH}"
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 "$URL" -o "$WORK_DIR/kubectl"
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 60 "${URL}.sha256" -o "$WORK_DIR/kubectl.sha256"
  HASH="$(tr -d '\r\n' < "$WORK_DIR/kubectl.sha256")"
  [[ "$HASH" =~ ^[a-fA-F0-9]{64}$ ]] || die "Checksum telecharge invalide."
  printf '%s  %s\n' "$HASH" "$WORK_DIR/kubectl" | sha256sum --check -
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$WORK_DIR/kubectl" "$HOME/.local/bin/kubectl"
fi
kubectl version --client

[ -n "$WORK_DIR" ] || WORK_DIR="$(mktemp -d)"
DEST="$HOME/.kube/kublab.yaml"
echo "==> Preparation de $DEST pour https://${MAC_IP}:6443"
# Flatten rend le fichier autonome, meme si la source reference des certificats.
kubectl --kubeconfig "$SOURCE" config view --raw --flatten > "$WORK_DIR/kublab.yaml"
CLUSTER="$(kubectl --kubeconfig "$WORK_DIR/kublab.yaml" config view --minify -o 'jsonpath={.contexts[0].context.cluster}')"
[ -n "$CLUSTER" ] || die "Aucun cluster dans le contexte courant du kubeconfig."
kubectl --kubeconfig "$WORK_DIR/kublab.yaml" config set-cluster "$CLUSTER" --server="https://${MAC_IP}:6443"
# La verification TLS reste active ; aucun insecure-skip-tls-verify n'est ajoute.
mkdir -p "$HOME/.kube"
if [ -e "$DEST" ]; then
  BACKUP="${DEST}.bak.$(date +%Y%m%d-%H%M%S).$$"
  cp -- "$DEST" "$BACKUP"
  chmod 600 "$BACKUP"
  echo "==> Ancienne configuration sauvegardee : $BACKUP"
fi
install -m 0600 "$WORK_DIR/kublab.yaml" "$DEST"
export KUBECONFIG="$DEST"

if "$PERSIST"; then
  touch "$HOME/.bashrc"
  for line in 'export PATH="$HOME/.local/bin:$PATH"' 'export KUBECONFIG="$HOME/.kube/kublab.yaml"'; do
    if ! grep -Fqx -- "$line" "$HOME/.bashrc"; then
      printf '\n%s\n' "$line" >> "$HOME/.bashrc"
    fi
  done
  echo "==> Configuration persistante ajoutee a ~/.bashrc."
fi

echo "==> Verification de l'acces au cluster"
if ! kubectl --kubeconfig "$DEST" --request-timeout=15s get nodes -o wide; then
  cat >&2 <<EOF
La configuration est prete, mais la connexion a echoue.
Verifiez sur le Mac : VM actives, socket_vmnet actif, port 6443 ouvert,
pare-feu et certificat contenant ${MAC_IP}. Le Wi-Fi ne doit pas isoler les clients.
Si l'erreur indique x509, corrigez le certificat ; ne desactivez pas TLS.
EOF
  exit 1
fi
printf '\nConfiguration terminee. Dans votre terminal WSL, executez :\n'
printf '  export PATH="$HOME/.local/bin:$PATH"\n'
printf '  export KUBECONFIG="$HOME/.kube/kublab.yaml"\n'
printf '  kubectl get nodes\n  kubectl get pods -A\n'
if "$PERSIST"; then
  echo "Ou ouvrez un nouveau terminal Bash WSL pour charger ~/.bashrc."
fi
