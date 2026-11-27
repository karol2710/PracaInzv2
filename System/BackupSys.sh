#!/bin/bash
set -euo pipefail

# ==========================================
# Konfiguracja
# ==========================================

SEAWEEDFS_NAMESPACE="seaweedfs"
SEAWEEDFS_RELEASE="seaweedfs"
SEAWEEDFS_CHART_VERSION="4.54.0"

S3_ACCESS_KEY="velero"
S3_SECRET_KEY="${S3_SECRET_KEY:?Ustaw hasło S3}"
S3_BUCKET="velero"
S3_REGION="us-east-1"

STORAGE_CLASS="platform-storageclass"
PERSISTENCE_SIZE="10Gi"
MEMORY_REQ="512Mi"
MEMORY_LIMIT="1Gi"

VELERO_NAMESPACE="velero"
VELERO_VERSION="v1.19.0"
VELERO_AWS_PLUGIN_VERSION="v1.15.0"

S3_URL="http://seaweedfs-all-in-one.${SEAWEEDFS_NAMESPACE}.svc.cluster.local:8333"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

umask 077
WORK_DIR=$(mktemp -d)
CREDENTIALS_FILE="$WORK_DIR/credentials"

trap 'rm -rf "$WORK_DIR"' EXIT

# ==========================================
# 0. Weryfikacja środowiska
# ==========================================

echo "==> Sprawdzanie środowiska"

command -v kubectl >/dev/null
command -v helm >/dev/null
command -v curl >/dev/null

kubectl get storageclass "$STORAGE_CLASS"
kubectl get csidriver driver.longhorn.io

kubectl get crd \
  volumesnapshots.snapshot.storage.k8s.io \
  volumesnapshotclasses.snapshot.storage.k8s.io \
  volumesnapshotcontents.snapshot.storage.k8s.io

# ==========================================
# 1. Instalacja SeaweedFS
# ==========================================

echo "==> Tworzenie namespace SeaweedFS"

kubectl create namespace "$SEAWEEDFS_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Instalacja SeaweedFS przez Helm"

helm repo add seaweedfs \
  https://seaweedfs.github.io/seaweedfs/helm \
  --force-update

helm repo update seaweedfs

helm upgrade --install "$SEAWEEDFS_RELEASE" \
  seaweedfs/seaweedfs \
  --version "$SEAWEEDFS_CHART_VERSION" \
  --namespace "$SEAWEEDFS_NAMESPACE" \
  --set allInOne.enabled=true \
  --set allInOne.replicas=1 \
  --set master.enabled=false \
  --set volume.enabled=false \
  --set filer.enabled=false \
  --set s3.enabled=false \
  --set allInOne.data.type=persistentVolumeClaim \
  --set-string allInOne.data.size="$PERSISTENCE_SIZE" \
  --set-string allInOne.data.storageClass="$STORAGE_CLASS" \
  --set allInOne.s3.enabled=true \
  --set allInOne.s3.enableAuth=true \
  --set-string s3.credentials.admin.accessKey="$S3_ACCESS_KEY" \
  --set-string s3.credentials.admin.secretKey="$S3_SECRET_KEY" \
  --set "allInOne.s3.createBuckets[0].name=$S3_BUCKET" \
  --set "allInOne.s3.createBuckets[0].anonymousRead=false" \
  --set allInOne.service.type=ClusterIP \
  --set allInOne.updateStrategy.type=Recreate \
  --set allInOne.resources.requests.memory="$MEMORY_REQ" \
  --set allInOne.resources.limits.memory="$MEMORY_LIMIT" \
  --wait \
  --wait-for-jobs \
  --timeout=10m

echo "==> Weryfikacja SeaweedFS"

kubectl get pods,pvc,svc -n "$SEAWEEDFS_NAMESPACE"

# ==========================================
# 2. Konfiguracja Longhorn CSI
# ==========================================

echo "==> Tworzenie VolumeSnapshotClass"

kubectl apply -f "$SCRIPT_DIR/velero-snapshotclass.yaml"

kubectl get volumesnapshotclass longhorn-velero

# ==========================================
# 3. Poświadczenia Velero
# ==========================================

echo "==> Przygotowanie poświadczeń Velero"

cat > "$CREDENTIALS_FILE" <<EOF
[default]
aws_access_key_id=$S3_ACCESS_KEY
aws_secret_access_key=$S3_SECRET_KEY
EOF

kubectl create namespace "$VELERO_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

# ==========================================
# 4. Instalacja Velero CLI
# ==========================================

echo "==> Instalacja Velero CLI"

case "$(uname -m)" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Nieobsługiwana architektura"
    exit 1
    ;;
esac

VELERO_ARCHIVE="velero-${VELERO_VERSION}-linux-${ARCH}"

curl -fsSL \
  "https://github.com/velero-io/velero/releases/download/${VELERO_VERSION}/${VELERO_ARCHIVE}.tar.gz" \
  -o "$WORK_DIR/velero.tar.gz"

tar -xzf "$WORK_DIR/velero.tar.gz" -C "$WORK_DIR"

install -m 0755 \
  "$WORK_DIR/$VELERO_ARCHIVE/velero" \
  /usr/local/bin/velero

velero version --client-only


# ==========================================
# 5. Instalacja Velero
# ==========================================

echo "==> Instalacja CRD Velero"

velero install \
  --crds-only \
  --dry-run -o yaml | kubectl apply -f -

echo "==> Oczekiwanie na rejestrację CRD Velero"

kubectl wait \
  --for=condition=Established \
  crd -l component=velero \
  --timeout=120s

kubectl wait \
  --for=condition=Established \
  crd/backupstoragelocations.velero.io \
  --timeout=120s

echo "==> Instalacja Velero"

velero install \
  --namespace "$VELERO_NAMESPACE" \
  --image "velero/velero:${VELERO_VERSION}" \
  --provider aws \
  --plugins "velero/velero-plugin-for-aws:${VELERO_AWS_PLUGIN_VERSION}" \
  --bucket "$S3_BUCKET" \
  --secret-file "$CREDENTIALS_FILE" \
  --backup-location-config "region=$S3_REGION,s3ForcePathStyle=true,s3Url=$S3_URL,checksumAlgorithm=" \
  --features=EnableCSI \
  --use-node-agent \
  --node-agent-disable-host-path \
  --use-volume-snapshots=false \
  --dry-run -o yaml | kubectl apply -f -


# ==========================================
# 6. Weryfikacja instalacji
# ==========================================

echo "==> Sprawdzanie Velero"

kubectl rollout status deployment/velero \
  -n "$VELERO_NAMESPACE" \
  --timeout=300s

echo "==> Sprawdzanie Node Agent"

kubectl rollout status daemonset/node-agent \
  -n "$VELERO_NAMESPACE" \
  --timeout=300s

echo "==> Sprawdzanie BackupStorageLocation"

kubectl wait \
  --for=jsonpath='{.status.phase}'=Available \
  backupstoragelocation/default \
  -n "$VELERO_NAMESPACE" \
  --timeout=300s

echo "==> Status SeaweedFS"

kubectl get pods,pvc,svc -n "$SEAWEEDFS_NAMESPACE"

echo "==> Status Velero"

kubectl get pods -n "$VELERO_NAMESPACE"

echo "==> Status VolumeSnapshotClass"

kubectl get volumesnapshotclass

echo "==> Status BackupStorageLocation"

velero backup-location get

echo "==> Status harmonogramów"

velero schedule get

echo "==> Instalacja zakończona pomyślnie!"