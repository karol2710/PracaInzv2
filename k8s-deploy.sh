#!/bin/bash
set -e

# ==========================================
# Kubernetes Deployment Configuration
# ==========================================
KUBE_CONTEXT=""                           # Kubernetes context (leave empty for current context)
KUBE_NAMESPACE="kubechart"                # Kubernetes namespace
KUBECHART_IMAGE="yoghlol/pracainz:va1"        # Docker image URL
DEPLOYMENT_NAME="kubechart"               # Deployment name
REPLICAS=3                                # Number of replicas
DATABASE_HOST="postgres.kubechart.svc.cluster.local"  # PostgreSQL host
DATABASE_PORT=5432                        # PostgreSQL port
DATABASE_NAME="kubechart"                 # PostgreSQL database name
DATABASE_USER="deployer_user"             # PostgreSQL user
DATABASE_PASSWORD="deployer_password"     # PostgreSQL password
JWT_SECRET="your-secret-jwt-key"          # JWT secret for authentication
PORT=3000                                 # Application port
LOG_LEVEL="info"                          # Log level (debug, info, warn, error)
STORAGE_CLASS="platform-storageclass"     # Longhorn storage class
CPU_REQUEST="100m"                        # CPU request
CPU_LIMIT="500m"                          # CPU limit
MEMORY_REQUEST="256Mi"                    # Memory request
MEMORY_LIMIT="512Mi"                      # Memory limit

