#!/bin/bash
set -euo pipefail

# ==================== 配置项（用户可自定义） ====================
# 终端配色方案：Gogh脚本中Dracula配色对应编号16
TERMINAL_COLOR_SCHEME="16"
# Win11主题风格：light/dark
WIN11_THEME_STYLE="light"
# Grub主题：win10dark（适配Win11风格）
GRUB_THEME="win10dark"
# 终端字体：Meslo Nerd Font
FONT_NAME="MesloLGS NF"
# ==============================================================

# 检查是否为root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用sudo权限运行此脚本：sudo bash $0"
        exit 1
    fi
}

# 检查系统版本
check_ubuntu_version() {
    if ! lsb_release -a | grep -q "Ubuntu 22.04\|Ubuntu 24.04"; then
        echo "⚠️  当前系统非Ubuntu 22.04/24.04 LTS，可能存在兼容性问题"
        read -p "是否继续执行？(y/n): " choice
        if [ "$choice" != "y" ]; then
            exit 0
        fi
    fi
}

# 阶段1：准备工作（系统更新+中文环境+依赖安装）
stage_prepare() {
    echo -e "\n========== 阶段1：系统准备 =========="
    echo "📦 正在更新系统包..."
    apt update && apt upgrade -y

    echo "📦 正在安装依赖工具..."
    apt install -y git wget curl unzip gnome-tweaks gnome-shell-extension-manager language-pack-zh-hans fonts-wqy-microhei fprintd libpam-fprintd grub-customizer

    echo "🌐 正在配置中文环境..."
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

    echo "✅ 阶段1完成"
}

# 阶段2：终端美化（字体+配色）
stage_terminal() {
    echo -e "\n========== 阶段2：终端美化 =========="
    echo "🔤 正在安装${FONT_NAME}字体..."
    mkdir -p /tmp/fonts
    wget -qO /tmp/fonts/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip
    unzip -q /tmp/fonts/Meslo.zip -d /usr/share/fonts
    fc-cache -fv
    rm -rf /tmp/fonts

    echo "🎨 正在安装终端配色方案（Dracula）..."
    # 自动选择配色方案，非交互式执行Gogh脚本
    echo "${TERMINAL_COLOR_SCHEME}" | bash -c "$(wget -qO- https://git.io/vQgMr)"

    echo "✅ 阶段2完成"
}

# 阶段3：桌面美化（仿Win11）
stage_desktop() {
    echo -e "\n========== 阶段3：桌面仿Win11美化 =========="
    echo "🎨 正在安装WhiteSur GTK主题..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-theme
    bash /tmp/WhiteSur-theme/install.sh -t all -i blue -c ${WIN11_THEME_STYLE}
    rm -rf /tmp/WhiteSur-theme

    echo "🖼️  正在安装WhiteSur图标主题..."
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon
    bash /tmp/WhiteSur-icon/install.sh
    rm -rf /tmp/WhiteSur-icon

    echo "🔌 正在启用GNOME扩展..."
    # 启用关键扩展（需用户后续在扩展管理器确认）
    gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
    echo "⚠️  请手动在扩展管理器安装并启用：Dash to Panel、Win11 Window Titlebars、Desktop Icons NG"

    echo "✅ 阶段3完成"
}

# 阶段4：Grub美化（双系统启动菜单）
stage_grub() {
    echo -e "\n========== 阶段4：Grub启动菜单美化 =========="
    echo "🎨 正在安装Win11风格Grub主题..."
    git clone --depth=1 https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes.git /tmp/grub-themes
    echo "${GRUB_THEME}" | bash /tmp/grub-themes/install.sh
    rm -rf /tmp/grub-themes

    echo "🔧 正在更新Grub配置..."
    update-grub

    echo "✅ 阶段4完成"
}

# 阶段5：华为MateBook 15d指纹适配
stage_fingerprint() {
    echo -e "\n========== 阶段5：指纹适配（登录+sudo） =========="
    echo "🔧 正在配置PAM指纹验证..."
    # 备份原配置文件
    cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak
    # 在文件开头添加指纹验证规则
    sed -i '1i auth    sufficient    pam_fprintd.so' /etc/pam.d/common-auth

    echo "✅ 阶段5完成"
    echo "⚠️  指纹录入需手动操作：设置 → 用户 → 指纹登录"
}

# 主执行流程
main() {
    clear
    echo "======================================"
    echo "  Ubuntu 一键美化脚本（仿Win11）"
    echo "  适配：华为MateBook 15d | 双系统"
    echo "======================================"
    check_root
    check_ubuntu_version

    read -p "是否执行完整美化流程？(y/n): " choice
    if [ "$choice" != "y" ]; then
        exit 0
    fi

    stage_prepare
    stage_terminal
    stage_desktop
    stage_grub
    stage_fingerprint

    echo -e "\n🎉 所有配置完成！请重启系统生效"
    echo "📌 重启后需手动操作："
    echo "  1. 终端首选项设置字体为${FONT_NAME}，选择Dracula配色"
    echo "  2. 扩展管理器启用Dash to Panel等扩展，配置任务栏"
    echo "  3. Tweaks工具选择WhiteSur主题和图标"
    echo "  4. 设置中录入指纹，验证sudo指纹功能"
}

main
