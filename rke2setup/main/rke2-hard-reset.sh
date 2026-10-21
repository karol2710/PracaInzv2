#!/bin/bash

set -e

echo "⚠️  HARD RESET RKE2 - WSZYSTKIE DANE ZOSTANĄ USUNIĘTE"
read -p "Czy na pewno chcesz kontynuować? (yes/NO): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Anulowano."
  exit 1
fi

echo "➡️ Zatrzymywanie rke2-server..."
systemctl stop rke2-server

echo "➡️ Usuwanie danych klastra..."
rm -rf /var/lib/rancher/rke2/server/db
rm -rf /var/lib/rancher/rke2/server/tls
rm -rf /etc/rancher/rke2

echo "➡️ Uruchamianie rke2-server..."
systemctl start rke2-server

echo "✅ Reset zakończony. Sprawdź status:"
echo "   systemctl status rke2-server"