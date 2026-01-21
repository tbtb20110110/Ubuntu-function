#!/bin/bash
set -euo pipefail

# ===================== 脚本元信息 =====================
SCRIPT_NAME="ubuntu-beautify"
VERSION="2.0.0"
AUTHOR="Ubuntu Beautify Team"
REPO_URL="https://github.com/example/ubuntu-beautify"
CONFIG_FILE="/etc/ubuntu-beautify.conf"
USER_CONFIG_FILE="${HOME}/.ubuntu-beautify.conf"
CACHE_DIR="${HOME}/.cache/ubuntu-beautify"
STATE_FILE="/var/lib/ubuntu-beautify/state"

# ===================== 颜色输出函数 =====================
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
highlight() {
    echo -e "\033[1;35m$1\033[0m"
}

# ===================== 初始化 =====================
init_environment() {
    # 创建必要的目录
    mkdir -p "$CACHE_DIR"
    mkdir -p "/var/lib/ubuntu-beautify"
    mkdir -p "/var/log/ubuntu-beautify"
    
    # 加载配置文件
    load_configs
}

# ===================== 配置管理 =====================
load_configs() {
    # 加载系统配置文件
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        info "已加载系统配置文件: $CONFIG_FILE"
    fi
    
    # 加载用户配置文件（优先级更高）
    if [ -f "$USER_CONFIG_FILE" ]; then
        source "$USER_CONFIG_FILE"
        info "已加载用户配置文件: $USER_CONFIG_FILE"
    fi
    
    # 设置默认值
    : ${INSTALL_TERMINAL:=true}
    : ${INSTALL_DESKTOP:=true}
    : ${INSTALL_FINGERPRINT:=true}
    : ${INSTALL_PERFORMANCE:=true}
    : ${USE_MIRRORS:=true}
    : ${SKIP_CONFIRMATIONS:=false}
    : ${MAX_RETRIES:=3}
    : ${DOWNLOAD_TIMEOUT:=30}
    : ${PARALLEL_DOWNLOADS:=4}
    : ${ENABLE_CACHE:=true}
    : ${KEEP_CACHE:=false}
    : ${LOG_LEVEL:="INFO"}
}

save_config() {
    local key="$1"
    local value="$2"
    
    # 保存到用户配置文件
    if grep -q "^$key=" "$USER_CONFIG_FILE" 2>/dev/null; then
        sed -i "s/^$key=.*/$key=\"$value\"/" "$USER_CONFIG_FILE"
    else
        echo "$key=\"$value\"" >> "$USER_CONFIG_FILE"
    fi
}

create_default_config() {
    cat > "$USER_CONFIG_FILE" << 'EOF'
# Ubuntu Beautify 配置文件
# 安装选项
INSTALL_TERMINAL=true        # 安装终端美化
INSTALL_DESKTOP=true         # 安装桌面美化
INSTALL_FINGERPRINT=true     # 安装指纹支持
INSTALL_PERFORMANCE=true     # 安装性能优化

# 网络设置
USE_MIRRORS=true             # 使用国内镜像源
HTTP_PROXY=""                # HTTP代理 (例如: http://proxy.example.com:8080)
HTTPS_PROXY=""               # HTTPS代理

# 下载设置
PARALLEL_DOWNLOADS=4         # 并行下载数
DOWNLOAD_TIMEOUT=30          # 下载超时(秒)
ENABLE_CACHE=true            # 启用下载缓存
KEEP_CACHE=false             # 安装后保留缓存

# 行为设置
SKIP_CONFIRMATIONS=false     # 跳过确认提示
LOG_LEVEL="INFO"            # 日志级别: DEBUG, INFO, WARN, ERROR
MAX_RETRIES=3               # 失败重试次数

# 硬件优化
OPTIMIZE_HUAWEI=true        # 华为设备优化
OPTIMIZE_NVIDIA=false       # NVIDIA显卡优化
OPTIMIZE_BATTERY=true       # 电池优化

# 主题设置
THEME="WhiteSur"            # 主题: WhiteSur, Arc, Materia
THEME_VARIANT="dark"        # 主题变体: light, dark
ICON_THEME="WhiteSur"       # 图标主题
CURSOR_THEME="WhiteSur"     # 光标主题

# 终端设置
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_PLUGINS="git zsh-autosuggestions zsh-syntax-highlighting"

# 性能设置
SWAPPINESS=10               # 交换性 (0-100)
DISABLE_TRACKER=true        # 禁用Tracker索引
DISABLE_BLUETOOTH=false     # 禁用蓝牙
ENABLE_PRELOAD=true         # 启用预加载
EOF
    
    chown "$SUDO_USER:$SUDO_USER" "$USER_CONFIG_FILE"
    info "已创建默认配置文件: $USER_CONFIG_FILE"
}

# ===================== 进度显示 =====================
TOTAL_STEPS=0
CURRENT_STEP=0
init_progress() {
    TOTAL_STEPS=$1
    CURRENT_STEP=0
}
show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    echo -ne "\r["
    for ((i=0; i<filled; i++)); do echo -ne "█"; done
    for ((i=0; i<empty; i++)); do echo -ne "░"; done
    echo -ne "] ${percentage}% (${CURRENT_STEP}/${TOTAL_STEPS})"
    
    if [ $CURRENT_STEP -eq $TOTAL_STEPS ]; then
        echo
    fi
}

# ===================== 日志系统 =====================
LOG_FILE="/var/log/ubuntu-beautify/$(date +%Y%m%d-%H%M%S).log"
log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # 检查日志级别
    case $LOG_LEVEL in
        DEBUG) local levels=("DEBUG" "INFO" "WARN" "ERROR") ;;
        INFO)  local levels=("INFO" "WARN" "ERROR") ;;
        WARN)  local levels=("WARN" "ERROR") ;;
        ERROR) local levels=("ERROR") ;;
        *)     local levels=("INFO" "WARN" "ERROR") ;;
    esac
    
    # 检查是否应该记录
    local should_log=false
    for l in "${levels[@]}"; do
        if [ "$level" = "$l" ]; then
            should_log=true
            break
        fi
    done
    
    if [ "$should_log" = true ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
        
        # 根据级别输出到控制台
        case $level in
            ERROR) red "[$level] $message" ;;
            WARN)  warn "[$level] $message" ;;
            INFO)  info "[$level] $message" ;;
            DEBUG) echo "[$level] $message" ;;
        esac
    fi
}

setup_logging() {
    exec 2> >(tee -a "$LOG_FILE" >&2)
    exec > >(tee -a "$LOG_FILE")
    log "INFO" "脚本启动: $SCRIPT_NAME v$VERSION"
    log "INFO" "日志文件: $LOG_FILE"
}

