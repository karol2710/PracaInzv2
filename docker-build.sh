##!/bin/bash
set -e

# ==========================================
# Docker Build Configuration
# ==========================================
IMAGE_NAME="pracainz"                    # Image name
IMAGE_TAG="va1"                        # Image tag (e.g., latest, v1.0.0)
DOCKERFILE="Dockerfile"                   # Path to Dockerfile
BUILD_CONTEXT="."                         # Build context directory
REGISTRY_URL="yoghlol"                           # Docker registry URL (leave empty for local build)

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

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

print_success "Docker is installed"

if ! command -v docker buildx &> /dev/null; then
    print_warning "docker buildx is not available. Using standard docker build."
    USE_BUILDX=false
else
    print_success "docker buildx is available"
    USE_BUILDX=true
fi

# ==========================================
# Validate configuration
# ==========================================
print_header "Configuration"

if [ -n "$REGISTRY_URL" ]; then
    echo "Registry URL:        $REGISTRY_URL"
fi
echo "Image Name:          $IMAGE_NAME"
echo "Image Tag:           $IMAGE_TAG"
echo "Dockerfile:          $DOCKERFILE"
echo "Build Context:       $BUILD_CONTEXT"
echo ""

if [ ! -f "$DOCKERFILE" ]; then
    print_error "Dockerfile not found at: $DOCKERFILE"
    exit 1
fi

print_success "Dockerfile found"

if [ ! -d "$BUILD_CONTEXT" ]; then
    print_error "Build context directory not found: $BUILD_CONTEXT"
    exit 1
fi

print_success "Build context found"

# ==========================================
# Build Docker image
# ==========================================
print_header "Building Docker Image"

if [ -z "$REGISTRY_URL" ]; then
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE_NAME="${REGISTRY_URL}/${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo "Building image: $FULL_IMAGE_NAME"
echo ""

if [ "$USE_BUILDX" = true ]; then
    # Use buildx for multi-architecture support
    echo "Using docker buildx..."
    docker buildx build \
        --file "$DOCKERFILE" \
        --tag "$FULL_IMAGE_NAME" \
        --load \
        "$BUILD_CONTEXT"
else
    # Standard docker build
    docker build \
        --file "$DOCKERFILE" \
        --tag "$FULL_IMAGE_NAME" \
        "$BUILD_CONTEXT"
fi

if [ $? -eq 0 ]; then
    print_success "Docker image built successfully"
else
    print_error "Failed to build Docker image"
    exit 1
fi

# ==========================================
# Verify image
# ==========================================
print_header "Verifying Image"

docker inspect "$FULL_IMAGE_NAME" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_success "Image verified successfully"
    
    # Show image info
    echo ""
    echo "Image details:"
    docker inspect "$FULL_IMAGE_NAME" --format='Size: {{.Size}} bytes'
    docker inspect "$FULL_IMAGE_NAME" --format='Created: {{.Created}}'
else
    print_error "Failed to verify image"
    exit 1
fi

# ==========================================
# Test image (optional)
# ==========================================
print_header "Image Test"

read -p "Run health check test? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running container for testing..."
    
    CONTAINER_ID=$(docker run -d \
        --rm \
        --name kubechart-test \
        -p 3000:3000 \
        "$FULL_IMAGE_NAME")
    
    echo "Container ID: $CONTAINER_ID"
    echo "Waiting for application to start..."
    sleep 5
    
    if docker exec "$CONTAINER_ID" curl -f http://localhost:3000/api/ping > /dev/null 2>&1; then
        print_success "Health check passed"
    else
        print_warning "Health check may have failed (this could be normal in test environment)"
    fi
    
    docker stop "$CONTAINER_ID" 2>/dev/null || true
    print_success "Test container stopped"
fi

# ==========================================
# Push to registry (optional)
# ==========================================
if [ -n "$REGISTRY_URL" ]; then
    print_header "Registry Push"

    read -p "Push image to registry? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Pushing image to registry: $FULL_IMAGE_NAME"

        docker push "$FULL_IMAGE_NAME"

        if [ $? -eq 0 ]; then
            print_success "Image pushed successfully"
        else
            print_error "Failed to push image"
            exit 1
        fi
    fi
else
    print_header "Local Build Complete"
    echo "Image built locally: $FULL_IMAGE_NAME"
    echo "Image is ready for Kubernetes deployment"
    echo "The image will be deployed with 'imagePullPolicy: Never'"
fi

# ==========================================
# Summary
# ==========================================
print_header "Build Complete"

echo "Image Name:   $FULL_IMAGE_NAME"
echo "Dockerfile:   $DOCKERFILE"
echo "Build Context: $BUILD_CONTEXT"
echo ""
echo "Next steps:"
if [ -n "$REGISTRY_URL" ]; then
    echo "1. Image is ready in registry: $FULL_IMAGE_NAME"
    echo "2. Update k8s-deploy.sh with: KUBECHART_IMAGE=\"$FULL_IMAGE_NAME\""
else
    echo "1. Image built successfully and ready locally"
    echo "2. Ensure k8s-deploy.sh has: KUBECHART_IMAGE=\"kubechart:latest\""
fi
echo "3. Run: ./k8s-deploy.sh"
echo ""