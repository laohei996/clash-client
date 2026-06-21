#!/bin/bash

set -euo pipefail

Server_Dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -f "$Server_Dir/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$Server_Dir/.env"
  set +a
fi

Image_Name="${IMAGE_NAME:-clash-for-linux}"
Container_Name="${CONTAINER_NAME:-clash}"
Dashboard_Port="${DASHBOARD_PORT:-9090}"
Http_Port="${HTTP_PORT:-7890}"
Socks_Port="${SOCKS_PORT:-7891}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] docker command not found" >&2
  exit 1
fi

if [ -z "${CLASH_URL:-}" ]; then
  echo "[ERROR] 请先在 .env 中配置 CLASH_URL，或通过环境变量传入 CLASH_URL" >&2
  exit 1
fi

echo "正在构建镜像: ${Image_Name}"
docker build -t "$Image_Name" "$Server_Dir"

Existing_Container=$(docker ps -aq -f "name=^/${Container_Name}$")
if [ -n "$Existing_Container" ]; then
  echo "正在移除已有容器: ${Container_Name}"
  docker rm -f "$Container_Name" >/dev/null
fi

Docker_Run_Args=(
  run
  -d
  --restart=always
  --name "$Container_Name"
  -p "${Dashboard_Port}:9090"
  -p "${Http_Port}:7890"
  -p "${Socks_Port}:7891"
  -e "CLASH_URL=${CLASH_URL}"
)

if [ -n "${PRIVATE_VMESS:-}" ]; then
  Docker_Run_Args+=(-e "PRIVATE_VMESS=${PRIVATE_VMESS}")
fi

if [ -n "${PRIVATE_VLESS:-}" ]; then
  Docker_Run_Args+=(-e "PRIVATE_VLESS=${PRIVATE_VLESS}")
fi

Docker_Run_Args+=("$Image_Name")

echo "正在启动容器: ${Container_Name}"
docker "${Docker_Run_Args[@]}"

echo
echo "容器已启动: ${Container_Name}"
echo "Dashboard: http://127.0.0.1:${Dashboard_Port}/ui"
echo "HTTP代理: http://127.0.0.1:${Http_Port}"
echo "SOCKS5代理: socks5://127.0.0.1:${Socks_Port}"
echo "查看日志: docker logs -f ${Container_Name}"
