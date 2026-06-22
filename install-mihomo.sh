#!/bin/bash

set -euo pipefail

Server_Dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
Bin_Dir="$Server_Dir/bin"
Release_Api="${MIHOMO_RELEASE_API:-https://api.github.com/repos/MetaCubeX/mihomo/releases/latest}"

for cmd in curl grep gzip uname; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] command not found: $cmd" >&2
    exit 1
  fi
done

mkdir -p "$Bin_Dir"

Cpu_Arch=$(uname -m)
case "$Cpu_Arch" in
  x86_64|amd64)
    Asset_Regex='mihomo-linux-amd64-compatible-v[0-9.]+\.gz'
    Target_Bin="mihomo-linux-amd64"
    Clash_Link="clash-linux-amd64"
    ;;
  aarch64|arm64)
    Asset_Regex='mihomo-linux-arm64-v[0-9.]+\.gz'
    Target_Bin="mihomo-linux-arm64"
    Clash_Link="clash-linux-arm64"
    ;;
  armv7*|armv7l)
    Asset_Regex='mihomo-linux-armv7-v[0-9.]+\.gz'
    Target_Bin="mihomo-linux-armv7"
    Clash_Link="clash-linux-armv7"
    ;;
  *)
    echo "[ERROR] Unsupported CPU architecture: $Cpu_Arch" >&2
    exit 1
    ;;
esac

echo "正在查询 Mihomo 最新版本..."
Release_Json=$(curl -fsSL "$Release_Api")
Download_Url=$(
  printf "%s" "$Release_Json" |
    grep -Eo 'https://[^"]+' |
    grep -E "/${Asset_Regex}$" |
    head -n 1 || true
)

if [ -z "$Download_Url" ]; then
  echo "[ERROR] 未找到匹配当前架构的 Mihomo 下载包: $Cpu_Arch" >&2
  echo "Release API: $Release_Api" >&2
  exit 1
fi

Tmp_Dir=$(mktemp -d)
trap 'rm -rf "$Tmp_Dir"' EXIT

echo "正在下载: $Download_Url"
curl -fL "$Download_Url" -o "$Tmp_Dir/mihomo.gz"

echo "正在安装到: $Bin_Dir/$Target_Bin"
gzip -dc "$Tmp_Dir/mihomo.gz" > "$Bin_Dir/$Target_Bin.tmp"
chmod +x "$Bin_Dir/$Target_Bin.tmp"
mv "$Bin_Dir/$Target_Bin.tmp" "$Bin_Dir/$Target_Bin"
ln -sfn "$Target_Bin" "$Bin_Dir/$Clash_Link"

echo
echo "Mihomo 安装完成:"
"$Bin_Dir/$Clash_Link" -v || true
echo
echo "现在可以重新启动:"
echo "bash start.sh"
