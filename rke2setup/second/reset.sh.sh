#!/bin/bash
set -e

echo "⚠️  HARD RESET RKE2 - WSZYSTKIE DANE ZOSTANĄ USUNIĘTE"
read -p "Czy na pewno chcesz kontynuować? (yes/NO): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Anulowano."
  exit 1
fi

echo "➡️ Zatrzymywanie rke2-server..."
systemctl stop rke2-server || true

echo "➡️ Zabijanie containerd / shim..."
pkill -9 rke2 || true
pkill -9 containerd || true
pkill -9 containerd-shim || true

sleep 2

echo "➡️ Odmontowywanie zasobów containerd (lazy umount)..."
mount | grep -E '/run/k3s|containerd' | awk '{print $3}' | sort -r | while read m; do
  umount -lf "$m" 2>/dev/null || true
done

echo "➡️ Usuwanie danych..."
rm -rf /var/lib/rancher/rke2
rm -rf /etc/rancher/rke2
rm -rf /run/k3s
rm -rf /run/containerd

echo "➡️ Start rke2-server..."
# systemctl start rke2-server

echo "✅ Reset zakończony"
echo "➡️ Sprawdź: systemctl status rke2-server"