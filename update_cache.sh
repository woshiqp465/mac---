#!/bin/bash
# Mac M4 软件包自动更新脚本 - 扩展版

set -uo pipefail

CACHE_DIR="/home/atai/software-cache"
SOFTWARE_DIR="$CACHE_DIR/macos-arm"
LOG_FILE="$CACHE_DIR/update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
USER_AGENT="mac-m4-cache/1.1"

mkdir -p "$SOFTWARE_DIR" "$CACHE_DIR"
touch "$LOG_FILE"
INITIAL_LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

echo "======================================"
echo "[$TIMESTAMP] 开始更新Mac M4软件缓存"
echo "======================================"

log_line() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查网络连接
if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_line "网络连接失败"
    exit 1
fi

log_line "网络连接正常"

get_remote_size() {
    local url="$1"
    curl -sIL --connect-timeout 30 --max-time 60 -A "$USER_AGENT" "$url" 2>/dev/null |
        awk 'BEGIN {IGNORECASE=1} /^content-length/ {gsub("\\r", ""); print $2; exit}'
}

download_to_temp() {
    local url="$1"
    local dest="$2"

    if curl -fL --connect-timeout 30 --max-time 300 -A "$USER_AGENT" -o "$dest" "$url"; then
        return 0
    fi

    wget -q --timeout=300 --tries=2 -U "$USER_AGENT" -O "$dest" "$url"
}

# 基础更新函数，可设置文件大小阈值
update_software() {
    local name="$1"
    local url="$2"
    local filename="$3"
    local min_size="${4:-1000000}"
    local dir="$SOFTWARE_DIR"
    local target="$dir/$filename"

    log_line "检查 $name..."

    local remote_size="$(get_remote_size "$url" || true)"
    if [[ -z "$remote_size" ]]; then
        remote_size=0
    fi

    if [[ -f "$target" ]]; then
        local local_size
        local_size=$(stat -c%s "$target" 2>/dev/null || echo 0)

        if [[ "$remote_size" != "0" && "$remote_size" != "$local_size" && "$remote_size" -ge "$min_size" ]]; then
            log_line "更新 $name (大小变化: $local_size -> $remote_size)"
            cp "$target" "$target.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true

            if download_to_temp "$url" "$target.tmp"; then
                local downloaded_size
                downloaded_size=$(stat -c%s "$target.tmp" 2>/dev/null || echo 0)
                if [[ "$downloaded_size" -ge "$min_size" ]]; then
                    mv "$target.tmp" "$target"
                    log_line "✓ $name 更新成功 ($(du -h "$target" | cut -f1))"
                    return 0
                fi
                rm -f "$target.tmp"
                log_line "✗ $name 下载文件太小"
                return 1
            else
                rm -f "$target.tmp"
                log_line "✗ $name 下载失败"
                return 1
            fi
        else
            log_line "$name 已是最新版本 (大小: $local_size)"
            return 0
        fi
    fi

    log_line "下载新软件 $name"
    if download_to_temp "$url" "$target"; then
        local downloaded_size
        downloaded_size=$(stat -c%s "$target" 2>/dev/null || echo 0)
        if [[ "$downloaded_size" -ge "$min_size" ]]; then
            log_line "✓ $name 下载成功 ($(du -h "$target" | cut -f1))"
            return 0
        fi
        rm -f "$target"
        log_line "✗ $name 下载文件太小，删除"
        return 1
    fi
    rm -f "$target"
    log_line "✗ $name 下载失败"
    return 1
}

# GitHub Release 更新
github_headers() {
    local headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: $USER_AGENT")
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28")
    fi
    printf '%s\n' "${headers[@]}"
}

get_github_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local headers
    mapfile -t headers < <(github_headers)
    curl -sL "${headers[@]}" "$api_url" |
        grep -oE '"browser_download_url"\s*:\s*"[^"]+"' |
        cut -d'"' -f4 |
        grep -E "$pattern" |
        head -1
}

update_from_github() {
    local name="$1"
    local repo="$2"
    local pattern="$3"
    local filename="$4"
    local min_size="${5:-1000000}"
    local url

    url=$(get_github_asset_url "$repo" "$pattern") || true
    if [[ -z "$url" ]]; then
        log_line "✗ $name 未找到匹配 $pattern 的 GitHub 资源"
        return 1
    fi

    update_software "$name" "$url" "$filename" "$min_size"
}