# ==========================================
# Color codes
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==========================================
# Functions
# ==========================================
print_header() {
    echo ""
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ==========================================
# Pre-flight checks
# ==========================================
print_header "Pre-flight Checks"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

print_success "kubectl is installed"

# Check cluster connectivity
if ! kubectl cluster-info > /dev/null 2>&1; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_success "Connected to Kubernetes cluster"

# Show current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "Current context: $CURRENT_CONTEXT"

if [ ! -z "$KUBE_CONTEXT" ]; then
    echo "Switching to context: $KUBE_CONTEXT"
    kubectl config use-context "$KUBE_CONTEXT"
fi

# ==========================================
# Validate configuration
# ==========================================
print_header "Configuration"

echo "Kubernetes Namespace:   $KUBE_NAMESPACE"
echo "Docker Image:           $KUBECHART_IMAGE"
echo "Deployment Name:        $DEPLOYMENT_NAME"
echo "Replicas:               $REPLICAS"
echo "Database Host:          $DATABASE_HOST"
echo "Database Port:          $DATABASE_PORT"
echo "Application Port:       $PORT"
echo "Storage Class:          $STORAGE_CLASS"
echo ""

# Check if using local image (without registry URL)
if [[ "$KUBECHART_IMAGE" != *"/"* ]]; then
    print_warning "Using local Docker image: $KUBECHART_IMAGE"
    print_warning "Make sure the image exists: docker images | grep kubechart"
fi

# ==========================================
# Step 1: Create namespace
# ==========================================
print_header "Step 1: Creating Kubernetes Namespace"

if kubectl get namespace "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_success "Namespace '$KUBE_NAMESPACE' already exists"
else
    echo "Creating namespace: $KUBE_NAMESPACE"
    kubectl create namespace "$KUBE_NAMESPACE"
    print_success "Namespace created"
fi

# ==========================================
# Step 1.5: Create RBAC resources
# ==========================================
print_header "Step 1.5: Creating RBAC Resources"

kubectl create secret docker-registry dockerhub-secret \
  --docker-username=yoghlol \
  --docker-password='dckr_pat_-UFdNXKObnWkP2s63E9bfA8kb0Q' \
  --docker-email='karol27100@gmail.com' \
  -n kubechart

# Create ServiceAccount
if kubectl get serviceaccount "$DEPLOYMENT_NAME" -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_success "ServiceAccount '$DEPLOYMENT_NAME' already exists"
else
    echo "Creating ServiceAccount: $DEPLOYMENT_NAME"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $KUBE_NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
imagePullSecrets:
  - name: dockerhub-secret
EOF
    print_success "ServiceAccount created"
fi

# Create ClusterRole for pod operations and deployment management (cluster-wide)
echo "Creating ClusterRole for $DEPLOYMENT_NAME"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $DEPLOYMENT_NAME
  labels:
    app: $DEPLOYMENT_NAME
rules:
  # Pod operations
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]

  # ConfigMaps and Secrets (read and write)
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Services
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Deployments
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # StatefulSets
  - apiGroups: ["apps"]
    resources: ["statefulsets"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # ReplicaSets
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Jobs
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # CronJobs
  - apiGroups: ["batch"]
    resources: ["cronjobs"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # PersistentVolumeClaims
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Ingress
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # NetworkPolicies
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # ResourceQuotas (across all namespaces)
  - apiGroups: [""]
    resources: ["resourcequotas"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # HorizontalPodAutoscalers
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Namespaces (cluster-wide)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # ServiceAccounts (across all namespaces)
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # RBAC - Roles and RoleBindings (cluster-wide)
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles", "clusterrolebindings"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Cert-Manager Certificates
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates", "issuers", "clusterissuers"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Gateway API
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes", "tcproutes", "udproutes", "tlsroutes", "gateways", "gatewayclasses"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Envoy Gateway BackendTrafficPolicy
  - apiGroups: ["gateway.envoyproxy.io"]
    resources: ["backendtrafficpolicies"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Velero Schedules and other Velero resources
  - apiGroups: ["velero.io"]
    resources: ["schedules", "backups", "restores", "backupstoragelocations", "volumesnapshotlocations"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Longhorn (if using)
  - apiGroups: ["longhorn.io"]
    resources: ["volumes", "engines", "replicas"]
    verbs: ["get", "list", "create", "patch", "update", "delete"]

  # Custom metrics
  - apiGroups: ["custom.metrics.k8s.io"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]

  # Allow all resource types via wildcard for flexibility
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list"]
EOF

# Create ClusterRoleBinding (cluster-wide)
echo "Creating ClusterRoleBinding for $DEPLOYMENT_NAME"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $DEPLOYMENT_NAME
  labels:
    app: $DEPLOYMENT_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $DEPLOYMENT_NAME
subjects:
  - kind: ServiceAccount
    name: $DEPLOYMENT_NAME
    namespace: $KUBE_NAMESPACE
EOF

print_success "RBAC resources created"

# ==========================================
# Step 2: Create secrets
# ==========================================
print_header "Step 2: Creating Kubernetes Secrets"

# Database credentials secret
SECRET_NAME="kubechart-db-credentials"

if kubectl get secret "$SECRET_NAME" -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_warning "Secret '$SECRET_NAME' already exists. Skipping creation."
else
    echo "Creating database credentials secret..."
    kubectl create secret generic "$SECRET_NAME" \
        --from-literal=database-url="postgresql://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}" \
        --from-literal=database-host="$DATABASE_HOST" \
        --from-literal=database-port="$DATABASE_PORT" \
        --from-literal=database-name="$DATABASE_NAME" \
        --from-literal=database-user="$DATABASE_USER" \
        --from-literal=database-password="$DATABASE_PASSWORD" \
        -n "$KUBE_NAMESPACE"
    print_success "Database secret created"
fi

# Application secrets
APP_SECRET_NAME="kubechart-app-secrets"

if kubectl get secret "$APP_SECRET_NAME" -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_warning "Secret '$APP_SECRET_NAME' already exists. Skipping creation."
else
    echo "Creating application secrets..."
    kubectl create secret generic "$APP_SECRET_NAME" \
        --from-literal=jwt-secret="$JWT_SECRET" \
        -n "$KUBE_NAMESPACE"
    print_success "Application secrets created"
fi

# ==========================================
# Step 3: Create ConfigMap
# ==========================================
print_header "Step 3: Creating ConfigMap"

CONFIGMAP_NAME="kubechart-config"

# Create temporary ConfigMap manifest
cat <<EOF > /tmp/kubechart-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CONFIGMAP_NAME
  namespace: $KUBE_NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
data:
  NODE_ENV: "production"
  PORT: "$PORT"
  LOG_LEVEL: "$LOG_LEVEL"
  DATABASE_HOST: "$DATABASE_HOST"
  DATABASE_PORT: "$DATABASE_PORT"
  DATABASE_NAME: "$DATABASE_NAME"
EOF

if kubectl get configmap "$CONFIGMAP_NAME" -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_warning "ConfigMap '$CONFIGMAP_NAME' already exists. Updating..."
    kubectl apply -f /tmp/kubechart-configmap.yaml
else
    echo "Creating ConfigMap..."
    kubectl apply -f /tmp/kubechart-configmap.yaml
    print_success "ConfigMap created"
fi

# ==========================================
# Step 4: Update deployment.yaml
# ==========================================
print_header "Step 4: Updating Deployment Manifest"

DEPLOYMENT_FILE="kubernetes/deployment.yaml"

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    print_error "Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

# Backup original deployment
cp "$DEPLOYMENT_FILE" "${DEPLOYMENT_FILE}.backup"
print_success "Deployment file backed up to ${DEPLOYMENT_FILE}.backup"

# Create updated deployment manifest
cat <<EOF > /tmp/kubechart-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $KUBE_NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    managed-by: k8s-deploy-script
spec:
  replicas: $REPLICAS
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: $DEPLOYMENT_NAME
  template:
    metadata:
      labels:
        app: $DEPLOYMENT_NAME
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "$PORT"
    spec:
      serviceAccountName: $DEPLOYMENT_NAME
      automountServiceAccountToken: true
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: wait-for-postgres
          image: busybox:latest
          command: ['sh', '-c', 'until nc -z postgres.$KUBE_NAMESPACE.svc.cluster.local 5432; do echo waiting for postgres; sleep 2; done; echo "PostgreSQL ready"; sleep 120']
      containers:
        - name: $DEPLOYMENT_NAME
          image: $KUBECHART_IMAGE
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: $PORT
              protocol: TCP
          env:
            - name: NODE_ENV
              valueFrom:
                configMapKeyRef:
                  name: $CONFIGMAP_NAME
                  key: NODE_ENV
            - name: PORT
              valueFrom:
                configMapKeyRef:
                  name: $CONFIGMAP_NAME
                  key: PORT
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: $CONFIGMAP_NAME
                  key: LOG_LEVEL
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-url
            - name: DATABASE_HOST
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-host
            - name: DATABASE_PORT
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-port
            - name: DATABASE_NAME
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-name
            - name: DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-user
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: $SECRET_NAME
                  key: database-password
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: $APP_SECRET_NAME
                  key: jwt-secret
          resources:
            requests:
              cpu: $CPU_REQUEST
              memory: $MEMORY_REQUEST
            limits:
              cpu: $CPU_LIMIT
              memory: $MEMORY_LIMIT
          livenessProbe:
            httpGet:
              path: /api/ping
              port: http
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /api/ping
              port: http
            initialDelaySeconds: 60
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - $DEPLOYMENT_NAME
                topologyKey: kubernetes.io/hostname
EOF

# ==========================================
# Step 5: Apply deployment
# ==========================================
print_header "Step 5: Applying Deployment"

echo "Applying deployment manifest..."
kubectl apply -f /tmp/kubechart-deployment.yaml

if [ $? -eq 0 ]; then
    print_success "Deployment applied successfully"
else
    print_error "Failed to apply deployment"
    exit 1
fi

# ==========================================
# Step 6: Deploy PostgreSQL (if not already running)
# ==========================================
print_header "Step 6: Deploying PostgreSQL Database"

# Check if postgres is already running
if kubectl get statefulset postgres -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
    print_success "PostgreSQL already deployed"

    # Ensure permissions are set for existing postgres
    echo "Ensuring database permissions are configured..."
    sleep 10

    if kubectl get pod postgres-0 -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
        kubectl exec postgres-0 -n "$KUBE_NAMESPACE" -- psql -U postgres -c "
          GRANT ALL PRIVILEGES ON DATABASE kubechart TO deployer_user;
          GRANT ALL PRIVILEGES ON SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO deployer_user;
        " 2>/dev/null || print_warning "Could not verify permissions"
    fi
else
    echo "Deploying PostgreSQL..."

    # Clean up old PVC if it exists (to avoid stale data)
    if kubectl get pvc postgres-storage-postgres-0 -n "$KUBE_NAMESPACE" > /dev/null 2>&1; then
        echo "Cleaning up old PostgreSQL storage..."
        kubectl delete pvc postgres-storage-postgres-0 -n "$KUBE_NAMESPACE" --wait=true
        sleep 5
    fi

    # Apply PostgreSQL resources in order
    echo "Creating PostgreSQL Secret..."
    kubectl apply -f kubernetes/postgres-secret.yaml

    echo "Creating PostgreSQL ConfigMap..."
    kubectl apply -f kubernetes/postgres-init-configmap.yaml

    echo "Creating PostgreSQL Service..."
    kubectl apply -f kubernetes/postgres-service.yaml

    echo "Creating PostgreSQL StatefulSet..."
    kubectl apply -f kubernetes/postgres-statefulset.yaml

    print_success "PostgreSQL resources created"

    echo "Waiting for PostgreSQL to be ready (timeout: 300s)..."
    if kubectl rollout status statefulset/postgres -n "$KUBE_NAMESPACE" --timeout=300s; then
        print_success "PostgreSQL is ready"

        # Wait for postgres to be fully responsive and accept connections
        sleep 20

        # Run post-initialization to ensure permissions are set
        echo "Setting up database permissions..."
        kubectl exec postgres-0 -n "$KUBE_NAMESPACE" -- psql -U postgres -c "
          GRANT ALL PRIVILEGES ON DATABASE kubechart TO deployer_user;
          GRANT ALL PRIVILEGES ON SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO deployer_user;
          GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO deployer_user;
          ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO deployer_user;
        " 2>/dev/null || print_warning "Could not set permissions - this is normal on fresh installs"

        print_success "Database permissions configured"
    else
        print_warning "PostgreSQL rollout incomplete or timed out"
    fi
fi

# ==========================================
# Step 6.5: Apply application service
# ==========================================
print_header "Step 6.5: Applying Application Service"

SERVICE_FILE="kubernetes/service.yaml"

if [ -f "$SERVICE_FILE" ]; then
    echo "Applying service manifest..."
    kubectl apply -f "$SERVICE_FILE"
    print_success "Service applied"
else
    print_warning "Service file not found at: $SERVICE_FILE"
fi

# ==========================================
# Step 7: Apply HTTPRoute (if exists)
# ==========================================
print_header "Step 7: Applying HTTPRoute"

HTTPROUTE_FILE="kubernetes/httproute.yaml"

if [ -f "$HTTPROUTE_FILE" ]; then
    echo "Applying HTTPRoute manifest..."
    kubectl apply -f "$HTTPROUTE_FILE"
    print_success "HTTPRoute applied"
else
    print_warning "HTTPRoute file not found at: $HTTPROUTE_FILE"
fi

# ==========================================
# Step 8: Apply HPA (if exists)
# ==========================================
print_header "Step 8: Applying HorizontalPodAutoscaler"

HPA_FILE="kubernetes/hpa.yaml"

if [ -f "$HPA_FILE" ]; then
    echo "Applying HPA manifest..."
    kubectl apply -f "$HPA_FILE"
    print_success "HPA applied"
else
    print_warning "HPA file not found at: $HPA_FILE"
fi

# ==========================================
# Step 9: Wait for rollout
# ==========================================
print_header "Step 9: Waiting for Deployment Rollout"

echo "Waiting for deployment to be ready (timeout: 300s)..."

if kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$KUBE_NAMESPACE" --timeout=300s; then
    print_success "Deployment rolled out successfully"
else
    print_warning "Deployment rollout incomplete or timed out"
    echo "Checking pod status..."
    kubectl get pods -n "$KUBE_NAMESPACE" -l app="$DEPLOYMENT_NAME"
fi

# ==========================================
# Step 10: Verify deployment
# ==========================================
print_header "Step 10: Verifying Deployment"

echo "Pods:"
kubectl get pods -n "$KUBE_NAMESPACE" -l app="$DEPLOYMENT_NAME"

echo ""
echo "Deployment status:"
kubectl describe deployment "$DEPLOYMENT_NAME" -n "$KUBE_NAMESPACE" | head -20

echo ""
echo "Services:"
kubectl get svc -n "$KUBE_NAMESPACE"

# ==========================================
# Step 11: Get access information
# ==========================================
print_header "Step 11: Access Information"

# Get service IP
SERVICE_IP=$(kubectl get svc -n "$KUBE_NAMESPACE" -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "pending")
SERVICE_TYPE=$(kubectl get svc -n "$KUBE_NAMESPACE" -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "unknown")

echo "Service Type: $SERVICE_TYPE"
echo "Service IP:   $SERVICE_IP"

if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    EXTERNAL_IP=$(kubectl get svc -n "$KUBE_NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    echo "External IP:  $EXTERNAL_IP"
fi

# ==========================================
# Step 12: Check logs
# ==========================================
print_header "Step 12: Application Logs"

echo "Recent logs from deployment:"
kubectl logs -n "$KUBE_NAMESPACE" -l app="$DEPLOYMENT_NAME" --tail=20 -f=false 2>/dev/null | head -20 || print_warning "No logs available yet"

# ==========================================
# Summary
# ==========================================
print_header "Deployment Complete"

echo "Deployment Summary:"
echo "  Namespace:      $KUBE_NAMESPACE"
echo "  Deployment:     $DEPLOYMENT_NAME"
echo "  Image:          $KUBECHART_IMAGE"
echo "  Replicas:       $REPLICAS"
echo "  Status:         $(kubectl get deployment "$DEPLOYMENT_NAME" -n "$KUBE_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')"
echo ""
echo "Useful commands:"
echo "  # View logs"
echo "  kubectl logs -n $KUBE_NAMESPACE -l app=$DEPLOYMENT_NAME -f"
echo ""
echo "  # Check pod status"
echo "  kubectl get pods -n $KUBE_NAMESPACE"
echo ""
echo "  # Describe deployment"
echo "  kubectl describe deployment $DEPLOYMENT_NAME -n $KUBE_NAMESPACE"
echo ""
echo "  # Port forward to access locally"
echo "  kubectl port-forward -n $KUBE_NAMESPACE svc/$DEPLOYMENT_NAME 3000:$PORT"
echo ""
echo "  # Rollout status"
echo "  kubectl rollout status deployment/$DEPLOYMENT_NAME -n $KUBE_NAMESPACE"
echo ""
echo "  # Restart deployment"
echo "  kubectl rollout restart deployment/$DEPLOYMENT_NAME -n $KUBE_NAMESPACE"
echo ""
