#!/bin/bash
set -e

### KONFIGURACJA ###
NODE_IP="192.168.0.22"          # IP serwera głównego
CLUSTER_NAME="platform-cluster"

echo "==> Instalacja RKE2 (server INIT)"

curl -sfL https://get.rke2.io | sudo sh -

mkdir -p /etc/rancher/rke2

cat <<EOF > /etc/rancher/rke2/config.yaml
node-ip: ${NODE_IP}
cluster-name: ${CLUSTER_NAME}
write-kubeconfig-mode: "0644"
tls-san:
  - ${NODE_IP}
EOF

echo "==> Włączanie i uruchamianie rke2-server"
systemctl enable rke2-server
systemctl start rke2-server

echo "==> Czekanie na start API..."
sleep 20

echo "==> Sprawdzenie statusu"
systemctl status rke2-server --no-pager

echo
echo "======================================"
echo "TOKEN DO DOŁĄCZANIA NODE'ÓW:"
echo
cat /var/lib/rancher/rke2/server/node-token
echo
echo "======================================"

echo "==> Eksport kubeconfig"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin

echo "==> Test klastra"
kubectl get nodes