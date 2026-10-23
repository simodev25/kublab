#!/usr/bin/env bash
# Prerequis Longhorn V1 pour les VM Ubuntu ; execution en root dans chaque VM.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Executez ce script en root dans une VM Ubuntu." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y open-iscsi nfs-common cryptsetup dmsetup curl util-linux

# Certains noyaux Ubuntu placent iscsi_tcp dans linux-modules-extra.
if ! modprobe -n iscsi_tcp >/dev/null 2>&1; then
  apt-get install -y "linux-modules-extra-$(uname -r)"
fi
modprobe iscsi_tcp
modprobe nfs
printf 'iscsi_tcp\nnfs\n' > /etc/modules-load.d/kublab-longhorn.conf
systemctl enable --now iscsid
systemctl is-active --quiet iscsid

# Ne pas generer un nouvel initiateur iSCSI a chaque execution.
test -s /etc/iscsi/initiatorname.iscsi
mkdir -p /var/lib/longhorn
case "$(findmnt -n -o FSTYPE -T /var/lib/longhorn)" in
  ext4|xfs) ;;
  *) echo "Longhorn V1 requiert un filesystem ext4 ou XFS." >&2; exit 1 ;;
esac

echo "==> Prerequis Longhorn prets sur $(hostname)"
iscsiadm --version
df -h /var/lib/longhorn
