#!/bin/bash
set -euo pipefail

# ==================== 自定义配置项（用户可修改） ====================
TERMINAL_COLOR_SCHEME="16"   # Dracula配色编号
WIN11_THEME_STYLE="light"    # light/dark 主题风格
GRUB_THEME="win10dark"       # Win11风格Grub主题
FONT_NAME="MesloLGS NF"      # 终端字体
# ====================================================================

# 全局检查：root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 请使用sudo权限运行：sudo bash $0"
        exit 1
    fi
}

# 全局检查：系统版本
check_ubuntu_version() {
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 22.04\|Ubuntu 24.04"; then
        echo "⚠️  当前系统非Ubuntu 22.04/24.04 LTS，可能存在兼容性问题"
        read -p "是否继续执行？(y/n): " choice
        [ "$choice" != "y" ] && exit 0
    fi
}

# 修复架构问题（移除多余arm64）
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

# ==================== 功能模块定义 ====================
# 模块1：系统准备（源配置+依赖+grub-customizer安装）
module_prepare() {
    fix_architecture
    echo -e "\n========== 模块1：系统准备（国内网络友好） =========="
    echo "🔧 安装源管理工具..."
    apt install -y software-properties-common

    echo "🔧 启用官方软件源组件..."
    add-apt-repository main restricted universe multiverse -y
    apt update -y && apt upgrade -y

    echo "🔧 国内加速安装 grub-customizer..."
    GRUB_DEB_URL="https://mirror.ghproxy.com/https://launchpad.net/~danielrichter2007/+archive/ubuntu/grub-customizer/+files/grub-customizer_5.2.3-1ubuntu1_amd64.deb"
    wget -qO /tmp/grub-customizer.deb "${GRUB_DEB_URL}"
    
    if [ ! -f /tmp/grub-customizer.deb ]; then
        echo "❌ grub-customizer deb包下载失败，请手动下载后放到/tmp目录"
        return 1
    fi

    dpkg -i /tmp/grub-customizer.deb || apt -f install -y
    rm -f /tmp/grub-customizer.deb

    echo "📦 安装核心依赖..."
    apt install -y git wget curl unzip gnome-tweaks gnome-shell-extension-manager language-pack-zh-hans fonts-wqy-microhei fprintd libpam-fprintd

    echo "🌐 配置中文环境..."
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    echo "✅ 模块1执行完成"
}

# 模块2：终端美化（字体+配色）
module_terminal() {
    echo -e "\n========== 模块2：终端美化 =========="
    echo "🔤 安装 ${FONT_NAME} 字体..."
    mkdir -p /tmp/fonts
    wget -qO /tmp/fonts/Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip
    unzip -q /tmp/fonts/Meslo.zip -d /usr/share/fonts
    fc-cache -fv
    rm -rf /tmp/fonts

    echo "🎨 安装Dracula配色方案..."
    echo "${TERMINAL_COLOR_SCHEME}" | bash -c "$(wget -qO- https://git.io/vQgMr)"
    echo "✅ 模块2执行完成"
    echo "💡 提示：重启终端后，在首选项中选择 ${FONT_NAME} 字体和Dracula配色"
}

# 模块3：桌面仿Win11美化
module_desktop() {
    echo -e "\n========== 模块3：桌面仿Win11美化 =========="
    echo "🎨 安装WhiteSur GTK主题..."
    # 国内Gitee镜像，防止GitHub克隆失败
    git clone --depth=1 https://gitee.com/mirrors/WhiteSur-gtk-theme.git /tmp/WhiteSur-theme || git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-theme
    bash /tmp/WhiteSur-theme/install.sh -t all -i blue -c ${WIN11_THEME_STYLE}
    rm -rf /tmp/WhiteSur-theme

    echo "🖼️  安装WhiteSur图标主题..."
    git clone --depth=1 https://gitee.com/mirrors/WhiteSur-icon-theme.git /tmp/WhiteSur-icon || git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon
    bash /tmp/WhiteSur-icon/install.sh
    rm -rf /tmp/WhiteSur-icon

    echo "🔌 启用基础GNOME扩展..."
    gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com || true
    echo "✅ 模块3执行完成"
    echo "💡 提示：需手动在扩展管理器启用 Dash to Panel、Win11 Window Titlebars、Desktop Icons NG"
}

# 模块4：Grub启动菜单美化
module_grub() {
    echo -e "\n========== 模块4：Grub启动菜单美化 =========="
    echo "🎨 安装Win11风格Grub主题..."
    git clone --depth=1 https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes.git /tmp/grub-themes
    echo "${GRUB_THEME}" | bash /tmp/grub-themes/install.sh
    rm -rf /tmp/grub-themes

    echo "🔧 更新Grub配置..."
    update-grub
    echo "✅ 模块4执行完成"
}

# 模块5：指纹适配（登录+sudo验证）
module_fingerprint() {
    echo -e "\n========== 模块5：指纹适配（登录+sudo） =========="
    echo "🔧 备份PAM配置文件..."
    cp /etc/pam.d/common-auth /etc/pam.d/common-auth.bak

    echo "🔧 配置指纹用于sudo验证..."
    sed -i '1i auth    sufficient    pam_fprintd.so' /etc/pam.d/common-auth
    echo "✅ 模块5执行完成"
    echo "💡 提示：重启后在 设置→用户→指纹登录 中录入指纹"
}

# 模块0：完整美化流程
module_full() {
    echo -e "\n========== 执行完整美化流程 =========="
    module_prepare
    module_terminal
    module_desktop
    module_grub
    module_fingerprint
    echo -e "\n🎉 完整流程执行完成！请重启系统后进行手动配置"
}

# ==================== 交互式菜单 ====================
show_menu() {
    clear
    echo "======================================"
    echo "  Ubuntu 仿Win11美化脚本（分步菜单版）"
    echo "  适配：华为MateBook 15d | x86_64架构"
    echo "======================================"
    echo "  0. 执行完整美化流程（所有模块）"
    echo "  1. 模块1：系统准备（必选前置步骤）"
    echo "  2. 模块2：终端美化（字体+配色）"
    echo "  3. 模块3：桌面仿Win11美化"
    echo "  4. 模块4：Grub启动菜单美化"
    echo "  5. 模块5：指纹适配（登录+sudo）"
    echo "  6. 退出脚本"
    echo "======================================"
}

# 主函数：菜单交互
main() {
    check_root
    check_ubuntu_version

    while true; do
        show_menu
        read -p "请输入要执行的模块编号 [0-6]：" choice
        case $choice in
            0)
                module_full
                break
                ;;
            1)
                module_prepare
                read -p "按任意键返回菜单..."
                ;;
            2)
                module_terminal
                read -p "按任意键返回菜单..."
                ;;
            3)
                module_desktop
                read -p "按任意键返回菜单..."
                ;;
            4)
                module_grub
                read -p "按任意键返回菜单..."
                ;;
            5)
                module_fingerprint
                read -p "按任意键返回菜单..."
                ;;
            6)
                echo "👋 退出脚本，再见！"
                exit 0
                ;;
            *)
                echo "❌ 无效输入，请输入0-6之间的编号"
                read -p "按任意键返回菜单..."
                ;;
        esac
    done
}

# 启动菜单
main
