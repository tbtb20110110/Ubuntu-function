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

# 进度显示
TOTAL_STEPS=0
CURRENT_STEP=0
init_progress() {
    TOTAL_STEPS=$1
}
show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -ne "\r["
    for ((i=0; i<percentage/2; i++)); do echo -ne "="; done
    echo -ne ">"
    for ((i=percentage/2; i<50; i++)); do echo -ne " "; done
    echo -ne "] $percentage%  "
}

# 回滚管理
BACKUP_FILES=()
ROLLBACK_STEPS=()
register_backup() {
    local file="$1"
    local backup="${file}.bak_$(date +%Y%m%d%H%M%S)"
    if [ -f "$file" ] && [ ! -f "$backup" ]; then
        cp "$file" "$backup"
        BACKUP_FILES+=("$backup")
        info "已备份: $file → $backup"
    fi
}
register_rollback_step() {
    ROLLBACK_STEPS+=("$1")
}
cleanup_on_error() {
    red "脚本执行失败，正在回滚..."
    for (( idx=${#ROLLBACK_STEPS[@]}-1 ; idx>=0 ; idx-- )); do
        eval "${ROLLBACK_STEPS[idx]}" 2>/dev/null || true
    done
    for backup in "${BACKUP_FILES[@]}"; do
        if [ -f "$backup" ]; then
            local original="${backup%.bak_*}"
            mv "$backup" "$original" 2>/dev/null || true
            info "已恢复: $backup → $original"
        fi
    done
    exit 1
}
trap cleanup_on_error ERR

# 日志记录
LOG_FILE="/tmp/ubuntu-beautify-$(date +%Y%m%d-%H%M%S).log"
exec 2> >(tee -a "$LOG_FILE" >&2)
exec > >(tee -a "$LOG_FILE")

# 备份函数
backup_file() {
    local file="$1"
    if [ -f "$file" ] && [ ! -f "${file}.bak" ]; then
        cp "$file" "${file}.bak"
        register_backup "$file"
    fi
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

# GitHub raw 内容 URL 替换函数
github_raw_url() {
    local repo_url="$1"
    local file_path="$2"
    if [ -n "${GITHUB_RAW_ALT_URL:-}" ]; then
        echo "${GITHUB_RAW_ALT_URL}/${repo_url#https://raw.githubusercontent.com/}/${file_path}"
    else
        echo "https://raw.githubusercontent.com/${repo_url#https://github.com/}/${file_path}"
    fi
}

# 设置网络代理
set_network_proxy() {
    if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        info "检测到代理设置，将使用代理下载..."
        export http_proxy="${HTTP_PROXY:-}"
        export https_proxy="${HTTPS_PROXY:-}"
        export ALL_PROXY="${HTTP_PROXY:-}"
        
        if command -v git >/dev/null 2>&1; then
            git config --global http.proxy "${HTTP_PROXY:-}"
            git config --global https.proxy "${HTTPS_PROXY:-}"
        fi
        
        if [ -n "${HTTP_PROXY:-}" ] && [ ! -f /etc/apt/apt.conf.d/proxy.conf ]; then
            cat > /etc/apt/apt.conf.d/proxy.conf << EOF
Acquire::http::Proxy "${HTTP_PROXY}";
Acquire::https::Proxy "${HTTPS_PROXY:-${HTTP_PROXY}}";
EOF
            register_rollback_step "rm -f /etc/apt/apt.conf.d/proxy.conf"
        fi
    fi
}

# 检查 Ubuntu 版本
check_ubuntu_version() {
    if [ ! -f /etc/os-release ]; then
        red "错误：此脚本仅适用于Ubuntu系统"
        exit 1
    fi
    
    . /etc/os-release
    if [ "$ID" != "ubuntu" ] && [ "$ID" != "ubuntu-core" ]; then
        red "错误：此脚本仅适用于Ubuntu系统"
        exit 1
    fi
    
    local version=$(echo "$VERSION_ID" | cut -d'.' -f1)
    if [ "$version" -lt 20 ]; then
        warn "警告：此脚本主要针对Ubuntu 20.04及以上版本，可能不完全兼容"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    info "检测到 Ubuntu $VERSION ($VERSION_CODENAME)"
}

# 改进的网络连接检查
check_internet_connection() {
    info "检查网络连接..."
    local test_urls=(
        "8.8.8.8"
        "1.1.1.1" 
        "114.114.114.114"
        "www.baidu.com"
        "www.github.com"
    )
    
    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 2 "$url" >/dev/null 2>&1; then
            green "网络连接正常 (通过 $url)"
            return 0
        fi
    done
    
    # 尝试HTTP连接
    if curl -s --connect-timeout 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        green "网络连接正常 (通过HTTPS)"
        return 0
    fi
    
    warn "无法连接到互联网"
    read -p "是否继续离线安装？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 1
    else
        exit 1
    fi
}

# 完整性验证
verify_critical_files() {
    info "验证关键系统文件..."
    local critical_files=(
        "/etc/passwd"
        "/etc/shadow" 
        "/etc/sudoers"
        "/etc/fstab"
        "${USER_HOME}/.bashrc"
        "${USER_HOME}/.zshrc"
    )
    
    local errors=0
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            if [ ! -s "$file" ]; then
                red "警告：关键文件为空: $file"
                ((errors++))
            fi
        fi
    done
    
    if [ $errors -eq 0 ]; then
        green "关键文件验证通过"
    else
        warn "发现 $errors 个关键文件问题"
    fi
    return $errors
}

# 改进的华为指纹设备配置
configure_huawei_fingerprint() {
    info "检测华为指纹设备..."
    
    local fingerprint_device=$(lsusb | grep -i -E "(huawei|goodix|elan|synaptics|authen)" | grep -i -E "(fingerprint|biometric)")
    
    if [ -n "$fingerprint_device" ]; then
        info "检测到指纹设备: $fingerprint_device"
        
        # 安装通用指纹支持
        local fingerprint_packages=(
            "fprintd"
            "libpam-fprintd"
            "libfprint-2-2"
            "libfprint-2-tod1"
        )
        
        for pkg in "${fingerprint_packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $pkg"; then
                retry_command "apt install -y $pkg"
            fi
        done
        
        # 根据具体设备类型配置
        if echo "$fingerprint_device" | grep -q "258a:"; then
            info "配置Goodix指纹设备..."
            configure_goodix_fingerprint
        elif echo "$fingerprint_device" | grep -q "04f3:"; then
            info "配置Elan指纹设备..."
            configure_elan_fingerprint
        fi
        
        # 检查并添加udev规则
        if lsusb | grep -q "258a:"; then
            info "检测到Goodix指纹设备 (VID:258a)"
            if [ ! -f /etc/udev/rules.d/99-fingerprint.rules ]; then
                cat > /etc/udev/rules.d/99-fingerprint.rules << 'EOF'
# Goodix fingerprint device
SUBSYSTEM=="usb", ATTR{idVendor}=="258a", ATTR{idProduct}=="00*", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="258a", ATTR{idProduct}=="00*", TAG+="uaccess"
EOF
                udevadm control --reload-rules
                udevadm trigger
                info "已添加Goodix指纹设备udev规则"
                register_rollback_step "rm -f /etc/udev/rules.d/99-fingerprint.rules"
            fi
        fi
        
        # 启用PAM配置
        if command -v pam-auth-update >/dev/null; then
            echo "fprintd" | pam-auth-update --enable
        fi
        
        # 重启指纹服务
        systemctl enable fprintd.service
        systemctl restart fprintd.service
        
        green "指纹配置完成"
    else
        warn "未检测到指纹设备，跳过特定配置"
    fi
}

configure_goodix_fingerprint() {
    info "安装Goodix指纹驱动..."
    retry_command "apt install -y libfprint-2-tod1 libfprint-2-tod-goodix"
    
    # 添加PPA获取最新驱动（仅限Ubuntu 20.04+）
    if lsb_release -rs | grep -q "^2[0-9]"; then
        retry_command "add-apt-repository -y ppa:uunicorn/open-fprintd"
        retry_command "apt update -y"
        retry_command "apt install -y open-fprintd fprintd-clients"
    fi
}

configure_elan_fingerprint() {
    info "配置Elan指纹设备..."
    # Elan设备通常由libfprint自动支持
    retry_command "apt install -y libfprint-2-tod-elan"
}

# 优化系统性能（已删除禁用蓝牙）
optimize_system_performance() {
    info "优化系统性能..."
    
    # 禁用 tracker（文件索引，占用CPU）
    if systemctl --user list-unit-files 2>/dev/null | grep -q tracker; then
        systemctl --user mask tracker-store.service tracker-miner-fs.service tracker-miner-rss.service tracker-extract.service tracker-miner-apps.service 2>/dev/null || true
        info "已禁用 tracker 服务"
        register_rollback_step "systemctl --user unmask tracker-store.service tracker-miner-fs.service tracker-miner-rss.service tracker-extract.service tracker-miner-apps.service 2>/dev/null || true"
    fi
    
    # 调整交换性（swapiness）
    if [ -f /proc/sys/vm/swappiness ]; then
        sysctl vm.swappiness=10 2>/dev/null || true
        if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
            echo "vm.swappiness=10" >> /etc/sysctl.conf
            register_rollback_step "sed -i '/vm.swappiness=10/d' /etc/sysctl.conf"
        fi
    fi
    
    # 安装预加载
    if ! dpkg -l | grep -q preload; then
        retry_command "apt install -y preload"
    fi
    
    # 优化文件系统挂载参数
    if [ -f /etc/fstab ]; then
        backup_file "/etc/fstab"
        # 为SSD优化
        if lsblk -d -o rota 2>/dev/null | grep -q "0"; then
            sed -i '/ext4/s/defaults/defaults,noatime,nodiratime,discard/' /etc/fstab 2>/dev/null || true
        fi
    fi
    
    # 禁用不必要的服务（已删除蓝牙）
    local unnecessary_services=(
        "ModemManager.service"
        "teamviewerd.service"
        "snapd.service"
    )
    
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q enabled; then
            systemctl disable "$service" 2>/dev/null || true
            warn "已禁用服务: $service"
            register_rollback_step "systemctl enable $service 2>/dev/null || true"
        fi
    done
}

# 改进的字体安装
install_fonts_alternative() {
    info "安装系统字体..."
    
    # 创建字体缓存目录
    mkdir -p /usr/local/share/fonts/
    
    # 安装基础字体包
    local font_packages=(
        "fonts-powerline"
        "fonts-firacode"
        "fonts-noto-cjk-extra"
        "fonts-noto-color-emoji"
        "fonts-wqy-microhei"
        "fonts-wqy-zenhei"
        "fonts-arphic-ukai"
        "fonts-arphic-uming"
        "fonts-liberation"
        "fonts-dejavu"
    )
    
    for pkg in "${font_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            retry_command "apt install -y $pkg"
        fi
    done
    
    # 尝试安装微软字体
    if ! dpkg -l | grep -q ttf-mscorefonts-installer; then
        retry_command "apt install -y ttf-mscorefonts-installer"
    fi
    
    # 从可靠源下载额外字体
    if [ "$ONLINE_MODE" = true ]; then
        install_nerd_fonts
    fi
    
    # 重建字体缓存
    fc-cache -fv
}

install_nerd_fonts() {
    info "安装 Nerd Fonts..."
    
    # 创建字体目录
    local font_dir="/usr/share/fonts/truetype/nerd-fonts"
    mkdir -p "$font_dir"
    
    # 下载并安装 FiraCode Nerd Font
    local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
    local font_file="/tmp/FiraCode-NerdFont.zip"
    
    if wget --show-progress --timeout=30 --tries=3 -O "$font_file" "$font_url" 2>/dev/null; then
        unzip -q "$font_file" -d "$font_dir"
        rm -f "$font_file"
        
        # 设置正确权限
        find "$font_dir" -type f -name "*.ttf" -exec chmod 644 {} \;
        
        info "FiraCode Nerd Font 安装成功！"
        register_rollback_step "rm -rf $font_dir"
    else
        warn "无法下载 FiraCode Nerd Font，使用系统自带的 Fira Code 字体"
    fi
    
    fc-cache -fv
}

# 验证安装结果
verify_installation() {
    echo
    info "=============================================="
    info "安装验证结果"
    info "=============================================="
    
    local errors=0
    local warnings=0
    
    check_component() {
        local name="$1"
        local cmd="$2"
        local optional="${3:-false}"
        
        if eval "$cmd" >/dev/null 2>&1; then
            green "✓ $name 安装成功"
            return 0
        else
            if [ "$optional" = true ]; then
                warn "⚠ $name 未安装（可选）"
                ((warnings++))
            else
                red "✗ $name 安装失败"
                ((errors++))
            fi
            return 1
        fi
    }
    
    # 检查核心组件
    check_component "zsh" "command -v zsh"
    check_component "oh-my-zsh" "[ -d ${USER_HOME}/.oh-my-zsh ]"
    check_component "Powerlevel10k" "[ -d ${P10K_DIR} ]"
    check_component "中文环境" "locale -a | grep -q zh_CN.utf8"
    check_component "GNOME Tweaks" "command -v gnome-tweaks"
    check_component "Grub Customizer" "command -v grub-customizer" "true"
    check_component "指纹支持" "command -v fprintd" "true"
    check_component "WhiteSur主题" "[ -d /usr/share/themes/WhiteSur-dark ]" "true"
    check_component "WhiteSur图标" "[ -d /usr/share/icons/WhiteSur ]" "true"
    check_component "Nerd Fonts" "fc-list | grep -q 'FiraCode Nerd Font'" "true"
    
    # 验证关键文件
    verify_critical_files || ((warnings++))
    
    echo
    info "=============================================="
    if [ $errors -eq 0 ]; then
        green "所有核心组件安装成功！"
        if [ $warnings -gt 0 ]; then
            warn "有 $warnings 个可选组件未安装"
        fi
    else
        warn "有 $errors 个核心组件安装失败，$warnings 个可选组件未安装"
        warn "请检查日志文件: $LOG_FILE"
    fi
    info "=============================================="
}

# 显示交互菜单
show_menu() {
    echo
    info "请选择安装选项:"
    echo "1) 完整安装（推荐）"
    echo "2) 仅安装终端美化"
    echo "3) 仅安装桌面美化"
    echo "4) 仅安装指纹支持"
    echo "5) 仅安装性能优化"
    echo "6) 自定义选择"
    echo "7) 退出"
    echo
    
    read -p "请输入选择 (1-7): " choice
    case $choice in
        1)
            INSTALL_TERMINAL=true
            INSTALL_DESKTOP=true
            INSTALL_FINGERPRINT=true
            INSTALL_PERFORMANCE=true
            ;;
        2)
            INSTALL_TERMINAL=true
            INSTALL_DESKTOP=false
            INSTALL_FINGERPRINT=false
            INSTALL_PERFORMANCE=false
            ;;
        3)
            INSTALL_TERMINAL=false
            INSTALL_DESKTOP=true
            INSTALL_FINGERPRINT=false
            INSTALL_PERFORMANCE=false
            ;;
        4)
            INSTALL_TERMINAL=false
            INSTALL_DESKTOP=false
            INSTALL_FINGERPRINT=true
            INSTALL_PERFORMANCE=false
            ;;
        5)
            INSTALL_TERMINAL=false
            INSTALL_DESKTOP=false
            INSTALL_FINGERPRINT=false
            INSTALL_PERFORMANCE=true
            ;;
        6)
            echo
            read -p "安装终端美化？(y/N): " term_choice
            INSTALL_TERMINAL=$( [[ $term_choice =~ ^[Yy]$ ]] && echo true || echo false )
            
            read -p "安装桌面美化？(y/N): " desk_choice
            INSTALL_DESKTOP=$( [[ $desk_choice =~ ^[Yy]$ ]] && echo true || echo false )
            
            read -p "安装指纹支持？(y/N): " fp_choice
            INSTALL_FINGERPRINT=$( [[ $fp_choice =~ ^[Yy]$ ]] && echo true || echo false )
            
            read -p "安装性能优化？(y/N): " perf_choice
            INSTALL_PERFORMANCE=$( [[ $perf_choice =~ ^[Yy]$ ]] && echo true || echo false )
            ;;
        7)
            info "退出安装"
            exit 0
            ;;
        *)
            red "无效选择，使用默认完整安装"
            INSTALL_TERMINAL=true
            INSTALL_DESKTOP=true
            INSTALL_FINGERPRINT=true
            INSTALL_PERFORMANCE=true
            ;;
    esac
}

