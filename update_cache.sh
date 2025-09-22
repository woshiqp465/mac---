#\!/bin/bash
# Mac M4 软件包简化更新脚本 - Ubuntu兼容版

CACHE_DIR="/home/atai/software-cache"
LOG_FILE="$CACHE_DIR/update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "======================================"
echo "[$TIMESTAMP] 开始更新Mac M4软件缓存"
echo "======================================"

# 检查网络连接
if \! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "[$TIMESTAMP] 网络连接失败" >> "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] 网络连接正常" >> "$LOG_FILE"

# 更新软件函数
update_software() {
    local name="$1"
    local url="$2"
    local filename="$3"
    local dir="$CACHE_DIR/macos-arm"
    
    echo "[$TIMESTAMP] 检查 $name..." >> "$LOG_FILE"
    
    if [ -f "$dir/$filename" ]; then
        # 获取本地文件大小
        local local_size=$(stat -c%s "$dir/$filename" 2>/dev/null || echo 0)
        
        # 获取远程文件大小
        local remote_size=$(curl -sI "$url" --connect-timeout 30 --max-time 60 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r' | head -1)
        
        # 如果无法获取远程大小，设为0
        if [ -z "$remote_size" ]; then
            remote_size=0
        fi
        
        # 检查是否需要更新
        if [ "$remote_size" \!= "0" ] && [ "$remote_size" \!= "$local_size" ] && [ "$remote_size" -gt 1000000 ]; then
            echo "[$TIMESTAMP] 更新 $name (大小变化: $local_size -> $remote_size)" >> "$LOG_FILE"
            
            # 备份原文件
            cp "$dir/$filename" "$dir/$filename.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
            
            # 下载到临时文件
            if wget -q --timeout=300 --tries=2 -O "$dir/$filename.tmp" "$url"; then
                local downloaded_size=$(stat -c%s "$dir/$filename.tmp" 2>/dev/null || echo 0)
                if [ "$downloaded_size" -gt 1000000 ]; then
                    mv "$dir/$filename.tmp" "$dir/$filename"
                    echo "[$TIMESTAMP] ✓ $name 更新成功 ($(du -h "$dir/$filename" | cut -f1))" >> "$LOG_FILE"
                else
                    rm -f "$dir/$filename.tmp"
                    echo "[$TIMESTAMP] ✗ $name 下载文件太小" >> "$LOG_FILE"
                fi
            else
                rm -f "$dir/$filename.tmp"
                echo "[$TIMESTAMP] ✗ $name 下载失败" >> "$LOG_FILE"
            fi
        else
            echo "[$TIMESTAMP] $name 已是最新版本 (大小: $local_size)" >> "$LOG_FILE"
        fi
    else
        echo "[$TIMESTAMP] 下载新软件 $name" >> "$LOG_FILE"
        if wget -q --timeout=300 --tries=2 -O "$dir/$filename" "$url"; then
            local downloaded_size=$(stat -c%s "$dir/$filename" 2>/dev/null || echo 0)
            if [ "$downloaded_size" -gt 1000000 ]; then
                echo "[$TIMESTAMP] ✓ $name 下载成功 ($(du -h "$dir/$filename" | cut -f1))" >> "$LOG_FILE"
            else
                rm -f "$dir/$filename"
                echo "[$TIMESTAMP] ✗ $name 下载文件太小，删除" >> "$LOG_FILE"
            fi
        else
            rm -f "$dir/$filename"
            echo "[$TIMESTAMP] ✗ $name 下载失败" >> "$LOG_FILE"
        fi
    fi
}

echo "[$TIMESTAMP] 开始检查软件更新..." >> "$LOG_FILE"

# 更新软件列表 - 使用正确的文件名和可靠的下载链接
update_software "Telegram" "https://updates.tdesktop.com/tmac/Telegram.dmg" "Telegram_M.dmg"
sleep 2

update_software "Chrome" "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg" "Chrome_M.dmg"
sleep 2

update_software "Docker Desktop" "https://desktop.docker.com/mac/main/arm64/Docker.dmg" "Docker_M.dmg"
sleep 2

update_software "Visual Studio Code" "https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64" "VSCode_ARM64.zip"
sleep 2

# 跳过我们手动管理的软件包
echo "[$TIMESTAMP] 跳过手动管理的软件包: ChatGPT, Wave Terminal, ClashVerge, WPS Office, Traefik" >> "$LOG_FILE"
echo "[$TIMESTAMP] 跳过旧版本软件包: WeChat (保持现有版本), Git, Node.js" >> "$LOG_FILE"

echo "[$TIMESTAMP] 更新检查完成" >> "$LOG_FILE"
echo "======================================"

# 显示软件包状态
echo "" >> "$LOG_FILE"
echo "[$TIMESTAMP] 当前软件包状态:" >> "$LOG_FILE"
cd "$CACHE_DIR/macos-arm"
for file in *.dmg *.pkg *.zip *.tar.gz; do
    if [ -f "$file" ]; then
        size=$(du -h "$file" | cut -f1)
        mtime=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
        echo "  $file: $size (更新: $mtime)" >> "$LOG_FILE"
    fi
done
echo "" >> "$LOG_FILE"

echo "[$TIMESTAMP] Mac M4软件缓存更新完成" >> "$LOG_FILE"
