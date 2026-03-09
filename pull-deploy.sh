#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$(dirname "$0")"

USE_LOCAL=false
CLI_VERSION="${1:-latest}"

if [ "$CLI_VERSION" = "--local" ]; then
    USE_LOCAL=true
    CLI_VERSION="local"
fi

if [ -f .env ]; then
    echo -e "${GREEN}[OK] 加载 .env 配置文件${NC}"
    set -a
    source .env
    set +a
else
    echo -e "${YELLOW}[WARN] 未找到 .env 文件，继续使用当前环境变量${NC}"
fi

VERSION="${CLI_VERSION:-${VERSION:-latest}}"
IMAGE_NAME="${IMAGE_NAME:-antigravity-manager}"
CONTAINER_NAME="${CONTAINER_NAME:-antigravity-manager}"
PORT="${PORT:-8045}"
API_KEY="${API_KEY:-sk-change-me-please}"
WEB_PASSWORD="${WEB_PASSWORD:-}"
ABV_AUTH_MODE="${ABV_AUTH_MODE:-all_except_health}"
ABV_BIND_LOCAL_ONLY="${ABV_BIND_LOCAL_ONLY:-false}"
ABV_MAX_BODY_SIZE="${ABV_MAX_BODY_SIZE:-104857600}"
ABV_PUBLIC_URL="${ABV_PUBLIC_URL:-}"
RUST_LOG="${RUST_LOG:-info}"
DATA_DIR="${DATA_DIR:-$HOME/.antigravity_tools}"

if [ -z "$GITHUB_USERNAME" ] && [ "$USE_LOCAL" = false ]; then
    echo -e "${RED}[ERROR] 请设置 GITHUB_USERNAME${NC}"
    echo "可在 .env 中配置 GITHUB_USERNAME=<你的 GitHub 用户名>"
    exit 1
fi

IMAGE_PREFIX="ghcr.io/${GITHUB_USERNAME}/${IMAGE_NAME}"
FULL_IMAGE="${IMAGE_PREFIX}:${VERSION}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 未检测到 Docker${NC}"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker 服务未运行${NC}"
    exit 1
fi

echo -e "${BLUE}==========================================${NC}"
echo "从 GHCR 拉取并部署 Headless 镜像"
echo -e "${BLUE}==========================================${NC}"
if [ "$USE_LOCAL" = true ]; then
    echo -e "${YELLOW}📍 使用本地镜像模式${NC}"
else
    echo -e "${YELLOW}📦 镜像: ${FULL_IMAGE}${NC}"
fi
echo -e "${YELLOW}🔌 端口: ${PORT}${NC}"
echo -e "${YELLOW}📁 数据目录: ${DATA_DIR}${NC}"
echo ""

if [ "$USE_LOCAL" = false ]; then
    if [ -n "$GITHUB_TOKEN" ]; then
        echo -e "${BLUE}[INFO] 登录 GHCR...${NC}"
        echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
    else
        echo -e "${YELLOW}[WARN] 未设置 GITHUB_TOKEN，如镜像为私有将无法拉取${NC}"
    fi
fi

mkdir -p "$DATA_DIR"

if [ "$USE_LOCAL" = true ]; then
    FULL_IMAGE="${IMAGE_NAME}:local"
    echo -e "${BLUE}[INFO] 检查本地镜像 ${FULL_IMAGE}...${NC}"
    if ! docker image inspect "$FULL_IMAGE" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] 本地镜像 ${FULL_IMAGE} 不存在${NC}"
        echo "请先运行 docker build -f docker/Dockerfile -t ${FULL_IMAGE} ."
        exit 1
    fi
else
    echo -e "${BLUE}[INFO] 拉取镜像 ${FULL_IMAGE}...${NC}"
    docker pull "$FULL_IMAGE"
fi

echo -e "${BLUE}[INFO] 停止旧容器...${NC}"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo -e "${BLUE}[INFO] 启动新容器...${NC}"
DOCKER_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  --network host
  -e "PORT=${PORT}"
  -e "API_KEY=${API_KEY}"
  -e "ABV_AUTH_MODE=${ABV_AUTH_MODE}"
  -e "ABV_BIND_LOCAL_ONLY=${ABV_BIND_LOCAL_ONLY}"
  -e "ABV_MAX_BODY_SIZE=${ABV_MAX_BODY_SIZE}"
  -e "RUST_LOG=${RUST_LOG}"
  -v "${DATA_DIR}:/root/.antigravity_tools"
  --restart unless-stopped
)

if [ -n "$WEB_PASSWORD" ]; then
  DOCKER_ARGS+=( -e "WEB_PASSWORD=${WEB_PASSWORD}" )
fi

if [ -n "$ABV_PUBLIC_URL" ]; then
  DOCKER_ARGS+=( -e "ABV_PUBLIC_URL=${ABV_PUBLIC_URL}" )
fi

docker run "${DOCKER_ARGS[@]}" "$FULL_IMAGE"

echo -e "${BLUE}[INFO] 等待服务启动...${NC}"
sleep 3

echo -e "${BLUE}[INFO] 健康检查...${NC}"
if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] 服务健康检查通过${NC}"
else
    echo -e "${YELLOW}[WARN] 健康检查暂未通过，服务可能仍在启动中${NC}"
    echo "可稍后手动检查: curl http://127.0.0.1:${PORT}/health"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}[OK] Headless 部署完成${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "容器: ${CONTAINER_NAME}"
echo "镜像: ${FULL_IMAGE}"
echo "Web UI: http://127.0.0.1:${PORT}"
echo "API Base: http://127.0.0.1:${PORT}/v1"
echo "Health: http://127.0.0.1:${PORT}/health"
echo ""
echo "查看日志: docker logs -f ${CONTAINER_NAME}"
echo "停止容器: docker stop ${CONTAINER_NAME}"
echo "删除容器: docker rm -f ${CONTAINER_NAME}"
