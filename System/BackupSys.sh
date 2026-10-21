#!/bin/bash
set -e

# ==========================================
# Konfiguracja
# ==========================================
MINIO_NAMESPACE="minio"
MINIO_RELEASE="minio"
MINIO_MODE="standalone"
MINIO_REPLICAS="1"
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="supersecretpassword"
MINIO_BUCKET="velero"
STORAGE_CLASS="platform-storageclass"   # Twój StorageClass Longhorn
VELERO_NAMESPACE="velero"
VELERO_BUCKET="$MINIO_BUCKET"
VELERO_REGION="minio"
PERSISTENCE_SIZE="1Gi"
MEMORY_REQ="512Mi"
MEMORY_LIMIT="1Gi"

# ==========================================
# 1️⃣ Instalacja MinIO
# ==========================================
echo "==> Tworzenie namespace MinIO"
kubectl create ns $MINIO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "==> Instalacja MinIO przez Helm"
helm repo add minio https://charts.min.io/
helm repo update

helm upgrade --install $MINIO_RELEASE minio/minio \
  -n $MINIO_NAMESPACE \
  --set mode=$MINIO_MODE \
  --set replicas=$MINIO_REPLICAS \
  --set rootUser=$MINIO_ROOT_USER \
  --set rootPassword=$MINIO_ROOT_PASSWORD \
  --set persistence.size=$PERSISTENCE_SIZE \
  --set persistence.storageClass=$STORAGE_CLASS \
  --set resources.requests.memory=$MEMORY_REQ \
  --set resources.limits.memory=$MEMORY_LIMIT \
  --wait=false


# Poczekaj aż MinIO pod będzie Running
echo "==> Czekanie na MinIO pod..."
kubectl wait --for=condition=ready pod -l app=minio -n $MINIO_NAMESPACE --timeout=300s

# ==========================================
# 2️⃣ Tworzenie bucketu
# ==========================================
echo "==> Tworzenie bucketu $MINIO_BUCKET w MinIO"
kubectl -n $MINIO_NAMESPACE exec svc/minio -- mc alias set local http://127.0.0.1:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
kubectl -n $MINIO_NAMESPACE exec svc/minio -- mc mb local/$MINIO_BUCKET || echo "Bucket już istnieje"

# ==========================================
# 3️⃣ Tworzenie secretu Velero
# ==========================================
echo "==> Tworzenie secretu z poświadczeniami Velero"
cat <<EOF > velero-credentials.txt
[default]
aws_access_key_id=$MINIO_ROOT_USER
aws_secret_access_key=$MINIO_ROOT_PASSWORD
EOF

kubectl create ns $VELERO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cloud-credentials \
  --namespace $VELERO_NAMESPACE \
  --from-file=credentials=velero-credentials.txt \
  --dry-run=client -o yaml | kubectl apply -f -

# ==========================================
# 4️⃣ Instalacja Velero
# ==========================================

echo "==> Instalacja Velero CLI"
if ! command -v velero >/dev/null 2>&1; then
  echo "==> Instalacja Velero CLI"
  VELERO_VERSION="v1.17.0"

  curl -L https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz \
    | tar -xz

  sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/velero
  sudo chmod +x /usr/local/bin/velero
fi

echo "==> Instalacja Velero z pluginem CSI"
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.6.0 \
  --bucket $VELERO_BUCKET \
  --secret-file ./velero-credentials.txt \
  --backup-location-config region=$VELERO_REGION,s3ForcePathStyle=true,s3Url=http://minio.$MINIO_NAMESPACE.svc.cluster.local:9000 \
  --snapshot-location-config region=$VELERO_REGION \
  --use-volume-snapshots=true \
  --namespace $VELERO_NAMESPACE \
  --pod-annotations "backup.velero.io/credentials=true"

echo "==> Checking if cloud-credentials volume already exists..."

# Check if the volume already exists
if kubectl get deployment velero -n $VELERO_NAMESPACE -o yaml | grep -q "cloud-credentials"; then
  echo "==> Cloud-credentials volume already exists, skipping patch"
else
  echo "==> Patching deployment Velero to add credentials volume"

  kubectl patch deployment velero -n $VELERO_NAMESPACE --type='json' -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/volumes/-",
      "value": {
        "name": "cloud-credentials",
        "secret": {
          "secretName": "cloud-credentials"
        }
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/volumeMounts/-",
      "value": {
        "mountPath": "/credentials",
        "name": "cloud-credentials",
        "readOnly": true
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/env/-",
      "value": {
        "name": "AWS_SHARED_CREDENTIALS_FILE",
        "value": "/credentials/credentials"
      }
    }
  ]'
fi

# ==========================================
# 5️⃣ Check instalacji
# ==========================================
echo "==> Sprawdzanie stanu instalacji..."

# MinIO pod
kubectl get pods -n $MINIO_NAMESPACE -l app=minio

# Sprawdzenie bucketu w MinIO
kubectl -n $MINIO_NAMESPACE exec svc/minio -- mc ls local/$MINIO_BUCKET || echo "UWAGA: Bucket nie istnieje"

# Velero pod
kubectl get pods -n $VELERO_NAMESPACE -l component=velero

# Secret Velero
kubectl get secret cloud-credentials -n $VELERO_NAMESPACE

echo "==> Sprawdzanie BackupStorageLocation"
velero backup-location get


echo "==> Instalacja zakończona!"