# ===================== 主程序开始 =====================

# 显示标题
echo "=============================================="
echo "    Ubuntu 仿 Win11 一键美化脚本"
echo "    专为华为 MateBook 15d 优化"
echo "=============================================="
echo "日志文件: $LOG_FILE"
echo "=============================================="

# 权限检查
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

info "检测到普通用户：$SUDO_USER，主目录：$USER_HOME"

# 检查系统版本
check_ubuntu_version

# 设置网络代理
set_network_proxy

# 显示安装菜单
show_menu

# 估算总步骤数
init_progress 20

# 检查网络连接
show_progress
if check_internet_connection; then
    ONLINE_MODE=true
    info "在线模式：将从网络下载资源"
else
    ONLINE_MODE=false
    warn "离线模式：仅安装本地可用组件"
fi

# 设置 GitHub 相关环境变量
export GIT_SSL_NO_VERIFY=1
export GITHUB_API_URL="https://api.github.com"

# 更新系统包
show_progress
info "更新系统包列表..."
retry_command "apt update -y"

# ===================== 1. 系统初始化 & 中文环境配置 =====================
show_progress
info "===== 开始配置系统中文环境 ====="
retry_command "apt install -y language-pack-zh-hans language-pack-zh-hans-base locales"

# 配置本地化
backup_file "/etc/default/locale"
echo "LANG=zh_CN.UTF-8" > /etc/default/locale
echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
export LC_ALL=zh_CN.UTF-8
register_rollback_step "update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8"

