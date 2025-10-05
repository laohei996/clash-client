#!/bin/bash

# 加载系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

# 获取脚本工作目录绝对路径
Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

# 加载.env变量文件
source $Server_Dir/.env

Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Log_Dir="$Server_Dir/logs"
URL=${CLASH_URL}

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

# 判断命令是否正常执行 函数
if_success() {
  local ReturnStatus=$3
  if [ $ReturnStatus -eq 0 ]; then
          action "$1" /bin/true
  else
          action "$2" /bin/false
          exit 1
  fi
}

# 临时取消环境变量
unset http_proxy
unset https_proxy
unset no_proxy

# 解析vmess分享链接并生成clash配置节点
parse_vmess_url() {
    local vmess_url=$1
    local decoded=$(echo "$vmess_url" | sed 's/vmess:\/\///' | base64 -d 2>/dev/null)
    
    if [ -z "$decoded" ]; then
        echo "无效的vmess链接" >&2
        return 1
    fi
    
    # 使用jq解析JSON（如果可用）否则使用grep和sed
    if command -v jq >/dev/null 2>&1; then
        local v=$(echo "$decoded" | jq -r '.v // empty')
        local ps=$(echo "$decoded" | jq -r '.ps // empty')
        local add=$(echo "$decoded" | jq -r '.add // empty')
        local port=$(echo "$decoded" | jq -r '.port // empty')
        local id=$(echo "$decoded" | jq -r '.id // empty')
        local aid=$(echo "$decoded" | jq -r '.aid // empty')
        local net=$(echo "$decoded" | jq -r '.net // empty')
        local type=$(echo "$decoded" | jq -r '.type // empty')
        local host=$(echo "$decoded" | jq -r '.host // empty')
        local path=$(echo "$decoded" | jq -r '.path // empty')
        local tls=$(echo "$decoded" | jq -r '.tls // empty')
    else
        # 不使用jq时的手动解析
        local v=$(echo "$decoded" | grep -o '"v":"[^"]*"' | sed 's/"v":"\([^"]*\)"/\1/')
        local ps=$(echo "$decoded" | grep -o '"ps":"[^"]*"' | sed 's/"ps":"\([^"]*\)"/\1/')
        local add=$(echo "$decoded" | grep -o '"add":"[^"]*"' | sed 's/"add":"\([^"]*\)"/\1/')
        local port=$(echo "$decoded" | grep -o '"port":"[^"]*"' | sed 's/"port":"\([^"]*\)"/\1/')
        local id=$(echo "$decoded" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/\1/')
        local aid=$(echo "$decoded" | grep -o '"aid":"[^"]*"' | sed 's/"aid":"\([^"]*\)"/\1/')
        local net=$(echo "$decoded" | grep -o '"net":"[^"]*"' | sed 's/"net":"\([^"]*\)"/\1/')
        local type=$(echo "$decoded" | grep -o '"type":"[^"]*"' | sed 's/"type":"\([^"]*\)"/\1/')
        local host=$(echo "$decoded" | grep -o '"host":"[^"]*"' | sed 's/"host":"\([^"]*\)"/\1/')
        local path=$(echo "$decoded" | grep -o '"path":"[^"]*"' | sed 's/"path":"\([^"]*\)"/\1/')
        local tls=$(echo "$decoded" | grep -o '"tls":"[^"]*"' | sed 's/"tls":"\([^"]*\)"/\1/')
    fi
    
    # 生成clash配置节点
    cat <<EOF
  - {name: "$ps", type: vmess, server: $add, port: $port, uuid: $id, alterId: ${aid:-0}, cipher: auto, network: ${net:-tcp}, tls: ${tls:-false}}
EOF
}

# 检查url是否有效
echo -e '\n正在检测订阅地址...'
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"
for i in {1..10}
do
        curl -o /dev/null -s -m 10 --connect-timeout 10 -w %{http_code} $URL | grep '[23][0-9][0-9]' &>/dev/null
        ReturnStatus=$?
        if [ $ReturnStatus -eq 0 ]; then
                break
        else
                continue
        fi
done
if_success $Text1 $Text2 $ReturnStatus

# 拉取更新config.yml文件
echo -e '\n正在下载Clash配置文件...'
Text3="配置文件config.yaml下载成功！"
Text4="配置文件config.yaml下载失败，退出启动！"
for i in {1..10}
do
        # wget -q -O $Temp_Dir/clash.yaml $URL
        curl -s -o $Temp_Dir/clash.yaml $URL
	ReturnStatus=$?
        if [ $ReturnStatus -eq 0 ]; then
                break
        else
                continue
        fi
done
if_success $Text3 $Text4 $ReturnStatus

# 取出代理相关配置 
sed -n '/^proxies:/,$p' $Temp_Dir/clash.yaml > $Temp_Dir/proxy.txt

# 新增 append_private_vmess 函数，在 $Temp_Dir/proxy.txt 的 proxies: 行后插入私有 vmess 节点，并更新 proxy-groups
append_private_vmess() {
    local proxy_file="$Temp_Dir/proxy.txt"
    local tmp_file="$Temp_Dir/proxy_with_private.txt"
    local vmess_nodes=""
    local node_names=()

    # 生成所有私有节点内容并收集节点名称
    IFS='|' read -ra VMESS_ARRAY <<< "$PRIVATE_VMESS"
    for vmess_url in "${VMESS_ARRAY[@]}"; do
        if [[ $vmess_url == vmess://* ]]; then
            # 解码vmess URL获取节点名称
            local decoded=$(echo "$vmess_url" | sed 's/vmess:\/\///' | base64 -d 2>/dev/null)
            local node_name=""
            
            if command -v jq >/dev/null 2>&1; then
                node_name=$(echo "$decoded" | jq -r '.ps // empty')
            else
                node_name=$(echo "$decoded" | grep -o '"ps":"[^"]*"' | sed 's/"ps":"\([^"]*\)"/\1/')
            fi
            
            if [ -n "$node_name" ]; then
                node_names+=("$node_name")
            fi
            
            vmess_nodes+=$(parse_vmess_url "$vmess_url")
            vmess_nodes+=$'\n'
        fi
    done

    if [ -z "$vmess_nodes" ]; then
        echo "没有有效的私有 vmess 节点"
        return 0
    fi

    # 在 proxies: 行后插入节点
    awk -v nodes="$vmess_nodes" '
        /^proxies:/ {
            print $0
            printf "%s\n", nodes
            next
        }
        { print }
    ' "$proxy_file" > "$tmp_file"

    mv "$tmp_file" "$proxy_file"
    
    # 将节点名称添加到 proxy-groups 中
    if [ ${#node_names[@]} -gt 0 ]; then
        local tmp_file2="$Temp_Dir/proxy_with_groups.txt"
        
        # 为每个 proxy-group 添加自定义节点
        awk -v names="${node_names[*]}" '
        BEGIN {
            split(names, name_array, " ")
            in_proxy_group = 0
            buffer = ""
            in_proxies = 0
        }
        /^proxy-groups:/ {
            in_proxy_group = 1
            print $0
            next
        }
        in_proxy_group && /^  - name:/ {
            if (buffer != "") {
                # 输出之前缓存的代理组内容，并在末尾添加自定义节点
                print buffer
                for (i in name_array) {
                    if (name_array[i] != "") {
                        print "      - " name_array[i]
                    }
                }
                buffer = ""
            }
            print $0
            in_proxies = 0
            next
        }
        in_proxy_group && /^    proxies:/ {
            in_proxies = 1
            buffer = $0
            next
        }
        in_proxy_group && in_proxies && /^      -/ {
            buffer = buffer "\n" $0
            next
        }
        in_proxy_group && in_proxies && !/^      -/ {
            # 代理列表结束，输出缓存内容并添加自定义节点
            print buffer
            for (i in name_array) {
                if (name_array[i] != "") {
                    print "      - " name_array[i]
                }
            }
            buffer = ""
            in_proxies = 0
            print $0
            next
        }
        in_proxy_group && /^  -/ && !in_proxies {
            if (buffer != "") {
                # 输出之前缓存的代理组内容，并在末尾添加自定义节点
                print buffer
                for (i in name_array) {
                    if (name_array[i] != "") {
                        print "      - " name_array[i]
                    }
                }
                buffer = ""
            }
             print $0
             next
         }
         !in_proxy_group || (!in_proxies && !/^  -/) {
             print $0
             next
         }
        ' "$proxy_file" > "$tmp_file2"
        
        mv "$tmp_file2" "$proxy_file"
    fi
}

# 添加私有vmess节点（如果环境变量中存在）
if [ -n "$PRIVATE_VMESS" ]; then
    echo "正在处理私有vmess节点..."
    append_private_vmess
fi

# 合并形成新的config.yaml
cat $Temp_Dir/templete_config.yaml > $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml
\cp $Temp_Dir/config.yaml $Conf_Dir/

# 随机一个新的 Secret 替换至 config.yaml
Secret=$(head -c 16 /dev/urandom | base64 | tr -d '+/=')
sed -ri "s@^secret: .*@secret: '$Secret'@g" $Conf_Dir/config.yaml

# Configure Clash Dashboard
Work_Dir=$(cd $(dirname $0); pwd)
Dashboard_Dir="${Work_Dir}/dashboard/public"
sed -ri "s@^# external-ui:.*@external-ui: ${Dashboard_Dir}@g" $Conf_Dir/config.yaml
# Get RESTful API Secret
Secret=`grep '^secret: ' $Conf_Dir/config.yaml | grep -Po "(?<=secret: ').*(?=')"`

# 获取CPU架构
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

# 启动Clash服务
echo -e '\n正在启动Clash服务...'
Text5="服务启动成功！"
Text6="服务启动失败！"
if [[ $CpuArch =~ "x86_64" ]]; then
	nohup $Server_Dir/bin/clash-linux-amd64 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "aarch64" ]]; then
	nohup $Server_Dir/bin/clash-linux-armv7 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi

# Output Dashboard access address and Secret
echo ''
echo -e "Clash Dashboard 访问地址：http://127.0.0.1:9090/ui"
echo -e "Secret：${Secret}"
echo ''

# 添加环境变量(root权限)
cat>/etc/profile.d/clash.sh<<EOF
# 开启系统代理
function proxy_on() {
	export http_proxy=http://127.0.0.1:7890
	export https_proxy=http://127.0.0.1:7890
	export no_proxy=127.0.0.1,localhost
	echo -e "\033[32m[√] 已开启代理\033[0m"
}

# 关闭系统代理
function proxy_off(){
	unset http_proxy
	unset https_proxy
	unset no_proxy
	echo -e "\033[31m[×] 已关闭代理\033[0m"
}
EOF

echo -e "请执行以下命令加载环境变量: source /etc/profile.d/clash.sh\n"
echo -e "请执行以下命令开启系统代理: proxy_on\n"
echo -e "若要临时关闭系统代理，请执行: proxy_off\n"
