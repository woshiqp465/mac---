#!/bin/bash

# Mac M4 一键安装 - 快速启动脚本
# 此脚本会下载并执行完整的安装程序

# 配置
SERVER_IP="192.168.9.147"
INSTALLER_URL="http://${SERVER_IP}:8000/mac_m4_installer.sh"

echo "🍎 Mac M4 一键软件安装器"
echo "======================================"
echo ""

# 检查网络连接
echo "🔍 检查服务器连接..."
if ! ping -c 1 "$SERVER_IP" >/dev/null 2>&1; then
    echo "❌ 无法连接到软件服务器 ($SERVER_IP)"
    echo "   请确保与软件服务器在同一网络环境下"
    exit 1
fi

echo "✅ 服务器连接正常"
echo ""

# 下载并执行安装脚本
echo "📥 下载安装脚本..."
if curl -fsSL "$INSTALLER_URL" -o /tmp/mac_m4_installer.sh; then
    echo "✅ 安装脚本下载完成"
    echo ""
    echo "🚀 开始安装..."
    echo ""

    # 给脚本执行权限并运行
    chmod +x /tmp/mac_m4_installer.sh
    /tmp/mac_m4_installer.sh
else
    echo "❌ 下载安装脚本失败"
    echo ""
    echo "🔧 备用方法："
    echo "1. 确保服务器IP地址正确: $SERVER_IP"
    echo "2. 手动下载: curl -O http://$SERVER_IP:8000/../mac_m4_installer.sh"
    echo "3. 运行: bash mac_m4_installer.sh"
    exit 1
fi