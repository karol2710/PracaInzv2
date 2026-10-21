#!/bin/bash
set -e

SERVER_IP="192.168.0.22"   # IP SERWERA GŁÓWNEGO
PORT=9999
DEST="/etc/rancher/rke2/node-token"

mkdir -p /etc/rancher/rke2

echo "==> Pobieranie tokenu z $SERVER_IP:$PORT"

nc $SERVER_IP $PORT > $DEST

chmod 600 $DEST

echo "==> Token zapisany w $DEST"
echo
echo "TOKEN:"
cat $DEST


# if token is note received instantly, then do ctl+c on receiving side nad it will be send.