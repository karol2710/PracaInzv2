#!/bin/bash
set -e

echo "➡️ Deleting manifests (setup + main)..."

kubectl delete --ignore-not-found=true \
  -f manifests/ \
  -f manifests/setup

echo "✅ Done"