# ===================== 状态管理 =====================
save_state() {
    local key="$1"
    local value="$2"
    local state_dir="$(dirname "$STATE_FILE")"
    
    mkdir -p "$state_dir"
    
    if grep -q "^$key=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s/^$key=.*/$key=\"$value\"/" "$STATE_FILE"
    else
        echo "$key=\"$value\"" >> "$STATE_FILE"
    fi
}

load_state() {
    local key="$1"
    local default="${2:-}"
    
    if [ -f "$STATE_FILE" ] && grep -q "^$key=" "$STATE_FILE"; then
        grep "^$key=" "$STATE_FILE" | cut -d'"' -f2
    else
        echo "$default"
    fi
}

# ===================== 回滚管理 =====================
BACKUP_FILES=()
ROLLBACK_STEPS=()
register_backup() {
    local file="$1"
    local backup="${file}.beautify.bak.$(date +%Y%m%d%H%M%S)"
    
    if [ -f "$file" ] && [ ! -f "$backup" ]; then
        cp -p "$file" "$backup"
        BACKUP_FILES+=("$backup")
        log "INFO" "已备份: $file → $backup"
    fi
}

register_rollback_step() {
    ROLLBACK_STEPS+=("$1")
}

cleanup_on_error() {
    log "ERROR" "脚本执行失败，正在回滚..."
    
    # 执行回滚步骤
    for (( idx=${#ROLLBACK_STEPS[@]}-1 ; idx>=0 ; idx-- )); do
        eval "${ROLLBACK_STEPS[idx]}" 2>/dev/null || true
        log "DEBUG" "执行回滚步骤: ${ROLLBACK_STEPS[idx]}"
    done
    
    # 恢复备份文件
    for backup in "${BACKUP_FILES[@]}"; do
        if [ -f "$backup" ]; then
            local original="${backup%.beautify.bak.*}"
            mv "$backup" "$original" 2>/dev/null || true
            log "INFO" "已恢复: $backup → $original"
        fi
    done
    
    log "ERROR" "回滚完成，脚本退出"
    exit 1
}

trap cleanup_on_error ERR
trap 'log "INFO" "用户中断脚本执行"; exit 1' INT

# ===================== 硬件检测 =====================
detect_hardware() {
    log "INFO" "开始硬件检测..."
    
    # 检测是否为华为设备
    if command -v dmidecode >/dev/null 2>&1; then
        local vendor=$(dmidecode -s system-manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
        if [[ $vendor == *"huawei"* ]] || [[ $vendor == *"honor"* ]]; then
            export IS_HUAWEI=true
            export HUAWEI_MODEL=$(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
            log "INFO" "检测到华为设备: $HUAWEI_MODEL"
        else
            export IS_HUAWEI=false
        fi
    fi
    
    # 检测指纹设备
    export HAS_FINGERPRINT=false
    if lsusb | grep -i -E "(huawei|goodix|elan|synaptics|authen)" | grep -i -E "(fingerprint|biometric)" >/dev/null; then
        export HAS_FINGERPRINT=true
        export FINGERPRINT_DEVICE=$(lsusb | grep -i -E "(huawei|goodix|elan|synaptics|authen)" | grep -i -E "(fingerprint|biometric)")
        log "INFO" "检测到指纹设备: $FINGERPRINT_DEVICE"
    fi
    
    # 检测显卡
    export HAS_NVIDIA=false
    export HAS_INTEL=false
    export HAS_AMD=false
    
    if lspci | grep -i "nvidia" >/dev/null; then
        export HAS_NVIDIA=true
        export NVIDIA_MODEL=$(lspci | grep -i "nvidia" | head -1)
        log "INFO" "检测到NVIDIA显卡: $NVIDIA_MODEL"
    fi
    
    if lspci | grep -i "intel.*graphics" >/dev/null; then
        export HAS_INTEL=true
    fi
    
    if lspci | grep -i "amd.*graphics" >/dev/null; then
        export HAS_AMD=true
    fi
    
    # 检测内存和存储
    if command -v free >/dev/null; then
        export TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')
        export AVAILABLE_MEM=$(free -g | awk '/^Mem:/ {print $7}')
    fi
    
    if command -v df >/dev/null; then
        export DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}')
        export DISK_TYPE=$(lsblk -d -o rota 2>/dev/null | grep -q "0" && echo "SSD" || echo "HDD")
    fi
    
    # 检测CPU
    export CPU_CORES=$(nproc 2>/dev/null || echo "1")
    export CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | sed 's/^[ \t]*//')
    
    log "INFO" "硬件检测完成"
}

show_hardware_info() {
    echo
    highlight "=== 硬件信息 ==="
    info "设备型号: ${HUAWEI_MODEL:-未知}"
    info "CPU: $CPU_MODEL ($CPU_CORES 核心)"
    info "内存: ${TOTAL_MEM:-?}GB (可用: ${AVAILABLE_MEM:-?}GB)"
    info "存储: $DISK_SPACE 可用 ($DISK_TYPE)"
    info "显卡: $(if $HAS_NVIDIA; then echo "NVIDIA"; elif $HAS_INTEL; then echo "Intel"; elif $HAS_AMD; then echo "AMD"; else echo "未知"; fi)"
    info "指纹: $(if $HAS_FINGERPRINT; then echo "支持"; else echo "不支持"; fi)"
    echo
}

# ===================== 网络工具 =====================
setup_download_tool() {
    # 优先使用 aria2，其次 wget，最后 curl
    if command -v aria2c >/dev/null 2>&1; then
        export DOWNLOAD_TOOL="aria2c"
        export DOWNLOAD_OPTIONS="--timeout=$DOWNLOAD_TIMEOUT --max-tries=$MAX_RETRIES --max-concurrent-downloads=$PARALLEL_DOWNLOADS --continue=true"
        log "DEBUG" "使用 aria2 下载工具"
    elif command -v wget >/dev/null 2>&1; then
        export DOWNLOAD_TOOL="wget"
        export DOWNLOAD_OPTIONS="--timeout=$DOWNLOAD_TIMEOUT --tries=$MAX_RETRIES --continue --show-progress"
        log "DEBUG" "使用 wget 下载工具"
    else
        export DOWNLOAD_TOOL="curl"
        export DOWNLOAD_OPTIONS="--connect-timeout $DOWNLOAD_TIMEOUT --retry $MAX_RETRIES -L -C -"
        log "DEBUG" "使用 curl 下载工具"
    fi
}

download_file() {
    local url="$1"
    local output="${2:-}"
    local cache_key="${3:-}"
    
    # 如果启用了缓存并且有缓存键，检查缓存
    if [ "$ENABLE_CACHE" = true ] && [ -n "$cache_key" ]; then
        local cache_file="$CACHE_DIR/$cache_key"
        if [ -f "$cache_file" ]; then
            log "DEBUG" "使用缓存文件: $cache_file"
            if [ -n "$output" ]; then
                cp "$cache_file" "$output"
            else
                cat "$cache_file"
            fi
            return 0
        fi
    fi
    
    # 选择下载工具
    case $DOWNLOAD_TOOL in
        aria2c)
            if [ -n "$output" ]; then
                aria2c $DOWNLOAD_OPTIONS -o "$output" "$url"
            else
                aria2c $DOWNLOAD_OPTIONS "$url" -o -
            fi
            ;;
        wget)
            if [ -n "$output" ]; then
                wget $DOWNLOAD_OPTIONS -O "$output" "$url"
            else
                wget $DOWNLOAD_OPTIONS -O - "$url"
            fi
            ;;
        curl)
            if [ -n "$output" ]; then
                curl $DOWNLOAD_OPTIONS -o "$output" "$url"
            else
                curl $DOWNLOAD_OPTIONS "$url"
            fi
            ;;
    esac
    
    # 保存到缓存
    if [ "$ENABLE_CACHE" = true ] && [ -n "$cache_key" ] && [ -n "$output" ] && [ -f "$output" ]; then
        cp "$output" "$CACHE_DIR/$cache_key"
        log "DEBUG" "文件已缓存: $cache_key"
    fi
}

