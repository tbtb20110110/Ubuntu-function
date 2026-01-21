#!/bin/bash
set -euo pipefail

# ===================== 基础配置（可根据需求修改） =====================
# 默认字体安装路径（普通用户可读写）
FONT_INSTALL_DIR="/usr/local/share/fonts"
# 日志文件保存路径（非/tmp，避免重启丢失）
LOG_DIR="$HOME/ubuntu-beautify-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ubuntu-beautify-$(date +%Y%m%d-%H%M%S).log"
# 兼容的桌面环境列表
SUPPORTED_DESKTOPS=("gnome" "ubuntu")
# 稳定版 WhiteSur 主题版本（避免拉取最新不稳定代码）
WHITESUR_VERSION="v2024.09.01"
# 重试次数和延迟（可动态调整）
RETRY_MAX=5
RETRY_DELAY=3

# ===================== 工具函数优化 =====================
# 颜色输出函数
green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }
info() { echo -e "\033[36m$1\033[0m"; }
warn() { echo -e "\033[33m$1\033[0m"; }

# 进度显示优化（支持动态步骤数）
TOTAL_STEPS=0
CURRENT_STEP=0
init_progress() { TOTAL_STEPS=$1; CURRENT_STEP=0; }
show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar_length=$((percentage / 2))
    echo -ne "\r["
    printf "%0.s=" $(seq 1 $bar_length)
    if [ $bar_length -lt 50 ]; then echo -ne ">"; fi
    printf "%0.s " $(seq $((bar_length + 1)) 50)
    echo -ne "] $percentage%  "
    [ $CURRENT_STEP -eq $TOTAL_STEPS ] && echo
}

# 回滚机制增强（添加 sysctl 回滚、服务状态回滚）
BACKUP_FILES=()
ROLLBACK_STEPS=()
SERVICE_STATES=() # 保存服务原始状态: name:state

register_backup() {
    local file="$1"
    [ ! -f "$file" ] && return
    local backup="${file}.bak_$(date +%Y%m%d%H%M%S)"
    [ -f "$backup" ] && return
    cp -a "$file" "$backup"
    BACKUP_FILES+=("$backup")
    info "已备份: $file → $backup"
}

register_service_state() {
    local name="$1"
    local state=$(systemctl is-enabled "$name" 2>/dev/null || echo "unknown")
    SERVICE_STATES+=("$name:$state")
}

register_rollback_step() { ROLLBACK_STEPS+=("$1"); }