# 安装字体
show_progress
install_fonts_alternative
green "中文环境配置完成！"

# ===================== 2. 性能优化（可选） =====================
if [ "$INSTALL_PERFORMANCE" = true ]; then
    show_progress
    info "===== 开始系统性能优化 ====="
    optimize_system_performance
    green "系统性能优化完成！"
fi

# ===================== 3. 终端美化（可选） =====================
if [ "$INSTALL_TERMINAL" = true ]; then
    show_progress
    info "===== 开始安装终端美化组件 ====="
    
    # 安装基础依赖
    retry_command "apt install -y zsh wget git curl fontconfig unzip"
    
    # 安装字体
    retry_command "apt install -y fonts-powerline fonts-firacode"
    
    # 下载并安装 Nerd Fonts
    if [ "$ONLINE_MODE" = true ]; then
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
    fi
    
    # 安装 oh-my-zsh
    OH_MY_ZSH_DIR="${USER_HOME}/.oh-my-zsh"
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        info "正在安装 oh-my-zsh..."
        
        if [ "$ONLINE_MODE" = true ]; then
            # 使用官方脚本
            if retry_command "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/install-oh-my-zsh.sh"; then
                sudo -u $SUDO_USER sh /tmp/install-oh-my-zsh.sh --unattended --keep-zshrc
                rm -f /tmp/install-oh-my-zsh.sh
            else
                # 手动安装
                warn "无法下载 oh-my-zsh 安装脚本，尝试手动安装..."
                retry_command "sudo -u $SUDO_USER git clone https://github.com/ohmyzsh/ohmyzsh.git '$OH_MY_ZSH_DIR'"
                if [ -f "${OH_MY_ZSH_DIR}/templates/zshrc.zsh-template" ]; then
                    cp "${OH_MY_ZSH_DIR}/templates/zshrc.zsh-template" "${USER_HOME}/.zshrc"
                    chown $SUDO_USER:$SUDO_USER "${USER_HOME}/.zshrc"
                fi
            fi
        else
            warn "离线模式：跳过 oh-my-zsh 安装"
        fi
    else
        info "oh-my-zsh 已安装，跳过！"
    fi
    
    # 安装 Powerlevel10k
    P10K_DIR="${USER_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
    if [ ! -d "$P10K_DIR" ]; then
        if [ "$ONLINE_MODE" = true ]; then
            info "正在安装 Powerlevel10k 主题..."
            if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/romkatv/powerlevel10k.git '$P10K_DIR'"; then
                info "Powerlevel10k 安装成功！"
            else
                red "无法安装 Powerlevel10k，请检查网络连接"
            fi
        else
            warn "离线模式：跳过 Powerlevel10k 安装"
        fi
    else
        info "Powerlevel10k 主题已存在，跳过！"
    fi
    
    # 配置 zsh 主题
    ZSH_RC="${USER_HOME}/.zshrc"
    if [ -f "$ZSH_RC" ]; then
        backup_file "$ZSH_RC"
        if ! grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZSH_RC"; then
            info "正在配置 zsh 主题..."
            sed -i 's/ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$ZSH_RC" 2>/dev/null || \
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
    
    # 安装 zsh 插件（仅在线模式）
    if [ "$ONLINE_MODE" = true ]; then
        ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"
        mkdir -p "${ZSH_CUSTOM}/plugins"
        
        # 安装 zsh-autosuggestions
        if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
            info "正在安装 zsh-autosuggestions 插件..."
            retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git '${ZSH_CUSTOM}/plugins/zsh-autosuggestions'"
        fi
        
        # 安装 zsh-syntax-highlighting
        if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
            info "正在安装 zsh-syntax-highlighting 插件..."
            retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git '${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting'"
        fi
        
        # 更新 .zshrc 中的插件配置
        if [ -f "$ZSH_RC" ]; then
            if ! grep -q "zsh-autosuggestions" "$ZSH_RC"; then
                sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSH_RC" 2>/dev/null || \
                echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSH_RC"
            fi
        fi
    fi
    
    # 设置默认 shell 为 zsh
    info "设置默认 shell 为 zsh"
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
    
    green "终端美化组件安装完成！"
