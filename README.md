# kublab — Cluster Kubernetes (k3s( sur QEMU via Vagrant

Cluster **k3s** de 3 nœuds exécutés dans des VM QEMU gérées par Vagrant (plugin [`vagrant-qemu`](https://github.com/ppggff/vagrant-qemu)( :

| Machine | Rôle | IP privée | vCPU | RAM |
|---------|------|-----------|-------|-----|
| `k3s-control` | Contrôleur | 192.168.105.11 | 4 | 4 Go |
| `k3s-worker1` | Worker | 192.168.105.12 | 4 | 4 Go |
| `k3s-worker2` | Worker | 192.168.105.13 | 4 | 4 Go |

Le réseau privé entre nœuds utilise le backend `:socket_vmnet` du plugin (VM↔VM **et** host↔VM, **sans sudo** au moment de lancer `vagrant up` — le daemon tient les privilèges root(.

## Prérequis

- Mac **Apple Silicon** (testé sur M4(, macOS ≥  ́12.4
- [Vagrant](https://www.vagrantup.com/downloads) ≥ 2.4.3
- Homebrew arm64▶ **important** : utilisez `/opt/homebrew/bin/brew`( pas celui de `/usr/local` (x86_64/Rosetta( qui ne peut plus compiler sur macOS récent(.

```bash
/opt/homebrew/bin/brew install qemu socket_vmnet
vagrant plugin install vagrant-qemu
```

La box `perk/ubuntu-2204-arm64` fait déjà **64 GiB** virtuel (696 MB réels — sparse( → **aucun besoin de `disk_resize`**. Sa metadata interne est étiquetée `libvirt` (incohérence côté Perk : l'API la propose aussi pour qemu(; le plugin `vagrant-qemu` sait importer ce format v1( (d'où la commande ci-dessous avec `--provider libvirt`(, puis le `Vagrantfile` pointe sur son `box.img` automatiquement( :

```bash
vagrant box add perk/ubuntu-2204-arm64 --provider libvirt
```

## 1. Lancer le daemon `socket_vmnet` (une fois, en root(

Le daemon doit tourner **avant** `vagrant up`. Il réserve une plage DHCP pour éviter de collisionner avec les IPs statiques du cluster (`.11`–`.13`( :

```bash
sudo /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet \
  --vmnet-gateway=192.168.105.1 \
  --vmnet-dhcp-end=192.168.105.100 \
  /opt/homebrew/var/run/socket_vmnet
```

> 💡 Pour qu'il tourne en permanence (au démarrage( : `sudo brew services start socket_vmnet`( — mais le service ne passe pas `--vmnet-dhcp-end`, vérifiez vos IPs si vous l'utilisez(.

> ⚠️ Le mot de passe sudo vous sera demandé — à lancer dans **votre** terminal( (je ne peux pas le faire à votre place(.

Le daemon lancé, vérification:
```bash
ls -l /opt/homebrew/var/run/socket_vmnet
```
Le socket doit exister.



## 2. Télécharger la box

```bash
vagrant box add perk/ubuntu-2204-arm64 --provider libvirt
```

> L'authentification SSH se fait **sans mot de passe** : la clé insecure de Vagrant est préinstallée dans la box pour le user `vagrant` (qui a `sudo` NOPASSWD(. **Ne configurez PAS `ssh.password`** dans votre Vagrantfile — cela forcerait la méthode mot de passe et l'auth échouerait( le `Vagrantfile` fourni est déjà correct(.

## 3. Démarrer le cluster

```bash
cd /Users/mbensass/projetPreso/kublab
vagrant up --provider qemu --no-parallel
```

> `--no-parallel` est important : les machines doivent être provisionnées **dans l'ordre** (contrôleur d'abord, puis workers(, afin que les workers puissent lire le token k3s du contrôleur.(

Quand le contrôleur est prêt, il affiche le token k3s. Les workers le récupèrent automatiquement via SSH, puis rejoignent le cluster — attendez ~1–2 min après le provisioning( (le statut `k3s-agent` et les pods mettent un moment à devenir prêts(.(

##  ́4. Utiliser le cluster

Récupérer le `kubeconfig` et l'utiliser (l'API k3s est forwardée sur `127.0.0.1:6443`( :

```bash
vagrant ssh k3s-control -c "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml
kubectl --kubeconfig kubeconfig.yaml get nodes
kubectl --kubeconfig kubeconfig.yaml get pods -A
```

(`kubectl` doit être installé sur le Mac, ou bien : `vagrant ssh k3s-control -c "sudo k3s kubectl get nodes"`((

##  Gestion

```bash
vagrant ssh k3s-control       # shell sur le contrôleur
vagrant ssh k3s-worker1      # shell sur worker 1
vagrant status                  # état des 3 machines
vagrant halt                    # éteindre (ACPI, puis NOOP period faire halt((
vagrant reload k3s-control --no-provision # redemarrer le controleur sans re-provisionner
vagrant destroy -f            # tout détruire
```

> ⚠️ Après un `sudo vagrant ...`( (utilisé si vous passez en backend vmnet natif(, les fichiers `.vagrant/` et les boxes deviennent root-owned — restaurez avec `sudo chown -R "$(id -un)":staff ~/.vagrant.d/boxes .vagrant`.

## Débogage

- Affichage du token manuellement :
  `vagrant ssh k3s-control -c "sudo cat /var/lib/rancher/k3s/server/node-token"`
- Statut du service k3s sur un nœud :
  `vagrant ssh k3s-control -c "sudo systemctl status k3s --no-pager"`
- Consulter la console série d'une VM :
  `nc -U ~/.vagrant.d/tmp/vagrant-qemu/<id>/qemu_socket_serial`( id dans `.vagrant/machines/<name>/qemu/id`(

## Commandes (Makefile(

Toutes les commandes du projet sont encapsulées dans un **Makefile** :

```bash
make help        # liste des cibles
make vmnet      # lance le daemon réseau (sudo, une fois —
make up          # démarre + provisionne le cluster (séquentiel(
make status      # état des 3 machines
make kubeconfig  # génère kubeconfig.yaml sur le Mac
make nodes       # kubectl get nodes
make pods        # kubectl get pods -A
make ssh-control # shell sur le contrôleur
make halt        # éteint les machines
make reload      # redemarre les 3 VM en sequence, sans re-provisionner
make destroy     # tout détruire
make snap-save    # sauvegarde un snapshot disque des 3 VM
make snap-restore # restaure un snapshot disque
make snap-list    # liste les snapshots des 3 VM
```

### 💾 Snapshots — sauvegarde et restauration

Snapshots **internes qcow2** stockés dans le disque de chaque VM, sans fichiers externes. La VM doit être **arrêtée** pour un snapshot cohérent :

```bash
make halt                        # éteindre le cluster
make snap-save NAME=avant-k3s  # sauvegarder un snapshot des 3 VM
make snap-list                   # lister les snapshots
make snap-restore NAME=avant-k3s # restaurer un snapshot disc/état
make up                         # redémarrer le cluster après restore
```

## Client kubectl depuis Windows / WSL

Sur le Mac, apres avoir prepare l'acces LAN et le certificat pour
`192.168.1.98`, executez `make kubeconfig`. Copiez `kubeconfig.yaml` et
`scripts/client-wsl.sh` dans le dossier Telechargements de Windows.

Dans WSL, remplacez `VOTRE_USER_WINDOWS` par votre utilisateur Windows :

```bash
bash "/mnt/c/Users/VOTRE_USER_WINDOWS/Downloads/client-wsl.sh" \
  --kubeconfig "/mnt/c/Users/VOTRE_USER_WINDOWS/Downloads/kubeconfig.yaml" \
  --ip 192.168.1.98 --install --persist
```

Le script verifie kubectl et l'installe s'il est absent, avec verification SHA256,
dans `~/.local/bin`, sans sudo. La version par defaut est `v1.36.5`, correspondant
au cluster ; `--version` permet de la changer. Si curl est absent, installez-le
avec `sudo apt-get update && sudo apt-get install -y curl ca-certificates`.

La configuration est stockee dans `~/.kube/kublab.yaml` avec permissions `600`.
`~/.kube/config` n'est pas modifie. Un ancien `kublab.yaml` est sauvegarde avant
remplacement. `--persist` selectionne ce cluster par defaut pour les futurs
terminaux Bash via `~/.bashrc`, sans dupliquer les lignes lors d'une reexecution.

Ouvrez un nouveau terminal Bash WSL, ou executez dans le terminal courant :

```bash
export PATH="$HOME/.local/bin:$PATH"
export KUBECONFIG="$HOME/.kube/kublab.yaml"
kubectl get nodes
kubectl get pods -A
```

Le script teste l'acces au cluster avec verification TLS et signale les erreurs
reseau ou de certificat. Le Mac doit rester allume avec les VM et socket_vmnet
actifs. Si son IP change, mettez a jour le certificat et relancez le script avec
la nouvelle valeur de `--ip`.

**Attention :** le kubeconfig donne un acces administrateur. Gardez-le prive et
n'utilisez que des fichiers provenant d'une source de confiance.

## Stockage distribue Longhorn

Configuration du lab : Longhorn **1.13.0**, compatible ARM64 et Kubernetes 1.36,
moteur **V1**, **3 repliques** par volume. Les 3 VM sont configurees avec
4 vCPU et 4 Go de RAM chacune. Le moteur V2 reste desactive car il necessite
notamment un noyau plus recent et des ressources supplementaires.

### Installation depuis le Mac

Le daemon reseau doit etre actif. La seule presence du fichier socket ne suffit
pas : si le daemon s'arrete, les VM peuvent rester accessibles en SSH via le NAT,
mais les workers deviennent `NotReady` faute de communication avec le controleur.

```bash
# Terminal 1 : sudo, laisser ce terminal ouvert
make vmnet
```

Apres un arret du daemon, reconnectez les VM en les redemarrant. Cette commande
applique aussi les nouvelles ressources du Vagrantfile, sans reinstaller k3s :

```bash
# Terminal 2 : depuis le projet sur le Mac
make reload
make kubeconfig
make nodes

# Attendre que les 3 noeuds soient Ready, puis :
make longhorn-install
make longhorn-status
make longhorn-test
```

`longhorn-install` prepare les 3 VM avec `open-iscsi`, `nfs-common`, `cryptsetup`
et `dmsetup`, charge les modules iSCSI/NFS de facon persistante, active `iscsid`,
puis installe le chart officiel avec Helm et attend la disponibilite des composants.
Le script refuse de commencer si l'un des 3 noeuds n'est pas `Ready`.

La preparation fixe aussi l'interface Flannel sur le reseau prive des VM
(fichier `/etc/rancher/k3s/config.yaml.d/20-kublab-network.yaml`). Un redemarrage
du service k3s est effectue uniquement si cette configuration change. Le NAT QEMU
attribue la meme IP `10.0.2.15` a chaque VM : il ne peut pas transporter le trafic
VXLAN entre noeuds. Un noeud `Ready` ne garantit donc pas que les pods communiquent.

Les donnees sont stockees dans `/var/lib/longhorn`, sur le disque systeme ext4
de chaque VM. Aucun disque n'est formate. Au moins 25 % d'espace libre sont
conserves et le surprovisionnement est limite a 100 %. Les disques qcow2 sont
sparse, mais les donnees et snapshots consomment bien de l'espace sur le Mac.
Surveillez aussi l'espace libre du Mac.

La StorageClass `local-path` reste la classe par defaut pour ne pas changer les
applications existantes. Pour utiliser Longhorn, precisez dans votre PVC :

```yaml
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### Interface web sur le Mac ou dans WSL

```bash
make longhorn-ui
# Ouvrir http://127.0.0.1:8080 ; Ctrl+C pour arreter
```

Depuis WSL deja configure pour le cluster :

```bash
kubectl -n longhorn-system port-forward --address 127.0.0.1 \
  service/longhorn-frontend 8080:80
```

Ouvrez http://localhost:8080 dans le navigateur Windows. L'interface n'a pas
d'authentification integree : elle n'est donc pas exposee en NodePort ou Ingress.

### Test du stockage

`make longhorn-test` cree un PVC de 1 Gi et un Job qui ecrit puis relit un fichier.
Le test conserve volontairement son PVC dans le namespace `longhorn-test`.
Pour verifier la persistance apres recreation du Job :

```bash
kubectl --kubeconfig kubeconfig.yaml -n longhorn-test delete job longhorn-smoke
make longhorn-test
```

Nettoyage explicite du test uniquement, supprimant aussi ses donnees :

```bash
kubectl --kubeconfig kubeconfig.yaml delete namespace longhorn-test
```

Les 3 VM tournant sur le meme Mac, cette replication ne protege pas d'une panne
ou perte du Mac. Les snapshots qcow2 ne remplacent pas les sauvegardes Longhorn
vers un stockage externe. Ne restaurez pas un seul disque de VM independamment
des autres alors que Longhorn est actif. Cette configuration est destinee au lab,
pas a la production.

Fichiers : `deploy/longhorn/values.yaml`, `deploy/longhorn/test-volume.yaml`,
`scripts/longhorn.sh` et `scripts/longhorn-node.sh`.

Documentation officielle : https://longhorn.io/docs/1.13.0/deploy/install/

## Fichiers

- `Vagrantfile` — définition des 3 VM (réseau, ressources, provisioning(
- `scripts/control.sh` — installe le serveur k3s sur le contrôleur
- `scripts/client-wsl.sh` — installation et configuration du client kubectl dans WSL
- `scripts/worker.sh` — installe l'agent k3s sur chaque worker (récupère le token via SSH(
