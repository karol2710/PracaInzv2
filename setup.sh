#!/bin/bash
set -e

REPO1_URL="https://github.com/prometheus-operator/kube-prometheus.git"
REPO1_DIR="kube-prometheus"

REPO2_URL="https://github.com/karol2710/Praca-20Inzynierska.git"
REPO2_DIR="Praca-20Inzynierska"

clone_repo() {
  local url=$1
  local dir=$2

  if [ -d "$dir" ]; then
    echo "⚠️  Directory '$dir' already exists, skipping clone"
  else
    echo "➡️  Cloning $url into $dir..."
    git clone "$url" "$dir"
  fi
}

clone_repo "$REPO1_URL" "$REPO1_DIR"
clone_repo "$REPO2_URL" "$REPO2_DIR"

echo "✅ All repositories are ready"