network_diagnostics() {
    log "INFO" "执行网络诊断..."
    
    local test_points=(
        "Google DNS:8.8.8.8"
        "Cloudflare DNS:1.1.1.1"
        "阿里DNS:223.5.5.5"
        "百度:www.baidu.com"
        "GitHub:api.github.com"
        "清华镜像:mirrors.tuna.tsinghua.edu.cn"
    )
    
    echo
    highlight "网络连接测试:"
    
    local reachable=0
    local total=${#test_points[@]}
    
    for point in "${test_points[@]}"; do
        local name="${point%:*}"
        local host="${point#*:}"
        
        if timeout 2 ping -c 1 "$host" >/dev/null 2>&1; then
            green "  ✓ $name ($host) 可达"
            ((reachable++))
        else
            # 尝试HTTP连接
            if timeout 3 curl -s --head "https://$host" >/dev/null 2>&1 || \
               timeout 3 curl -s --head "http://$host" >/dev/null 2>&1; then
                green "  ✓ $name ($host) HTTP可达"
                ((reachable++))
            else
                red "  ✗ $name ($host) 不可达"
            fi
        fi
    done
    
    local percentage=$((reachable * 100 / total))
    echo
    info "网络连通性: $reachable/$total ($percentage%)"
    
    if [ $reachable -eq 0 ]; then
        warn "网络完全不可达，将进入离线模式"
        return 1
    elif [ $reachable -lt $((total/2)) ]; then
        warn "网络连通性较差，部分功能可能无法使用"
        return 2
    else
        green "网络连接正常"
        return 0
    fi
}

check_internet_connection() {
    log "INFO" "检查网络连接..."
    
    # 如果有代理设置，先检查代理
    if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        info "检测到代理设置: ${HTTP_PROXY:-${HTTPS_PROXY:-无}}"
        export http_proxy="${HTTP_PROXY:-}"
        export https_proxy="${HTTPS_PROXY:-}"
        export ALL_PROXY="${HTTP_PROXY:-}"
    fi
    
    # 执行网络诊断
    network_diagnostics
    local result=$?
    
    case $result in
        0)
            export ONLINE_MODE=true
            return 0
            ;;
        1)
            export ONLINE_MODE=false
            if [ "$SKIP_CONFIRMATIONS" = false ]; then
                read -p "网络不可达，是否继续离线安装？(y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            warn "进入离线模式，仅安装本地可用组件"
            return 1
            ;;
        2)
            export ONLINE_MODE=true
            warn "网络连接不稳定，部分下载可能失败"
            return 0
            ;;
    esac
}

# ===================== 系统检测 =====================
check_ubuntu_version() {
    log "INFO" "检查Ubuntu版本..."
    
    if [ ! -f /etc/os-release ]; then
        red "错误：此脚本仅适用于Ubuntu系统"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        red "错误：此脚本仅适用于Ubuntu系统"
        exit 1
    fi
    
    local version=$(echo "$VERSION_ID" | cut -d'.' -f1)
    if [ "$version" -lt 20 ]; then
        warn "警告：此脚本主要针对Ubuntu 20.04及以上版本"
        if [ "$SKIP_CONFIRMATIONS" = false ]; then
            read -p "是否继续？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
    
    export UBUNTU_VERSION="$VERSION_ID"
    export UBUNTU_CODENAME="$VERSION_CODENAME"
    log "INFO" "检测到 Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
}

check_system_resources() {
    log "INFO" "检查系统资源..."
    
    local warnings=()
    
    # 检查磁盘空间
    local root_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$root_space" -lt 10 ]; then
        warnings+=("根分区可用空间不足 ($root_space GB)，建议至少 10 GB")
    fi
    
    # 检查内存
    local total_mem=$(free -g | awk '/^Mem:/ {print $2}')
    if [ "$total_mem" -lt 4 ]; then
        warnings+=("系统内存较小 ($total_mem GB)，美化可能会影响性能")
    fi
    
    # 检查CPU核心数
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        warnings+=("CPU核心数较少 ($cpu_cores 核)，安装过程可能较慢")
    fi
    
    # 显示警告
    if [ ${#warnings[@]} -gt 0 ]; then
        warn "系统资源警告："
        for warning in "${warnings[@]}"; do
            warn "  • $warning"
        done
        
        if [ "$SKIP_CONFIRMATIONS" = false ]; then
            read -p "是否继续安装？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
}

# ===================== 依赖检查 =====================
check_dependencies() {
    log "INFO" "检查系统依赖..."
    
    local missing_deps=()
    local required_cmds=("wget" "curl" "git" "unzip" "sed" "grep" "apt-get")
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        info "正在安装缺失的依赖: ${missing_deps[*]}"
        apt update -y
        for dep in "${missing_deps[@]}"; do
            case $dep in
                apt-get) dep="apt" ;;
            esac
            apt install -y "$dep"
        done
    fi
    
    # 安装下载加速工具
    if ! command -v aria2c >/dev/null 2>&1; then
        info "安装 aria2 加速下载工具..."
        apt install -y aria2
    fi
}

# ===================== 资源监控 =====================
monitor_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local mem_usage=$(free | awk '/^Mem:/ {print $3/$2 * 100.0}')
    
    if (( $(echo "$cpu_usage > 80" | bc -l 2>/dev/null || echo "0") )); then
        warn "CPU使用率较高: ${cpu_usage}%"
        if [ "$SKIP_CONFIRMATIONS" = false ]; then
            read -p "是否继续？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
    
    if (( $(echo "$mem_usage > 85" | bc -l 2>/dev/null || echo "0") )); then
        warn "内存使用率较高: ${mem_usage}%"
    fi
}

