#!/bin/bash
set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

if ! kubectl get nodes >/dev/null 2>&1; then
  echo "❌ kubectl nie ma połączenia z klastrem"
  echo "➡ Sprawdź czy RKE2 działa i kubeconfig istnieje:"
  echo "   /etc/rancher/rke2/rke2.yaml"
  exit 1
fi

echo "==> Połączenie z klastrem Kubernetes OK"

echo "=========================="
echo "==> Instalacja Helm"
echo "=========================="

if command -v helm >/dev/null 2>&1; then
  echo "==> Helm już zainstalowany"
  helm version
else
  sudo apt-get install curl gpg apt-transport-https --yes
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt-get update
  sudo apt-get install helm
fi

echo "=========================="
echo " INSTALLACJA MetalLB"
echo "=========================="

kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -

if helm status metallb -n metallb-system >/dev/null 2>&1; then
  echo "==> MetalLB już zainstalowany"
else
  echo "==> Instalacja MetalLB"
  helm repo add metallb https://metallb.github.io/metallb
  helm repo update

  helm upgrade --install metallb metallb/metallb -n metallb-system
fi

echo "==> Czekanie na MetalLB controller..."
kubectl wait --for=condition=available deployment/metallb-controller \
  -n metallb-system --timeout=180s

echo "==> Czekanie na webhook MetalLB (endpointy)..."
for i in {1..30}; do
  ENDPOINTS=$(kubectl -n metallb-system get endpoints metallb-webhook-service \
    -o jsonpath='{.subsets[*].addresses[*].ip}')
  if [[ -n "$ENDPOINTS" ]]; then
    echo "==> Webhook MetalLB gotowy: $ENDPOINTS"
    break
  fi
  echo "Czekam na webhook MetalLB..."
  sleep 5
done

if [[ -z "$ENDPOINTS" ]]; then
  echo "❌ Webhook MetalLB NIE jest gotowy"
  kubectl -n metallb-system get pods
  exit 1
fi

echo "==> Zastosowanie AddressPool"
kubectl apply -f metallb-pool.yaml

echo "==> Sprawdzanie MetalLB"
kubectl -n metallb-system get all


echo "=========================="
echo " INSTALLACJA Envoy Gateway"
echo "=========================="

# Namespace
kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f -

if helm status eg -n envoy-gateway-system >/dev/null 2>&1; then
  echo "==> Envoy Gateway już zainstalowany"
else
  echo "==> Instalacja Envoy Gateway"
  helm install eg oci://docker.io/envoyproxy/gateway-helm \
    --version 1.6.2 \
    -n envoy-gateway-system \
    --set config.provider.kubernetes.service.type=LoadBalancer
fi

echo "==> Czekanie na gotowość Envoy Gateway..."
kubectl wait \
  --timeout=5m \
  -n envoy-gateway-system \
  deployment/envoy-gateway \
  --for=condition=Available

echo "==> Envoy Gateway gotowy"

echo "==============================="
echo " Envoy Gateway zainstalowany ✔"
echo "==============================="

# Informacyjnie – pokaż Service (MetalLB IP)
echo
echo "==> Service Envoy Gateway:"
kubectl -n envoy-gateway-system get svc


echo "=========================="
echo " INSTALLACJA cert-manager"
echo "=========================="

CERT_MANAGER_VERSION="v1.19.2"

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

echo "==> Instalacja / aktualizacja CRD cert-manager"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version ${CERT_MANAGER_VERSION} \
  --set config.enableGatewayAPI=true


echo "==> Oczekiwanie na gotowość cert-manager..."

kubectl rollout restart deployment cert-manager-webhook -n cert-manager
kubectl rollout restart deployment cert-manager -n cert-manager
kubectl rollout restart deployment cert-manager-cainjector -n cert-manager

echo "==> Czekam na webhook cert-manager po restarcie..."

kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=180s
kubectl rollout status deployment cert-manager -n cert-manager --timeout=180s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=180s


# Aplikacja Gateway.yaml (z lokalnego katalogu)
if [ ! -f gateway.yaml ]; then
  echo "❌ Brak pliku gateway.yaml w katalogu!"
  exit 1
fi
echo "==> Stosowanie gateway.yaml"
kubectl apply -f platform-placeholder-tls.yaml
kubectl apply -f gateway.yaml

