#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#       System Required: CentOS/Debian/Ubuntu
#       Description: Snell Server 管理脚本
#       Modified: Claude -- install from user snell
#=================================================

sh_ver="1.6.4"
filepath=$(cd "$(dirname "$0")"; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/opt/snell"
FILE="/opt/snell/bin/snell-server"
CONF="/opt/snell/etc/config.conf"
Now_ver_File="/opt/snell/etc/ver.txt"
Local="/etc/sysctl.d/local.conf"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

checkRoot(){
    [[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

createUser() {
    if ! id "snell" &>/dev/null; then
        useradd -r -s /sbin/nologin snell
        echo -e "${Info} 已创建 snell 用户"
    else
        echo -e "${Info} snell 用户已存在"
    fi
}

createDirs() {
    mkdir -p /opt/snell/{bin,etc,log}
    
    chown root:snell /opt/snell
    chown root:snell /opt/snell/bin
    chown root:snell /opt/snell/etc
    chown snell:snell /opt/snell/log
    
    chmod 775 /opt/snell
    chmod 775 /opt/snell/bin
    chmod 770 /opt/snell/etc
    chmod 755 /opt/snell/log
}

#检查系统
checkSys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
}
InstallationDependency(){
    if [[ ${release} == "centos" ]]; then
        yum update
        yum install gzip wget curl unzip jq -y
    else
        apt-get update
        apt-get install gzip wget curl unzip jq -y
    fi
    sysctl -w net.core.rmem_max=26214400
    sysctl -w net.core.rmem_default=26214400
    \cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

#检查系统内核版本
sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i386"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="armv7l"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="amd64"
    fi    
}

#开启系统 TCP Fast Open
enableSystfo() {
    kernel=$(uname -r | awk -F . '{print $1}')
    if [ "$kernel" -ge 3 ]; then
        echo 3 >/proc/sys/net/ipv4/tcp_fastopen
        [[ ! -e $Local ]] && echo "fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/local.conf && sysctl --system >/dev/null 2>&1
    else
        echo -e "$Error系统内核版本过低，无法支持 TCP Fast Open ！"
    fi
}

checkInstalledStatus(){
    [[ ! -e ${FILE} ]] && echo -e "${Error} Snell Server 没有安装，请检查！" && exit 1
}

checkStatus(){
    status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
}

getSnellv4Url(){
    sysArch
    snell_v4_url="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-${arch}.zip"
}

getVer(){
    getSnellv4Url
    filename=$(basename "${snell_v4_url}")
    if [[ $filename =~ v([0-9]+\.[0-9]+\.[0-9]+(rc[0-9]*|b[0-9]*)?) ]]; then
        new_ver=${BASH_REMATCH[1]}
        echo -e "${Info} 检测到 Snell 最新版本为 [ ${new_ver} ]"
    else
        echo -e "${Error} Snell Server 最新版本获取失败！"
    fi
}
# v2 备用源
v2_download() {
    echo -e "${Info} 默认开始下载 ${Yellow_font_prefix}v2 备用源版 ${Font_color_suffix} Snell Server ……"
    wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v2.0.6/snell-server-v2.0.6-linux-${arch}.zip"
    if [[ ! -e "snell-server-v2.0.6-linux-${arch}.zip" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix} 下载失败！"
        return 1 && exit 1
    else
        unzip -o "snell-server-v2.0.6-linux-${arch}.zip"
    fi
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix} 解压失败！"
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix } 安装失败！"
        return 1 && exit 1
    else
        rm -rf "snell-server-v2.0.6-linux-${arch}.zip"
        chmod +x snell-server
        mv -f snell-server "${FILE}"
        echo "v2.0.6" > ${Now_ver_File}
        echo -e "${Info} Snell Server 主程序下载安装完毕！"
        return 0
    fi
}

# v3 备用源
v3_download() {
    echo -e "${Info} 试图请求 ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} Snell Server ……"
    wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v3.0.1/snell-server-v3.0.1-linux-${arch}.zip"
    if [[ ! -e "snell-server-v3.0.1-linux-${arch}.zip" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 下载失败！"
        return 1 && exit 1
    else
        unzip -o "snell-server-v3.0.1-linux-${arch}.zip"
    fi
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 解压失败！"
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 安装失败！"
        return 1 && exit 1
    else
        rm -rf "snell-server-v3.0.1-linux-${arch}.zip"
        chmod +x snell-server
        mv -f snell-server "${FILE}"
        echo "v3.0.1" > ${Now_ver_File}
        echo -e "${Info} Snell Server 主程序下载安装完毕！"
        return 0
    fi
}

# v4 官方源
v4_download(){
    echo -e "${Info} 试图请求 ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} Snell Server ……"
    getVer
    wget --no-check-certificate -N "${snell_v4_url}"
    if [[ ! -e "snell-server-v${new_ver}-linux-${arch}.zip" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 下载失败！"
        return 1 && exit 1
    else
        unzip -o "snell-server-v${new_ver}-linux-${arch}.zip"
    fi
    if [[ ! -e "snell-server" ]]; then
        echo -e "${Error} Snell Server ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 解压失败！"
        echo -e "${Error} Snell Server${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 安装失败！"
        return 1 && exit 1
    else
        rm -rf "snell-server-v${new_ver}-linux-${arch}.zip"
        chmod +x snell-server
        mv -f snell-server "${FILE}"
        echo "v${new_ver}" > ${Now_ver_File}
        echo -e "${Info} Snell Server 主程序下载安装完毕！"
        return 0
    fi
}
# 安装
Install() {
    if [[ ! -e "${FOLDER}" ]]; then
        mkdir "${FOLDER}"
    else
        [[ -e "${FILE}" ]] && rm -rf "${FILE}"
    fi
    echo -e "选择安装版本${Yellow_font_prefix}[2-4]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2  ${Green_font_prefix} 3.${Font_color_suffix} v3  ${Green_font_prefix} 4.${Font_color_suffix} v4
=================================="
    read -e -p "(默认：4.v4)：" ver
    [[ -z "${ver}" ]] && ver="4"
    if [[ ${ver} == "2" ]]; then
        Install_v2
    elif [[ ${ver} == "3" ]]; then
        Install_v3
    elif [[ ${ver} == "4" ]]; then
        Install_v4
    else
        Install_v4
    fi
}

Service(){
    echo '
[Unit]
Description= Snell Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767 
Type=simple
User=snell
Group=snell
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c 'ulimit -n 51200'
ExecStart=/opt/snell/bin/snell-server -c /opt/snell/etc/config.conf

[Install]
WantedBy=multi-user.target' > /etc/systemd/system/snell-server.service
    systemctl enable --now snell-server
    echo -e "${Info} Snell Server 服务配置完成！"
}

writeConfig(){
    if [[ -z "${dns}" ]]; then
        cat > ${CONF}<<-EOF
[snell-server]
listen = ::0:${port}
ipv6 = ${ipv6}
psk = ${psk}
obfs = ${obfs}
obfs-host = ${host}
tfo = ${tfo}
version = ${ver}
EOF
    else
        cat > ${CONF}<<-EOF
[snell-server]
listen = ::0:${port}
ipv6 = ${ipv6}
psk = ${psk}
obfs = ${obfs}
obfs-host = ${host}
tfo = ${tfo}
dns = ${dns}
version = ${ver}
EOF
    fi
    chown root:snell ${CONF}
    chmod 660 ${CONF}
}

readConfig(){
    [[ ! -e ${CONF} ]] && echo -e "${Error} Snell Server 配置文件不存在！" && exit 1
    ipv6=$(cat ${CONF}|grep 'ipv6 = '|awk -F 'ipv6 = ' '{print $NF}')
    port=$(grep -E '^listen\s*=' ${CONF} | awk -F ':' '{print $NF}' | xargs)
    psk=$(cat ${CONF}|grep 'psk = '|awk -F 'psk = ' '{print $NF}')
    obfs=$(cat ${CONF}|grep 'obfs = '|awk -F 'obfs = ' '{print $NF}')
    host=$(cat ${CONF}|grep 'obfs-host = '|awk -F 'obfs-host = ' '{print $NF}')
    tfo=$(cat ${CONF}|grep 'tfo = '|awk -F 'tfo = ' '{print $NF}')
    dns=$(cat ${CONF}|grep 'dns = '|awk -F 'dns = ' '{print $NF}')
    ver=$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')
}
setPort(){
    while true
    do
        echo -e "${Tip} 本步骤不涉及系统防火墙端口操作，请手动放行相应端口！"
        echo -e "请输入 Snell Server 端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
        read -e -p "(默认: 2345):" port
        [[ -z "${port}" ]] && port="2345"
        echo $((${port}+0)) &>/dev/null
        if [[ $? -eq 0 ]]; then
            if [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
                echo && echo "=============================="
                echo -e "端口 : ${Red_background_prefix} ${port} ${Font_color_suffix}"
                echo "==============================" && echo
                break
            else
                echo "输入错误, 请输入正确的端口。"
            fi
        else
            echo "输入错误, 请输入正确的端口。"
        fi
    done
}

setIpv6(){
    echo -e "是否开启 IPv6 解析 ？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
    read -e -p "(默认：2.关闭)：" ipv6
    [[ -z "${ipv6}" ]] && ipv6="false"
    if [[ ${ipv6} == "1" ]]; then
        ipv6=true
    else
        ipv6=false
    fi
    echo && echo "=================================="
    echo -e "IPv6 解析 开启状态：${Red_background_prefix} ${ipv6} ${Font_color_suffix}"
    echo "==================================" && echo
}

setPSK(){
    echo "请输入 Snell Server 密钥 [0-9][a-z][A-Z] "
    read -e -p "(默认: 随机生成):" psk
    [[ -z "${psk}" ]] && psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    echo && echo "=============================="
    echo -e "密钥 : ${Red_background_prefix} ${psk} ${Font_color_suffix}"
    echo "==============================" && echo
}

setObfs(){
    echo -e "配置 OBFS，${Tip} 无特殊作用不建议启用该项。
==================================
${Green_font_prefix} 1.${Font_color_suffix} TLS  ${Green_font_prefix} 2.${Font_color_suffix} HTTP ${Green_font_prefix} 3.${Font_color_suffix} 关闭
=================================="
    read -e -p "(默认：3.关闭)：" obfs
    [[ -z "${obfs}" ]] && obfs="3"
    if [[ ${obfs} == "1" ]]; then
        obfs=tls
    elif [[ ${obfs} == "2" ]]; then
        obfs=http
    elif [[ ${obfs} == "3" ]]; then
        obfs=off
    else
        obfs=off
    fi
    echo && echo "=================================="
    echo -e "OBFS 状态：${Red_background_prefix} ${obfs} ${Font_color_suffix}"
    echo "==================================" && echo
}

setVer(){
    echo -e "配置 Snell Server 协议版本${Yellow_font_prefix}[2-4]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2 ${Green_font_prefix} 3.${Font_color_suffix} v3 ${Green_font_prefix} 4.${Font_color_suffix} v4 
=================================="
    read -e -p "(默认：4.v4)：" ver
    [[ -z "${ver}" ]] && ver="4"
    if [[ ${ver} == "2" ]]; then
        ver=2
    elif [[ ${ver} == "3" ]]; then
        ver=3
    elif [[ ${ver} == "4" ]]; then
        ver=4
    else
        ver=4
    fi
    echo && echo "=================================="
    echo -e "Snell Server 协议版本：${Red_background_prefix} ${ver} ${Font_color_suffix}"
    echo "==================================" && echo
}
setHost(){
    echo "请输入 Snell Server 域名，v4 版本以上已弃用，可忽略。"
    read -e -p "(默认: icloud.com):" host
    [[ -z "${host}" ]] && host=icloud.com
    echo && echo "=============================="
    echo -e "域名 : ${Red_background_prefix} ${host} ${Font_color_suffix}"
    echo "==============================" && echo
}

setTFO(){
    echo -e "是否开启 TCP Fast Open ？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
    read -e -p "(默认：1.开启)：" tfo
    [[ -z "${tfo}" ]] && tfo="1"
    if [[ ${tfo} == "1" ]]; then
        tfo=true
        enableSystfo
    else
        tfo=false
    fi
    echo && echo "=================================="
    echo -e "TCP Fast Open 开启状态：${Red_background_prefix} ${tfo} ${Font_color_suffix}"
    echo "==================================" && echo
}

setDNS(){
    echo -e "是否要配置 DNS？(仅支持 v4.1.0b1 及以上版本)
==================================
${Green_font_prefix} 1.${Font_color_suffix} 是  ${Green_font_prefix} 2.${Font_color_suffix} 否
=================================="
    read -e -p "(默认: 2.否)：" dns_enable
    [[ -z "${dns_enable}" ]] && dns_enable="2"
    
    if [[ ${dns_enable} == "1" ]]; then
        echo -e "${Tip} 请输入 DNS，多条记录以英文逗号隔开"
        read -e -p "(示例: 1.1.1.1, 8.8.8.8, 2001:4860:4860::8888)：" dns
        [[ -z "${dns}" ]] && dns="1.1.1.1, 8.8.8.8, 2001:4860:4860::8888"
        echo && echo "=================================="
        echo -e "DNS 设置为：${Red_background_prefix} ${dns} ${Font_color_suffix}"
        echo "==================================" && echo
    else
        dns=""
        echo && echo "=================================="
        echo -e "DNS 设置：${Red_background_prefix} 未设置 ${Font_color_suffix}"
        echo "==================================" && echo
    fi
}

Install_v2(){
    checkRoot
    [[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装！" && exit 1
    echo -e "${Info} 开始设置 配置..."
    setPort
    setPSK
    setObfs
    setHost
    setIpv6
    setTFO
    echo -e "${Info} 开始安装/配置 依赖..."
    InstallationDependency
    echo -e "${Info} 开始下载/安装..."
    createUser
    createDirs
    v2_download
    echo -e "${Info} 开始安装 服务脚本..."
    Service
    echo -e "${Info} 开始写入 配置文件..."
    writeConfig
    echo -e "${Info} 所有步骤 安装完毕，开始启动..."
    Start
    echo -e "${Info} 启动完成，查看配置..."
    View
}
Install_v3(){
    checkRoot
    [[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装！" && exit 1
    echo -e "${Info} 开始设置 配置..."
    setPort
    setPSK
    setObfs
    setHost
    setIpv6
    setTFO
    echo -e "${Info} 开始安装/配置 依赖..."
    InstallationDependency
    echo -e "${Info} 开始下载/安装..."
    createUser
    createDirs
    v3_download
    echo -e "${Info} 开始安装 服务脚本..."
    Service
    echo -e "${Info} 开始写入 配置文件..."
    writeConfig
    echo -e "${Info} 所有步骤 安装完毕，开始启动..."
    Start
    echo -e "${Info} 启动完成，查看配置..."
    View
}

Install_v4(){
    checkRoot
    [[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装！" && exit 1
    echo -e "${Info} 开始设置 配置..."
    setPort
    setPSK
    setObfs
    setHost
    setIpv6
    setTFO
    setDNS
    echo -e "${Info} 开始安装/配置 依赖..."
    InstallationDependency
    echo -e "${Info} 开始下载/安装..."
    createUser
    createDirs
    v4_download
    echo -e "${Info} 开始安装 服务脚本..."
    Service
    echo -e "${Info} 开始写入 配置文件..."
    writeConfig
    echo -e "${Info} 所有步骤 安装完毕，开始启动..."
    Start
    echo -e "${Info} 启动完成，查看配置..."
    View
}

Start(){
    checkInstalledStatus
    checkStatus
    if [[ "$status" == "running" ]]; then
        echo -e "${Info} Snell Server 已在运行！"
    else
        systemctl start snell-server
        checkStatus
        if [[ "$status" == "running" ]]; then
            echo -e "${Info} Snell Server 启动成功！"
        else
            echo -e "${Error} Snell Server 启动失败！"
            exit 1
        fi
    fi
    sleep 3s
}

Stop(){
    checkInstalledStatus
    checkStatus
    [[ !"$status" == "running" ]] && echo -e "${Error} Snell Server 没有运行，请检查！" && exit 1
    systemctl stop snell-server
    echo -e "${Info} Snell Server 停止成功！"
    sleep 3s
    startMenu
}

Restart(){
    checkInstalledStatus
    systemctl restart snell-server
    echo -e "${Info} Snell Server 重启完毕!"
    sleep 3s
    startMenu
}
Uninstall(){
    checkInstalledStatus
    echo "确定要卸载 Snell Server ? (y/N)"
    echo
    read -e -p "(默认: n):" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        systemctl stop snell-server
        systemctl disable snell-server
        echo -e "${Info} 移除主程序..."
        rm -rf "${FILE}"
        rm -rf "${FOLDER}"
        userdel snell
        rm -f /etc/systemd/system/snell-server.service
        echo -e "${Info} snell 用户已删除"
        echo && echo "Snell Server 卸载完成！" && echo
    else
        echo && echo "卸载已取消..." && echo
    fi
    sleep 3s
    startMenu
}

getIpv4(){
    ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
    if [[ -z "${ipv4}" ]]; then
        ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
        if [[ -z "${ipv4}" ]]; then
            ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
            if [[ -z "${ipv4}" ]]; then
                ipv4="IPv4_Error"
            fi
        fi
    fi
}

getIpv6(){
    ip6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
    if [[ -z "${ip6}" ]]; then
        ip6="IPv6_Error"
    fi
}

View(){
    checkInstalledStatus
    readConfig
    getIpv4
    getIpv6
    clear && echo
    echo -e "Snell Server 配置信息："
    echo -e "—————————————————————————"
    [[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
    [[ "${ip6}" != "IPv6_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ip6}${Font_color_suffix}"
    echo -e " 端口\t: ${Green_font_prefix}${port}${Font_color_suffix}"
    echo -e " 密钥\t: ${Green_font_prefix}${psk}${Font_color_suffix}"
    echo -e " OBFS\t: ${Green_font_prefix}${obfs}${Font_color_suffix}"
    echo -e " 域名\t: ${Green_font_prefix}${host}${Font_color_suffix}"
    echo -e " IPv6\t: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
    echo -e " TFO\t: ${Green_font_prefix}${tfo}${Font_color_suffix}"
    [[ ! -z "${dns}" ]] && echo -e " DNS\t: ${Green_font_prefix}${dns}${Font_color_suffix}"
    echo -e " VER\t: ${Green_font_prefix}${ver}${Font_color_suffix}"
    echo -e "—————————————————————————"
    echo -e "${Info} Surge 配置："
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        if [[ "${obfs}" == "off" ]]; then
            echo -e "$(uname -n) = snell,${ipv4},${port},psk=${psk},version=${ver},tfo=${tfo},reuse=true,ecn=true"
        else
            echo -e "$(uname -n) = snell,${ipv4},${port},psk=${psk},version=${ver},tfo=${tfo},obfs=${obfs},host=${host},reuse=true,ecn=true"
        fi
    else
        if [[ "${obfs}" == "off" ]]; then
            echo -e "$(uname -n) = snell,${ip6},${port},psk=${psk},version=${ver},tfo=${tfo},reuse=true,ecn=true"
        else
            echo -e "$(uname -n) = snell,${ip6},${port},psk=${psk},version=${ver},tfo=${tfo},obfs=${obfs},host=${host},reuse=true,ecn=true"
        fi
    fi
    echo -e "—————————————————————————"
    beforeStartMenu
}

Status(){
    echo -e "${Info} 获取 Snell Server 活动日志 ……"
    echo -e "${Tip} 返回主菜单请按 q ！"
    systemctl status snell-server
    startMenu
}

beforeStartMenu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    startMenu
}

startMenu(){
    clear
    checkRoot
    checkSys
    sysArch
    action=$1
    echo && echo -e "  
==============================
Snell Server 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==============================
 ${Green_font_prefix} 0.${Font_color_suffix} 更新脚本
——————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 Snell Server
 ${Green_font_prefix} 2.${Font_color_suffix} 卸载 Snell Server
——————————————————————————————
 ${Green_font_prefix} 3.${Font_color_suffix} 启动 Snell Server
 ${Green_font_prefix} 4.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix} 5.${Font_color_suffix} 重启 Snell Server
——————————————————————————————
 ${Green_font_prefix} 6.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix} 7.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 运行状态
——————————————————————————————
 ${Green_font_prefix} 9.${Font_color_suffix} 退出脚本
==============================" && echo
    if [[ -e ${FILE} ]]; then
        checkStatus
        if [[ "$status" == "running" ]]; then
            echo -e " 当前状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
        else
            echo -e " 当前状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
        fi
    else
        echo -e " 当前状态: ${Red_font_prefix}未安装${Font_color_suffix}"
    fi
    echo
    read -e -p " 请输入数字[0-9]:" num
    case "$num" in
        0)
        updateShell
        ;;
        1)
        Install
        ;;
        2)
        Uninstall
        ;;
        3)
        Start
        ;;
        4)
        Stop
        ;;
        5)
        Restart
        ;;
        6)
        Set
        ;;
        7)
        View
        ;;
        8)
        Status
        ;;
        9)
        exit 1
        ;;
        *)
        echo "请输入正确数字${Yellow_font_prefix}[0-9]${Font_color_suffix}"
        ;;
    esac
}
startMenu