# ===================== 镜像源配置 =====================
setup_mirror_sources() {
    if [ "$ONLINE_MODE" = true ] && [ "$USE_MIRRORS" = true ]; then
        log "INFO" "配置国内镜像源..."
        
        # 检测地理位置
        local country_code="US"
        if command -v curl >/dev/null 2>&1; then
            country_code=$(curl -s --max-time 3 https://ipapi.co/country/ 2>/dev/null || echo "US")
        fi
        
        if [ "$country_code" = "CN" ]; then
            info "检测到中国大陆位置，使用国内镜像源"
            
            backup_file "/etc/apt/sources.list"
            
            local mirror_url=""
            local mirrors=(
                "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                "https://mirrors.aliyun.com/ubuntu/"
                "https://mirrors.huaweicloud.com/ubuntu/"
                "https://mirrors.ustc.edu.cn/ubuntu/"
            )
            
            # 测试最快的镜像
            for mirror in "${mirrors[@]}"; do
                if curl -s --max-time 2 --head "$mirror" >/dev/null 2>&1; then
                    mirror_url="$mirror"
                    info "选择镜像源: $mirror"
                    break
                fi
            done
            
            if [ -n "$mirror_url" ]; then
                cat > /etc/apt/sources.list << EOF
# Ubuntu 镜像源 - $mirror_url
deb ${mirror_url} $UBUNTU_CODENAME main restricted universe multiverse
deb ${mirror_url} $UBUNTU_CODENAME-updates main restricted universe multiverse
deb ${mirror_url} $UBUNTU_CODENAME-backports main restricted universe multiverse
deb ${mirror_url} $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                
                # 设置GitHub镜像
                export GITHUB_MIRRORS=(
                    "https://hub.fastgit.xyz"
                    "https://ghproxy.com"
                    "https://github.com.cnpmjs.org"
                )
                
                register_rollback_step "mv /etc/apt/sources.list.bak /etc/apt/sources.list 2>/dev/null || true"
            fi
        fi
    fi
}

# ===================== 安装组件 =====================
install_system_basics() {
    show_progress
    log "INFO" "安装系统基础组件..."
    
    # 更新系统
    retry_command "apt update -y"
    retry_command "apt upgrade -y"
    
    # 安装基础工具
    local basic_packages=(
        "software-properties-common"
        "build-essential"
        "cmake"
        "pkg-config"
        "libglib2.0-dev"
        "libxml2-utils"
        "sassc"
        "gnupg"
        "ca-certificates"
    )
    
    for pkg in "${basic_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            retry_command "apt install -y $pkg"
        fi
    done
    
    # 安装中文环境
    retry_command "apt install -y language-pack-zh-hans language-pack-zh-hans-base"
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    export LANG=zh_CN.UTF-8
    
    log "INFO" "系统基础组件安装完成"
}

install_fonts() {
    show_progress
    log "INFO" "安装字体..."
    
    # 安装系统字体
    local font_packages=(
        "fonts-powerline"
        "fonts-firacode"
        "fonts-noto-cjk-extra"
        "fonts-noto-color-emoji"
        "fonts-wqy-microhei"
        "fonts-wqy-zenhei"
        "fonts-liberation"
        "fonts-dejavu"
        "fonts-roboto"
        "fonts-ubuntu"
    )
    
    for pkg in "${font_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            retry_command "apt install -y $pkg"
        fi
    done
    
    # 安装微软字体
    if [ ! -f /etc/apt/sources.list.d/msfonts.list ]; then
        echo "deb http://ftp.debian.org/debian/ $(lsb_release -sc) main contrib non-free" > /etc/apt/sources.list.d/msfonts.list
        apt update
        retry_command "apt install -y ttf-mscorefonts-installer"
    fi
    
    # 安装Nerd Fonts
    if [ "$ONLINE_MODE" = true ]; then
        local nerd_fonts=(
            "FiraCode"
            "Meslo"
            "RobotoMono"
            "UbuntuMono"
        )
        
        for font in "${nerd_fonts[@]}"; do
            install_nerd_font "$font"
        done
    fi
    
    # 重建字体缓存
    fc-cache -fv
    log "INFO" "字体安装完成"
}

install_nerd_font() {
    local font_name="$1"
    local font_dir="/usr/share/fonts/truetype/nerd-fonts"
    mkdir -p "$font_dir"
    
    local font_urls=(
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/${font_name}.zip"
        "https://ghproxy.com/https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/${font_name}.zip"
    )
    
    local font_file="/tmp/${font_name}-NerdFont.zip"
    local downloaded=false
    
    for font_url in "${font_urls[@]}"; do
        log "DEBUG" "尝试下载字体: $font_url"
        if download_file "$font_url" "$font_file" "nerd-font-${font_name}.zip"; then
            downloaded=true
            break
        fi
    done
    
    if [ "$downloaded" = true ]; then
        unzip -q -o "$font_file" -d "$font_dir"
        find "$font_dir" -name "*.ttf" -exec chmod 644 {} \;
        log "INFO" "字体 $font_name 安装成功"
        rm -f "$font_file"
    else
        warn "字体 $font_name 下载失败"
    fi
}

install_terminal_beautification() {
    show_progress
    log "INFO" "安装终端美化..."
    
    # 安装zsh
    if ! command -v zsh >/dev/null 2>&1; then
        retry_command "apt install -y zsh"
    fi
    
    # 安装oh-my-zsh
    OH_MY_ZSH_DIR="${USER_HOME}/.oh-my-zsh"
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        if [ "$ONLINE_MODE" = true ]; then
            info "安装 oh-my-zsh..."
            local install_script="/tmp/install-oh-my-zsh.sh"
            download_file "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "$install_script"
            
            if [ -f "$install_script" ]; then
                sudo -u "$SUDO_USER" sh "$install_script" --unattended --keep-zshrc
                rm -f "$install_script"
            else
                # 手动克隆
                sudo -u "$SUDO_USER" git clone https://github.com/ohmyzsh/ohmyzsh.git "$OH_MY_ZSH_DIR"
            fi
        fi
    fi
    
    # 安装Powerlevel10k
    P10K_DIR="${USER_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
    if [ ! -d "$P10K_DIR" ]; then
        if [ "$ONLINE_MODE" = true ]; then
            info "安装 Powerlevel10k..."
            sudo -u "$SUDO_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
        fi
    fi
    
    # 配置zsh
    ZSH_RC="${USER_HOME}/.zshrc"
    if [ -f "$ZSH_RC" ]; then
        backup_file "$ZSH_RC"
        
        # 设置主题
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSH_RC" 2>/dev/null || \
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSH_RC"
        
        # 添加插件配置
        if ! grep -q "zsh-autosuggestions" "$ZSH_RC"; then
            echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSH_RC"
        fi
        
        # 添加Powerlevel10k配置
        cat >> "$ZSH_RC" << 'EOF'

# Powerlevel10k 配置
POWERLEVEL9K_MODE="nerdfont-complete"
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
EOF
    fi
    
    # 安装zsh插件
    if [ "$ONLINE_MODE" = true ]; then
        ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"
        
        # zsh-autosuggestions
        if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
            sudo -u "$SUDO_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
        fi
        
        # zsh-syntax-highlighting
        if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
            sudo -u "$SUDO_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
        fi
    fi
    
    # 设置默认shell
    if command -v zsh >/dev/null 2>&1; then
        ZSH_PATH=$(which zsh)
        if [ "$(getent passwd "$SUDO_USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
            chsh -s "$ZSH_PATH" "$SUDO_USER"
            log "INFO" "设置默认shell为zsh"
        fi
    fi
    
    log "INFO" "终端美化安装完成"
}

install_desktop_beautification() {
    show_progress
    log "INFO" "安装桌面美化..."
    
    # 安装基础工具
    retry_command "apt install -y gnome-tweaks gnome-shell-extension-manager chrome-gnome-shell"
    
    # 安装WhiteSur主题
    if [ "$ONLINE_MODE" = true ]; then
        info "安装 WhiteSur 主题..."
        
        # 克隆主题仓库
        local theme_dir="/tmp/WhiteSur-gtk-theme"
        if [ ! -d "$theme_dir" ]; then
            sudo -u "$SUDO_USER" git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$theme_dir"
        fi
        
        if [ -d "$theme_dir" ]; then
            cd "$theme_dir"
            ./install.sh -t all -N mojave -c "$THEME_VARIANT"
            ./install.sh -w all
            ./install.sh -g -c "$THEME_VARIANT"
            cd -
        fi
        
        # 安装图标
        local icon_dir="/tmp/WhiteSur-icon-theme"
        if [ ! -d "$icon_dir" ]; then
            sudo -u "$SUDO_USER" git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "$icon_dir"
        fi
        
        if [ -d "$icon_dir" ]; then
            cd "$icon_dir"
            ./install.sh
            cd -
        fi
        
        # 安装光标
        local cursor_dir="/tmp/WhiteSur-cursors"
        if [ ! -d "$cursor_dir" ]; then
            sudo -u "$SUDO_USER" git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git "$cursor_dir"
        fi
        
        if [ -d "$cursor_dir" ]; then
            cd "$cursor_dir"
            ./install.sh
            cd -
        fi
        
        # 清理临时文件
        rm -rf /tmp/WhiteSur-*
    fi
    
    # 安装GNOME扩展
    retry_command "apt install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-arc-menu")
    
    # 配置Dash to Dock
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
    chown -R "$SUDO_USER:$SUDO_USER" "$DASH_CONF"
    
    # 安装Grub Customizer
    if ! dpkg -l | grep -q "grub-customizer"; then
        retry_command "add-apt-repository -y ppa:danielrichter2007/grub-customizer"
        retry_command "apt update -y"
        retry_command "apt install -y grub-customizer"
    fi
    
    log "INFO" "桌面美化安装完成"
}

install_fingerprint_support() {
    show_progress
    log "INFO" "安装指纹支持..."
    
    # 安装基础指纹组件
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
    
    # 华为设备特殊配置
    if [ "$IS_HUAWEI" = true ]; then
        configure_huawei_fingerprint
    fi
    
    # 添加udev规则
    if [ "$HAS_FINGERPRINT" = true ]; then
        if [ ! -f /etc/udev/rules.d/99-fingerprint.rules ]; then
            cat > /etc/udev/rules.d/99-fingerprint.rules << 'EOF'
# Goodix fingerprint device
SUBSYSTEM=="usb", ATTR{idVendor}=="258a", ATTR{idProduct}=="00*", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="258a", ATTR{idProduct}=="00*", TAG+="uaccess"

# Elan fingerprint device
SUBSYSTEM=="usb", ATTR{idVendor}=="04f3", ATTR{idProduct}=="0*", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="04f3", ATTR{idProduct}=="0*", TAG+="uaccess"
EOF
            udevadm control --reload-rules
            udevadm trigger
        fi
    fi
    
    # 配置PAM
    if command -v pam-auth-update >/dev/null; then
        echo "fprintd" | pam-auth-update --enable
    fi
    
    # 启动服务
    systemctl enable fprintd.service
    systemctl restart fprintd.service
    
    log "INFO" "指纹支持安装完成"
}

configure_huawei_fingerprint() {
    log "INFO" "配置华为指纹设备..."
    
    # 根据指纹设备类型安装相应驱动
    if echo "$FINGERPRINT_DEVICE" | grep -q "258a:"; then
        retry_command "apt install -y libfprint-2-tod-goodix"
    elif echo "$FINGERPRINT_DEVICE" | grep -q "04f3:"; then
        retry_command "apt install -y libfprint-2-tod-elan"
    fi
    
    # 添加PPA获取最新驱动
    if lsb_release -rs | grep -q "^2[0-9]"; then
        retry_command "add-apt-repository -y ppa:uunicorn/open-fprintd"
        retry_command "apt update -y"
        retry_command "apt install -y open-fprintd fprintd-clients"
    fi
}

install_performance_optimization() {
    show_progress
    log "INFO" "安装性能优化..."
    
    # 安装预加载
    if ! dpkg -l | grep -q preload; then
        retry_command "apt install -y preload"
    fi
    
    # 安装优化工具
    local perf_packages=(
        "tlp"
        "thermald"
        "powertop"
    )
    
    for pkg in "${perf_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            retry_command "apt install -y $pkg"
        fi
    done
    
    # 优化系统配置
    optimize_system_settings
    
    # NVIDIA优化
    if [ "$HAS_NVIDIA" = true ] && [ "$OPTIMIZE_NVIDIA" = true ]; then
        optimize_nvidia
    fi
    
    # 电池优化
    if [ "$OPTIMIZE_BATTERY" = true ]; then
        optimize_battery
    fi
    
    log "INFO" "性能优化安装完成"
}

optimize_system_settings() {
    # 优化交换性
    if [ -f /proc/sys/vm/swappiness ]; then
        sysctl vm.swappiness="$SWAPPINESS" 2>/dev/null || true
        if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
            echo "vm.swappiness=$SWAPPINESS" >> /etc/sysctl.conf
        fi
    fi
    
    # 禁用Tracker（如果配置）
    if [ "$DISABLE_TRACKER" = true ]; then
        if systemctl --user list-unit-files 2>/dev/null | grep -q tracker; then
            systemctl --user mask tracker-store.service tracker-miner-fs.service tracker-miner-rss.service tracker-extract.service tracker-miner-apps.service 2>/dev/null || true
        fi
    fi
    
    # 禁用不必要的服务
    if [ "$DISABLE_BLUETOOTH" = true ]; then
        systemctl disable bluetooth.service 2>/dev/null || true
    fi
    
    # 优化文件系统
    if [ -f /etc/fstab ]; then
        backup_file "/etc/fstab"
        if [ "$DISK_TYPE" = "SSD" ]; then
            sed -i '/ext4/s/defaults/defaults,noatime,nodiratime,discard/' /etc/fstab 2>/dev/null || true
        fi
    fi
}

optimize_nvidia() {
    log "INFO" "优化NVIDIA显卡..."
    
    # 安装NVIDIA驱动
    if ! dpkg -l | grep -q "nvidia-driver"; then
        retry_command "add-apt-repository -y ppa:graphics-drivers/ppa"
        retry_command "apt update -y"
        retry_command "ubuntu-drivers autoinstall"
    fi
    
    # 配置NVIDIA性能模式
    if command -v nvidia-settings >/dev/null 2>&1; then
        sudo -u "$SUDO_USER" nvidia-settings --assign "[gpu:0]/GPUPowerMizerMode=1" 2>/dev/null || true
    fi
}

optimize_battery() {
    log "INFO" "优化电池使用..."
    
    # 启用TLP
    systemctl enable tlp.service
    systemctl start tlp.service
    
    # 配置TLP
    if [ -f /etc/tlp.conf ]; then
        backup_file "/etc/tlp.conf"
        
        # 优化电池设置
        sed -i 's/^#CPU_SCALING_GOVERNOR_ON_BAT=.*/CPU_SCALING_GOVERNOR_ON_BAT=powersave/' /etc/tlp.conf
        sed -i 's/^#CPU_MAX_PERF_ON_BAT=.*/CPU_MAX_PERF_ON_BAT=60/' /etc/tlp.conf
        sed -i 's/^#CPU_BOOST_ON_BAT=.*/CPU_BOOST_ON_BAT=0/' /etc/tlp.conf
    fi
}

# ===================== 工具函数 =====================
retry_command() {
    local cmd="$1"
    local retries=${MAX_RETRIES:-3}
    local delay=5
    local count=0
    local success=false
    
    while [ $count -lt $retries ]; do
        log "DEBUG" "执行命令: $cmd (尝试 $((count+1))/$retries)"
        if eval "$cmd"; then
            success=true
            break
        fi
        count=$((count + 1))
        warn "命令执行失败，${delay}秒后重试 ($count/$retries)..."
        sleep $delay
    done
    
    if [ "$success" = false ]; then
        red "命令失败超过 $retries 次：$cmd"
        return 1
    fi
    return 0
}

confirm() {
    local prompt="$1"
    
    if [ "$SKIP_CONFIRMATIONS" = true ]; then
        return 0
    fi
    
    read -p "$prompt (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

show_environment_summary() {
    echo
    highlight "=== 环境摘要 ==="
    info "系统: Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
    info "内核: $(uname -r)"
    info "架构: $(uname -m)"
    info "用户: $SUDO_USER"
    info "主目录: $USER_HOME"
    info "网络模式: $( [ "$ONLINE_MODE" = true ] && echo "在线" || echo "离线" )"
    info "镜像源: $( [ "$USE_MIRRORS" = true ] && echo "启用" || echo "禁用" )"
    info "代理设置: ${HTTP_PROXY:-无}"
    echo
}

show_installation_summary() {
    echo
    highlight "=== 安装计划摘要 ==="
    info "将安装以下组件："
    [ "$INSTALL_TERMINAL" = true ] && info "  ✓ 终端美化 (Zsh, Oh-My-Zsh, Powerlevel10k)"
    [ "$INSTALL_DESKTOP" = true ] && info "  ✓ 桌面美化 ($THEME 主题, GNOME扩展)"
    [ "$INSTALL_FINGERPRINT" = true ] && info "  ✓ 指纹支持 (华为设备优化)"
    [ "$INSTALL_PERFORMANCE" = true ] && info "  ✓ 系统性能优化"
    echo
    info "硬件优化："
    [ "$IS_HUAWEI" = true ] && info "  ✓ 华为设备优化"
    [ "$HAS_NVIDIA" = true ] && [ "$OPTIMIZE_NVIDIA" = true ] && info "  ✓ NVIDIA显卡优化"
    [ "$OPTIMIZE_BATTERY" = true ] && info "  ✓ 电池优化"
    echo
    info "运行模式: $( [ "$ONLINE_MODE" = true ] && echo "在线" || echo "离线" )"
    info "预计时间: 15-45分钟 (取决于网络速度)"
    info "磁盘空间: 约 1-3 GB"
    info "日志文件: $LOG_FILE"
    highlight "=============================================="
    
    if ! confirm "是否继续安装？"; then
        info "用户取消安装"
        exit 0
    fi
}

verify_installation() {
    echo
    highlight "=== 安装验证结果 ==="
    
    local errors=0
    local warnings=0
    
    check_component() {
        local name="$1"
        local cmd="$2"
        local optional="${3:-false}"
        
        if eval "$cmd" >/dev/null 2>&1; then
            green "  ✓ $name 安装成功"
            return 0
        else
            if [ "$optional" = true ]; then
                warn "  ⚠ $name 未安装（可选）"
                ((warnings++))
            else
                red "  ✗ $name 安装失败"
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
    check_component "WhiteSur主题" "[ -d /usr/share/themes/WhiteSur* ]" "true"
    check_component "Nerd Fonts" "fc-list | grep -q 'Nerd Font'" "true"
    check_component "性能工具" "command -v tlp" "true"
    
    echo
    highlight "=============================================="
    if [ $errors -eq 0 ]; then
        green "所有核心组件安装成功！"
        if [ $warnings -gt 0 ]; then
            warn "有 $warnings 个可选组件未安装"
        fi
    else
        warn "有 $errors 个核心组件安装失败，$warnings 个可选组件未安装"
        warn "请检查日志文件: $LOG_FILE"
    fi
    highlight "=============================================="
}

# ===================== 卸载功能 =====================
uninstall_beautification() {
    echo
    highlight "=== 卸载 Ubuntu 美化组件 ==="
    
    if ! confirm "确定要卸载所有美化组件吗？"; then
        info "卸载已取消"
        return
    fi
    
    # 恢复备份文件
    info "恢复备份文件..."
    for backup in "${BACKUP_FILES[@]}"; do
        if [ -f "$backup" ]; then
            local original="${backup%.beautify.bak.*}"
            if [ -f "$original" ]; then
                mv "$backup" "$original"
                info "已恢复: $original"
            fi
        fi
    done
    
    # 恢复默认shell
    if command -v bash >/dev/null; then
        chsh -s /bin/bash "$SUDO_USER"
    fi
    
    # 删除用户配置文件
    if [ -f "${USER_HOME}/.zshrc" ]; then
        rm -f "${USER_HOME}/.zshrc"
    fi
    
    # 删除oh-my-zsh
    if [ -d "${USER_HOME}/.oh-my-zsh" ]; then
        rm -rf "${USER_HOME}/.oh-my-zsh"
    fi
    
    # 删除主题和图标
    rm -rf /usr/share/themes/WhiteSur*
    rm -rf /usr/share/icons/WhiteSur*
    
    # 清理缓存
    if [ "$KEEP_CACHE" = false ]; then
        rm -rf "$CACHE_DIR"
    fi
    
    # 删除状态文件
    rm -f "$STATE_FILE"
    
    # 删除配置文件
    if confirm "是否删除配置文件？"; then
        rm -f "$USER_CONFIG_FILE"
    fi
    
    green "卸载完成！建议重启系统使所有更改生效"
}

# ===================== 更新检查 =====================
check_for_updates() {
    if [ "$ONLINE_MODE" = false ]; then
        return
    fi
    
    info "检查脚本更新..."
    
    local latest_version
    local update_urls=(
        "https://raw.githubusercontent.com/example/ubuntu-beautify/main/VERSION"
        "https://ghproxy.com/https://raw.githubusercontent.com/example/ubuntu-beautify/main/VERSION"
    )
    
    for url in "${update_urls[@]}"; do
        if latest_version=$(download_file "$url" "" "version-check"); then
            break
        fi
    done
    
    if [ -n "$latest_version" ] && [ "$latest_version" != "$VERSION" ]; then
        warn "发现新版本: $latest_version (当前: $VERSION)"
        if confirm "是否更新脚本？"; then
            update_script
        fi
    else
        info "脚本已是最新版本 ($VERSION)"
    fi
}

update_script() {
    info "更新脚本..."
    
    local script_urls=(
        "https://raw.githubusercontent.com/example/ubuntu-beautify/main/ubuntu-beautify.sh"
        "https://ghproxy.com/https://raw.githubusercontent.com/example/ubuntu-beautify/main/ubuntu-beautify.sh"
    )
    
    local script_path=$(realpath "$0")
    
    for url in "${script_urls[@]}"; do
        if download_file "$url" "${script_path}.new" "script-update"; then
            chmod +x "${script_path}.new"
            mv "${script_path}.new" "${script_path}"
            green "脚本更新成功！"
            info "请重新运行脚本"
            exit 0
        fi
    done
    
    red "脚本更新失败"
}

# ===================== 帮助信息 =====================
show_help() {
    cat << 'EOF'
Ubuntu 仿 Win11 一键美化脚本 v2.0.0

使用方法:
  sudo ./ubuntu-beautify.sh [选项]

选项:
  -h, --help          显示此帮助信息
  -v, --version       显示版本信息
  -c, --config        生成配置文件
  -u, --uninstall     卸载美化组件
  -f, --full          完整安装（默认）
  -t, --terminal      仅安装终端美化
  -d, --desktop       仅安装桌面美化
  -p, --performance   仅安装性能优化
  -s, --fingerprint   仅安装指纹支持
  --skip-confirm      跳过确认提示
  --no-mirrors       不使用镜像源
  --no-cache         禁用下载缓存
  --keep-cache       安装后保留缓存
  --proxy URL        设置代理服务器

示例:
  sudo ./ubuntu-beautify.sh                    # 交互式完整安装
  sudo ./ubuntu-beautify.sh --full --skip-confirm  # 无确认完整安装
  sudo ./ubuntu-beautify.sh --uninstall        # 卸载美化组件
  sudo ./ubuntu-beautify.sh --terminal         # 仅安装终端美化
  sudo ./ubuntu-beautify.sh --proxy http://proxy.example.com:8080

配置文件:
  用户配置文件: ~/.ubuntu-beautify.conf
  系统配置文件: /etc/ubuntu-beautify.conf
  缓存目录: ~/.cache/ubuntu-beautify
  日志文件: /var/log/ubuntu-beautify/
  状态文件: /var/lib/ubuntu-beautify/state

硬件支持:
  - 华为 MateBook 全系列优化
  - Goodix/Elan 指纹设备
  - NVIDIA/Intel/AMD 显卡优化
  - 电池续航优化

EOF
}

show_version() {
    echo "Ubuntu Beautify Script v$VERSION"
    echo "Copyright (C) 2023 Ubuntu Beautify Team"
    echo "License: MIT"
    echo "GitHub: $REPO_URL"
}

# ===================== 主菜单 =====================
show_menu() {
    echo
    highlight "请选择安装选项:"
    echo "  1) 完整安装（推荐）"
    echo "  2) 仅安装终端美化"
    echo "  3) 仅安装桌面美化"
    echo "  4) 仅安装指纹支持"
    echo "  5) 仅安装性能优化"
    echo "  6) 自定义选择"
    echo "  7) 生成配置文件"
    echo "  8) 卸载美化组件"
    echo "  9) 检查更新"
    echo "  10) 显示帮助"
    echo "  11) 退出"
    echo
    
    read -p "请输入选择 (1-11): " choice
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
            create_default_config
            exit 0
            ;;
        8)
            uninstall_beautification
            exit 0
            ;;
        9)
            check_for_updates
            exit 0
            ;;
        10)
            show_help
            exit 0
            ;;
        11)
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

