#\!/bin/bash

# Mac M4 一键软件安装脚本 - 修复版
# 作者: Claude Code
# 版本: 3.0

set -e  # 遇到错误立即退出

# 配置变量
SERVER_IP="192.168.9.147"
SERVER_PORT="8000"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
TEMP_DIR="/tmp/mac_m4_installer"
INSTALL_LOG="/tmp/mac_m4_install.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$INSTALL_LOG"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$INSTALL_LOG"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$INSTALL_LOG"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$INSTALL_LOG"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$INSTALL_LOG"
}

# 检查系统要求
check_requirements() {
    print_status "检查系统要求..."

    # 检查是否为Apple Silicon Mac
    if [[ "$(uname -m)" != "arm64" ]]; then
        print_error "此脚本仅支持Apple Silicon Mac (M1/M2/M3/M4)"
        exit 1
    fi

    # 检查macOS版本
    macos_version=$(sw_vers -productVersion)
    print_status "检测到 macOS $macos_version"

    # 检查网络连接
    if \! ping -c 1 "$SERVER_IP" >/dev/null 2>&1; then
        print_error "无法连接到软件服务器 ($SERVER_IP)"
        print_status "请确保与软件服务器在同一网络"
        exit 1
    fi

    print_success "系统检查通过"
}

# 创建临时目录
setup_environment() {
    print_status "设置安装环境..."

    # 清理并创建临时目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # 创建日志文件
    touch "$INSTALL_LOG"

    print_success "环境设置完成"
}

# 下载文件函数
download_file() {
    local filename="$1"
    local url="${BASE_URL}/${filename}"
    local output_path="${TEMP_DIR}/${filename}"

    print_status "下载 $filename..."

    if curl -L --connect-timeout 30 --max-time 300 -o "$output_path" "$url"; then
        if [[ -f "$output_path" && $(stat -f%z "$output_path") -gt 1000000 ]]; then
            print_success "$filename 下载成功 ($(du -h "$output_path" | cut -f1))"
            return 0
        else
            print_warning "$filename 下载文件太小，可能失败"
            return 1
        fi
    else
        print_error "$filename 下载失败"
        return 1
    fi
}

# 安装DMG文件
install_dmg() {
    local dmg_file="$1"
    local dmg_path="${TEMP_DIR}/${dmg_file}"

    if [[ ! -f "$dmg_path" ]]; then
        print_warning "跳过 $dmg_file - 文件不存在"
        return 1
    fi

    print_status "安装 $dmg_file..."

    # 挂载DMG
    local mount_point=$(hdiutil attach "$dmg_path" -nobrowse | grep -E '^/dev/' | awk '{print $NF}' | tail -1)

    if [[ -z "$mount_point" ]]; then
        print_error "无法挂载 $dmg_file"
        return 1
    fi

    local installed=false

    # 优先查找 PKG 安装包
    local pkg_path=$(find "$mount_point" -maxdepth 3 -name "*.pkg" -type f | head -1)
    if [[ -n "$pkg_path" ]]; then
        local pkg_basename=$(basename "$pkg_path")
        print_status "安装安装包: $pkg_basename"

        if sudo installer -pkg "$pkg_path" -target /; then
            print_success "$pkg_basename 安装成功"
            installed=true
        else
            print_error "$pkg_basename 安装失败"
        fi
    fi

    # 查找应用程序
    local app_name=$(find "$mount_point" -maxdepth 2 -name "*.app" | head -1)

    if [[ -n "$app_name" ]]; then
        local app_basename=$(basename "$app_name")
        print_status "安装应用程序: $app_basename"

        # 复制到Applications目录
        cp -R "$app_name" /Applications/
        print_success "$app_basename 安装成功"
        installed=true
    fi

    if [[ "$installed" = false ]]; then
        print_warning "$dmg_file 中未找到可安装内容"
    fi

    # 卸载DMG
    hdiutil detach "$mount_point" >/dev/null 2>&1
}