echo "==> Uruchomienie LoadBalancer"
kubectl apply -f envoylb.yaml

echo "==> Sprawdzam czy API akceptuje gatewayHTTPRoute..."

for i in {1..60}; do
  if kubectl apply --dry-run=server -f cert-issuer-prod.yaml >/dev/null 2>&1; then
    echo "==> Gateway solver zaakceptowany przez API"
    break
  fi
  echo "Czekam aż webhook zacznie akceptować gatewayHTTPRoute..."
  sleep 5
done

kubectl apply -f cert-issuer-prod.yaml
kubectl apply -f cert-issuer-staging.yaml

echo "==> Oczekiwanie na EXTERNAL-IP z MetalLB..."

# Czekamy na External IP
for i in {1..60}; do
  IP=$(kubectl -n envoy-gateway-system get svc platform-gateway-lb --no-headers | awk '{print $4}')
  if [[ "$IP" != "<pending>" && "$IP" != "" ]]; then
    echo "==> EXTERNAL-IP przydzielony: $IP"
    break
  fi
  echo "Czekam na przydzielenie IP..."
  sleep 5
done

if [[ "$IP" == "<pending>" || "$IP" == "" ]]; then
  echo "❌ ERROR: MetalLB nie przydzielił IP!"
  exit 1
fi

echo "=========================="
echo " INSTALACJA LONGHORN"
echo "=========================="

kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

if helm status longhorn -n longhorn-system >/dev/null 2>&1; then
  echo "==> Longhorn już zainstalowany"
else
  helm repo add longhorn https://charts.longhorn.io
  helm repo update

  helm upgrade --install longhorn longhorn/longhorn \
    -n longhorn-system \
    --set defaultSettings.replicaAutoBalance=least-effort \
    --set persistence.defaultClassReplicaCount=3
fi

echo "==> Czekanie na Longhorn CRD i komponenty..."

CRDS=("volumes.longhorn.io" "engines.longhorn.io" "replicas.longhorn.io" "nodes.longhorn.io")

for crd in "${CRDS[@]}"; do
  for i in {1..60}; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
      kubectl wait --for=condition=established crd/$crd --timeout=300s
      echo "CRD $crd gotowa"
      break
    fi
    echo "Czekam aż CRD $crd zostanie utworzona..."
    sleep 5
  done
done

echo "==> Czekam aż longhorn-manager będzie READY..."

for i in {1..60}; do
  READY=$(kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{.status.numberReady}')
  DESIRED=$(kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{.status.desiredNumberScheduled}')

  if [[ "$READY" == "$DESIRED" && "$READY" != "" ]]; then
    echo "==> longhorn-manager gotowy ($READY/$DESIRED)"
    break
  fi

  echo "Czekam na longhorn-manager ($READY/$DESIRED)..."
  sleep 5
done

kubectl wait --for=condition=available --timeout=600s deployment/longhorn-ui -n longhorn-system
kubectl wait --for=condition=available --timeout=600s deployment/longhorn-driver-deployer -n longhorn-system

echo "==> Czekam na CRD Longhorna..."

for crd in volumes.longhorn.io engines.longhorn.io replicas.longhorn.io nodes.longhorn.io; do
  kubectl wait --for=condition=established crd/$crd --timeout=300s
done


kubectl apply -f LonghornEncrypt.yaml
kubectl apply -f StorageClass.yaml

echo "==> Longhorn + StorageClass skonfigurowane!"


echo "=========================="
echo " WALIDACJA INSTALACJI"
echo "=========================="

echo "==> Sprawdzanie Helm"
helm version

echo "==> Sprawdzanie MetalLB pods:"
kubectl -n metallb-system get pods

echo "==> Sprawdzanie Envoy Gateway pods:"
kubectl -n envoy-gateway-system get pods

echo "==> Sprawdzanie cert-manager pods:"
kubectl -n cert-manager get pods

echo "==> Sprawdzanie Service Envoy Gateway:"
kubectl -n envoy-gateway-system get svc

echo "==> Sprawdzanie longhorn:"
kubectl -n longhorn-system get pods

echo "=========================="
echo " INSTALACJA ZAKOŃCZONA ✔"
echo "=========================="
echo "Publiczny adres IP Envoy Gateway: $IP"
