#!/bin/bash

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "此脚本必须以 root 用户运行"
    exit 1
fi

# 设置基本环境
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 检查并安装依赖项
install_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 未安装，正在安装..."
        if [ -x "$(command -v apt)" ]; then
            apt update && apt install -y "$1"
        elif [ -x "$(command -v yum)" ]; then
            yum install -y "$1"
        else
            echo "不支持的包管理器，请手动安装 $1"
            exit 1
        fi
    fi
}

# 获取用户输入
echo "请输入 Shadowsocks 服务器配置信息："
read -p "服务器地址: " server_address
read -p "服务器端口 [18388]: " server_port
server_port=${server_port:-18388}  # 如果用户直接回车，使用默认值 18388
read -p "密码: " server_password

install_dependency curl
install_dependency dpkg

# 安装 sing-box
bash -c "$(curl -L https://sing-box.app/deb-install.sh)"

# 创建配置文件
cat > /etc/sing-box/config.json << 'EOL'
{
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "inet4_address": "198.18.0.1/30",
      "auto_route": true,
      "strict_route": false,
      "stack": "system",
      "mtu": 60000,
      "sniff": true,
      "sniff_override_destination": true,
      "include_uid": [
        1000
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    },
    {
      "type": "shadowsocks",
      "tag": "reddit-server",
      "server": "SERVER_ADDRESS",
      "server_port": SERVER_PORT,
      "method": "aes-128-gcm",
      "password": "SERVER_PASSWORD"
    }
  ],
  "route": {
    "rules": [
      {
        "domain_suffix": [
          "reddit.com",
          "redd.it",
          "redditmedia.com",
          "redditstatic.com"
        ],
        "outbound": "reddit-server"
      },
      {
        "outbound": "direct-out"
      }
    ]
  }
}
EOL

# 替换配置文件中的变量
sed -i "s/SERVER_ADDRESS/${server_address}/g" /etc/sing-box/config.json
sed -i "s/SERVER_PORT/${server_port}/g" /etc/sing-box/config.json
sed -i "s/SERVER_PASSWORD/${server_password}/g" /etc/sing-box/config.json

# 设置正确的权限
chmod 644 /etc/sing-box/config.json

# 重启 sing-box 服务
systemctl restart sing-box

# 检查服务状态
echo "正在检查 sing-box 服务状态..."
systemctl status sing-box | grep "Active:"
