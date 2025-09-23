# Mac电脑软件更新一键自动安装（服务器）

## 🍎 项目简介

这是一个为Mac M系列芯片（M1/M2/M3/M4）电脑提供软件一键批量安装和自动更新的服务器端解决方案。通过HTTP服务器提供软件包分发，支持新Mac电脑的快速软件环境配置。

## ✨ 主要功能

- 🚀 **一键安装13个常用软件**：包括开发工具、办公软件、通讯工具等
- 🔄 **15天自动更新**：智能检测软件版本，自动下载最新版本
- 🌐 **HTTP服务器分发**：通过内网HTTP服务器提供软件包下载
- 🛡️ **静态IP配置**：确保服务稳定性，支持断电重启
- 📱 **智能版本检测**：避免重复下载，节省网络带宽

## 📦 包含的软件

| 软件名称 | 功能描述 | 文件格式 | 大小 |
|---------|----------|----------|------|
| ChatGPT | AI助手 | DMG | 49MB |
| Google Chrome | 浏览器 | DMG | 214MB |
| Docker Desktop | 容器平台 | DMG | 511MB |
| Telegram | 即时通讯 | DMG | 110MB |
| 微信 WeChat | 社交通讯 | DMG | 354MB |
| Wave Terminal | 新一代终端 | DMG | 182MB |
| Clash Verge | 代理工具 | DMG | 43MB |
| Visual Studio Code | 代码编辑器 | ZIP | 147MB |
| WPS Office | 办公软件 | ZIP | 6.5MB |
| Git | 版本控制 | PKG | 24MB |
| Node.js | JavaScript运行环境 | PKG | 71MB |
| Homebrew | 包管理器 | PKG | 25MB |
| Traefik | 反向代理 | TAR.GZ | 42MB |

## 🚀 快速开始

### 服务器端部署

1. **克隆项目**
```bash
git clone https://github.com/your-username/mac-software-auto-installer.git
cd mac-software-auto-installer
```

2. **设置权限**
```bash
chmod +x *.sh
```

3. **启动HTTP服务器**
```bash
# 在软件包目录启动HTTP服务器
cd /path/to/software-cache/macos-arm
python3 -m http.server 8000 --bind 0.0.0.0
```

4. **配置自动更新**
```bash
# 添加到crontab
0 3 1,16 * * /path/to/update_cache.sh >> /path/to/update.log 2>&1
```

### 客户端使用

在新Mac mini上运行以下命令：

```bash
curl -fsSL http://YOUR_SERVER_IP:8000/quick_install.sh | bash
```

## 📋 脚本说明

### 1. quick_install.sh
- **功能**：快速启动脚本，检查网络连接并下载主安装程序
- **使用**：新Mac电脑的入口脚本

### 2. mac_m4_installer.sh
- **功能**：主安装脚本，负责下载和安装所有软件包
- **特性**：
  - 系统要求检查（Apple Silicon Mac）
  - 分类安装不同格式的软件包
  - 自动配置程序坞
  - 安装CLI工具（Claude Code CLI, Homebrew）

### 3. update_cache.sh
- **功能**：自动更新脚本，定期检查和更新软件包
- **特性**：
  - 智能版本检测（文件大小比较）
  - 自动备份旧版本
  - 详细日志记录
  - 网络连接检查

## ⚙️ 配置说明

### 网络配置
```bash
# 默认服务器配置
SERVER_IP="192.168.9.147"
SERVER_PORT="8000"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
```

### 目录结构
```
/home/atai/software-cache/
├── macos-arm/              # 软件包存储目录
│   ├── *.dmg              # Mac应用程序
│   ├── *.pkg              # 系统级安装包
│   ├── *.zip              # 压缩应用程序
│   └── *.tar.gz           # 命令行工具
├── backup/                # 自动备份目录
├── update.log             # 更新日志
└── cron.log              # 定时任务日志
```

## 🔄 自动更新机制

### 更新频率
- **定时更新**：每月1号和16号凌晨3点
- **手动更新**：随时运行 `update_cache.sh`

### 更新策略
- 比较文件大小判断是否需要更新
- 自动备份旧版本文件
- 仅更新有变化的软件包
- 跳过手动管理的特殊软件包

## 🛠️ 系统要求

### 服务器端
- Ubuntu 20.04+ 或其他Linux发行版
- Python 3.6+
- curl, wget
- 足够的存储空间（建议10GB+）

### 客户端
- macOS 11.0+
- Apple Silicon Mac (M1/M2/M3/M4)
- 网络连接到服务器
- 管理员权限

## 📊 监控和日志

### 查看更新日志
```bash
tail -f /home/atai/software-cache/update.log
```

### 查看HTTP服务器日志
```bash
tail -f /tmp/http_server.log
```

### 查看软件包状态
```bash
ls -lh /home/atai/software-cache/macos-arm/
```

## 🔧 故障排除

### 常见问题

1. **网络连接失败**
   - 检查服务器IP地址和端口
   - 确保防火墙允许8000端口访问

2. **软件包下载失败**
   - 检查HTTP服务器是否运行
   - 验证软件包文件完整性

3. **权限问题**
   - 确保脚本有执行权限
   - 检查文件夹写入权限

### 调试命令
```bash
# 测试网络连接
ping SERVER_IP

# 测试HTTP服务
curl -I http://SERVER_IP:8000/

# 检查脚本语法
bash -n script_name.sh

# 手动运行更新
bash update_cache.sh
```

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 🙏 致谢

- 感谢所有软件厂商提供优秀的Mac应用程序
- 感谢开源社区的技术支持

## 📞 联系方式

如有问题或建议，请通过以下方式联系：

- 创建 [Issue](https://github.com/your-username/mac-software-auto-installer/issues)
- 发送邮件到：your-email@example.com

---

**⚠️ 注意：使用本项目前请确保遵守相关软件的许可协议和法律法规。**