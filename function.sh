#!/bin/bash
set -euo pipefail

# 颜色输出函数
green() {
    echo -e "\033[32m$1\033[0m"
}
red() {
    echo -e "\033[31m$1\033[0m"
}
info() {
    echo -e "\033[36m$1\033[0m"
}
warn() {
    echo -e "\033[33m$1\033[0m"
}

# 重试函数
retry_command() {
    local retries=3
    local delay=5
    local count=0
    local success=false
    
    while [ $count -lt $retries ]; do
        if eval "$1"; then
            success=true
            break
        fi
        count=$((count + 1))
        warn "命令执行失败，$delay 秒后重试 ($count/$retries)..."
        sleep $delay
    done
    
    if [ "$success" = false ]; then
        red "命令失败超过 $retries 次：$1"
        return 1
    fi
    return 0
}

# GitHub raw 内容 URL 替换函数（解决raw.githubusercontent.com访问问题）
github_raw_url() {
    local repo_url="$1"
    local file_path="$2"
    # 如果提供了备用URL，则使用备用URL
    if [ -n "${GITHUB_RAW_ALT_URL:-}" ]; then
        echo "${GITHUB_RAW_ALT_URL}/${repo_url#https://raw.githubusercontent.com/}/${file_path}"
    else
        echo "https://raw.githubusercontent.com/${repo_url#https://github.com/}/${file_path}"
    fi
}

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
    USER_HOME="/home/${SUDO_USER%%-*}"  # 尝试去掉可能的域名部分
    if [ ! -d "$USER_HOME" ]; then
        red "错误：普通用户目录 $USER_HOME 不存在！"
        exit 1
    fi
fi

info "===== 检测到普通用户：$SUDO_USER，主目录：$USER_HOME ====="

# 设置 GitHub 相关环境变量（可选代理）
export GIT_SSL_NO_VERIFY=1  # 跳过 SSL 验证（某些网络环境需要）
export GITHUB_API_URL="https://api.github.com"

# ===================== 1. 系统初始化 & 中文环境配置 =====================
info "===== 开始配置系统中文环境 ====="
retry_command "apt update -y"
retry_command "apt install -y language-pack-zh-hans language-pack-zh-hans-base locales"

# 配置本地化
echo "LANG=zh_CN.UTF-8" > /etc/default/locale
echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
export LC_ALL=zh_CN.UTF-8

# 安装中文字体
retry_command "apt install -y fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei"

green "中文环境配置完成！"

# ===================== 2. 终端美化（oh-my-zsh + Powerlevel10k + 系统字体） =====================
info "===== 开始安装终端美化组件 ====="

# 安装基础依赖
retry_command "apt install -y zsh wget git curl fontconfig unzip"

# 安装字体
retry_command "apt install -y fonts-powerline fonts-firacode"

# 下载并安装 Nerd Fonts（包含更多图标）
NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
FIRACODE_NERD_DIR="/usr/share/fonts/truetype/firacode-nerd"

if [ ! -d "$FIRACODE_NERD_DIR" ]; then
    info "正在下载 FiraCode Nerd Font..."
    mkdir -p /tmp/firacode-nerd
    cd /tmp/firacode-nerd
    
    if retry_command "wget --show-progress --timeout=30 --tries=3 -O FiraCode.zip '$NERD_FONT_URL'"; then
        mkdir -p "$FIRACODE_NERD_DIR"
        unzip -q FiraCode.zip -d "$FIRACODE_NERD_DIR"
        fc-cache -fv
        info "FiraCode Nerd Font 安装成功！"
    else
        warn "无法下载 FiraCode Nerd Font，使用系统自带的 Fira Code 字体"
    fi
    cd -
    rm -rf /tmp/firacode-nerd
else
    info "FiraCode Nerd Font 已安装，跳过！"
fi

# 安装 oh-my-zsh
OH_MY_ZSH_DIR="${USER_HOME}/.oh-my-zsh"
if [ ! -d "$OH_MY_ZSH_DIR" ]; then
    info "正在安装 oh-my-zsh..."
    
    # 方法1：使用官方脚本（如果可访问）
    if retry_command "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/install-oh-my-zsh.sh"; then
        sudo -u $SUDO_USER sh /tmp/install-oh-my-zsh.sh --unattended --keep-zshrc
        rm -f /tmp/install-oh-my-zsh.sh
    else
        # 方法2：手动安装
        warn "无法下载 oh-my-zsh 安装脚本，尝试手动安装..."
        sudo -u $SUDO_USER git clone https://github.com/ohmyzsh/ohmyzsh.git "$OH_MY_ZSH_DIR"
        # 复制默认配置文件
        if [ -f "${OH_MY_ZSH_DIR}/templates/zshrc.zsh-template" ]; then
            cp "${OH_MY_ZSH_DIR}/templates/zshrc.zsh-template" "${USER_HOME}/.zshrc"
            chown $SUDO_USER:$SUDO_USER "${USER_HOME}/.zshrc"
        fi
    fi
