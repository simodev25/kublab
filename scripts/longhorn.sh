#!/usr/bin/env bash
# Installation reproductible de Longhorn sur le cluster kublab.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIG="${KUBECONFIG_FILE:-$ROOT/kubeconfig.yaml}"
VERSION="${LONGHORN_VERSION:-1.13.0}"
ACTION="${1:-help}"

kube() { kubectl --kubeconfig "$CONFIG" --request-timeout=30s "$@"; }
ready() {
  # Refuser une installation partielle sur le seul controleur.
  kube wait --for=condition=Ready --timeout=60s \
    node/k3s-control node/k3s-worker1 node/k3s-worker2 || {
    echo "ERREUR : les 3 noeuds doivent etre Ready. Verifiez socket_vmnet et le reseau prive." >&2
    exit 1
  }
  for node in k3s-control k3s-worker1 k3s-worker2; do
    cpu="$(kube get node "$node" -o 'jsonpath={.status.capacity.cpu}')"
    memory="$(kube get node "$node" -o 'jsonpath={.status.capacity.memory}')"
    if ! [[ "$cpu" =~ ^[0-9]+$ && "$memory" =~ ^[0-9]+Ki$ ]]; then
      echo "ERREUR : capacite CPU/RAM inattendue pour $node : $cpu / $memory" >&2
      exit 1
    fi
    # Une VM de 4 Gi declare un peu moins de 4 Gi apres reservation du noyau.
    if [ "$cpu" -lt 4 ] || [ "${memory%Ki}" -lt 3500000 ]; then
      echo "ERREUR : $node a $cpu CPU et $memory de RAM. Appliquez les 4 CPU / 4 Go avec make reload." >&2
      exit 1
    fi
    node_ip="$(kube get node "$node" -o 'jsonpath={.status.addresses[?(@.type=="InternalIP")].address}')"
    flannel_ip="$(kube get node "$node" -o 'jsonpath={.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip}')"
    if [ "$flannel_ip" != "$node_ip" ]; then
      echo "ERREUR : Flannel sur $node annonce $flannel_ip au lieu de $node_ip. Lancez make longhorn-prepare." >&2
      exit 1
    fi
  done
}

case "$ACTION" in
  help|--help|-h)
    echo "Usage : bash scripts/longhorn.sh prepare|install|status|ui|test"
    echo "Variables : KUBECONFIG_FILE, LONGHORN_VERSION (defaut 1.13.0)."
    exit 0
    ;;
  prepare|install|status|ui|test) ;;
  *) echo "Action inconnue : $ACTION" >&2; exit 1 ;;
esac

command -v kubectl >/dev/null || { echo "kubectl absent" >&2; exit 1; }
[ -s "$CONFIG" ] || { echo "Kubeconfig absent : lancez make kubeconfig." >&2; exit 1; }

case "$ACTION" in
  prepare)
    command -v vagrant >/dev/null || { echo "Executez prepare sur le Mac avec Vagrant." >&2; exit 1; }
    # Ready ne garantit pas la communication entre pods : corriger VXLAN avant Helm.
    for node in k3s-control k3s-worker1 k3s-worker2; do
      case "$node" in
        k3s-control) node_ip=192.168.105.11; service=k3s ;;
        k3s-worker1) node_ip=192.168.105.12; service=k3s-agent ;;
        k3s-worker2) node_ip=192.168.105.13; service=k3s-agent ;;
      esac
      vagrant ssh "$node" -c "sudo bash -s -- '$node_ip' '$service'" < scripts/k3s-network.sh
    done
    ready
    for node in k3s-control k3s-worker1 k3s-worker2; do
      echo "==> Preparation de $node"
      vagrant ssh "$node" -c 'sudo bash -s' < scripts/longhorn-node.sh
    done
    ;;
  install)
    command -v helm >/dev/null || { echo "helm absent" >&2; exit 1; }
    ready
    helm repo add longhorn https://charts.longhorn.io
    helm repo update longhorn
    helm upgrade --install longhorn longhorn/longhorn \
      --kubeconfig "$CONFIG" --namespace longhorn-system --create-namespace \
      --version "$VERSION" --values deploy/longhorn/values.yaml \
      --wait --timeout 15m
    kube -n longhorn-system rollout status daemonset/longhorn-manager --timeout=300s
    # Le driver-deployer cree les composants CSI apres le deploiement Helm.
    kube -n longhorn-system wait --for=create daemonset/longhorn-csi-plugin --timeout=300s
    kube -n longhorn-system rollout status daemonset/longhorn-csi-plugin --timeout=300s
    for component in csi-attacher csi-provisioner csi-resizer csi-snapshotter; do
      kube -n longhorn-system wait --for=create "deployment/$component" --timeout=300s
      kube -n longhorn-system rollout status "deployment/$component" --timeout=300s
    done
    kube wait --for=create storageclass/longhorn --timeout=300s
    kube get storageclass longhorn
    ;;
  status)
    kube -n longhorn-system get pods -o wide
    kube -n longhorn-system get nodes.longhorn.io
    kube get storageclasses
    ;;
  ui)
    echo "Interface locale : http://127.0.0.1:8080 ; Ctrl+C pour arreter."
    # Fonctionne aussi depuis WSL avec KUBECONFIG_FILE=~/.kube/kublab.yaml.
    kubectl --kubeconfig "$CONFIG" -n longhorn-system \
      port-forward --address 127.0.0.1 service/longhorn-frontend 8080:80
    ;;
  test)
    ready
    kube apply -f deploy/longhorn/test-volume.yaml
    kube -n longhorn-test wait --for=condition=complete job/longhorn-smoke --timeout=300s
    kube -n longhorn-test logs job/longhorn-smoke
    kube -n longhorn-test get pvc
    echo "Le PVC de test de 1 Gi est conserve. Nettoyage explicite :"
    echo "kubectl --kubeconfig '$CONFIG' delete namespace longhorn-test"
    ;;
esac
