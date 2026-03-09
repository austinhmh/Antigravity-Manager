#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLI_VERSION="${1:-latest}"
USE_MIRROR="${2:-false}"

cd "$(dirname "$0")"

if [ -f .env ]; then
    echo -e "${GREEN}[OK] 加载 .env 配置文件${NC}"
    set -a
    source .env
    set +a
else
    echo -e "${YELLOW}[WARN] 未找到 .env 文件，继续使用当前环境变量${NC}"
fi

if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}[ERROR] 请设置 GITHUB_USERNAME${NC}"
    echo "可在 .env 中配置 GITHUB_USERNAME=<你的 GitHub 用户名>"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}[ERROR] 请设置 GITHUB_TOKEN${NC}"
    echo "GITHUB_TOKEN 需要具备 write:packages 权限"
    exit 1
fi

IMAGE_NAME="${IMAGE_NAME:-antigravity-manager}"
IMAGE_PREFIX="ghcr.io/${GITHUB_USERNAME}/${IMAGE_NAME}"
VERSION="${CLI_VERSION}"
FULL_IMAGE="${IMAGE_PREFIX}:${VERSION}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        PLATFORM="amd64"
        ;;
    aarch64|arm64)
        PLATFORM="arm64"
        ;;
    *)
        echo -e "${RED}[ERROR] 不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}==========================================${NC}"
echo "推送 Headless 镜像到 GHCR"
echo -e "${BLUE}==========================================${NC}"
echo "镜像名称: ${FULL_IMAGE}"
echo "当前架构: ${PLATFORM}"
echo "USE_MIRROR: ${USE_MIRROR}"
echo ""

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 未检测到 Docker${NC}"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker 服务未运行${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] 登录 GHCR...${NC}"
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin

echo -e "${BLUE}[INFO] 切换到默认 Docker builder...${NC}"
docker buildx use default 2>/dev/null || true

echo -e "${BLUE}[INFO] 构建镜像...${NC}"
docker build \
    --build-arg USE_MIRROR="$USE_MIRROR" \
    -f docker/Dockerfile \
    -t "$FULL_IMAGE" \
    .

echo -e "${BLUE}[INFO] 推送镜像...${NC}"
docker push "$FULL_IMAGE"

if [ "$VERSION" != "latest" ]; then
    LATEST_IMAGE="${IMAGE_PREFIX}:latest"
    echo -e "${BLUE}[INFO] 同步 latest 标签...${NC}"
    docker tag "$FULL_IMAGE" "$LATEST_IMAGE"
    docker push "$LATEST_IMAGE"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}[OK] GHCR 推送完成${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "镜像: ${FULL_IMAGE}"
echo "拉取: docker pull ${FULL_IMAGE}"