else
    info "oh-my-zsh 已安装，跳过！"
fi

# 安装 Powerlevel10k
P10K_DIR="${USER_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    info "正在安装 Powerlevel10k 主题..."
    if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${P10K_DIR}"; then
        info "Powerlevel10k 安装成功！"
    else
        red "无法安装 Powerlevel10k，请检查网络连接"
    fi
else
    info "Powerlevel10k 主题已存在，跳过！"
fi

# 配置 zsh 主题
ZSH_RC="${USER_HOME}/.zshrc"
if [ -f "$ZSH_RC" ]; then
    if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSH_RC"; then
        info "正在配置 zsh 主题..."
        sed -i 's/ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$ZSH_RC" || \
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSH_RC"
    else
        info "zsh 主题已配置为 Powerlevel10k，跳过！"
    fi
    
    # 添加 Powerlevel10k 配置
    if ! grep -q 'POWERLEVEL9K_MODE="nerdfont-complete"' "$ZSH_RC"; then
        echo '' >> "$ZSH_RC"
        echo '# Powerlevel10k 配置' >> "$ZSH_RC"
        echo 'POWERLEVEL9K_MODE="nerdfont-complete"' >> "$ZSH_RC"
        echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> "$ZSH_RC"
    fi
fi

# 安装 zsh 插件
ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"
mkdir -p "${ZSH_CUSTOM}/plugins"

# 安装 zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    info "正在安装 zsh-autosuggestions 插件..."
    retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

# 安装 zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    info "正在安装 zsh-syntax-highlighting 插件..."
    retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

# 更新 .zshrc 中的插件配置
if [ -f "$ZSH_RC" ]; then
    if ! grep -q "zsh-autosuggestions" "$ZSH_RC"; then
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSH_RC" 2>/dev/null || \
        echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSH_RC"
    fi
fi

green "终端美化组件安装完成！"

# ===================== 3. 桌面美化（WhiteSur 官方 GitHub 源） =====================
info "===== 开始安装桌面美化组件 ====="

# 安装基础依赖
retry_command "apt install -y gnome-tweaks gnome-shell-extension-manager chrome-gnome-shell"
retry_command "apt install -y sassc libglib2.0-dev libxml2-utils"

# 安装 WhiteSur 主题
info "正在安装 WhiteSur 主题..."
WHITESUR_THEME_DIR="/tmp/WhiteSur-gtk-theme"
if [ ! -d "$WHITESUR_THEME_DIR" ]; then
    info "正在克隆 WhiteSur 主题..."
    if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git ${WHITESUR_THEME_DIR}"; then
        cd "$WHITESUR_THEME_DIR"
        ./install.sh -t all -N mojave -c Dark
        ./install.sh -w all
        ./install.sh -g -c Dark
        cd -
    else
        warn "无法克隆 WhiteSur 主题，跳过主题安装"
    fi
else
    info "WhiteSur 主题已存在，跳过克隆！"
fi

# 安装 WhiteSur 图标
info "正在安装 WhiteSur 图标..."
WHITESUR_ICON_DIR="/tmp/WhiteSur-icon-theme"
if [ ! -d "$WHITESUR_ICON_DIR" ]; then
    if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git ${WHITESUR_ICON_DIR}"; then
        cd "$WHITESUR_ICON_DIR"
        ./install.sh
        cd -
    else
        warn "无法克隆 WhiteSur 图标，跳过图标安装"
    fi
else
    info "WhiteSur 图标已存在，跳过克隆！"
fi

# 安装 WhiteSur 光标
info "正在安装 WhiteSur 光标..."
WHITESUR_CURSOR_DIR="/tmp/WhiteSur-cursors"
if [ ! -d "$WHITESUR_CURSOR_DIR" ]; then
    if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git ${WHITESUR_CURSOR_DIR}"; then
        cd "$WHITESUR_CURSOR_DIR"
        ./install.sh
        cd -
    else
        warn "无法克隆 WhiteSur 光标，跳过光标安装"
    fi
else
    info "WhiteSur 光标已存在，跳过克隆！"
fi

# 清理临时文件
rm -rf /tmp/WhiteSur-* 2>/dev/null || true

