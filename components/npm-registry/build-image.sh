#!/bin/bash
set -euo pipefail

# Build custom Verdaccio image with auth-proxy plugin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="verdaccio-auth-proxy"
IMAGE_TAG="latest"

# Build the image
echo "Building custom Verdaccio image with auth-proxy plugin..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}"

# For K3s, we need to import the image
if command -v k3s &> /dev/null; then
    echo "Importing image into K3s..."
    docker save "${IMAGE_NAME}:${IMAGE_TAG}" | sudo k3s ctr images import -
fi

echo "Image built successfully: ${IMAGE_NAME}:${IMAGE_TAG}"