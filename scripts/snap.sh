#!/usr/bin/env bash
# snap.sh — sauvegarde / restauration / listing de snapshots des VM du cluster.

# Usage :
#   make snap-save    NAME=mon-snap   avant : make halt
#   make snap-restore NAME=mon-snap   après : make up
#   make snap-list
#
# Principe : snapshots INTERNES qcow2, stockés dans le disque overlay
# de chaque VM. La VM doit être ARRÊTÉE pour un état disque cohérent.


set -euo pipefail

ACTION="${1:?usage: save|restore|list}"
shift || true
NAME="${NAME:-}"

MACHINES="k3s-control k3s-worker1 k3s-worker2"
QEMU_IMG="$(command -v qemu-img || echo /opt/homebrew/bin/qemu-img)"

# Exécute qemu-img avec un message clair si le disque est verrouillé par une VM active.

qemu_img() {
  if ! "$@" 2>/tmp/snap_qemu_err.$$;then
    if grep -q "Failed to get shared" /tmp/snap_qemu_err.$$;then
      echo "  → disque verrouillé : la VM est en marche. Faites 'make halt' puis réessayez."
    else
      cat /tmp/snap_qemu_err.$$
    fi
    rm -f /tmp/snap_qemu_err.$$
    return 1
  fi
  rm -f /tmp/snap_qemu_err.$$
}

failed=0

for m in $MACHINES; do
  id_file=".vagrant/machines/${m}/qemu/id"
  if [ ! -f "$id_file" ]; then
    echo "ATTENTION ${m} : machine non créée - ignorée"
    continue
  fi
  id="$(cat "$id_file")"
  disk=".vagrant/machines/${m}/qemu/${id}/linked-box.img"
  if [ ! -f "$disk" ]; then
    echo "ATTENTION ${m} : disque introuvable ${disk} - ignorée"
    continue
  fi

  case "$ACTION" in
    save)
      [ -n "$NAME" ] || { echo "ERREUR : make snap-save NAME=mon-snap" >&2; exit 1; }
      echo "==> ${m} : création du snapshot ${NAME}"
      if ! qemu_img "$QEMU_IMG" snapshot -c "$NAME" "$disk"; then
        failed=1
        continue
      fi
      ;;
    restore)
      [ -n "$NAME" ] || { echo "ERREUR : make snap-restore NAME=mon-snap" >&2; exit 1; }
      echo "==> ${m} : restauration du snapshot ${NAME}"
      if ! qemu_img "$QEMU_IMG" snapshot -a "$NAME" "$disk";then
        failed=1
        continue
      fi
      ;;
    list)
      echo "==> ${m} : snapshots"
      if ! qemu_img "$QEMU_IMG" snapshot -l "$disk";then
        failed=1
      fi
      ;;
    *)
      echo "Usage: $0 save|restore|list"
      exit 1
      ;;
  esac
done

exit "$failed"