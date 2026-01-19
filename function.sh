#!/bin/bash
set -euo pipefail

# ==================== 自定义配置项（用户可修改） ====================
# 终端配色方案：Gogh脚本中Dracula配色对应编号16
TERMINAL_COLOR_SCHEME="16"
# Win11主题风格：light（浅色）/dark（深色）
WIN11_THEME_STYLE="light"
# Grub主题：win10dark（适配Win11风格）
GRUB_THEME="win10dark"
# 终端字体：Meslo Nerd Font
FONT_NAME="MesloLGS NF"
# ====================================================================

# 检查是否为root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用sudo权限运行：sudo bash $0"
        exit 1
    fi
}

# 检查系统版本兼容性
check_ubuntu_version() {
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 22.04\|Ubuntu 24.04"; then
        echo "⚠️  当前系统非Ubuntu 22.04/24.04 LTS，可能存在兼容性问题"
        read -p "是否继续执行？(y/n): " choice
        [ "$choice" != "y" ] && exit 0
    fi
}

# 修复架构问题（移除多余arm64架构）
fix_architecture() {
    echo -e "\n========== 前置修复：清理多余架构 =========="
    ARCH=$(dpkg --print-architecture)
    FOREIGN_ARCH=$(dpkg --print-foreign-architectures)
    if [ "$ARCH" = "amd64" ] && echo "$FOREIGN_ARCH" | grep -q "arm64"; then
        echo "🔧 检测到amd64架构下启用了arm64，正在移除..."
        dpkg --remove-architecture arm64
    fi
    echo "✅ 架构修复完成"
}

# 系统准备（源配置+依赖安装+国内加速安装grub-customizer）
stage_prepare() {
    echo -e "\n========== 阶段1：系统准备（国内网络友好） =========="
    echo "🔧 安装源管理工具..."
    apt install -y software-properties-common

    echo "🔧 启用官方软件源组件..."
    add-apt-repository main restricted universe multiverse -y
    apt update -y && apt upgrade -y

    echo "🔧 国内加速安装 grub-customizer（跳过PPA）..."
    # 使用GHProxy加速Launchpad下载链接
    GRUB_DEB_URL="https://mirror.ghproxy.com/https://launchpad.net/~danielrichter2007/+archive/ubuntu/grub-customizer/+files/grub-customizer_5.2.3-1ubuntu1_amd64.deb"
    wget -qO /tmp/grub-customizer.deb "${GRUB_DEB_URL}"
    
    # 判断下载是否成功
    if [ ! -f /tmp/grub-customizer.deb ]; then
        echo "❌ grub-customizer deb包下载失败，请检查网络或手动下载后放到/tmp目录"
        exit 1
    fi

    # 安装deb包并自动修复依赖
    dpkg -i /tmp/grub-customizer.deb || apt -f install -y
    rm -f /tmp/grub-customizer.deb

    echo "📦 安装核心依赖工具..."
    apt install -y git wget curl unzip gnome-tweaks gnome-shell-extension-manager language-pack-zh-hans fonts-wqy-microhei fprintd libpam-fprintd

    echo "🌐 配置系统中文环境..."
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    echo "✅ 阶段1完成"
}

# 终端美化（字体+配色）
stage_terminal() {
    echo -e "\n========== 阶段2：终端美化 =========="
    echo "🔤 安装 ${FONT_NAME} 字体..."
    mkdir -p /tmp/fonts
    wget -qO /tmp/fonts/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip
    unzip -q /tmp/fonts/Meslo.zip -d /usr/share/fonts
    fc-cache -fv
    rm -rf /tmp/fonts

    echo "🎨 安装终端配色方案（Dracula）..."
    echo "${TERMINAL_COLOR_SCHEME}" | bash -c "$(wget -qO- https://git.io/vQgMr)"
    echo "✅ 阶段2完成"
}

# 桌面美化（仿Win11风格）
stage_desktop() {
    echo -e "\n========== 阶段3：桌面仿Win11美化 =========="
    echo "🎨 安装WhiteSur GTK主题..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-theme
    bash /tmp/WhiteSur-theme/install.sh -t all -i blue -c ${WIN11_THEME_STYLE}
    rm -rf /tmp/WhiteSur-theme

    echo "🖼️  安装WhiteSur图标主题..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon
    bash /tmp/WhiteSur-icon/install.sh
    rm -rf /tmp/WhiteSur-icon

    echo "🔌 启用基础GNOME扩展..."
    gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com || true
    echo "⚠️  需手动在扩展管理器启用：Dash to Panel、Win11 Window Titlebars、Desktop Icons NG"
    echo "✅ 阶段3完成"
}

# Grub美化（双系统启动菜单）
stage_grub() {
    echo -e "\n========== 阶段4：Grub启动菜单美化 =========="
    echo "🎨 安装Win11风格Grub主题..."
    git clone --depth=1 https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes.git /tmp/grub-themes
    echo "${GRUB_THEME}" | bash /tmp/grub-themes/install.sh
    rm -rf /tmp/grub-themes

    echo "🔧 更新Grub配置..."
    update-grub
    echo "✅ 阶段4完成"
}

# 华为MateBook 15d指纹适配（登录+sudo验证）
stage_fingerprint() {
    echo -e "\n========== 阶段5：指纹适配（登录+sudo） =========="
    echo "🔧 备份PAM配置文件..."
    cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak

    echo "🔧 配置指纹用于sudo验证..."
    sed -i '1i auth    sufficient    pam_fprintd.so' /etc/pam.d/common-auth
    echo "✅ 阶段5完成，重启后需手动录入指纹"
}

# 主执行流程
main() {
    clear
    echo "======================================"
    echo "  全网友好版 Ubuntu 一键美化脚本（仿Win11）"
    echo "  适配：华为MateBook 15d | x86_64架构"
    echo "  特性：国内加速下载 | 无PPA依赖 | 架构修复"
    echo "======================================"
    check_root
    check_ubuntu_version
    fix_architecture
    stage_prepare
    stage_terminal
    stage_desktop
    stage_grub
    stage_fingerprint

    echo -e "\n🎉 所有自动化配置完成！请重启系统生效"
    echo "📌 重启后必做的手动配置步骤："
    echo "  1. 终端 → 首选项 → 配置文件 → 编辑 → 外观：字体选择 ${FONT_NAME}"
    echo "  2. 终端 → 颜色：取消系统主题，选择Dracula配色"
    echo "  3. 扩展管理器：安装并启用 Dash to Panel 等3个扩展"
    echo "  4. GNOME Tweaks → 外观：选择 WhiteSur-${WIN11_THEME_STYLE} 主题/图标"
    echo "  5. 系统设置 → 用户 → 指纹登录：点击+号录入指纹"
}

main
