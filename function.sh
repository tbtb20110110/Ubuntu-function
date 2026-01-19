#!/bin/bash
set -euo pipefail

# 颜色输出函数
green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# ===================== 权限 & 环境检查 =====================
if [ $EUID -ne 0 ]; then
    red "错误：请使用 sudo 权限运行此脚本！"
    exit 1
fi

if [ -z "$SUDO_USER" ]; then
    red "错误：禁止直接以 root 用户运行，请用普通用户执行 sudo 命令！"
    exit 1
fi

USER_HOME="/home/$SUDO_USER"
if [ ! -d "$USER_HOME" ]; then
    red "错误：普通用户目录 $USER_HOME 不存在！"
    exit 1
fi

info "===== 检测到普通用户：$SUDO_USER，主目录：$USER_HOME ====="

# ===================== 1. 系统初始化 & 中文环境配置 =====================
info "===== 开始配置系统中文环境 ====="
apt update -y && apt install -y language-pack-zh-hans language-pack-zh-hans-base
echo "zh_CN.UTF-8 UTF-8" > /etc/locale.conf
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8
green "中文环境配置完成！"

# ===================== 2. 终端美化（oh-my-zsh + Powerlevel10k） =====================
info "===== 开始安装终端美化组件 ====="
apt install -y zsh wget git fonts-powerline curl

# 安装 oh-my-zsh（判断是否已安装）
OH_MY_ZSH_DIR="${USER_HOME}/.oh-my-zsh"
if [ ! -d "$OH_MY_ZSH_DIR" ]; then
    info "正在安装 oh-my-zsh..."
    sudo -u $SUDO_USER sh -c "$(curl -fsSL --no-check-certificate https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    info "oh-my-zsh 已安装，跳过！"
fi

# 安装 Powerlevel10k（判断目录是否存在）
P10K_DIR="${USER_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    info "正在安装 Powerlevel10k 主题..."
    sudo -u $SUDO_USER git clone -c http.sslVerify=false --depth=1 https://github.com/romkatv/powerlevel10k.git ${P10K_DIR}
else
    info "Powerlevel10k 主题已存在，跳过克隆！"
fi

# 配置 zsh 主题（判断是否已配置）
if ! grep -q "ZSH_THEME=\"powerlevel10k/powerlevel10k\"" ${USER_HOME}/.zshrc; then
    info "正在配置 zsh 主题..."
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ${USER_HOME}/.zshrc
else
    info "zsh 主题已配置为 Powerlevel10k，跳过！"
fi

# 下载 Meslo Nerd Font 字体
info "正在下载 Meslo 字体..."
FONT_DIR="/usr/share/fonts"
FONT_FILES=("MesloLGS%20NF%20Regular.ttf" "MesloLGS%20NF%20Bold.ttf" "MesloLGS%20NF%20Italic.ttf" "MesloLGS%20NF%20Bold%20Italic.ttf")
for font in "${FONT_FILES[@]}"; do
    FONT_PATH="${FONT_DIR}/${font//%20/ }"
    if [ ! -f "$FONT_PATH" ]; then
        wget --no-check-certificate -P $FONT_DIR https://github.com/romkatv/powerlevel10k-media/raw/master/${font}
    else
        info "字体 ${font//%20/ } 已存在，跳过下载！"
    fi
done
fc-cache -fv
green "终端美化组件安装完成！"

# ===================== 3. 桌面美化（WhiteSur 主题 + 图标 + 光标） =====================
info "===== 开始安装桌面美化组件 ====="
apt install -y gnome-tweaks gnome-shell-extensions chrome-gnome-shell

# 安装 WhiteSur 主题
WHITESUR_THEME_DIR="/tmp/WhiteSur-gtk-theme"
if [ ! -d "$WHITESUR_THEME_DIR" ]; then
    info "正在克隆 WhiteSur 主题..."
    sudo -u $SUDO_USER git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-gtk-theme.git ${WHITESUR_THEME_DIR}
else
    info "WhiteSur 主题临时目录已存在，跳过克隆！"
fi
bash ${WHITESUR_THEME_DIR}/install.sh -t all

# 安装 WhiteSur 图标
WHITESUR_ICON_DIR="/tmp/WhiteSur-icon-theme"
if [ ! -d "$WHITESUR_ICON_DIR" ]; then
    info "正在克隆 WhiteSur 图标..."
    sudo -u $SUDO_USER git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-icon-theme.git ${WHITESUR_ICON_DIR}
else
    info "WhiteSur 图标临时目录已存在，跳过克隆！"
fi
bash ${WHITESUR_ICON_DIR}/install.sh

# 安装 WhiteSur 光标
WHITESUR_CURSOR_DIR="/tmp/WhiteSur-cursors"
if [ ! -d "$WHITESUR_CURSOR_DIR" ]; then
    info "正在克隆 WhiteSur 光标..."
    sudo -u $SUDO_USER git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-cursors.git ${WHITESUR_CURSOR_DIR}
else
    info "WhiteSur 光标临时目录已存在，跳过克隆！"
fi
bash ${WHITESUR_CURSOR_DIR}/install.sh

rm -rf /tmp/WhiteSur-*
green "桌面美化组件安装完成！"

# ===================== 4. Grub 美化工具安装 =====================
info "===== 开始安装 Grub 美化工具 ====="
if ! dpkg -l | grep -q "grub-customizer"; then
    add-apt-repository -y ppa:danielrichter2007/grub-customizer
    apt update -y && apt install -y grub-customizer
else
    info "Grub Customizer 已安装，跳过！"
fi
green "Grub Customizer 安装完成！"

# ===================== 5. 华为 MateBook 15d 指纹适配 =====================
info "===== 开始配置指纹登录 & sudo 验证 ====="
if ! dpkg -l | grep -q "fprintd" || ! dpkg -l | grep -q "libpam-fprintd"; then
    apt install -y fprintd libpam-fprintd
else
    info "指纹相关组件已安装，跳过！"
fi

if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
    echo "auth sufficient pam_fprintd.so" >> /etc/pam.d/sudo
else
    info "sudo 指纹验证已配置，跳过！"
fi
green "指纹配置完成！"

# ===================== 脚本结束提示 =====================
green "===== Ubuntu 仿 Win11 一键美化脚本执行完成！ ====="
info "=============================================="
info "  1. 重启系统生效所有配置：sudo reboot"
info "  2. 终端首次启动会触发 Powerlevel10k 配置向导，请选择中文"
info "  3. 桌面配置：打开 GNOME 插件商店安装 Dash to Panel + Windows 11 Style Menu"
info "  4. 主题应用：GNOME Tweaks → 外观 → 选择 WhiteSur 系列"
info "  5. Grub 美化：运行 sudo grub-customizer 自定义背景和启动项"
info "  6. 指纹登录：系统设置 → 用户 → 录入指纹即可使用"
info "=============================================="