cleanup_on_error() {
    red "脚本执行失败，正在回滚..."
    # 执行自定义回滚步骤
    for (( idx=${#ROLLBACK_STEPS[@]}-1 ; idx>=0 ; idx-- )); do
        eval "${ROLLBACK_STEPS[idx]}" 2>/dev/null || true
    done
    # 恢复文件备份
    for backup in "${BACKUP_FILES[@]}"; do
        [ -f "$backup" ] || continue
        local original="${backup%.bak_*}"
        mv -f "$backup" "$original" 2>/dev/null || true
        info "已恢复: $backup → $original"
    done
    # 恢复服务原始状态
    for item in "${SERVICE_STATES[@]}"; do
        local name=${item%%:*}
        local state=${item#*:}
        [ "$state" = "unknown" ] && continue
        systemctl "$state" "$name" 2>/dev/null || true
        info "已恢复服务状态: $name → $state"
    done
    # 恢复 sysctl 参数
    if [ -f "/etc/sysctl.conf.bak" ]; then
        mv -f "/etc/sysctl.conf.bak" "/etc/sysctl.conf" 2>/dev/null || true
        sysctl -p 2>/dev/null || true
    fi
    exit 1
}
trap cleanup_on_error ERR

# 日志记录优化（同时输出到终端和文件）
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# 重试函数优化（动态延迟、输出详细日志）
retry_command() {
    local cmd="$1"
    local retries=${2:-$RETRY_MAX}
    local delay=${3:-$RETRY_DELAY}
    local count=0
    local success=false

    while [ $count -lt $retries ]; do
        info "执行命令 (尝试 $((count+1))/$retries): $cmd"
        if eval "$cmd"; then
            success=true
            break
        fi
        count=$((count + 1))
        warn "命令执行失败，$delay 秒后重试..."
        sleep $delay
        delay=$((delay * 2)) # 指数退避
    done

    if [ "$success" = false ]; then
        red "命令失败超过 $retries 次：$cmd"
        return 1
    fi
    return 0
}

# 权限修复函数（确保用户目录归属正确）
fix_permissions() {
    local dir="$1"
    local user="$2"
    [ -d "$dir" ] && chown -R "$user:$user" "$dir" 2>/dev/null || true
}

# ===================== 系统检查增强 =====================
check_ubuntu_version() {
    [ ! -f /etc/os-release ] && red "错误：此脚本仅适用于Ubuntu系统" && exit 1
    . /etc/os-release
    if [ "$ID" != "ubuntu" ] && [ "$ID" != "ubuntu-core" ]; then
        red "错误：此脚本仅适用于Ubuntu系统"
        exit 1
    fi
    local version=$(echo "$VERSION_ID" | cut -d'.' -f1)
    if [ "$version" -lt 20 ]; then
        red "错误：此脚本不支持Ubuntu 20.04以下版本"
        exit 1
    fi
    info "检测到 Ubuntu $VERSION ($VERSION_CODENAME)"
}

check_desktop_env() {
    local desktop=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
    local supported=false
    for de in "${SUPPORTED_DESKTOPS[@]}"; do
        if [[ "$desktop" == *"$de"* ]]; then
            supported=true
            break
        fi
    done
    if [ "$supported" = false ]; then
        warn "检测到非GNOME桌面环境: $desktop"
        warn "桌面美化功能将自动禁用"
        INSTALL_DESKTOP=false
    fi
}

check_internet_connection() {
    info "检查网络连接..."
    local test_urls=("8.8.8.8" "1.1.1.1" "www.baidu.com")
    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 2 "$url" >/dev/null 2>&1; then
            green "网络连接正常 (通过 $url)"
            ONLINE_MODE=true
            return 0
        fi
    done
    warn "无法连接到互联网"
    read -p "是否继续离线安装？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
    ONLINE_MODE=false
    return 1
}

# ===================== 核心功能修复 =====================
# 1. 性能优化修复（增加服务状态备份、sysctl 备份）
optimize_system_performance() {
    info "===== 开始系统性能优化 ====="
    # 备份 sysctl 配置
    register_backup "/etc/sysctl.conf"

    # 禁用 tracker 服务（备份状态）
    local tracker_services=(
        "tracker-store.service" "tracker-miner-fs.service"
        "tracker-miner-rss.service" "tracker-extract.service"
    )
    for service in "${tracker_services[@]}"; do
        register_service_state "$service"
        systemctl --user mask "$service" 2>/dev/null || true
    done

    # 调整 swappiness（仅备份后修改）
    if [ -f /proc/sys/vm/swappiness ]; then
        local current_swappiness=$(cat /proc/sys/vm/swappiness)
        if [ "$current_swappiness" -ne 10 ]; then
            echo "vm.swappiness=10" >> /etc/sysctl.conf
            sysctl vm.swappiness=10 2>/dev/null || true
            register_rollback_step "sed -i '/vm.swappiness=10/d' /etc/sysctl.conf"
        fi
    fi

    # 安装预加载
    retry_command "apt install -y preload"

    # SSD 优化（增加判断，避免重复修改）
    if [ -f /etc/fstab ] && lsblk -d -o rota 2>/dev/null | grep -q "0"; then
        register_backup "/etc/fstab"
        sed -i '/ext4/!b; /noatime,nodiratime/d; s/defaults/defaults,noatime,nodiratime,discard/' /etc/fstab 2>/dev/null || true
    fi

    # 禁用不必要服务（先备份状态）
    local unnecessary_services=(
        "bluetooth.service" "ModemManager.service"
        "teamviewerd.service" "snapd.service"
    )
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-enabled "$service" 2>/dev/null | grep -q enabled; then
            register_service_state "$service"
            systemctl disable "$service" 2>/dev/null || true
            warn "已禁用服务: $service"
        fi
    done
    green "系统性能优化完成！"
}

# 2. 终端美化修复（修复权限、添加字体权限检查）
install_terminal_beautify() {
    info "===== 开始安装终端美化组件 ====="
    retry_command "apt install -y zsh wget git curl fontconfig unzip"

    # 安装字体（修复权限）
    local font_packages=(
        "fonts-powerline" "fonts-firacode" "fonts-noto-cjk-extra"
    )
    for pkg in "${font_packages[@]}"; do
        retry_command "apt install -y $pkg"
    done

    # 安装 Nerd Fonts（使用国内镜像备选）
    if [ "$ONLINE_MODE" = true ]; then
        local font_urls=(
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
            "https://mirror.ghproxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
        )
        local font_dir="$FONT_INSTALL_DIR/firacode-nerd"
        mkdir -p "$font_dir"
        local font_downloaded=false

        for url in "${font_urls[@]}"; do
            if retry_command "wget --show-progress --timeout=30 -O /tmp/FiraCode.zip '$url'" 3 3; then
                unzip -q /tmp/FiraCode.zip -d "$font_dir"
                rm -f /tmp/FiraCode.zip
                font_downloaded=true
                break
            fi
        done

        if [ "$font_downloaded" = true ]; then
            chmod -R 644 "$font_dir"/*.ttf
            fc-cache -fv
            info "FiraCode Nerd Font 安装成功！"
        else
            warn "无法下载 Nerd Fonts，使用系统自带字体"
        fi
    fi

    # 安装 Oh My Zsh（修复权限）
    local oh_my_zsh_dir="$USER_HOME/.oh-my-zsh"
    if [ ! -d "$oh_my_zsh_dir" ] && [ "$ONLINE_MODE" = true ]; then
        local install_scripts=(
            "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
            "https://mirror.ghproxy.com/https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
        )
        local script_downloaded=false
        for script_url in "${install_scripts[@]}"; do
            if retry_command "curl -fsSL '$script_url' -o /tmp/install-oh-my-zsh.sh" 2 2; then
                sudo -u "$SUDO_USER" sh /tmp/install-oh-my-zsh.sh --unattended --keep-zshrc
                rm -f /tmp/install-oh-my-zsh.sh
                script_downloaded=true
                break
            fi
        done
        [ "$script_downloaded" = false ] && red "Oh My Zsh 安装失败" && return 1
    fi
    fix_permissions "$oh_my_zsh_dir" "$SUDO_USER"

    # 安装 Powerlevel10k（修复权限、指定稳定版本）
    local p10k_dir="$oh_my_zsh_dir/custom/themes/powerlevel10k"
    if [ ! -d "$p10k_dir" ] && [ "$ONLINE_MODE" = true ]; then
        local p10k_repos=(
            "https://github.com/romkatv/powerlevel10k.git"
            "https://mirror.ghproxy.com/https://github.com/romkatv/powerlevel10k.git"
        )
        local repo_cloned=false
        for repo in "${p10k_repos[@]}"; do
            if retry_command "sudo -u $SUDO_USER git clone --depth=1 --branch=v1.18.0 '$repo' '$p10k_dir'" 2 2; then
                repo_cloned=true
                break
            fi
        done
        [ "$repo_cloned" = false ] && red "Powerlevel10k 安装失败" && return 1
    fi
    fix_permissions "$p10k_dir" "$SUDO_USER"

    # 配置 .zshrc（修复权限）
    local zsh_rc="$USER_HOME/.zshrc"
    if [ -f "$zsh_rc" ]; then
        register_backup "$zsh_rc"
        sed -i 's/ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$zsh_rc" 2>/dev/null || \
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$zsh_rc"
        # 添加插件配置
        if ! grep -q "zsh-autosuggestions" "$zsh_rc"; then
            sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions zsh-syntax-highlighting)/' "$zsh_rc" 2>/dev/null || \
            echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$zsh_rc"
        fi
        fix_permissions "$zsh_rc" "$SUDO_USER"
    fi

    # 安装插件（修复权限）
    local zsh_custom="$oh_my_zsh_dir/custom"
    if [ "$ONLINE_MODE" = true ]; then
        local plugins=(
            "zsh-users/zsh-autosuggestions"
            "zsh-users/zsh-syntax-highlighting"
        )
        for plugin in "${plugins[@]}"; do
            local plugin_name=${plugin#*/}
            local plugin_dir="$zsh_custom/plugins/$plugin_name"
            [ -d "$plugin_dir" ] && continue
            local plugin_urls=(
                "https://github.com/$plugin.git"
                "https://mirror.ghproxy.com/https://github.com/$plugin.git"
            )
            for url in "${plugin_urls[@]}"; do
                if retry_command "sudo -u $SUDO_USER git clone --depth=1 '$url' '$plugin_dir'" 2 2; then
                    fix_permissions "$plugin_dir" "$SUDO_USER"
                    break
                fi
            done
        done
    fi

    # 设置默认 shell（验证是否安装成功）
    if command -v zsh >/dev/null; then
        local zsh_path=$(which zsh)
        if [ "$(getent passwd $SUDO_USER | cut -d: -f7)" != "$zsh_path" ]; then
            chsh -s "$zsh_path" "$SUDO_USER"
            info "已将 $SUDO_USER 的默认 shell 设置为 zsh"
        fi
    fi
    green "终端美化组件安装完成！"
}

# 3. 桌面美化修复（增加桌面环境判断、版本控制）
install_desktop_beautify() {
    [ "$INSTALL_DESKTOP" = false ] && return 0
    info "===== 开始安装桌面美化组件 ====="
    retry_command "apt install -y gnome-tweaks gnome-shell-extension-manager sassc libglib2.0-dev"

    # 安装 WhiteSur 主题（指定稳定版本、国内镜像）
    if [ "$ONLINE_MODE" = true ]; then
        local theme_repos=(
            "https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
            "https://mirror.ghproxy.com/https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
        )
        local theme_dir="/tmp/WhiteSur-gtk-theme"
        rm -rf "$theme_dir"
        local repo_cloned=false
        for repo in "${theme_repos[@]}"; do
            if retry_command "git clone --depth=1 --branch=$WHITESUR_VERSION '$repo' '$theme_dir'" 2 2; then
                repo_cloned=true
                break
            fi
        done
        if [ "$repo_cloned" = true ]; then
            cd "$theme_dir"
            ./install.sh -t all -N mojave -c Dark
            ./install.sh -w all
            cd -
            rm -rf "$theme_dir"
        else
            warn "WhiteSur 主题克隆失败，跳过"
        fi
    fi

    # 配置 Dash to Dock（修复权限）
    local dash_conf_dir="$USER_HOME/.config/dash-to-dock"
    mkdir -p "$dash_conf_dir"
    cat > "$dash_conf_dir/settings.json" << 'EOF'
{
    "apply-custom-theme": false,
    "background-color": "rgb(66,66,66)",
    "background-opacity": 0.8,
    "dock-position": "BOTTOM",
    "intellihide": true
}
EOF
    fix_permissions "$dash_conf_dir" "$SUDO_USER"

    # 安装 Grub Customizer
    retry_command "add-apt-repository -y ppa:danielrichter2007/grub-customizer"
    retry_command "apt update -y"
    retry_command "apt install -y grub-customizer"
    green "桌面美化组件安装完成！"
}

# 4. 指纹配置修复（增加硬件兼容性判断）
configure_fingerprint() {
    [ "$INSTALL_FINGERPRINT" = false ] && return 0
    info "===== 开始配置指纹支持 ====="
    retry_command "apt install -y fprintd libpam-fprintd"

    # 检测指纹设备（通用适配）
    local fingerprint_device=$(lsusb | grep -i -E "(fingerprint|biometric|goodix|elan|synaptics)")
    if [ -z "$fingerprint_device" ]; then
        warn "未检测到指纹设备，跳过硬件配置"
        return 0
    fi
    info "检测到指纹设备: $fingerprint_device"

    # 安装对应驱动（增加更多设备支持）
    local driver_packages=(
        "libfprint-2-2" "libfprint-2-tod1"
        "libfprint-2-tod-goodix" "libfprint-2-tod-elan"
    )
    for pkg in "${driver_packages[@]}"; do
        retry_command "apt install -y $pkg"
    done

    # Udev 规则（通用规则，适配更多设备）
    if [ ! -f /etc/udev/rules.d/99-fingerprint.rules ]; then
        cat > /etc/udev/rules.d/99-fingerprint.rules << 'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="258a", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04f3", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="0b", MODE="0666", GROUP="plugdev", TAG+="uaccess"
EOF
        udevadm control --reload-rules
        udevadm trigger
        register_rollback_step "rm -f /etc/udev/rules.d/99-fingerprint.rules"
    fi

    # 配置 PAM（备份后修改）
    local pam_files=("/etc/pam.d/sudo" "/etc/pam.d/common-auth")
    for pam_file in "${pam_files[@]}"; do
        [ ! -f "$pam_file" ] && continue
        register_backup "$pam_file"
        if ! grep -q "pam_fprintd.so" "$pam_file"; then
            echo "auth sufficient pam_fprintd.so" >> "$pam_file"
            info "已配置 $pam_file 指纹验证"
        fi
    done

    systemctl enable --now fprintd.service
    info "指纹配置完成！请重启后运行 fprintd-enroll 录入指纹"
    green "指纹支持配置完成！"
}

# ===================== 安装验证增强 =====================
verify_installation() {
    info "=============================================="
    info "                安装验证结果                  "
    info "=============================================="
    local errors=0
    local warnings=0

    check_component() {
        local name="$1"
        local check_cmd="$2"
        local optional="${3:-false}"
        if eval "$check_cmd" >/dev/null 2>&1; then
            green "✓ $name 安装成功"
        else
            if [ "$optional" = true ]; then
                warn "⚠ $name 未安装（可选）"
                ((warnings++))
            else
                red "✗ $name 安装失败"
                ((errors++))
            fi
        fi
    }

    # 核心组件检查
    check_component "zsh" "command -v zsh"
    check_component "Oh My Zsh" "[ -d $USER_HOME/.oh-my-zsh ]"
    check_component "Powerlevel10k" "[ -d $USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k ]"
    check_component "指纹服务" "command -v fprintd" true
    check_component "GNOME Tweaks" "command -v gnome-tweaks" true

    # 权限检查
    if [ -f "$USER_HOME/.zshrc" ] && [ "$(stat -c %U "$USER_HOME/.zshrc")" != "$SUDO_USER" ]; then
        warn "⚠ $USER_HOME/.zshrc 权限异常，已自动修复"
        fix_permissions "$USER_HOME/.zshrc" "$SUDO_USER"
        ((warnings++))
    fi

    info "=============================================="
    if [ $errors -eq 0 ]; then
        green "✅ 所有核心组件安装成功！"
        [ $warnings -gt 0 ] && warn "⚠ 发现 $warnings 个可选组件问题"
    else
        red "❌ 有 $errors 个核心组件安装失败，请查看日志: $LOG_FILE"
    fi
}

# ===================== 主程序 =====================
main() {
    # 显示标题
    echo "=============================================="
    echo "    Ubuntu 仿 Win11 一键美化脚本（优化版）    "
    echo "    专为华为 MateBook 15d 优化 | 兼容 Ubuntu 20.04+    "
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
    [ ! -d "$USER_HOME" ] && red "错误：用户目录 $USER_HOME 不存在！" && exit 1
    info "检测到普通用户：$SUDO_USER，主目录：$USER_HOME"

    # 初始化变量
    INSTALL_TERMINAL=true
    INSTALL_DESKTOP=true
    INSTALL_FINGERPRINT=true
    INSTALL_PERFORMANCE=true
    ONLINE_MODE=true

    # 系统检查
    check_ubuntu_version
    check_desktop_env
    check_internet_connection

    # 显示安装菜单
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
            1) ;; # 默认完整安装
            2) INSTALL_DESKTOP=false; INSTALL_FINGERPRINT=false; INSTALL_PERFORMANCE=false ;;
            3) INSTALL_TERMINAL=false; INSTALL_FINGERPRINT=false; INSTALL_PERFORMANCE=false ;;
            4) INSTALL_TERMINAL=false; INSTALL_DESKTOP=false; INSTALL_PERFORMANCE=false ;;
            5) INSTALL_TERMINAL=false; INSTALL_DESKTOP=false; INSTALL_FINGERPRINT=false ;;
            6)
                read -p "安装终端美化？(y/N): " term_choice
                INSTALL_TERMINAL=$( [[ $term_choice =~ ^[Yy]$ ]] && echo true || echo false )
                read -p "安装桌面美化？(y/N): " desk_choice
                INSTALL_DESKTOP=$( [[ $desk_choice =~ ^[Yy]$ ]] && echo true || echo false )
                read -p "安装指纹支持？(y/N): " fp_choice
                INSTALL_FINGERPRINT=$( [[ $fp_choice =~ ^[Yy]$ ]] && echo true || echo false )
                read -p "安装性能优化？(y/N): " perf_choice
                INSTALL_PERFORMANCE=$( [[ $perf_choice =~ ^[Yy]$ ]] && echo true || echo false )
                ;;
            7) info "退出安装"; exit 0 ;;
            *) warn "无效选择，使用默认完整安装" ;;
        esac
    }
    show_menu

    # 初始化进度
    init_progress 8

    # 执行安装步骤
    show_progress; info "更新系统包列表"; retry_command "apt update -y"
    show_progress; info "配置中文环境"; retry_command "apt install -y language-pack-zh-hans locales"
    show_progress; info "安装字体"; retry_command "apt install -y fonts-noto-color-emoji fonts-wqy-microhei"
    [ "$INSTALL_PERFORMANCE" = true ] && show_progress && optimize_system_performance
    [ "$INSTALL_TERMINAL" = true ] && show_progress && install_terminal_beautify
    [ "$INSTALL_DESKTOP" = true ] && show_progress && install_desktop_beautify
    [ "$INSTALL_FINGERPRINT" = true ] && show_progress && configure_fingerprint
    show_progress; verify_installation

    # 结束提示
    echo
    green "===== Ubuntu 仿 Win11 一键美化脚本（优化版）执行完成！ ====="
    echo
    info "=============================================="
    info "  重要操作指南："
    info "  1. 重启系统生效配置：sudo reboot"
    info "  2. 终端配置：首次打开 zsh 执行 p10k configure"
    info "  3. 桌面配置：打开 GNOME Tweaks 选择 WhiteSur 主题"
    info "  4. 指纹录入：重启后执行 fprintd-enroll"
    info "  5. 日志文件：$LOG_FILE"
    info "=============================================="
}

# 启动主程序
main
