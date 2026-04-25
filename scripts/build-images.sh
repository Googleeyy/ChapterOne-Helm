#!/bin/bash
# Build Docker images for Library E2E microservices.
# Usage: ./build-images.sh [registry]

set -euo pipefail

REGISTRY="${1:-googleyy}"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Building Docker images for Library E2E"

echo ""
echo "Building book-service image"
cd "${PROJECT_ROOT}/book-service"
docker build -t "${REGISTRY}/book-service:latest" .
docker push "${REGISTRY}/book-service:latest"

echo ""
echo "Building user-service image"
cd "${PROJECT_ROOT}/user-service"
docker build -t "${REGISTRY}/user-service:latest" .
docker push "${REGISTRY}/user-service:latest"

echo ""
echo "Building borrow-service image"
cd "${PROJECT_ROOT}/borrow-service"
docker build -t "${REGISTRY}/borrow-service:latest" .
docker push "${REGISTRY}/borrow-service:latest"

echo ""
echo "Building frontend image"
cd "${PROJECT_ROOT}/frontend"
docker build -t "${REGISTRY}/chapterone-frontend:latest" .
docker push "${REGISTRY}/chapterone-frontend:latest"

echo ""
echo "All images built and pushed successfully"
