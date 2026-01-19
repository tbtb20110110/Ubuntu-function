#!/bin/bash
set -euo pipefail

# ==================== 自定义配置项（用户可修改） ====================
TERMINAL_COLOR_SCHEME="16"
WIN11_THEME_STYLE="light"
GRUB_THEME="win10dark"
FONT_NAME="MesloLGS NF"
# ====================================================================

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用sudo权限运行：sudo bash $0"
        exit 1
    fi
}

# 检查系统版本
check_ubuntu_version() {
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 22.04\|Ubuntu 24.04"; then
        echo "⚠️  当前系统非Ubuntu 22.04/24.04 LTS，可能兼容问题"
        read -p "是否继续？(y/n): " choice
        [ "$choice" != "y" ] && exit 0
    fi
}

# 修复架构问题（核心防坑步骤）
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

# 系统准备（源配置+依赖安装+PPA源修复）
stage_prepare() {
    echo -e "\n========== 阶段1：系统准备 =========="
    echo "🔧 安装源管理工具..."
    apt install -y software-properties-common

    echo "🔧 启用官方软件源组件..."
    add-apt-repository main restricted universe multiverse -y
    apt update -y && apt upgrade -y

    echo "🔧 添加 grub-customizer 官方 PPA 源（解决包定位问题）..."
    add-apt-repository ppa:danielrichter2007/grub-customizer -y
    apt update -y

    echo "📦 安装核心依赖..."
    apt install -y git wget curl unzip gnome-tweaks gnome-shell-extension-manager language-pack-zh-hans fonts-wqy-microhei fprintd libpam-fprintd grub-customizer

    echo "🌐 配置中文环境..."
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    echo "✅ 阶段1完成"
}

# 终端美化
stage_terminal() {
    echo -e "\n========== 阶段2：终端美化 =========="
    mkdir -p /tmp/fonts
    wget -qO /tmp/fonts/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip
    unzip -q /tmp/fonts/Meslo.zip -d /usr/share/fonts
    fc-cache -fv && rm -rf /tmp/fonts

    echo "🎨 安装Dracula配色..."
    echo "${TERMINAL_COLOR_SCHEME}" | bash -c "$(wget -qO- https://git.io/vQgMr)"
    echo "✅ 阶段2完成"
}

# 桌面仿Win11美化
stage_desktop() {
    echo -e "\n========== 阶段3：桌面美化 =========="
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-theme
    bash /tmp/WhiteSur-theme/install.sh -t all -i blue -c ${WIN11_THEME_STYLE}
    rm -rf /tmp/WhiteSur-theme

    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon
    bash /tmp/WhiteSur-icon/install.sh
    rm -rf /tmp/WhiteSur-icon

    gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com || true
    echo "⚠️  需手动在扩展管理器启用：Dash to Panel、Win11 Window Titlebars、Desktop Icons NG"
    echo "✅ 阶段3完成"
}

# Grub美化
stage_grub() {
    echo -e "\n========== 阶段4：Grub美化 =========="
    git clone --depth=1 https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes.git /tmp/grub-themes
    echo "${GRUB_THEME}" | bash /tmp/grub-themes/install.sh
    rm -rf /tmp/grub-themes
    update-grub
    echo "✅ 阶段4完成"
}

# 指纹适配
stage_fingerprint() {
    echo -e "\n========== 阶段5：指纹适配 =========="
    cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak
    sed -i '1i auth    sufficient    pam_fprintd.so' /etc/pam.d/common-auth
    echo "✅ 阶段5完成，重启后手动录入指纹"
}

# 主流程
main() {
    clear
    echo "======================================"
    echo "  最终版 Ubuntu 一键美化脚本（仿Win11）"
    echo "  适配：华为MateBook 15d | x86_64架构"
    echo "======================================"
    check_root
    check_ubuntu_version
    fix_architecture
    stage_prepare
    stage_terminal
    stage_desktop
    stage_grub
    stage_fingerprint

    echo -e "\n🎉 自动化配置完成！重启后执行手动步骤："
    echo "1. 终端配置字体和配色；2. 扩展管理器启用插件；3. Tweaks选主题；4. 设置录入指纹"
}

main
