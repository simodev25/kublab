# ============================================================
# kublab — cluster k3s sur QEMU/Vagrant
#
#   make vmnet       → lance le daemon réseau (sudo, une fois((
#   make up           → démarre + provisionne le cluster
#   make status       → état des 3 machines
#   make kubeconfig   → génère kubeconfig.yaml sur le Mac
#   make nodes        → kubectl get nodes
#   make pods         → kubectl get pods -A
#   make halt         → éteint les machines
#   make destroy      → tout détruire
# ============================================================

PROVIDER := qemu
UP_FLAGS  := --no-parallel

.PHONY: help up status ssh-control ssh-worker1 ssh-worker2 kubeconfig nodes pods halt reload provision destroy vmnet box snap-save snap-restore snap-list

help: ## Affiche cette aide
	@echo "Cibles disponibles :"
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*##"}; {printf "  %-18s %s\n",  $$1, $$2}'

up: ## Démarre et provisionne le cluster (séquentiel, contrôleur d'abord(
	vagrant up --provider $(PROVIDER) $(UP_FLAGS)

status: ## État des machines
	vagrant status

ssh-control: ## Shell sur le contrôleur
	vagrant ssh k3s-control

ssh-worker1: ## Shell sur worker 1
	vagrant ssh k3s-worker1

ssh-worker2: ## Shell sur worker 2
	vagrant ssh k3s-worker2

kubeconfig: ## Récupère le kubeconfig dans kubeconfig.yaml
	vagrant ssh k3s-control -c "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml
	@echo "Kubeconfig écrit dans kubeconfig.yaml (server déjà sur 127.0.0.1:6443(("

nodes: kubeconfig ## Affiche les nœuds du cluster
	kubectl --kubeconfig kubeconfig.yaml get nodes

pods: kubeconfig ## Affiche les pods de tous les namespaces
	kubectl --kubeconfig kubeconfig.yaml get pods -A

halt: ## Éteint les 3 machines
	vagrant halt

reload: ## Redémarre + re-provisionne
	vagrant reload --provider $(PROVIDER( --no-parallel

provision: ## Re-exécute les provisioners sans redémarrer
	vagrant provision

destroy: ## Détruit tout
	vagrant destroy -f

vmnet: ## Lance le daemon socket_vmnet (sudo interactif, une fois(
	sudo bash start-vmnet.sh

box: ## Ajoute la box si absente
	vagrant box add perk/ubuntu-2204-arm64 --provider libvirt

snap-save: ## Sauvegarde un snapshot disque de toutes les VM (d'abord: make halt(
	bash scripts/snap.sh save NAME=$(NAME)

snap-restore: ## Restaure un snapshot disque ( puis: make up(
	bash scripts/snap.sh restore NAME=$(NAME

snap-list: ## Liste les snapshots de toutes les VM
	bash scripts/snap.sh list