fi

# ===================== 4. 桌面美化（可选） =====================
if [ "$INSTALL_DESKTOP" = true ]; then
    show_progress
    info "===== 开始安装桌面美化组件 ====="
    
    # 安装基础依赖
    retry_command "apt install -y gnome-tweaks gnome-shell-extension-manager chrome-gnome-shell"
    retry_command "apt install -y sassc libglib2.0-dev libxml2-utils"
    
    # 安装 WhiteSur 主题（仅在线模式）
    if [ "$ONLINE_MODE" = true ]; then
        info "正在安装 WhiteSur 主题..."
        WHITESUR_THEME_DIR="/tmp/WhiteSur-gtk-theme"
        if [ ! -d "$WHITESUR_THEME_DIR" ]; then
            info "正在克隆 WhiteSur 主题..."
            if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git '$WHITESUR_THEME_DIR'"; then
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
            if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git '$WHITESUR_ICON_DIR'"; then
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
            if retry_command "sudo -u $SUDO_USER git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git '$WHITESUR_CURSOR_DIR'"; then
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
    else
        warn "离线模式：跳过 WhiteSur 主题安装"
    fi
    
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
fi

# ===================== 5. Grub 美化工具安装 =====================
if [ "$INSTALL_DESKTOP" = true ] || [ "$INSTALL_TERMINAL" = true ]; then
    show_progress
    info "===== 开始安装 Grub 美化工具 ====="
    if ! dpkg -l | grep -q "grub-customizer"; then
        retry_command "add-apt-repository -y ppa:danielrichter2007/grub-customizer"
        retry_command "apt update -y"
        retry_command "apt install -y grub-customizer"
    else
        info "Grub Customizer 已安装，跳过！"
    fi
    green "Grub Customizer 安装完成！"
