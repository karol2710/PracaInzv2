#!/bin/bash
set -e

### KONFIGURACJA ###
SERVER_IP="192.168.0.22"
TOKEN="/etc/rancher/rke2/node-token"

### DANE WĘZŁA ###
echo "=== Konfiguracja węzła RKE2 ==="

read -r -p "Podaj Node IP (np. 192.168.0.59): " NODE_IP
read -r -p "Podaj Node Name (np. WorkA): " NODE_NAME

# Walidacja
if [[ -z "$NODE_IP" || -z "$NODE_NAME" ]]; then
    echo "Błąd: Node IP i Node Name są wymagane."
    exit 1
fi

if [[ ! "$NODE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Błąd: nieprawidłowy format IPv4."
    exit 1
fi

if [[ ! "$NODE_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    echo "Błąd: nieprawidłowy Node Name."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Uruchom skrypt jako root: sudo $0"
    exit 1
fi

if [[ ! -f "$TOKEN" ]]; then
    echo "Błąd: nie znaleziono tokena: $TOKEN"
    echo "Sprawdź, czy token został skopiowany z serwera głównego."
    exit 1
fi

echo
echo "Konfiguracja:"
echo "  Node IP:   $NODE_IP"
echo "  Node Name: $NODE_NAME"
echo "  Server IP: $SERVER_IP"
echo

read -r -p "Czy kontynuować? [t/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[tT]$ ]]; then
    echo "Anulowano."
    exit 0
fi

echo "==> Instalacja RKE2 (agent node)"

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent sh -

mkdir -p /etc/rancher/rke2

cat > /etc/rancher/rke2/config.yaml <<EOF
node-ip: ${NODE_IP}
node-name: ${NODE_NAME}
server: https://${SERVER_IP}:9345
token: $(cat "$TOKEN")
write-kubeconfig-mode: "0644"
tls-san:
  - ${SERVER_IP}
  - ${NODE_IP}
EOF

echo "==> Włączanie i uruchamianie rke2-agent"
systemctl enable rke2-agent
systemctl start rke2-agent

echo "==> Status usługi RKE2"
systemctl status rke2-agent --no-pager