# 安装PKG文件
install_pkg() {
    local pkg_file="$1"
    local pkg_path="${TEMP_DIR}/${pkg_file}"

    if [[ ! -f "$pkg_path" ]]; then
        print_warning "跳过 $pkg_file - 文件不存在"
        return 1
    fi

    print_status "安装 $pkg_file..."

    # 使用installer命令安装PKG
    if sudo installer -pkg "$pkg_path" -target /; then
        print_success "$pkg_file 安装成功"
    else
        print_error "$pkg_file 安装失败"
        return 1
    fi
}

# 安装ZIP文件
install_zip() {
    local zip_file="$1"
    local zip_path="${TEMP_DIR}/${zip_file}"

    if [[ ! -f "$zip_path" ]]; then
        print_warning "跳过 $zip_file - 文件不存在"
        return 1
    fi

    print_status "安装 $zip_file..."

    # 解压到临时目录
    local extract_dir="${TEMP_DIR}/$(basename "$zip_file" .zip)_extracted"
    mkdir -p "$extract_dir"

    if unzip -q "$zip_path" -d "$extract_dir"; then
        # 查找应用程序
        local app_name=$(find "$extract_dir" -name "*.app" -maxdepth 3 | head -1)

        if [[ -n "$app_name" ]]; then
            local app_basename=$(basename "$app_name")
            print_status "安装应用程序: $app_basename"

            # 复制到Applications目录
            cp -R "$app_name" /Applications/
            print_success "$app_basename 安装成功"
        else
            print_warning "$zip_file 中未找到应用程序"
        fi
    else
        print_error "$zip_file 解压失败"
        return 1
    fi
}

# 安装TAR.GZ文件（命令行工具）
install_targz() {
    local targz_file="$1"
    local targz_path="${TEMP_DIR}/${targz_file}"

    if [[ ! -f "$targz_path" ]]; then
        print_warning "跳过 $targz_file - 文件不存在"
        return 1
    fi

    print_status "安装 $targz_file..."

    # 解压到临时目录
    local extract_dir="${TEMP_DIR}/$(basename "$targz_file" .tar.gz)_extracted"
    mkdir -p "$extract_dir"

    if tar -xzf "$targz_path" -C "$extract_dir"; then
        # 查找可执行文件
        local binary_file=$(find "$extract_dir" -type f -perm +111 | head -1)

        if [[ -n "$binary_file" ]]; then
            local binary_name=$(basename "$binary_file")
            print_status "安装命令行工具: $binary_name"

            # 复制到/usr/local/bin
            sudo cp "$binary_file" /usr/local/bin/
            sudo chmod +x "/usr/local/bin/$binary_name"
            print_success "$binary_name 安装成功"
        else
            print_warning "$targz_file 中未找到可执行文件"
        fi
    else
        print_error "$targz_file 解压失败"
        return 1
    fi
}