# ===================== 命令行参数解析 =====================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -c|--config)
                create_default_config
                exit 0
                ;;
            -u|--uninstall)
                uninstall_beautification
                exit 0
                ;;
            -f|--full)
                INSTALL_TERMINAL=true
                INSTALL_DESKTOP=true
                INSTALL_FINGERPRINT=true
                INSTALL_PERFORMANCE=true
                SKIP_CONFIRMATIONS=true
                ;;
            -t|--terminal)
                INSTALL_TERMINAL=true
                INSTALL_DESKTOP=false
                INSTALL_FINGERPRINT=false
                INSTALL_PERFORMANCE=false
                SKIP_CONFIRMATIONS=true
                ;;
            -d|--desktop)
                INSTALL_TERMINAL=false
                INSTALL_DESKTOP=true
                INSTALL_FINGERPRINT=false
                INSTALL_PERFORMANCE=false
                SKIP_CONFIRMATIONS=true
                ;;
            -p|--performance)
                INSTALL_TERMINAL=false
                INSTALL_DESKTOP=false
                INSTALL_FINGERPRINT=false
                INSTALL_PERFORMANCE=true
                SKIP_CONFIRMATIONS=true
                ;;
            -s|--fingerprint)
                INSTALL_TERMINAL=false
                INSTALL_DESKTOP=false
                INSTALL_FINGERPRINT=true
                INSTALL_PERFORMANCE=false
                SKIP_CONFIRMATIONS=true
                ;;
            --skip-confirm)
                SKIP_CONFIRMATIONS=true
                ;;
            --no-mirrors)
                USE_MIRRORS=false
                ;;
            --no-cache)
                ENABLE_CACHE=false
                ;;
            --keep-cache)
                KEEP_CACHE=true
                ;;
            --proxy)
                if [[ -n "${2:-}" ]]; then
                    export HTTP_PROXY="$2"
                    export HTTPS_PROXY="$2"
                    shift
                else
                    red "错误: --proxy 需要参数"
                    exit 1
                fi
                ;;
            *)
                red "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# ===================== 主程序 =====================