fi

# ===================== 6. 华为 MateBook 15d 指纹适配 =====================
if [ "$INSTALL_FINGERPRINT" = true ]; then
    show_progress
    info "===== 开始配置指纹登录 & sudo 验证 ====="
    
    # 安装基础指纹组件
    if ! dpkg -l | grep -q "fprintd" || ! dpkg -l | grep -q "libpam-fprintd"; then
        retry_command "apt install -y fprintd libpam-fprintd"
    else
        info "指纹相关组件已安装，跳过！"
    fi
    
    # 华为指纹设备特定配置
    configure_huawei_fingerprint
    
    # 配置指纹（添加当前用户）
    if command -v fprintd-enroll &> /dev/null; then
        info "指纹录入配置"
        warn "注意：指纹录入需要图形界面支持"
        info "请重启后运行以下命令录入指纹："
        echo "  sudo -u $SUDO_USER fprintd-enroll"
        echo "或使用系统设置 → 用户 → 指纹"
    fi
    
    # 配置 sudo 使用指纹验证
    if [ -f "/etc/pam.d/sudo" ]; then
        backup_file "/etc/pam.d/sudo"
        if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
            echo "auth sufficient pam_fprintd.so" >> /etc/pam.d/sudo
            info "已配置 sudo 指纹验证"
        fi
    fi
    
    # 配置系统登录使用指纹
    if [ -f "/etc/pam.d/common-auth" ]; then
        backup_file "/etc/pam.d/common-auth"
        if ! grep -q "pam_fprintd.so" /etc/pam.d/common-auth; then
            # 在合适的位置插入指纹验证
            sed -i '/^auth.*pam_unix.so/s/^/auth sufficient pam_fprintd.so\n/' /etc/pam.d/common-auth
            info "已配置系统登录指纹验证"
        fi
    fi
    
    green "指纹配置完成！"
