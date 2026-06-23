#!/bin/bash
# =============================================================================
# OAI gNB + nrUE 本機 Build Script
#
# 問題：官方 oaisoftwarealliance/oai-gnb 的 pre-built image 含 AVX-512 指令，
#       在 Intel i5-8265U（只有 AVX2）上啟動時 SIGILL → exit code 132
#
# 解法：使用官方 Dockerfile 在本機 build，加上 --noavx512 旗標
# =============================================================================

set -euo pipefail

# ----- 設定變數（可由環境變數覆寫）-----
OAI_TAG="${OAI_TAG:-2025.w12}"
OAI_REPO="${OAI_REPO:-https://github.com/openairinterface/openairinterface5G.git}"
BUILD_DIR="${BUILD_DIR:-/home/oscar/free5gctest/openairinterface5g}"
GNB_IMAGE="${GNB_IMAGE:-oai-gnb-local}"
UE_IMAGE="${UE_IMAGE:-oai-nr-ue-local}"

CPU_FLAGS=$(grep -m1 'flags' /proc/cpuinfo | grep -o 'avx[^ ]*' | tr '\n' ' ' || echo "unknown")

echo "=============================================="
echo " OAI Local Build Script (AVX-512 disabled)"
echo " TAG:       $OAI_TAG"
echo " Build dir: $BUILD_DIR"
echo " gNB image: $GNB_IMAGE"
echo " UE image:  $UE_IMAGE"
echo " CPU AVX:   $CPU_FLAGS"
echo "=============================================="

# ----- Step 1: Clone or update OAI source -----
if [ -d "$BUILD_DIR/.git" ]; then
    echo ""
    echo "[1/5] OAI source already exists at $BUILD_DIR"
    echo "      Updating and checking out tag $OAI_TAG..."
    cd "$BUILD_DIR"
    git fetch --tags --quiet
    git checkout "$OAI_TAG" --quiet
    echo "      ✓ Checked out: $(git describe --tags)"
else
    echo ""
    echo "[1/5] Cloning OAI source (shallow clone, tag: $OAI_TAG)..."
    echo "      From: $OAI_REPO"
    git clone --depth 1 --branch "$OAI_TAG" "$OAI_REPO" "$BUILD_DIR"
    cd "$BUILD_DIR"
    echo "      ✓ Clone complete"
fi

# ----- Step 2: Build ran-base image -----
echo ""
echo "[2/5] Building ran-base image (compiler toolchain)..."
echo "      This installs build dependencies and takes ~5 minutes"

docker build \
    --file docker/Dockerfile.base.ubuntu22 \
    --target ran-base \
    --tag ran-base:latest \
    . 2>&1 | grep -E "Step|error|ERROR|warning|--->" || true

echo "      ✓ ran-base built"

# ----- Step 3: Build ran-build image (compile OAI with --noavx512) -----
echo ""
echo "[3/5] Building ran-build image (compiling OAI with --noavx512)..."
echo "      This compiles nr-softmodem + nr-uesoftmodem, takes 20-40 minutes"
echo "      The --noavx512 flag ensures no AVX-512 instructions are used"

docker build \
    --file docker/Dockerfile.build.ubuntu22 \
    --target ran-build \
    --build-arg BUILD_OPTION="--noavx512" \
    --tag ran-build:latest \
    . 2>&1 | tail -5

echo "      ✓ ran-build complete (AVX-512 disabled)"

# ----- Step 4: Build final gNB image -----
echo ""
echo "[4/5] Building final gNB image: $GNB_IMAGE"

docker build \
    --file docker/Dockerfile.gNB.ubuntu22 \
    --target oai-gnb \
    --build-arg BUILD_OPTION="--noavx512" \
    --tag "$GNB_IMAGE" \
    . 2>&1 | tail -5

echo "      ✓ gNB image: $GNB_IMAGE"

# ----- Step 5: Build final nrUE image -----
echo ""
echo "[5/5] Building final nrUE image: $UE_IMAGE"

docker build \
    --file docker/Dockerfile.nrUE.ubuntu22 \
    --target oai-nr-ue \
    --build-arg BUILD_OPTION="--noavx512" \
    --tag "$UE_IMAGE" \
    . 2>&1 | tail -5

echo "      ✓ nrUE image: $UE_IMAGE"

# ----- Verify -----
echo ""
echo "=============================================="
echo " ✓ Build Complete!"
echo ""
echo " Built images:"
docker images | grep -E "oai-gnb-local|oai-nr-ue-local|ran-base|ran-build" | awk '{printf "   %-30s %s\n", $1":"$2, $7" "$8}'

echo ""
echo " Next steps:"
echo "   1. Update docker-compose.yaml:"
echo "      oai-gnb: image: $GNB_IMAGE"
echo "      oai-ue:  image: $UE_IMAGE"
echo ""
echo "   2. Start services:"
echo "      cd /home/oscar/free5gctest/free5gc-compose"
echo "      docker compose up oai-gnb -d"
echo "      docker compose logs -f oai-gnb"
echo "      docker compose up oai-ue -d"
echo "=============================================="
