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

with_github_mirror() {
    local url="$1"

    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*|https://api.github.com/*|https://objects.githubusercontent.com/*)
            local stripped="${url#https://}"
            echo "https://mirror.ghproxy.com/${stripped}"
            ;;
        *)
            echo "$url"
            ;;
    esac
}

log_line "网络连接正常"

FAILED_UPDATES=()

get_remote_size() {
    local url="$1"
    curl -sIL --connect-timeout 30 --max-time 60 -A "$USER_AGENT" "$url" 2>/dev/null |
        awk 'BEGIN {IGNORECASE=1} /^content-length/ {gsub("\\r", ""); print $2; exit}'
}

_download_with_clients() {
    local url="$1"
    local dest="$2"

    if curl -fL --connect-timeout 30 --max-time 1200 --retry 3 --retry-delay 5 -C - -A "$USER_AGENT" -o "$dest" "$url"; then
        return 0
    fi

    wget --quiet --timeout=600 --tries=3 --continue -U "$USER_AGENT" -O "$dest" "$url"
}

download_to_temp() {
    local url="$1"
    local dest="$2"

    local mirrored
    mirrored=$(with_github_mirror "$url")

    if [[ "$mirrored" != "$url" ]]; then
        if _download_with_clients "$mirrored" "$dest"; then
            return 0
        fi
        rm -f "$dest"
    fi

    _download_with_clients "$url" "$dest"
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

    local resolved_url
    resolved_url=$(with_github_mirror "$url")

    local remote_size="$(get_remote_size "$resolved_url" || true)"
    if [[ -z "$remote_size" || "$remote_size" == "0" ]] && [[ "$resolved_url" != "$url" ]]; then
        remote_size="$(get_remote_size "$url" || true)"
    fi
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
                FAILED_UPDATES+=("$name: 文件太小")
                return 1
            else
                rm -f "$target.tmp"
                log_line "✗ $name 下载失败"
                FAILED_UPDATES+=("$name: 下载失败")
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
        FAILED_UPDATES+=("$name: 文件太小")
        return 1
    fi
    rm -f "$target"
    log_line "✗ $name 下载失败"
    FAILED_UPDATES+=("$name: 下载失败")
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
update_nodejs_pkg() {
    local name="$1"
    local filename="$2"
    local min_size="${3:-50000000}"
    local url="https://nodejs.org/dist/latest/node-latest.pkg"

    if ! update_software "$name" "$url" "$filename" "$min_size"; then
        FAILED_UPDATES+=("$name: 下载失败")
        return 1
    fi

    if [[ ! -s "$SOFTWARE_DIR/$filename" ]]; then
        FAILED_UPDATES+=("$name: 文件缺失或为空")
        return 1
    fi

    return 0
}

get_latest_trae_pkg_url() {
    local api="https://api.trae.ai/icube/api/v1/native/version/trae/latest"
    local headers=(-H "Accept: application/json" -H "User-Agent: $USER_AGENT")
    local response

    response=$(curl -sL "${headers[@]}" "$api" || true)
    if [[ -z "$response" ]]; then
        log_line "✗ Trae 接口无响应"
        return 1
    fi

    local parsed=""

    if command -v python3 >/dev/null 2>&1; then
        parsed=$(printf '%s' "$response" | python3 - <<'PY'
import json
import sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
manifest = (((data or {}).get("data") or {}).get("manifest") or {}).get("darwin") or {}
downloads = manifest.get("download") or []
if isinstance(downloads, dict):
    downloads = downloads.values()
for item in downloads:
    if isinstance(item, dict):
        candidate = item.get("apple") or item.get("url") or next((v for v in item.values() if isinstance(v, str) and v.startswith("http")), None)
        if candidate:
            print(candidate)
            sys.exit(0)
    elif isinstance(item, str) and item.startswith("http"):
        print(item)
        sys.exit(0)
url = manifest.get("apple")
if isinstance(url, str) and url.startswith("http"):
    print(url)
    sys.exit(0)
PY
        ) || parsed=""
    fi

    if [[ -z "$parsed" ]] && command -v node >/dev/null 2>&1; then
        parsed=$(printf '%s' "$response" | node <<'NODE'
const fs = require('fs');
try {
  const data = JSON.parse(fs.readFileSync(0, 'utf8'));
  const manifest = (((data || {}).data || {}).manifest || {}).darwin || {};
  let downloads = manifest.download || [];
  if (downloads && typeof downloads === 'object' && !Array.isArray(downloads)) {
    downloads = Object.values(downloads);
  }
  const pick = item => {
    if (!item) return null;
    if (typeof item === 'string') return item.startsWith('http') ? item : null;
    if (typeof item === 'object') {
      return item.apple || item.url || Object.values(item).find(v => typeof v === 'string' && v.startswith('http')) || null;
    }
    return null;
  };
  for (const item of downloads) {
    const candidate = pick(item);
    if (candidate) {
      console.log(candidate);
      process.exit(0);
    }
  }
  const fallback = pick(manifest.apple);
  if (fallback) {
    console.log(fallback);
    process.exit(0);
  }
} catch (err) {
  process.exit(1);
}
process.exit(1);
NODE
        ) || parsed=""
    fi

    if [[ -z "$parsed" ]]; then
        parsed=$(printf '%s\n' "$response" | sed -n "s/.*\"apple\":\"\(https:\/\/[^\"]*\)\".*/\1/p" | head -1)
    fi

    if [[ -z "$parsed" ]]; then
        log_line "✗ Trae 接口返回异常或解析失败"
        return 1
    fi

    printf "%s\n" "$parsed"
}
update_trae_pkg() {
    local name="$1"
    local filename="$2"
    local min_size="${3:-60000000}"
    local url

    url=$(get_latest_trae_pkg_url) || true
    if [[ -z "$url" ]]; then
        log_line "✗ $name 未能解析最新版本"
        FAILED_UPDATES+=("$name: 解析失败")
        return 1
    fi

    update_software "$name" "$url" "$filename" "$min_size"
    return $?
}

# Homebrew 最新 pkg
get_latest_homebrew_pkg_url() {
    local api="https://api.github.com/repos/Homebrew/brew/releases/latest"
    local headers
    mapfile -t headers < <(github_headers)
    curl -sL "${headers[@]}" "$api"         | grep -oE '"browser_download_url"\s*:\s*"[^"]+\.pkg"'         | head -1         | cut -d'"' -f4
}

update_homebrew_pkg() {
    local name="$1"
    local filename="$2"
    local min_size="${3:-20000000}"
    local url

    url=$(get_latest_homebrew_pkg_url) || true
    if [[ -z "$url" ]]; then
        log_line "✗ $name 未能解析最新版本"
        return 1
    fi

    update_software "$name" "$url" "$filename" "$min_size"
}

# Git 最新 pkg (基于 SourceForge 下载列表)
get_latest_git_pkg_url() {
    local api_json="https://sourceforge.net/projects/git-osx-installer/best_release.json?platform=mac"
    local listing_url="https://sourceforge.net/projects/git-osx-installer/files/?source=navbar"
    local json
    local listing
    local parsed=""

    json=$(curl -sL -A "$USER_AGENT" "$api_json" || true)
    if [[ -n "$json" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            parsed=$(printf '%s' "$json" | python3 - <<'PY'
import json
import sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
url = (data or {}).get('url')
if isinstance(url, str) and url.startswith('http'):
    print(url)
    sys.exit(0)
PY
            ) || parsed=""
        fi
        if [[ -z "$parsed" ]]; then
            parsed=$(printf '%s' "$json" | grep -oE '"url"\s*:\s*"https?://[^"\"]+' | head -1 | sed -E 's/.*"(https?:\/\/[^"\"]+)"/\1/')
        fi
        if [[ -n "$parsed" ]]; then
            printf '%s\n' "$parsed"
            return 0
        fi
    fi

    listing=$(curl -sL -A "$USER_AGENT" "$listing_url" || true)
    if [[ -n "$listing" ]] && command -v python3 >/dev/null 2>&1; then
        parsed=$(printf '%s' "$listing" | python3 - <<'PY'
import re
import sys
html = sys.stdin.read()
pattern = re.compile(r'/projects/git-osx-installer/files/[^"]*/(git-[^"/]*(?:arm64|universal)[^"/]*\.dmg)/download', re.IGNORECASE)
match = pattern.search(html)
if match:
    print(match.group(1))
PY
        ) || parsed=""
    fi
    if [[ -z "$parsed" ]]; then
        parsed=$(printf '%s' "$listing" | grep -oE '/projects/git-osx-installer/files/[^"?]*/(git-[^"/]*(arm64|universal)[^"/]*\.dmg)/download' | head -1 | sed -E 's#.*/(git-[^/]+\.dmg)/download#\1#')
    fi
    if [[ -n "$parsed" ]]; then
        printf 'https://downloads.sourceforge.net/project/git-osx-installer/%s\n' "$parsed"
        return 0
    fi

    local fallback_url="https://downloads.sourceforge.net/project/git-osx-installer/latest/download?source=files"
    log_line "⚠ Git 列表解析失败，使用 latest/download"
    printf '%s\n' "$fallback_url"
    return 0
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

    if update_software "$name" "$url" "$filename" "$min_size"; then
        return 0
    fi

    log_line "✗ $name 主下载失败，尝试备用镜像"
    local fallback_url="https://mirrors.edge.kernel.org/pub/software/scm/git/mac/$(basename "$url")"
    if update_software "$name" "$fallback_url" "$filename" "$min_size"; then
        return 0
    fi

    log_line "✗ $name 镜像下载失败"
    return 1
}


log_line "开始检查软件更新..."

update_software "ChatGPT" "https://persistent.oaistatic.com/sidekick/public/ChatGPT.dmg" "ChatGPT_M.dmg" 40000000
sleep 2

update_software "Telegram" "https://osx.telegram.org/updates/Telegram.dmg" "Telegram_M.dmg" 80000000
sleep 2

update_software "Google Chrome" "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg" "Chrome_M.dmg" 150000000
sleep 2

update_software "Docker Desktop" "https://desktop.docker.com/mac/main/arm64/Docker.dmg" "Docker_M.dmg" 300000000
sleep 2

update_software "WeChat" "https://dldir1v6.qq.com/weixin/Universal/Mac/WeChatMac.dmg" "WeChat_M.dmg" 150000000
sleep 2

update_from_github "Wave Terminal" "wavetermdev/waveterm" "Wave-darwin-arm64.*\\.dmg$" "Wave_M.dmg" 60000000
sleep 2

update_trae_pkg "Trae" "Trae_M.dmg" 60000000
sleep 2

update_software "Qoder" "https://download.qoder.com/release/latest/Qoder-darwin-arm64.dmg" "Qoder_M.dmg" 60000000
sleep 2

update_from_github "Clash Verge" "clash-verge-rev/clash-verge-rev" "(arm64|aarch64).*\\.dmg$" "ClashVerge_M.dmg" 20000000
sleep 2

update_software "Visual Studio Code" "https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64" "VSCode_ARM64.zip" 60000000
sleep 2

update_software "WPS Office" "https://package.mac.wpscdn.cn/mac_wps_pkg/wps_installer/WPS_Office_Installer.zip" "WPS_M.zip" 5000000
sleep 2

sleep 2

update_homebrew_pkg "Homebrew" "Homebrew.pkg" 20000000
sleep 2

update_nodejs_pkg "Node.js" "NodeJS_ARM64.pkg" 50000000
sleep 2

update_from_github "Traefik" "traefik/traefik" "traefik_v.*darwin_arm64\\.tar\\.gz$" "Traefik_M.tar.gz" 10000000
sleep 2

log_line "更新检查完成"

if (( ${#FAILED_UPDATES[@]} > 0 )); then
    log_line "以下软件更新失败:"
    for item in "${FAILED_UPDATES[@]}"; do
        log_line "  - $item"
    done
else
    log_line "本次所有软件均更新成功"
fi
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
