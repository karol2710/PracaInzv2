#!/bin/bash
set -e

TOKEN_FILE="/var/lib/rancher/rke2/server/node-token"
PORT=9999

if [ ! -f "$TOKEN_FILE" ]; then
  echo "❌ Nie znaleziono tokenu: $TOKEN_FILE"
  exit 1
fi

echo "==> Wysyłanie tokenu RKE2 na porcie $PORT"
echo "==> Oczekiwanie na połączenie z drugiego serwera..."

nc -l -p $PORT < "$TOKEN_FILE"

echo "==> Token wysłany"