# Node.js 最新 pkg
get_latest_node_pkg_url() {
    local channel="${1:-latest}"
    local base="https://nodejs.org/dist/$channel/"
    local pkg_name
    pkg_name=$(curl -sL -A "$USER_AGENT" "${base}SHASUMS256.txt" | awk '/darwin-arm64\\.pkg/ {print $2; exit}')
    if [[ -z "$pkg_name" ]]; then
        return 1
    fi
    printf '%s\n' "${base}${pkg_name}"
}

update_nodejs_pkg() {
    local name="$1"
    local filename="$2"
    local min_size="${3:-50000000}"
    local url

    url=$(get_latest_node_pkg_url "latest") || true
    if [[ -z "$url" ]]; then
        log_line "✗ $name 未能解析最新版本"
        return 1
    fi

    update_software "$name" "$url" "$filename" "$min_size"
}

# Git 最新 pkg (基于 SourceForge 命名规则)
get_latest_git_pkg_url() {
    local api="https://api.github.com/repos/git/git/tags?per_page=1"
    local headers
    mapfile -t headers < <(github_headers)
    local version
    version=$(curl -sL "${headers[@]}" "$api" | grep -m1 '"name"' | sed -E 's/.*"v?([0-9]+\\.[0-9]+\\.[0-9]+)".*/\1/')
    if [[ -z "$version" ]]; then
        return 1
    fi
    printf '%s\n' "https://downloads.sourceforge.net/project/git-osx-installer/git-${version}-arm64-big-sur.pkg"
}

update_git_pkg() {
    local name="$1"
    local filename="$2"
    local min_size="${3:-20000000}"
    local url

    url=$(get_latest_git_pkg_url) || true
    if [[ -z "$url" ]]; then
        log_line "✗ $name 未能解析最新版本"
        return 1
    fi

    update_software "$name" "$url" "$filename" "$min_size"
}

log_line "开始检查软件更新..."

update_software "ChatGPT" "https://persistent.oaistatic.com/sidekick/public/ChatGPT.dmg" "ChatGPT_M.dmg" 40000000
sleep 2

update_software "Telegram" "https://updates.tdesktop.com/tmac/Telegram.dmg" "Telegram_M.dmg" 80000000
sleep 2

update_software "Google Chrome" "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg" "Chrome_M.dmg" 150000000
sleep 2

update_software "Docker Desktop" "https://desktop.docker.com/mac/main/arm64/Docker.dmg" "Docker_M.dmg" 300000000
sleep 2

update_software "WeChat" "https://dldir1.qq.com/weixin/mac/WeChatMac.dmg" "WeChat_M.dmg" 150000000
sleep 2

update_software "Warp Terminal" "https://releases.warp.dev/stable/latest/mac/Warp-macOS-arm64.dmg" "Warp_M.dmg" 60000000
sleep 2

update_software "Wave Terminal" "https://download.wave.gg/Wave-latest-arm64.dmg" "Wave_M.dmg" 60000000
sleep 2

update_from_github "Clash Verge" "clash-verge-rev/clash-verge-rev" "(arm64|aarch64).*\\.dmg$" "ClashVerge_M.dmg" 20000000
sleep 2

update_software "Visual Studio Code" "https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64" "VSCode_ARM64.zip" 60000000
sleep 2

update_software "WPS Office" "https://wdl1.cache.wpscdn.com/wps/download/mac/latest/WPSOffice_arm64.zip" "WPS_M.zip" 5000000
sleep 2

update_git_pkg "Git" "Git_M.pkg" 20000000
sleep 2

update_nodejs_pkg "Node.js" "NodeJS_ARM64.pkg" 50000000
sleep 2

update_from_github "Traefik" "traefik/traefik" "traefik_v.*darwin_arm64\\.tar\\.gz$" "Traefik_M.tar.gz" 10000000
sleep 2

log_line "更新检查完成"
echo "======================================"

log_line "当前软件包状态:"
cd "$SOFTWARE_DIR"
for file in *.dmg *.pkg *.zip *.tar.gz; do
    if [[ -f "$file" ]]; then
        size=$(du -h "$file" | cut -f1)
        mtime=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
        log_line "  $file: $size (更新: $mtime)"
    fi
done

log_line "Mac M4软件缓存更新完成"

start_line=$((INITIAL_LOG_LINES + 1))
current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
if (( start_line <= current_lines )); then
    echo ""
    echo "本次更新日志："
    tail -n +"$start_line" "$LOG_FILE"
else
    echo ""
    echo "本次更新未生成新的日志条目。"
fi