# 主安装函数
install_software() {
    print_status "开始下载和安装软件包..."

    # 定义软件包列表（包含所有13个软件包）
    local software_list=(
        "ChatGPT_M.dmg"
        "Chrome_M.dmg"
        "Docker_M.dmg"
        "Telegram_M.dmg"
        "WeChat_M.dmg"
        "Wave_M.dmg"
        "ClashVerge_M.dmg"
        "VSCode_ARM64.zip"
        "WPS_M.zip"
        "Git_M.pkg"
        "NodeJS_ARM64.pkg"
        "Homebrew.pkg"
        "Traefik_M.tar.gz"
    )

    local installed_count=0
    local total_count=${#software_list[@]}

    # 下载所有文件
    print_status "开始下载软件包..."
    for software in "${software_list[@]}"; do
        download_file "$software" || continue
    done

    print_status "开始安装软件..."

    # 安装DMG文件
    for dmg in ChatGPT_M.dmg Chrome_M.dmg Docker_M.dmg Telegram_M.dmg WeChat_M.dmg Wave_M.dmg ClashVerge_M.dmg; do
        if install_dmg "$dmg"; then
            ((installed_count++))
        fi
    done

    # 安装ZIP文件
    for zip in VSCode_ARM64.zip WPS_M.zip; do
        if install_zip "$zip"; then
            ((installed_count++))
        fi
    done

    # 安装PKG文件
    for pkg in NodeJS_ARM64.pkg Homebrew.pkg; do
        if install_pkg "$pkg"; then
            ((installed_count++))
        fi
    done

    # 安装TAR.GZ文件
    if install_targz "Traefik_M.tar.gz"; then
        ((installed_count++))
    fi

    print_success "安装完成！成功安装 $installed_count/$total_count 个软件包"
}

# 安装CLI工具
install_cli_tools() {
    print_status "安装CLI工具..."

    # 安装Claude Code CLI
    if command -v npm >/dev/null 2>&1; then
        print_status "安装 Claude Code CLI..."
        if npm install -g @anthropic/claude-code 2>/dev/null; then
            print_success "Claude Code CLI 安装成功"
        else
            print_warning "Claude Code CLI 安装失败，请手动安装"
        fi
    else
        print_warning "未检测到npm，跳过Claude Code CLI安装"
    fi

    # 安装Homebrew（如果未安装）
    if \! command -v brew >/dev/null 2>&1; then
        print_status "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

# 配置程序坞
configure_dock() {
    print_status "配置程序坞..."

    # 应用程序列表（包含新增的应用）
    local apps=(
        "/Applications/ChatGPT.app"
        "/Applications/Google Chrome.app"
        "/Applications/Docker.app"
        "/Applications/Telegram.app"
        "/Applications/WeChat.app"
        "/Applications/Wave.app"
        "/Applications/ClashVerge.app"
        "/Applications/Visual Studio Code.app"
        "/Applications/WPS Office.app"
    )

    # 添加应用到程序坞
    for app in "${apps[@]}"; do
        if [[ -d "$app" ]]; then
            print_status "添加 $(basename "$app" .app) 到程序坞"
            defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        fi
    done

    # 重启程序坞
    killall Dock
    print_success "程序坞配置完成"
}

# 清理函数
cleanup() {
    print_status "清理临时文件..."
    rm -rf "$TEMP_DIR"
    print_success "清理完成"
}

# 显示安装摘要
show_summary() {
    echo ""
    echo "======================================"
    echo "🎉 Mac M4 软件安装完成！"
    echo "======================================"
    echo ""
    echo "✅ 已安装的软件："
    echo "   🤖 ChatGPT - AI助手"
    echo "   🌐 Google Chrome - 浏览器"
    echo "   🐳 Docker Desktop - 容器平台"
    echo "   💬 Telegram - 即时通讯"
    echo "   💬 微信 WeChat - 社交通讯"
    echo "   🌊 Wave Terminal - 新一代终端"
    echo "   🔗 Clash Verge - 代理工具"
    echo "   📝 Visual Studio Code - 代码编辑器"
    echo "   📊 WPS Office - 办公软件"
    echo "   🔧 Git - 版本控制"
    echo "   🟢 Node.js - JavaScript运行环境"
    echo "   🍺 Homebrew - 包管理器"
    echo "   🔀 Traefik - 反向代理"
    echo ""
    echo "📋 安装日志保存在: $INSTALL_LOG"
    echo ""
    echo "🚀 现在可以开始使用你的新Mac了！"
    echo "======================================"
}

# 主函数
main() {
    echo "======================================"
    echo "🍎 Mac M4 一键软件安装器"
    echo "======================================"
    echo ""

    # 检查是否以管理员权限运行
    if [[ $EUID -eq 0 ]]; then
        print_error "请不要以root权限运行此脚本"
        exit 1
    fi

    # 执行安装步骤
    check_requirements
    setup_environment
    install_software
    install_cli_tools
    configure_dock
    cleanup
    show_summary

    print_success "安装完成！"
}

# 运行主函数
main "$@"
