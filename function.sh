#!/bin/bash
set -euo pipefail

# 颜色输出函数
green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }

# 检查是否为 root 权限
if [ $EUID -ne 0 ]; then
    red "错误：请使用 sudo 或 root 权限运行此脚本！"
    exit 1
fi

# ===================== 1. 系统初始化 & 中文环境配置 =====================
info "===== 开始配置系统中文环境 ====="
apt update -y && apt install -y language-pack-zh-hans language-pack-zh-hans-base
# 设置默认 locale 为中文
echo "zh_CN.UTF-8 UTF-8" > /etc/locale.conf
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8
green "中文环境配置完成！"

# ===================== 2. 终端美化（oh-my-zsh + Powerlevel10k） =====================
info "===== 开始安装终端美化组件 ====="
# 安装依赖
apt install -y zsh wget git fonts-powerline curl
# 安装 oh-my-zsh（自动跳过交互）
sh -c "$(curl -fsSL --no-check-certificate https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
# 安装 Powerlevel10k 主题
git clone -c http.sslVerify=false --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
# 配置 zsh 主题
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' $HOME/.zshrc
# 下载 Meslo Nerd Font 字体（跳过 SSL 校验）
info "===== 开始下载 Meslo 字体 ====="
FONT_DIR="/usr/share/fonts"
wget --no-check-certificate -P $FONT_DIR https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
wget --no-check-certificate -P $FONT_DIR https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
wget --no-check-certificate -P $FONT_DIR https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
wget --no-check-certificate -P $FONT_DIR https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf
fc-cache -fv
green "终端美化组件安装完成！"

# ===================== 3. 桌面美化（WhiteSur 主题 + GNOME 插件依赖） =====================
info "===== 开始安装桌面美化组件 ====="
apt install -y gnome-tweaks gnome-shell-extensions chrome-gnome-shell
# 下载 WhiteSur 主题（使用公开 Gitee 镜像，无鉴权）
git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-gtk-theme.git /tmp/WhiteSur-gtk-theme
# 安装主题（仅保留有效参数）
bash /tmp/WhiteSur-gtk-theme/install.sh -t all
# 下载 WhiteSur 图标
git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-icon-theme.git /tmp/WhiteSur-icon-theme
bash /tmp/WhiteSur-icon-theme/install.sh
# 下载 WhiteSur 光标
git clone -c http.sslVerify=false --depth=1 https://gitee.com/laomocode/WhiteSur-cursors.git /tmp/WhiteSur-cursors
bash /tmp/WhiteSur-cursors/install.sh
# 清理临时文件
rm -rf /tmp/WhiteSur-*
green "桌面主题安装完成！"

# ===================== 4. Grub 美化工具安装 =====================
info "===== 开始安装 Grub 美化工具 ====="
add-apt-repository -y ppa:danielrichter2007/grub-customizer
apt update -y && apt install -y grub-customizer
green "Grub Customizer 安装完成！"

# ===================== 5. 华为 MateBook 15d 指纹适配 =====================
info "===== 开始配置指纹登录 & sudo 验证 ====="
apt install -y fprintd libpam-fprintd
# 配置 sudo 指纹验证
echo "auth sufficient pam_fprintd.so" >> /etc/pam.d/sudo
green "指纹配置完成！请重启后在系统设置中录入指纹！"

# ===================== 脚本结束提示 =====================
green "===== 一键美化脚本执行完成！ ====="
info "1. 重启系统后生效所有配置：sudo reboot"
info "2. 终端首次启动会触发 Powerlevel10k 配置向导，请选择中文选项"
info "3. 桌面美化需在 GNOME 插件商店安装 Dash to Panel + Windows 11 Style Menu"
info "4. Grub 美化请运行 sudo grub-customizer 进行配置"
info "5. 指纹登录请在 系统设置->用户 中录入指纹"
