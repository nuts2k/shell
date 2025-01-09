#!/usr/bin/env bash

# 检查并安装依赖项
install_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "$1 未安装，正在安装..."
        if [ -x "$(command -v apt)" ]; then
            sudo apt update && sudo apt install -y "$1"
        elif [ -x "$(command -v yum)" ]; then
            sudo yum install -y "$1"
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
bash <(curl -s https://sing-box.app/deb-install.sh)

# 创建配置文件
cat << EOF | sudo tee /etc/sing-box/config.json
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
      "server": "${server_address}",
      "server_port": ${server_port},
      "method": "aes-128-gcm",
      "password": "${server_password}"
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
EOF

# 设置正确的权限
sudo chmod 644 /etc/sing-box/config.json

# 重启 sing-box 服务
sudo systemctl restart sing-box

# 检查服务状态
echo "正在检查 sing-box 服务状态..."
sudo systemctl status sing-box | grep "Active:"