main() {
    # 显示标题
    echo "=============================================="
    echo "    Ubuntu 仿 Win11 一键美化脚本 v$VERSION"
    echo "    专为华为 MateBook 系列优化"
    echo "=============================================="
    
    # 权限检查
    if [ $EUID -ne 0 ]; then
        red "错误：请使用 sudo 权限运行此脚本！"
        echo "用法: sudo $0"
        exit 1
    fi
    
    if [ -z "$SUDO_USER" ]; then
        red "错误：禁止直接以 root 用户运行，请用普通用户执行 sudo 命令！"
        exit 1
    fi
    
    USER_HOME="/home/$SUDO_USER"
    if [ ! -d "$USER_HOME" ]; then
        USER_HOME="/home/${SUDO_USER%%-*}"
        if [ ! -d "$USER_HOME" ]; then
            red "错误：普通用户目录 $USER_HOME 不存在！"
            exit 1
        fi
    fi
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 初始化环境
    init_environment
    setup_logging
    
    # 检查更新（命令行模式不检查）
    if [ $# -eq 0 ]; then
        check_for_updates
    fi
    
    # 硬件检测
    detect_hardware
    show_hardware_info
    
    # 检查系统版本
    check_ubuntu_version
    
    # 检查系统资源
    check_system_resources
    monitor_resources
    
    # 检查依赖
    check_dependencies
    
    # 设置下载工具
    setup_download_tool
    
    # 检查网络连接
    check_internet_connection
    
    # 配置镜像源
    setup_mirror_sources
    
    # 显示环境摘要
    show_environment_summary
    
    # 显示菜单（如果没有命令行参数）
    if [ $# -eq 0 ]; then
        show_menu
    fi
    
    # 显示安装摘要
    show_installation_summary
    
    # 估算总步骤数
    local total_steps=2  # 基础组件和字体
    [ "$INSTALL_TERMINAL" = true ] && total_steps=$((total_steps + 1))
    [ "$INSTALL_DESKTOP" = true ] && total_steps=$((total_steps + 1))
    [ "$INSTALL_FINGERPRINT" = true ] && total_steps=$((total_steps + 1))
    [ "$INSTALL_PERFORMANCE" = true ] && total_steps=$((total_steps + 1))
    
    init_progress $total_steps
    
    # 开始安装
    log "INFO" "开始安装过程..."
    
    # 1. 安装系统基础组件
    install_system_basics
    
    # 2. 安装字体
    install_fonts
    
    # 3. 安装终端美化
    if [ "$INSTALL_TERMINAL" = true ]; then
        install_terminal_beautification
    fi
    
    # 4. 安装桌面美化
    if [ "$INSTALL_DESKTOP" = true ]; then
        install_desktop_beautification
    fi
    
    # 5. 安装指纹支持
    if [ "$INSTALL_FINGERPRINT" = true ]; then
        install_fingerprint_support
    fi
    
    # 6. 安装性能优化
    if [ "$INSTALL_PERFORMANCE" = true ]; then
        install_performance_optimization
    fi
    
    # 验证安装结果
    verify_installation
    
    # 保存安装状态
    save_state "INSTALLED" "true"
    save_state "INSTALL_DATE" "$(date '+%Y-%m-%d %H:%M:%S')"
    save_state "VERSION" "$VERSION"
    
    # 显示完成信息
    show_completion_info
}

show_completion_info() {
    echo
    green "===== Ubuntu 仿 Win11 一键美化脚本执行完成！ ====="
    echo
    highlight "重要操作指南："
    echo "  1. 重启系统生效所有配置："
    echo "     sudo reboot"
    echo
    echo "  2. 终端配置（重启后）："
    echo "     a. 首次打开终端会触发 Powerlevel10k 配置向导"
    echo "     b. 如果没触发，手动运行：p10k configure"
    echo "     c. 字体选择：FiraCode Nerd Font 或 Fira Code"
    echo
    echo "  3. 桌面主题配置："
    echo "     a. 打开 '优化' (Gnome Tweaks)"
    echo "     b. 外观 → 主题：选择 $THEME-$THEME_VARIANT"
    echo "     c. 外观 → 图标：选择 $ICON_THEME"
    echo "     d. 外观 → 光标：选择 $CURSOR_THEME"
    echo
    echo "  4. GNOME 扩展："
    echo "     a. 打开 '扩展管理器'"
    echo "     b. 启用 'Dash to Dock' 和 'Arc Menu'"
    echo "     c. 根据需要调整扩展设置"
    echo
    echo "  5. Grub 美化（可选）："
    echo "     sudo grub-customizer"
    echo
    echo "  6. 指纹登录配置："
    echo "     系统设置 → 用户 → 指纹"
    echo "     或运行：sudo pam-auth-update"
    echo
    echo "  7. 性能优化："
    echo "     - Tracker 服务已禁用"
    echo "     - 交换性已优化为 $SWAPPINESS"
    echo "     - 已安装预加载"
    echo "     - 电池优化已启用"
    echo
    echo "  8. 故障排除："
    echo "     查看完整日志：less $LOG_FILE"
    echo
    echo "  9. 卸载美化："
    echo "     sudo $0 --uninstall"
    echo
    highlight "安装摘要："
    echo "  - 终端美化: $( [ "$INSTALL_TERMINAL" = true ] && echo "✓" || echo "✗" )"
    echo "  - 桌面美化: $( [ "$INSTALL_DESKTOP" = true ] && echo "✓" || echo "✗" )"
    echo "  - 指纹支持: $( [ "$INSTALL_FINGERPRINT" = true ] && echo "✓" || echo "✗" )"
    echo "  - 性能优化: $( [ "$INSTALL_PERFORMANCE" = true ] && echo "✓" || echo "✗" )"
    echo "  - 运行模式: $( [ "$ONLINE_MODE" = true ] && echo "在线" || echo "离线" )"
    echo "  - 使用缓存: $( [ "$ENABLE_CACHE" = true ] && echo "是" || echo "否" )"
    echo
    warn "注意：部分配置需要重启后才能完全生效！"
    green "完成！"
}

# ===================== 脚本入口 =====================
main "$@"