fi

# ===================== 验证安装结果 =====================
show_progress
verify_installation

# ===================== 脚本结束提示 =====================
echo
green "===== Ubuntu 仿 Win11 一键美化脚本执行完成！ ====="
echo
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
info "  7. 性能优化："
info "     - Tracker 服务已禁用"
info "     - 交换性已优化为 10"
info "     - 已安装预加载"
info "     - 蓝牙功能已保留"
info ""
info "  8. 故障排除："
info "     查看完整日志：less $LOG_FILE"
info ""
info "  9. 网络问题："
info "     可设置代理后再运行脚本："
info "     export HTTP_PROXY=http://your-proxy:port"
info "     export HTTPS_PROXY=http://your-proxy:port"
info "     sudo -E ./script.sh"
info "=============================================="
echo
warn "注意：部分配置需要重启后才能完全生效！"
green "完成！"
echo
info "安装摘要："
echo "  - 终端美化: $( [ "$INSTALL_TERMINAL" = true ] && echo "是" || echo "否" )"
echo "  - 桌面美化: $( [ "$INSTALL_DESKTOP" = true ] && echo "是" || echo "否" )"
echo "  - 指纹支持: $( [ "$INSTALL_FINGERPRINT" = true ] && echo "是" || echo "否" )"
echo "  - 性能优化: $( [ "$INSTALL_PERFORMANCE" = true ] && echo "是" || echo "否" )"
echo "  - 运行模式: $( [ "$ONLINE_MODE" = true ] && echo "在线" || echo "离线" )"
echo