# 安装常用 GNOME 扩展
info "正在安装 GNOME 扩展..."
retry_command "apt install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-arc-menu"

# 配置 Dash to Dock
DASH_CONF="${USER_HOME}/.config/dash-to-dock"
mkdir -p "$DASH_CONF"
cat > "$DASH_CONF/settings.json" << 'EOF'
{
    "apply-custom-theme": false,
    "background-color": "rgb(66,66,66)",
    "background-opacity": 0.8,
    "custom-background-color": true,
    "custom-theme-shrink": true,
    "dock-fixed": true,
    "dock-position": "BOTTOM",
    "extend-height": false,
    "height-fraction": 0.9,
    "intellihide": true,
    "multi-monitor": true,
    "show-apps-at-top": false,
    "show-running": true,
    "show-trash": false
}
EOF
chown -R $SUDO_USER:$SUDO_USER "$DASH_CONF"

green "桌面美化组件安装完成！"

# ===================== 4. Grub 美化工具安装 =====================
info "===== 开始安装 Grub 美化工具 ====="
if ! dpkg -l | grep -q "grub-customizer"; then
    retry_command "add-apt-repository -y ppa:danielrichter2007/grub-customizer"
    retry_command "apt update -y"
    retry_command "apt install -y grub-customizer"
else
    info "Grub Customizer 已安装，跳过！"
fi
green "Grub Customizer 安装完成！"

# ===================== 5. 华为 MateBook 15d 指纹适配 =====================
info "===== 开始配置指纹登录 & sudo 验证 ====="
if ! dpkg -l | grep -q "fprintd" || ! dpkg -l | grep -q "libpam-fprintd"; then
    retry_command "apt install -y fprintd libpam-fprintd"
else
    info "指纹相关组件已安装，跳过！"
fi

# 配置指纹（添加当前用户）
if command -v fprintd-enroll &> /dev/null; then
    info "请按照提示录入指纹（可能需要多次扫描）..."
    sudo -u $SUDO_USER fprintd-enroll || warn "指纹录入失败或用户取消"
fi

# 配置 sudo 使用指纹验证
if [ -f "/etc/pam.d/sudo" ]; then
    if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
        echo "auth sufficient pam_fprintd.so" >> /etc/pam.d/sudo
        info "已配置 sudo 指纹验证"
    fi
fi
green "指纹配置完成！"

# ===================== 6. 设置默认 shell 为 zsh =====================
info "===== 设置默认 shell 为 zsh ====="
if command -v zsh >/dev/null 2>&1; then
    ZSH_PATH=$(which zsh)
    if [ "$(getent passwd $SUDO_USER | cut -d: -f7)" != "$ZSH_PATH" ]; then
        chsh -s "$ZSH_PATH" "$SUDO_USER"
        info "已将 $SUDO_USER 的默认 shell 设置为 zsh"
    else
        info "$SUDO_USER 的默认 shell 已经是 zsh"
    fi
else
    warn "zsh 未安装，无法设置默认 shell"
fi

# ===================== 脚本结束提示 =====================
green "===== Ubuntu 仿 Win11 一键美化脚本执行完成！ ====="
echo ""
info "=============================================="
info "  重要操作指南："
info "=============================================="
info "  1. 重启系统生效所有配置："
info "     sudo reboot"
info ""
info "  2. 终端配置（重启后）："
info "     a. 首次打开终端会触发 Powerlevel10k 配置向导"
info "     b. 如果没触发，手动运行：p10k configure"
info "     c. 字体选择：FiraCode Nerd Font 或 Fira Code"
info ""
info "  3. 桌面主题配置："
info "     a. 打开 '优化' (Gnome Tweaks)"
info "     b. 外观 → 主题：选择 WhiteSur-dark"
info "     c. 外观 → 图标：选择 WhiteSur"
info "     d. 外观 → 光标：选择 WhiteSur"
info ""
info "  4. GNOME 扩展："
info "     a. 打开 '扩展管理器'"
info "     b. 启用 'Dash to Dock' 和 'Arc Menu'"
info "     c. 根据需要调整扩展设置"
info ""
info "  5. Grub 美化（可选）："
info "     sudo grub-customizer"
info ""
info "  6. 指纹登录配置："
info "     系统设置 → 用户 → 指纹"
info "     或运行：sudo pam-auth-update"
info ""
info "  7. 如果遇到网络问题："
info "     可设置 HTTP/HTTPS 代理后再运行脚本："
info "     export http_proxy=http://your-proxy:port"
info "     export https_proxy=http://your-proxy:port"
info "=============================================="
echo ""
warn "注意：部分配置需要重启后才能完全生效！"
green "完成！"
