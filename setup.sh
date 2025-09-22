#!/bin/bash

# Mac M4 软件分发服务器设置脚本
# 用于快速部署整个服务器环境

set -e

# 配置变量
SERVER_IP="192.168.9.147"
SERVER_PORT="8000"
SOFTWARE_DIR="/home/$(whoami)/software-cache/macos-arm"
LOG_DIR="/home/$(whoami)/software-cache"

echo "🍎 Mac M4 软件分发服务器设置"
echo "======================================"

# 创建必要目录
echo "📁 创建目录结构..."
mkdir -p "$SOFTWARE_DIR"
mkdir -p "$LOG_DIR/backup"

# 设置脚本权限
echo "🔧 设置脚本权限..."
chmod +x quick_install.sh
chmod +x mac_m4_installer.sh
chmod +x update_cache.sh

# 复制脚本到软件目录
echo "📋 复制脚本文件..."
cp quick_install.sh "$SOFTWARE_DIR/"
cp mac_m4_installer.sh "$SOFTWARE_DIR/"
cp update_cache.sh "/home/$(whoami)/"

# 更新脚本中的IP地址
echo "🌐 配置服务器IP地址..."
read -p "请输入服务器IP地址 (默认: $SERVER_IP): " input_ip
if [ ! -z "$input_ip" ]; then
    SERVER_IP="$input_ip"
fi

# 更新脚本中的IP配置
sed -i "s/192\.168\.9\.147/$SERVER_IP/g" "$SOFTWARE_DIR/quick_install.sh"
sed -i "s/192\.168\.9\.147/$SERVER_IP/g" "$SOFTWARE_DIR/mac_m4_installer.sh"

# 设置cron任务
echo "⏰ 配置自动更新任务..."
echo "是否设置自动更新任务？(每月1号和16号凌晨3点)"
read -p "输入 y/n (默认: y): " setup_cron

if [ "$setup_cron" != "n" ]; then
    # 添加cron任务
    (crontab -l 2>/dev/null; echo "0 3 1,16 * * /home/$(whoami)/update_cache.sh >> $LOG_DIR/cron.log 2>&1") | crontab -
    echo "✅ 自动更新任务已设置"
else
    echo "⏭️ 跳过自动更新任务设置"
fi

# 启动HTTP服务器
echo "🌐 启动HTTP服务器..."
echo "是否现在启动HTTP服务器？"
read -p "输入 y/n (默认: y): " start_server

if [ "$start_server" != "n" ]; then
    cd "$SOFTWARE_DIR"
    echo "启动HTTP服务器在端口 $SERVER_PORT..."
    echo "服务器将在后台运行，日志保存到 /tmp/http_server.log"
    nohup python3 -m http.server $SERVER_PORT --bind 0.0.0.0 > /tmp/http_server.log 2>&1 &
    echo "✅ HTTP服务器已启动"
    echo "📊 访问地址: http://$SERVER_IP:$SERVER_PORT"
else
    echo "⏭️ 跳过HTTP服务器启动"
    echo "手动启动命令:"
    echo "cd $SOFTWARE_DIR && python3 -m http.server $SERVER_PORT --bind 0.0.0.0"
fi

echo ""
echo "🎉 设置完成！"
echo "======================================"
echo "📍 软件包目录: $SOFTWARE_DIR"
echo "📄 日志目录: $LOG_DIR"
echo "🌐 服务器地址: http://$SERVER_IP:$SERVER_PORT"
echo ""
echo "📋 下一步操作："
echo "1. 将软件包文件放入: $SOFTWARE_DIR"
echo "2. 在Mac电脑上运行: curl -fsSL http://$SERVER_IP:$SERVER_PORT/quick_install.sh | bash"
echo "3. 查看日志: tail -f $LOG_DIR/update.log"
echo ""
echo "🔧 管理命令："
echo "- 手动更新软件包: /home/$(whoami)/update_cache.sh"
echo "- 查看HTTP服务器状态: ps aux | grep http.server"
echo "- 停止HTTP服务器: pkill -f 'http.server $SERVER_PORT'"
echo ""