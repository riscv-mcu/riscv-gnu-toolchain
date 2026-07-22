#!/usr/bin/env bash
# Script to build and tag docker images for gnutoolchain
#
# Usage:
#   ./build_images.sh [tag]
#   e.g. ./build_images.sh v2
#   e.g. ./build_images.sh v3
#
# Default tag is v2 if not specified.

set -e

SCRIPTDIR=$(dirname $(readlink -f $BASH_SOURCE))
SCRIPTDIR=$(readlink -f $SCRIPTDIR)
cd $SCRIPTDIR

TAG=${1:-v2}

# Auto-detect container engine (podman or docker)
if command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
else
    echo "ERROR: Neither podman nor docker was found in PATH!"
    exit 1
fi
echo "INFO: Using container engine: $ENGINE"

CENTOS_DF="Dockerfile.centos7_${TAG}"
UBUNTU_DF="Dockerfile.ubuntu20.04_${TAG}"

if [ ! -f "$CENTOS_DF" ]; then
    echo "ERROR: Dockerfile $CENTOS_DF not found!"
    exit 1
fi

if [ ! -f "$UBUNTU_DF" ]; then
    echo "ERROR: Dockerfile $UBUNTU_DF not found!"
    exit 1
fi

# Ask for confirmation before building
echo "Prepare to build and tag the following images with tag '$TAG':"
echo "  - gnutoolchain-centos7"
echo "  - gnutoolchain-ubuntu20.04"
read -p "Do you want to proceed with the build? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo "Build cancelled by user."
    exit 0
fi

REGO_REPO="rego.corp.nucleisys.com/software"
DOCKER_REPO="docker.io/nucleisoftware"

# 1. Build CentOS 7 Image (Linux toolchain build environment)
echo "INFO: Building CentOS 7 image with tag: $TAG"
$ENGINE build -t gnutoolchain-centos7:${TAG} -f ${CENTOS_DF} .

# 2. Build Ubuntu 20.04 Image (Windows toolchain build environment)
echo "INFO: Building Ubuntu 20.04 image with tag: $TAG"
$ENGINE build -t gnutoolchain-ubuntu20.04:${TAG} -f ${UBUNTU_DF} .

# 3. Tag images for registries
echo "INFO: Tagging images..."
# CentOS 7
$ENGINE tag gnutoolchain-centos7:${TAG} ${REGO_REPO}/gnutoolchain-centos7:${TAG}
$ENGINE tag gnutoolchain-centos7:${TAG} ${DOCKER_REPO}/gnutoolchain-centos7:${TAG}

# Ubuntu 20.04
$ENGINE tag gnutoolchain-ubuntu20.04:${TAG} ${REGO_REPO}/gnutoolchain-ubuntu20.04:${TAG}
$ENGINE tag gnutoolchain-ubuntu20.04:${TAG} ${DOCKER_REPO}/gnutoolchain-ubuntu20.04:${TAG}

echo "=========================================================="
echo "Build and Tagging Completed Successfully!"
echo "Local images:"
$ENGINE images | grep -E "gnutoolchain-centos7|gnutoolchain-ubuntu20.04" | grep "${TAG}"
echo "=========================================================="
echo "To push the images when ready, run:"
echo "  $ENGINE push ${REGO_REPO}/gnutoolchain-centos7:${TAG}"
echo "  $ENGINE push ${DOCKER_REPO}/gnutoolchain-centos7:${TAG}"
echo "  $ENGINE push ${REGO_REPO}/gnutoolchain-ubuntu20.04:${TAG}"
echo "  $ENGINE push ${DOCKER_REPO}/gnutoolchain-ubuntu20.04:${TAG}"
echo "=========================================================="
