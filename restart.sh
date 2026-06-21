#!/bin/bash

# 自定义action函数，实现通用action功能
success() {
  echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
  return 0
}

failure() {
  local rc=$?
  echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
  [ -x /bin/plymouth ] && /bin/plymouth --details
  return $rc
}

action() {
  local STRING rc

  STRING=$1
  echo -n "$STRING "
  shift
  "$@" && success $"$STRING" || failure $"$STRING"
  rc=$?
  echo
  return $rc
}

# 函数，判断命令是否正常执行
if_success() {
  local ReturnStatus=$3
  if [ $ReturnStatus -eq 0 ]; then
          action "$1" /bin/true
  else
          action "$2" /bin/false
          exit 1
  fi
}

print_clash_log_tail() {
  if [ -f "$Log_Dir/clash.log" ]; then
    echo -e "\nClash日志最后40行："
    tail -n 40 "$Log_Dir/clash.log"
    echo
  fi
}

start_clash() {
  local bin_path=$1

  nohup "$bin_path" -d "$Conf_Dir" &> "$Log_Dir/clash.log" &
  local clash_pid=$!

  sleep 1
  if kill -0 "$clash_pid" 2>/dev/null; then
    return 0
  fi

  wait "$clash_pid" 2>/dev/null || true
  print_clash_log_tail
  return 1
}

# 定义路劲变量
Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
Conf_Dir="$Server_Dir/conf"
Log_Dir="$Server_Dir/logs"

mkdir -p "$Conf_Dir" "$Log_Dir"

## 关闭clash服务
Text1="服务关闭成功！"
Text2="服务关闭失败！"
# 查询并关闭程序进程
PID_NUM=`ps -ef | grep [c]lash-linux-a | wc -l`
PID=`ps -ef | grep [c]lash-linux-a | awk '{print $2}'`
ReturnStatus=0
if [ $PID_NUM -ne 0 ]; then
	kill -9 $PID
  ReturnStatus=$?
	# ps -ef | grep [c]lash-linux-a | awk '{print $2}' | xargs kill -9
fi
if_success $Text1 $Text2 $ReturnStatus

sleep 3

## 获取CPU架构
if /bin/arch &>/dev/null; then
	CpuArch=`/bin/arch`
elif /usr/bin/arch &>/dev/null; then
	CpuArch=`/usr/bin/arch`
elif /bin/uname -m &>/dev/null; then
	CpuArch=`/bin/uname -m`
else
	echo -e "\033[31m\n[ERROR] Failed to obtain CPU architecture！\033[0m"
	exit 1
fi

## 重启启动clash服务
Text5="服务启动成功！"
Text6="服务启动失败！"
if [[ $CpuArch =~ "x86_64" ]]; then
  start_clash "$Server_Dir/bin/clash-linux-amd64"
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "aarch64" ]]; then
	start_clash "$Server_Dir/bin/clash-linux-armv7"
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi
