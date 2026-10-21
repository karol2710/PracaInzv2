#!/bin/bash
set -e

NAMESPACE="monitoring"

echo "➡️ Applying setup manifests (server-side)..."
kubectl apply --server-side -f manifests/setup

echo "➡️ Waiting for CRDs to be Established..."
kubectl wait \
  --for=condition=Established \
  --all CustomResourceDefinition \
  --timeout=120s

echo "➡️ Applying main manifests..."
kubectl apply -f manifests/

echo "➡️ Waiting for pods in namespace ${NAMESPACE}..."
kubectl wait \
  --for=condition=Ready pod \
  --all \
  -n ${NAMESPACE} \
  --timeout=300s

echo "➡️ Starting port-forwards..."

kubectl -n ${NAMESPACE} port-forward svc/prometheus-k8s 9090:9090 &
PF_PROM=$!

kubectl -n ${NAMESPACE} port-forward svc/grafana 3000:3000 &
PF_GRAF=$!

kubectl -n ${NAMESPACE} port-forward svc/alertmanager-main 9093:9093 &
PF_ALERT=$!

echo ""
echo "✅ Port-forward active:"
echo "  🔹 Prometheus   → http://localhost:9090"
echo "  🔹 Grafana      → http://localhost:3000"
echo "  🔹 Alertmanager → http://localhost:9093"
echo ""
echo "⛔ Press Ctrl+C to stop all port-forwards"

# Sprzątanie po Ctrl+C
trap cleanup INT TERM

cleanup() {
  echo ""
  echo "🧹 Stopping port-forwards..."
  kill $PF_PROM $PF_GRAF $PF_ALERT 2>/dev/null || true
  exit 0
}

# Czekaj wiecznie, żeby port-forwardy żyły
wait
