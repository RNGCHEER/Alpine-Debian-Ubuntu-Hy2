#!/usr/bin/env bash
# ============================================================
# Hysteria2 一键安装管理脚本
# 支持: Alpine / Debian / Ubuntu
# 架构: x86_64 / aarch64 / armv7
# 功能: 输入IP、选择端口、自签SNI证书、安装/卸载/管理
#       安装完成后可直接输入 hy2 呼出管理菜单
#       (查看节点信息 / 修改节点配置 / 重启 / 日志 / 卸载)
# ============================================================

set -euo pipefail

# --------------- 常量 ---------------
HY2_SERVICE="hysteria-server"
HY2_CONFIG="/etc/hysteria/config.yaml"
HY2_INFO_FILE="/etc/hysteria/.install_info"
HY2_CERT_DIR="/etc/ssl/private"
HY2_LOG="/var/log/hysteria2.log"
HY2_SCRIPT_URL="https://raw.githubusercontent.com/RNGCHEER/Alpine-Debian-Ubuntu-Hy2/main/hy2.sh"
HY2_LOCAL_SCRIPT="/usr/local/lib/hy2/hy2.sh"
HY2_CMD="/usr/local/bin/hy2"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 变量兜底 (配合 set -u)
OS=""
PKG=""
INIT=""
HY2_ARCH=""
SERVER_IP4=""
SERVER_IP6=""
SERVER_PORT=""
HY2_PASSWORD=""
SNI_DOMAIN=""
CERT_PATH=""
KEY_PATH=""
NODE_NAME=""
MASQUERADE_URL=""
PIN_SHA256=""

# --------------- 工具函数 ---------------
info()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✘]${NC} $*"; }
tip()   { echo -e "${CYAN}[→]${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "请以 root 用户运行此脚本"
        exit 1
    fi
}

# --------------- 系统检测 ---------------
detect_os() {
    if [[ -f /etc/alpine-release ]]; then
        OS="alpine"
        PKG="apk"
    elif [[ -f /etc/debian_version ]] || grep -qi debian /etc/os-release 2>/dev/null; then
        OS="debian"
        PKG="apt"
    elif grep -qi ubuntu /etc/os-release 2>/dev/null; then
        OS="ubuntu"
        PKG="apt"
    else
        err "不支持的系统，仅支持 Alpine / Debian / Ubuntu"
        exit 1
    fi
    info "检测到系统: ${OS}"
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)  HY2_ARCH="amd64" ;;
        aarch64|arm64)  HY2_ARCH="arm64" ;;
        armv7l)         HY2_ARCH="armv7" ;;
        *)
            err "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    info "检测到架构: ${HY2_ARCH}"
}

detect_init() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        INIT="systemd"
    elif command -v openrc &>/dev/null || [[ -f /run/openrc/softlevel ]]; then
        INIT="openrc"
    else
        # Alpine fallback
        if [[ "$OS" == "alpine" ]]; then
            INIT="openrc"
        else
            INIT="systemd"
        fi
    fi
    info "Init 系统: ${INIT}"
}

# 是否已安装 (有配置文件或二进制即视为已安装)
is_installed() {
    if command -v hysteria &>/dev/null; then
        return 0
    fi
    if [[ -f "$HY2_CONFIG" ]]; then
        return 0
    fi
    return 1
}

# 服务是否运行中 (只看状态，不输出)
service_active() {
    if [[ "${INIT:-}" == "systemd" ]]; then
        systemctl is-active --quiet ${HY2_SERVICE} 2>/dev/null
    else
        rc-service ${HY2_SERVICE} status &>/dev/null
    fi
}

# --------------- 安装信息读写 ---------------
# 读取安装信息 (缺失时从 config.yaml 兜底解析)
load_install_info() {
    SERVER_IP4=""; SERVER_IP6=""; SERVER_PORT=""; HY2_PASSWORD=""
    SNI_DOMAIN=""; CERT_PATH=""; KEY_PATH=""; NODE_NAME=""; MASQUERADE_URL=""

    if [[ -f "$HY2_INFO_FILE" ]]; then
        set +u
        # shellcheck disable=SC1090
        source "$HY2_INFO_FILE" || true
        set -u
    fi

    # 从 config.yaml 兜底解析
    if [[ -f "$HY2_CONFIG" ]]; then
        local v
        if [[ -z "${SERVER_PORT:-}" ]]; then
            v=$(grep -E '^listen:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/^listen:[[:space:]]*//;s/[[:space:]]//g' || true)
            v="${v##*:}"
            [[ -n "$v" ]] && SERVER_PORT="$v"
        fi
        if [[ -z "${HY2_PASSWORD:-}" ]]; then
            v=$(grep -E '^[[:space:]]+password:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*password:[[:space:]]*//' || true)
            v="${v%% *}"
            [[ -n "$v" ]] && HY2_PASSWORD="$v"
        fi
        if [[ -z "${CERT_PATH:-}" ]]; then
            v=$(grep -E '^[[:space:]]+cert:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*cert:[[:space:]]*//' || true)
            [[ -n "$v" ]] && CERT_PATH="$v"
        fi
        if [[ -z "${KEY_PATH:-}" ]]; then
            v=$(grep -E '^[[:space:]]+key:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*key:[[:space:]]*//' || true)
            [[ -n "$v" ]] && KEY_PATH="$v"
        fi
        if [[ -z "${SNI_DOMAIN:-}" ]]; then
            v=$(grep -E '^[[:space:]]+sni:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*sni:[[:space:]]*//' || true)
            [[ -n "$v" ]] && SNI_DOMAIN="$v"
        fi
        if [[ -z "${MASQUERADE_URL:-}" ]]; then
            v=$(grep -E '^[[:space:]]+url:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*url:[[:space:]]*//' || true)
            [[ -n "$v" ]] && MASQUERADE_URL="$v"
        fi
    fi

    # 伪装站点兜底
    if [[ -z "${MASQUERADE_URL:-}" ]]; then
        if [[ -n "${SNI_DOMAIN:-}" ]]; then
            MASQUERADE_URL="https://${SNI_DOMAIN}"
        else
            MASQUERADE_URL="https://bing.com"
        fi
    fi

    # IP 兜底: 缺少信息时自动检测
    if [[ -z "${SERVER_IP4:-}" && -z "${SERVER_IP6:-}" ]]; then
        SERVER_IP4=$(curl -4 -fsSL --connect-timeout 4 --max-time 8 "https://api.ipify.org" 2>/dev/null || echo "")
        if [[ -z "$SERVER_IP4" ]]; then
            SERVER_IP6=$(curl -6 -fsSL --connect-timeout 4 --max-time 8 "https://api6.ipify.org" 2>/dev/null || echo "")
        fi
    fi

    NODE_NAME=${NODE_NAME:-Hysteria2-节点}
    SERVER_PORT=${SERVER_PORT:-443}
}

save_install_info() {
    mkdir -p "$(dirname "$HY2_INFO_FILE")"
    cat > "$HY2_INFO_FILE" <<EOF
SERVER_IP4=${SERVER_IP4:-}
SERVER_IP6=${SERVER_IP6:-}
SERVER_PORT=${SERVER_PORT:-443}
HY2_PASSWORD=${HY2_PASSWORD:-}
SNI_DOMAIN=${SNI_DOMAIN:-}
CERT_PATH=${CERT_PATH:-}
KEY_PATH=${KEY_PATH:-}
NODE_NAME=${NODE_NAME:-Hysteria2-节点}
MASQUERADE_URL=${MASQUERADE_URL:-https://${SNI_DOMAIN:-bing.com}}
EOF
    chmod 600 "$HY2_INFO_FILE" 2>/dev/null || true
}

# 以 config.yaml 为准刷新安装信息 (手动编辑配置后同步)
sync_install_info_from_config() {
    [[ -f "$HY2_CONFIG" ]] || return 0
    local v
    v=$(grep -E '^listen:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/^listen:[[:space:]]*//;s/[[:space:]]//g' || true)
    v="${v##*:}"
    if [[ -n "$v" ]]; then SERVER_PORT="$v"; fi

    v=$(grep -E '^[[:space:]]+password:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*password:[[:space:]]*//' || true)
    v="${v%% *}"
    if [[ -n "$v" ]]; then HY2_PASSWORD="$v"; fi

    v=$(grep -E '^[[:space:]]+cert:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*cert:[[:space:]]*//' || true)
    if [[ -n "$v" ]]; then CERT_PATH="$v"; fi

    v=$(grep -E '^[[:space:]]+key:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*key:[[:space:]]*//' || true)
    if [[ -n "$v" ]]; then KEY_PATH="$v"; fi

    v=$(grep -E '^[[:space:]]+sni:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*sni:[[:space:]]*//' || true)
    if [[ -n "$v" ]]; then SNI_DOMAIN="$v"; fi

    v=$(grep -E '^[[:space:]]+url:' "$HY2_CONFIG" 2>/dev/null | head -1 | sed 's/.*url:[[:space:]]*//' || true)
    if [[ -n "$v" ]]; then MASQUERADE_URL="$v"; fi

    save_install_info
}

# --------------- 获取IP ---------------
get_ip() {
    # 自动检测 IPv4
    local auto_ip4
    auto_ip4=$(curl -4 -fsSL --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null || echo "")
    # 自动检测 IPv6
    local auto_ip6
    auto_ip6=$(curl -6 -fsSL --connect-timeout 5 --max-time 10 "https://api6.ipify.org" 2>/dev/null || echo "")

    echo ""
    echo "=========================================="
    tip "自动检测到的 IPv4: ${auto_ip4:-未检测到}"
    tip "自动检测到的 IPv6: ${auto_ip6:-未检测到}"
    echo "=========================================="
    echo ""
    echo "请选择 IP 获取方式:"
    echo "  1) 使用自动检测的 IPv4 (${auto_ip4:-无})"
    echo "  2) 使用自动检测的 IPv6 (${auto_ip6:-无})"
    echo "  3) 手动输入 IP 地址"
    echo "  4) 两者都输出 (IPv4 + IPv6)"
    echo ""
    read -rp "请输入选项 [1-4，默认1]: " ip_choice || ip_choice=1
    ip_choice=${ip_choice:-1}

    case "$ip_choice" in
        1)
            if [[ -z "$auto_ip4" ]]; then
                err "未检测到 IPv4，请手动输入"
                read -rp "请输入 IPv4 地址: " SERVER_IP4 || SERVER_IP4=""
                SERVER_IP6=""
            else
                SERVER_IP4="$auto_ip4"
                SERVER_IP6=""
            fi
            ;;
        2)
            if [[ -z "$auto_ip6" ]]; then
                err "未检测到 IPv6，请手动输入"
                read -rp "请输入 IPv6 地址: " SERVER_IP6 || SERVER_IP6=""
                SERVER_IP4=""
            else
                SERVER_IP6="$auto_ip6"
                SERVER_IP4=""
            fi
            ;;
        3)
            read -rp "请输入 IP 地址 (支持 IPv4 或 IPv6): " custom_ip || custom_ip=""
            if echo "$custom_ip" | grep -q ':'; then
                SERVER_IP6="$custom_ip"
                SERVER_IP4=""
            else
                SERVER_IP4="$custom_ip"
                SERVER_IP6=""
            fi
            ;;
        4)
            if [[ -z "$auto_ip4" ]]; then
                read -rp "请输入 IPv4 地址: " SERVER_IP4 || SERVER_IP4=""
            else
                SERVER_IP4="$auto_ip4"
            fi
            if [[ -z "$auto_ip6" ]]; then
                read -rp "请输入 IPv6 地址 (回车跳过): " SERVER_IP6 || SERVER_IP6=""
            else
                SERVER_IP6="$auto_ip6"
            fi
            ;;
        *)
            SERVER_IP4="${auto_ip4}"
            SERVER_IP6=""
            ;;
    esac

    if [[ -n "${SERVER_IP4:-}" ]]; then info "IPv4: ${SERVER_IP4}"; fi
    if [[ -n "${SERVER_IP6:-}" ]]; then info "IPv6: ${SERVER_IP6}"; fi
}

# --------------- 选择端口 ---------------
get_port() {
    echo ""
    echo "=========================================="
    echo "  请选择 HY2 端口:"
    echo "  1) 443  (默认)"
    echo "  2) 8443"
    echo "  3) 自定义端口"
    echo "=========================================="
    read -rp "请输入选项 [1-3，默认1]: " port_choice || port_choice=1
    port_choice=${port_choice:-1}

    case "$port_choice" in
        1) SERVER_PORT=443 ;;
        2) SERVER_PORT=8443 ;;
        3)
            while true; do
                read -rp "请输入端口号 (1-65535): " SERVER_PORT || SERVER_PORT=""
                if [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && (( SERVER_PORT >= 1 && SERVER_PORT <= 65535 )); then
                    break
                fi
                err "无效端口号，请重新输入"
            done
            ;;
        *) SERVER_PORT=443 ;;
    esac
    info "使用端口: ${SERVER_PORT}"
}

# --------------- SNI 域名选择 (仅选择，不生成证书) ---------------
select_sni_from_list() {
    echo "" >&2
    echo "  推荐域名 (用于SNI伪装):" >&2
    echo "    ---- 科技巨头 ----" >&2
    echo "    1) bing.com               (微软必应)" >&2
    echo "    2) microsoft.com          (微软官网)" >&2
    echo "    3) windows.com            (Windows)" >&2
    echo "    4) outlook.com            (Outlook邮箱)" >&2
    echo "    5) cloudflare.com         (Cloudflare)" >&2
    echo "    6) apple.com               (苹果官网)" >&2
    echo "    7) google.com             (谷歌)" >&2
    echo "    8) github.com             (GitHub)" >&2
    echo "    ---- CDN/云服务 ----" >&2
    echo "    9) amazon.com             (亚马逊)" >&2
    echo "   10) aws.amazon.com         (AWS)" >&2
    echo "   11) azure.com              (Azure)" >&2
    echo "   12) fastly.com             (Fastly CDN)" >&2
    echo "   13) akamai.com             (Akamai)" >&2
    echo "   14) edgekey.net            (Akamai Edge)" >&2
    echo "   ---- 媒体/社交 ----" >&2
    echo "   15) twitter.com            (推特)" >&2
    echo "   16) x.com                  (X/Twitter)" >&2
    echo "   17) youtube.com            (YouTube)" >&2
    echo "   18) facebook.com           (Facebook)" >&2
    echo "   19) instagram.com          (Instagram)" >&2
    echo "   20) tiktok.com             (TikTok)" >&2
    echo "   ---- 中国网站 ----" >&2
    echo "   21) qq.com                 (腾讯QQ)" >&2
    echo "   22) taobao.com             (淘宝)" >&2
    echo "   23) baidu.com              (百度)" >&2
    echo "   24) weibo.com              (微博)" >&2
    echo "   25) jd.com                 (京东)" >&2
    echo "   26) 163.com                (网易)" >&2
    echo "   ---- 其他 ----" >&2
    echo "   27) zoom.us                (Zoom)" >&2
    echo "   28) teams.microsoft.com    (Teams)" >&2
    echo "   29) linkedin.com           (LinkedIn)" >&2
    echo "   30) shopify.com            (Shopify)" >&2
    echo "   31) netflix.com            (Netflix)" >&2
    echo "   32) 自定义域名" >&2
    echo "" >&2
    read -rp "请选择域名 [1-32，默认1]: " domain_choice || domain_choice=1
    domain_choice=${domain_choice:-1}

    local domain=""
    case "$domain_choice" in
        1)  domain="bing.com" ;;
        2)  domain="microsoft.com" ;;
        3)  domain="windows.com" ;;
        4)  domain="outlook.com" ;;
        5)  domain="cloudflare.com" ;;
        6)  domain="apple.com" ;;
        7)  domain="google.com" ;;
        8)  domain="github.com" ;;
        9)  domain="amazon.com" ;;
        10) domain="aws.amazon.com" ;;
        11) domain="azure.com" ;;
        12) domain="fastly.com" ;;
        13) domain="akamai.com" ;;
        14) domain="edgekey.net" ;;
        15) domain="twitter.com" ;;
        16) domain="x.com" ;;
        17) domain="youtube.com" ;;
        18) domain="facebook.com" ;;
        19) domain="instagram.com" ;;
        20) domain="tiktok.com" ;;
        21) domain="qq.com" ;;
        22) domain="taobao.com" ;;
        23) domain="baidu.com" ;;
        24) domain="weibo.com" ;;
        25) domain="jd.com" ;;
        26) domain="163.com" ;;
        27) domain="zoom.us" ;;
        28) domain="teams.microsoft.com" ;;
        29) domain="linkedin.com" ;;
        30) domain="shopify.com" ;;
        31) domain="netflix.com" ;;
        32)
            read -rp "请输入自定义域名: " domain || domain=""
            if [[ -z "$domain" ]]; then
                domain="bing.com"
                warn "域名为空，使用默认: bing.com" >&2
            fi
            ;;
        *) domain="bing.com" ;;
    esac
    echo "$domain"
}

# --------------- 生成自签证书 ---------------
generate_self_signed_cert() {
    mkdir -p "$HY2_CERT_DIR"

    # 安装 openssl
    if ! command -v openssl &>/dev/null; then
        install_deps "openssl"
    fi

    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -subj "/CN=${SNI_DOMAIN}" \
        -days 36500 2>/dev/null

    chmod -R 777 "$HY2_CERT_DIR"
    info "自签证书已生成: ${CERT_PATH}"
    info "自签密钥已生成: ${KEY_PATH}"

    # 计算 pinSHA256
    PIN_SHA256=$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256 2>/dev/null \
        | sed 's/.*=//;s/://g' || echo "")
    if [[ -n "$PIN_SHA256" ]]; then
        info "pinSHA256: ${PIN_SHA256}"
    fi
}

# --------------- SNI 域名 / 证书 ---------------
get_sni_domain() {
    echo ""
    echo "=========================================="
    echo "  SNI 证书域名设置"
    echo "  1) 使用自签证书 (自动生成)"
    echo "  2) 使用已有证书 (指定路径)"
    echo "=========================================="
    read -rp "请输入选项 [1-2，默认1]: " cert_choice || cert_choice=1
    cert_choice=${cert_choice:-1}

    case "$cert_choice" in
        1)
            SNI_DOMAIN=$(select_sni_from_list)
            CERT_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.crt"
            KEY_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.key"

            info "生成自签证书: ${SNI_DOMAIN}"
            generate_self_signed_cert
            ;;
        2)
            read -rp "请输入证书文件路径 (.crt): " CERT_PATH || CERT_PATH=""
            read -rp "请输入密钥文件路径 (.key): " KEY_PATH || KEY_PATH=""

            if [[ ! -f "$CERT_PATH" ]]; then
                err "证书文件不存在: $CERT_PATH"
                exit 1
            fi
            if [[ ! -f "$KEY_PATH" ]]; then
                err "密钥文件不存在: $KEY_PATH"
                exit 1
            fi
            # 从证书提取 CN 作为 SNI
            SNI_DOMAIN=$(openssl x509 -in "$CERT_PATH" -noout -subject 2>/dev/null \
                | sed 's/.*CN\s*=\s*//' | sed 's/\/.*//' || echo "unknown")

            info "使用已有证书: ${CERT_PATH}"
            info "证书 CN/SNI: ${SNI_DOMAIN}"
            ;;
    esac

    # 伪装站点默认与 SNI 一致
    MASQUERADE_URL="https://${SNI_DOMAIN}"
}

# --------------- 生成密码 ---------------
gen_password() {
    HY2_PASSWORD=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        openssl rand -hex 16)
    info "生成随机密码: ${HY2_PASSWORD}"
}

# --------------- 节点命名 ---------------
get_node_name() {
    echo ""
    echo "=========================================="
    echo " 🏷️  节点命名"
    echo "=========================================="
    echo ""
    tip "为你的 Hysteria2 节点设置一个名称"
    tip "该名称将显示在客户端的节点列表中"
    echo ""
    tip "示例: 香港-01, 日本节点, 自建-IEPL, 东京BGP..."
    echo ""
    read -rp "请输入节点名称 (回车使用默认名称): " NODE_NAME || NODE_NAME=""
    NODE_NAME=${NODE_NAME:-"Hysteria2-节点"}
    info "节点名称: ${NODE_NAME}"
}

# --------------- 安装依赖 ---------------
install_deps() {
    local extra="${1:-}"
    info "安装依赖..."
    if [[ "${PKG:-}" == "apk" ]]; then
        apk update
        apk add curl wget openssl $extra
    else
        apt update
        apt install -y curl wget openssl $extra
    fi
}

# --------------- 安装 Hysteria2 ---------------
install_hy2() {
    info "安装 Hysteria2..."

    # 检查是否已安装
    if command -v hysteria &>/dev/null; then
        local cur_ver
        cur_ver=$(hysteria version 2>/dev/null | head -1 || echo "未知")
        warn "已安装 Hysteria2: ${cur_ver}"
        read -rp "是否重新安装? [y/N]: " reinstall || reinstall=""
        if [[ "${reinstall,,}" != "y" ]]; then
            return 0
        fi
    fi

    if [[ "$OS" == "alpine" ]]; then
        # ---- Alpine: 手动下载，不走官方脚本 (BusyBox grep/useradd 不兼容) ----
        info "Alpine 系统，使用手动安装..."
        _install_hy2_manual
    else
        # ---- Debian/Ubuntu: 优先官方脚本 ----
        bash <(curl -fsSL "https://get.hy2.sh/") 2>&1

        if command -v hysteria &>/dev/null; then
            info "Hysteria2 安装成功"
        else
            warn "官方脚本安装失败，尝试手动下载..."
            _install_hy2_manual
        fi
    fi
}

# 手动下载安装 (所有系统通用)
_install_hy2_manual() {
    # 版本号：默认值先写死，API 获取失败时直接用
    HY2_VER="2.12.2"
    HY2_TAG="app/v${HY2_VER}"
    api_result=$(curl -fsSL --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/apernet/hysteria/releases/latest" 2>/dev/null) || true
    if [ -n "$api_result" ]; then
        # 提取完整 tag_name (如 app/v2.12.2)，保留 app/ 前缀
        detected_tag=$(echo "$api_result" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/".*//') || true
        if [ -n "$detected_tag" ]; then
            HY2_TAG="$detected_tag"
            HY2_VER="${detected_tag#*/}"
        fi
    fi

    bin_url="https://github.com/apernet/hysteria/releases/download/${HY2_TAG}/hysteria-linux-${HY2_ARCH}"
    info "下载 Hysteria2 v${HY2_VER} (${HY2_ARCH})..."
    tip "URL: ${bin_url}"

    # GitHub releases 需要 -L 跟随重定向
    if curl -fSL --connect-timeout 15 --max-time 180 -o /usr/local/bin/hysteria "$bin_url" 2>/dev/null; then
        chmod +x /usr/local/bin/hysteria
    elif wget --timeout=120 -q -O /usr/local/bin/hysteria "$bin_url" 2>/dev/null; then
        chmod +x /usr/local/bin/hysteria
    else
        err "下载失败，请检查网络或手动下载:"
        tip "curl -fSL -o /usr/local/bin/hysteria '${bin_url}'"
        exit 1
    fi

    if ! command -v hysteria &>/dev/null; then
        err "Hysteria2 安装失败"
        exit 1
    fi

    # 创建 hysteria 用户 (Alpine 用 adduser，Debian/Ubuntu 用 useradd)
    if ! id hysteria &>/dev/null 2>&1; then
        if command -v adduser &>/dev/null && [[ "$OS" == "alpine" ]]; then
            adduser -S -s /sbin/nologin hysteria 2>/dev/null || true
        elif command -v useradd &>/dev/null; then
            useradd -r -s /sbin/nologin hysteria 2>/dev/null || true
        fi
    fi

    info "Hysteria2 v${HY2_VER} 手动安装成功"
}

# --------------- 安装 hy2 快捷命令 ---------------
install_hy2_command() {
    info "安装 hy2 快捷命令..."

    # Alpine 默认没有 bash，而本脚本需要 bash
    if ! command -v bash &>/dev/null && [[ -f /etc/alpine-release ]]; then
        warn "未检测到 bash，正在安装..."
        apk add --no-cache bash 2>/dev/null || warn "bash 安装失败，请手动执行: apk add bash"
    fi

    mkdir -p "$(dirname "$HY2_LOCAL_SCRIPT")"
    mkdir -p "$(dirname "$HY2_CMD")"

    # 优先保存脚本自身副本，保证离线也能用
    local self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && "$self" != "$HY2_LOCAL_SCRIPT" && -f "$self" ]]; then
        cp -f "$self" "$HY2_LOCAL_SCRIPT" 2>/dev/null || true
    fi
    if [[ ! -s "$HY2_LOCAL_SCRIPT" ]]; then
        curl -fsSL --connect-timeout 10 --max-time 60 -o "$HY2_LOCAL_SCRIPT" "$HY2_SCRIPT_URL" 2>/dev/null || true
    fi

    cat > "$HY2_CMD" <<EOF
#!/usr/bin/env bash
# hy2 快捷命令 - 由 Hysteria2 一键脚本自动生成
# 用法: hy2  (呼出管理菜单)  |  hy2 info / edit / restart / log / uninstall / update
HY2_LOCAL_SCRIPT="${HY2_LOCAL_SCRIPT}"
HY2_SCRIPT_URL="${HY2_SCRIPT_URL}"

if [[ ! -s "\$HY2_LOCAL_SCRIPT" ]]; then
    mkdir -p "\$(dirname "\$HY2_LOCAL_SCRIPT")"
    curl -fsSL --connect-timeout 10 --max-time 60 -o "\$HY2_LOCAL_SCRIPT" "\$HY2_SCRIPT_URL" 2>/dev/null || true
fi

if [[ -s "\$HY2_LOCAL_SCRIPT" ]]; then
    exec bash "\$HY2_LOCAL_SCRIPT" "\$@"
fi

exec bash <(curl -fsSL "\$HY2_SCRIPT_URL") "\$@"
EOF
    chmod +x "$HY2_CMD"

    if [[ -x "$HY2_CMD" ]]; then
        info "已安装命令: hy2  (之后在终端输入 hy2 即可呼出管理菜单)"
    else
        warn "hy2 命令创建失败，仍可用: bash <(curl -fsSL ${HY2_SCRIPT_URL})"
    fi
}

# --------------- 更新脚本 ---------------
do_update_script() {
    check_root
    info "正在从 GitHub 更新脚本..."
    mkdir -p "$(dirname "$HY2_LOCAL_SCRIPT")"
    if curl -fsSL --connect-timeout 10 --max-time 60 -o "${HY2_LOCAL_SCRIPT}.tmp" "$HY2_SCRIPT_URL"; then
        mv -f "${HY2_LOCAL_SCRIPT}.tmp" "$HY2_LOCAL_SCRIPT"
        chmod +x "$HY2_LOCAL_SCRIPT"
        # 脚本自身即为最新版时，用自身覆盖缓存副本
        local self="${BASH_SOURCE[0]:-}"
        if [[ -n "$self" && "$self" != "$HY2_LOCAL_SCRIPT" && -f "$self" ]]; then
            cp -f "$self" "$HY2_LOCAL_SCRIPT" 2>/dev/null || true
        fi
        install_hy2_command
        info "脚本已更新: ${HY2_LOCAL_SCRIPT} (下次输入 hy2 生效)"
    else
        rm -f "${HY2_LOCAL_SCRIPT}.tmp" 2>/dev/null || true
        err "下载失败，请检查网络"
        return 1
    fi
}

# --------------- 写配置文件 ---------------
write_config() {
    info "写入配置文件..."
    mkdir -p "$(dirname "$HY2_CONFIG")"

    # 根据证书类型决定 SNI 和 insecure 设置
    cat > "$HY2_CONFIG" <<EOF
# Hysteria2 配置文件 - 自动生成
listen: :${SERVER_PORT}

tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}
  sni: ${SNI_DOMAIN}
  insecure: true

auth:
  type: password
  password: ${HY2_PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: ${MASQUERADE_URL:-https://${SNI_DOMAIN}}
    rewriteHost: true
EOF

    info "配置文件已写入: ${HY2_CONFIG}"
}

# --------------- 进程管理 (systemd) ---------------
setup_systemd() {
    info "配置 systemd 服务..."
    cat > /etc/systemd/system/${HY2_SERVICE}.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
Type=simple
ExecStart=$(command -v hysteria) server -c ${HY2_CONFIG}
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${HY2_SERVICE}
    systemctl restart ${HY2_SERVICE}

    if systemctl is-active --quiet ${HY2_SERVICE}; then
        info "systemd 服务已启动"
    else
        err "服务启动失败，查看日志: journalctl -u ${HY2_SERVICE} -n 20"
    fi
}

# --------------- 进程管理 (openrc - Alpine) ---------------
setup_openrc() {
    info "配置 OpenRC 服务..."
    cat > /etc/init.d/${HY2_SERVICE} <<'INITEOF'
#!/sbin/openrc-run

name="hysteria-server"
description="Hysteria2 Server"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/hysteria2.log"
error_log="/var/log/hysteria2.log"

depend() {
    need net
    after firewall
}
INITEOF
    chmod +x /etc/init.d/${HY2_SERVICE}
    rc-update add ${HY2_SERVICE} default
    rc-service ${HY2_SERVICE} restart

    if rc-service ${HY2_SERVICE} status &>/dev/null; then
        info "OpenRC 服务已启动"
    else
        warn "服务可能未正常启动，请检查日志: /var/log/hysteria2.log"
    fi
}

# --------------- 重启服务 (带健康检查) ---------------
restart_service() {
    detect_init
    if [[ "$INIT" == "systemd" ]]; then
        systemctl restart ${HY2_SERVICE} 2>/dev/null || true
        sleep 1
        if systemctl is-active --quiet ${HY2_SERVICE}; then
            info "服务已重启"
        else
            err "服务启动失败，查看日志: journalctl -u ${HY2_SERVICE} -n 30"
            return 1
        fi
    else
        rc-service ${HY2_SERVICE} restart 2>/dev/null || true
        sleep 1
        if rc-service ${HY2_SERVICE} status &>/dev/null; then
            info "服务已重启"
        else
            warn "服务可能未正常启动，请检查日志: ${HY2_LOG}"
            return 1
        fi
    fi
    return 0
}

# --------------- 输出分享链接 ---------------
show_links() {
    local port="${SERVER_PORT:-443}"
    local pwd="${HY2_PASSWORD:-}"
    local sni="${SNI_DOMAIN:-}"
    local display_name="${NODE_NAME:-Hysteria2-节点}"

    # 根据 IP 情况决定链接中的节点名称
    local link_name_v4="$display_name"
    local link_name_v6="$display_name"
    if [[ -n "${SERVER_IP4:-}" && -n "${SERVER_IP6:-}" ]]; then
        link_name_v4="${display_name}-IPv4"
        link_name_v6="${display_name}-IPv6"
    fi

    echo ""
    echo "------------ 分享链接 ------------"
    if [[ -n "${SERVER_IP4:-}" ]]; then
        tip "IPv4 链接: hysteria2://${pwd}@${SERVER_IP4}:${port}?sni=${sni}&insecure=1#${link_name_v4}"
    fi
    if [[ -n "${SERVER_IP6:-}" ]]; then
        tip "IPv6 链接: hysteria2://${pwd}@[${SERVER_IP6}]:${port}?sni=${sni}&insecure=1#${link_name_v6}"
    fi
    if [[ -z "${SERVER_IP4:-}" && -z "${SERVER_IP6:-}" ]]; then
        warn "未获取到 IP 地址，无法生成分享链接"
    fi
    echo "----------------------------------"
    echo ""
}

# --------------- 生成链接 (安装完成提示) ---------------
generate_link() {
    echo ""
    echo "============================================================"
    echo "  Hysteria2 安装完成!"
    echo "============================================================"
    echo ""

    echo "------------ 客户端配置信息 ------------"
    tip "🏷️  节点名称: ${NODE_NAME}"
    tip "地址:     ${SERVER_IP4:-${SERVER_IP6}}"
    tip "端口:     ${SERVER_PORT}"
    tip "密码:     ${HY2_PASSWORD}"
    tip "SNI:      ${SNI_DOMAIN}"
    tip "证书:     自签 (客户端需开启 insecure)"
    if [[ -n "${PIN_SHA256:-}" ]]; then
        tip "pinSHA256: ${PIN_SHA256}"
    fi
    echo "----------------------------------------"

    show_links
}

# --------------- 安装主流程 ---------------
do_install() {
    echo ""
    echo "======================================================"
    echo "  Hysteria2 一键安装脚本"
    echo "  支持: Alpine / Debian / Ubuntu"
    echo "  架构: x86_64 / aarch64 / armv7"
    echo "======================================================"
    echo ""

    check_root
    detect_os
    detect_arch
    detect_init
    install_deps
    get_ip
    get_port
    get_node_name
    get_sni_domain
    gen_password
    install_hy2
    write_config

    # 启动服务
    if [[ "$INIT" == "systemd" ]]; then
        setup_systemd
    else
        setup_openrc
    fi

    generate_link

    # 保存安装信息到文件，方便后续管理
    save_install_info
    info "安装信息已保存至: ${HY2_INFO_FILE}"

    # 安装 hy2 快捷命令
    install_hy2_command

    info "配置文件位置: ${HY2_CONFIG}"
    echo ""
    echo "============================================================"
    tip "以后在终端直接输入  hy2  即可呼出管理菜单"
    tip "  ( 查看节点信息 / 修改节点配置 / 重启服务 / 查看日志 / 卸载 )"
    echo "============================================================"
    echo ""
}

# --------------- 卸载 ---------------
do_uninstall() {
    check_root
    detect_os
    detect_init

    warn "即将卸载 Hysteria2，此操作不可撤销!"
    read -rp "确认卸载? [y/N]: " confirm || confirm=""
    if [[ "${confirm,,}" != "y" ]]; then
        info "已取消卸载"
        return 0
    fi

    # 停止服务
    if [[ "$INIT" == "systemd" ]]; then
        systemctl stop ${HY2_SERVICE} 2>/dev/null || true
        systemctl disable ${HY2_SERVICE} 2>/dev/null || true
        rm -f /etc/systemd/system/${HY2_SERVICE}.service
        systemctl daemon-reload
    else
        rc-service ${HY2_SERVICE} stop 2>/dev/null || true
        rc-update del ${HY2_SERVICE} 2>/dev/null || true
        rm -f /etc/init.d/${HY2_SERVICE}
    fi

    # 删除文件
    rm -f "$(command -v hysteria 2>/dev/null)" 2>/dev/null || true
    rm -f /usr/local/bin/hysteria 2>/dev/null || true
    rm -rf /etc/hysteria 2>/dev/null || true
    rm -rf "$HY2_CERT_DIR" 2>/dev/null || true
    rm -f "$HY2_LOG" 2>/dev/null || true

    # 删除 hy2 快捷命令
    rm -f "$HY2_CMD" 2>/dev/null || true
    rm -rf "$(dirname "$HY2_LOCAL_SCRIPT")" 2>/dev/null || true

    info "Hysteria2 已卸载 (hy2 快捷命令已移除)"
}

# --------------- 查看节点信息 ---------------
do_node_info() {
    check_root
    detect_init
    load_install_info

    echo ""
    echo "======================================================"
    echo "  Hysteria2 节点信息"
    echo "======================================================"
    echo ""

    # ---- 服务状态 ----
    echo "------------ 服务状态 ------------"
    if service_active; then
        local pid
        pid=$(pgrep -f "hysteria server" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            echo "  运行状态: ${GREEN}运行中${NC} (PID ${pid})"
        else
            echo "  运行状态: ${GREEN}运行中${NC}"
        fi
    else
        echo "  运行状态: ${RED}未运行${NC}"
    fi

    if [[ "$INIT" == "systemd" ]]; then
        if systemctl is-enabled --quiet ${HY2_SERVICE} 2>/dev/null; then
            echo "  开机自启: 已启用"
        else
            echo "  开机自启: 未启用"
        fi
    else
        if rc-update show default 2>/dev/null | grep -q "${HY2_SERVICE}"; then
            echo "  开机自启: 已启用"
        else
            echo "  开机自启: 未启用"
        fi
    fi

    if command -v hysteria &>/dev/null; then
        local ver
        ver=$(hysteria version 2>/dev/null | head -1 || echo "未知")
        echo "  版本:     ${ver}"
    else
        echo "  版本:     未安装"
    fi
    echo "----------------------------------"
    echo ""

    # ---- 节点参数 ----
    echo "------------ 节点参数 ------------"
    echo "  🏷️  节点名称: ${NODE_NAME}"
    echo "  IPv4:     ${SERVER_IP4:-无}"
    echo "  IPv6:     ${SERVER_IP6:-无}"
    echo "  端口:     ${SERVER_PORT} (UDP)"
    echo "  密码:     ${HY2_PASSWORD:-未读取到}"
    echo "  SNI:      ${SNI_DOMAIN:-未读取到}"
    echo "  伪装站点: ${MASQUERADE_URL:-未读取到}"

    if [[ -n "${CERT_PATH:-}" ]]; then
        if [[ -f "$CERT_PATH" ]]; then
            echo "  证书:     ${CERT_PATH}"
            if [[ "$CERT_PATH" == "${HY2_CERT_DIR}/"* ]]; then
                echo "  证书类型: 自签 (客户端需设置 insecure: true)"
            else
                echo "  证书类型: 自定义证书"
            fi
            if command -v openssl &>/dev/null; then
                local end_date pin
                end_date=$(openssl x509 -in "$CERT_PATH" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || true)
                pin=$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//;s/://g' || true)
                if [[ -n "$end_date" ]]; then
                    echo "  证书有效期: ${end_date}"
                fi
                if [[ -n "$pin" ]]; then
                    echo "  pinSHA256: ${pin}"
                fi
            fi
        else
            echo "  证书:     ${CERT_PATH} ${RED}(文件不存在!)${NC}"
        fi
    fi
    echo "  配置文件: ${HY2_CONFIG}"
    if [[ -f "$HY2_INFO_FILE" ]]; then
        echo "  信息文件: ${HY2_INFO_FILE}"
    fi
    echo "----------------------------------"
    echo ""

    # ---- 分享链接 ----
    show_links

    echo "  ${CYAN}提示: 输入 hy2 呼出菜单，选择 2 可修改以上配置${NC}"
    echo ""
}

# --------------- 修改节点配置 ---------------
do_edit_config() {
    check_root
    detect_init
    load_install_info

    if [[ ! -f "$HY2_CONFIG" ]]; then
        err "未找到配置文件 ${HY2_CONFIG}，请先安装 Hysteria2"
        return 1
    fi

    while true; do
        echo ""
        echo "======================================================"
        echo "  修改节点配置"
        echo "======================================================"
        echo ""
        echo "  当前: 🏷️ ${NODE_NAME} | 端口 ${SERVER_PORT} | SNI ${SNI_DOMAIN}"
        echo ""
        echo "  1) 修改节点名称"
        echo "  2) 修改端口"
        echo "  3) 修改密码 (重新生成随机密码)"
        echo "  4) 修改 SNI / 证书"
        echo "  5) 修改伪装站点 (masquerade)"
        echo "  6) 修改 IP 地址 (影响分享链接)"
        echo "  7) 直接编辑 config.yaml (高级)"
        echo "  0) 返回上级菜单"
        echo ""
        read -rp "请输入 [0-7]: " c || c=0

        case "${c:-0}" in
            1) edit_node_name || true ;;
            2) edit_port || true ;;
            3) edit_password || true ;;
            4) edit_sni || true ;;
            5) edit_masquerade || true ;;
            6) edit_ip || true ;;
            7) edit_raw_config || true ;;
            0) return 0 ;;
            *) err "无效选项" ;;
        esac

        load_install_info
    done
}

edit_node_name() {
    echo ""
    echo "  当前节点名称: ${NODE_NAME}"
    local new_name=""
    read -rp "请输入新的节点名称 (回车保持不变): " new_name || new_name=""
    if [[ -z "$new_name" ]]; then
        info "未修改"
        return 0
    fi
    NODE_NAME="$new_name"
    save_install_info
    info "节点名称已更新: ${NODE_NAME}"
    tip "节点名称只影响分享链接里的显示名，无需重启服务"
    show_links
}

edit_port() {
    echo ""
    echo "  当前端口: ${SERVER_PORT}"
    local new_port=""
    read -rp "请输入新端口 (1-65535，回车保持不变): " new_port || new_port=""
    if [[ -z "$new_port" ]]; then
        info "未修改"
        return 0
    fi
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
        err "无效端口号: ${new_port}"
        return 0
    fi
    if [[ "$new_port" == "$SERVER_PORT" ]]; then
        info "端口未变化"
        return 0
    fi

    # 端口占用检查 (UDP)
    if command -v ss &>/dev/null && ss -lun 2>/dev/null | grep -q ":${new_port}[[:space:]]"; then
        warn "端口 UDP ${new_port} 似乎已被占用，请确认后继续"
    fi

    local old_port="$SERVER_PORT"
    SERVER_PORT="$new_port"
    write_config
    save_install_info
    restart_service || true
    info "端口已修改: ${old_port} -> ${SERVER_PORT}"
    warn "请确保防火墙 / 安全组已放行 UDP ${SERVER_PORT}"
    show_links
}

edit_password() {
    echo ""
    echo "  当前密码: ${HY2_PASSWORD}"
    local ans=""
    read -rp "是否重新生成随机密码? [y/N]: " ans || ans=""
    if [[ "${ans,,}" != "y" ]]; then
        info "未修改"
        return 0
    fi
    gen_password
    write_config
    save_install_info
    restart_service || true
    info "密码已更新，客户端需要使用新链接"
    show_links
}

edit_sni() {
    local sni_prev="$SNI_DOMAIN"
    echo ""
    echo "  当前 SNI: ${SNI_DOMAIN}"
    echo "  当前证书: ${CERT_PATH:-未设置}"
    echo ""
    echo "  1) 使用自签证书 (重新生成)"
    echo "  2) 使用已有证书 (指定路径)"
    echo "  0) 返回"
    echo ""
    local c=""
    read -rp "请输入 [0-2]: " c || c=0
    case "${c:-0}" in
        1)
            local new_sni
            new_sni=$(select_sni_from_list)
            SNI_DOMAIN="$new_sni"
            CERT_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.crt"
            KEY_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.key"
            generate_self_signed_cert
            # 伪装站点若原本跟随 SNI，则同步更新
            if [[ -z "${MASQUERADE_URL:-}" || "$MASQUERADE_URL" == "https://${sni_prev}" ]]; then
                MASQUERADE_URL="https://${SNI_DOMAIN}"
            fi
            write_config
            save_install_info
            restart_service || true
            info "SNI 已更新: ${SNI_DOMAIN}"
            show_links
            ;;
        2)
            local new_cert="" new_key=""
            read -rp "请输入证书文件路径 (.crt): " new_cert || new_cert=""
            read -rp "请输入密钥文件路径 (.key): " new_key || new_key=""
            if [[ ! -f "$new_cert" ]]; then
                err "证书文件不存在: ${new_cert}"
                return 0
            fi
            if [[ ! -f "$new_key" ]]; then
                err "密钥文件不存在: ${new_key}"
                return 0
            fi
            CERT_PATH="$new_cert"
            KEY_PATH="$new_key"
            local cn
            cn=$(openssl x509 -in "$CERT_PATH" -noout -subject 2>/dev/null \
                | sed 's/.*CN\s*=\s*//' | sed 's/\/.*//' || echo "")
            if [[ -n "$cn" ]]; then
                SNI_DOMAIN="$cn"
            fi
            write_config
            save_install_info
            restart_service || true
            info "已切换证书: ${CERT_PATH}"
            info "SNI: ${SNI_DOMAIN}"
            warn "自有证书无需客户端 insecure，请按你的证书情况配置客户端"
            show_links
            ;;
        0|*) info "已取消" ;;
    esac
}

edit_masquerade() {
    echo ""
    echo "  当前伪装站点: ${MASQUERADE_URL}"
    local new_url=""
    read -rp "请输入新的伪装站点 URL (如 https://bing.com，回车保持不变): " new_url || new_url=""
    if [[ -z "$new_url" ]]; then
        info "未修改"
        return 0
    fi
    # 自动补全协议
    if [[ "$new_url" != http://* && "$new_url" != https://* ]]; then
        new_url="https://${new_url}"
        tip "已自动补全为: ${new_url}"
    fi
    MASQUERADE_URL="$new_url"
    write_config
    save_install_info
    restart_service || true
    info "伪装站点已更新: ${MASQUERADE_URL}"
    show_links
}

edit_ip() {
    echo ""
    echo "  当前 IPv4: ${SERVER_IP4:-无}"
    echo "  当前 IPv6: ${SERVER_IP6:-无}"
    echo ""
    echo "  1) 重新自动检测"
    echo "  2) 手动输入 IPv4"
    echo "  3) 手动输入 IPv6"
    echo "  4) 清空 IPv4"
    echo "  5) 清空 IPv6"
    echo "  0) 返回"
    echo ""
    local c=""
    read -rp "请输入 [0-5]: " c || c=0
    case "${c:-0}" in
        1)
            local ip4 ip6
            ip4=$(curl -4 -fsSL --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null || echo "")
            ip6=$(curl -6 -fsSL --connect-timeout 5 --max-time 10 "https://api6.ipify.org" 2>/dev/null || echo "")
            if [[ -n "$ip4" ]]; then SERVER_IP4="$ip4"; fi
            if [[ -n "$ip6" ]]; then SERVER_IP6="$ip6"; fi
            if [[ -z "$ip4" && -z "$ip6" ]]; then
                err "自动检测失败，请手动输入"
                return 0
            fi
            ;;
        2) read -rp "请输入 IPv4 地址: " SERVER_IP4 || SERVER_IP4="" ;;
        3) read -rp "请输入 IPv6 地址: " SERVER_IP6 || SERVER_IP6="" ;;
        4) SERVER_IP4="" ;;
        5) SERVER_IP6="" ;;
        0|*) info "已取消"; return 0 ;;
    esac
    save_install_info
    info "IP 已更新 (仅影响分享链接显示)"
    show_links
}

edit_raw_config() {
    echo ""
    local editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        local e
        for e in nano vim vi; do
            if command -v "$e" &>/dev/null; then
                editor="$e"
                break
            fi
        done
    fi
    if [[ -z "$editor" ]]; then
        err "未找到可用编辑器 (nano / vim / vi)，请手动编辑: ${HY2_CONFIG}"
        return 0
    fi

    tip "使用 ${editor} 编辑 ${HY2_CONFIG}，保存退出后将重启服务"
    "$editor" "$HY2_CONFIG" || true

    # 校验 YAML 基本结构 (至少要能解析出 listen)
    if ! grep -qE '^listen:' "$HY2_CONFIG"; then
        err "配置文件中未找到 listen 项，可能编辑有误，已跳过重启"
        return 0
    fi

    local ans=""
    read -rp "是否重启服务以应用修改? [Y/n]: " ans || ans="y"
    sync_install_info_from_config
    if [[ "${ans,,}" != "n" ]]; then
        restart_service || true
    fi
    info "已同步安装信息: ${HY2_INFO_FILE}"
    show_links
}

# --------------- 查看状态 (兼容旧参数，等价于节点信息) ---------------
do_status() {
    do_node_info
}

# --------------- 重启服务 ---------------
do_restart() {
    check_root
    restart_service || true
}

# --------------- 查看日志 ---------------
do_log() {
    detect_init
    if [[ "$INIT" == "systemd" ]]; then
        journalctl -u ${HY2_SERVICE} -n 50 --no-pager
    elif [[ -f "$HY2_LOG" ]]; then
        tail -50 "$HY2_LOG"
    else
        warn "未找到日志"
    fi
}

# --------------- 菜单 ---------------
show_menu() {
    local choice=""

    while true; do
        echo ""
        echo "======================================================"
        echo "  Hysteria2 管理脚本"
        echo "  支持: Alpine / Debian / Ubuntu"
        echo "======================================================"
        echo ""

        if is_installed; then
            echo "  1) 查看节点信息"
            echo "  2) 修改节点配置"
            echo "  3) 重启服务"
            echo "  4) 查看日志"
            echo "  5) 重新安装 / 覆盖安装"
            echo "  6) 卸载 Hysteria2"
            echo "  7) 更新脚本"
            echo "  0) 退出"
            echo ""
            read -rp "请输入 [0-7]: " choice || choice=0

            case "${choice:-0}" in
                1) do_node_info ;;
                2) do_edit_config ;;
                3) do_restart ;;
                4) do_log ;;
                5) do_install ;;
                6) do_uninstall ;;
                7) do_update_script || true ;;
                0) exit 0 ;;
                *) err "无效选项" ;;
            esac
        else
            echo "  1) 安装 Hysteria2"
            echo "  7) 更新脚本"
            echo "  0) 退出"
            echo ""
            echo "  (未检测到 Hysteria2 安装)"
            echo ""
            read -rp "请输入 [0-1]: " choice || choice=0

            case "${choice:-0}" in
                1) do_install ;;
                7) do_update_script || true ;;
                0) exit 0 ;;
                *) err "无效选项" ;;
            esac
        fi
    done
}

# --------------- 帮助 ---------------
show_help() {
    cat <<'HELPEOF'

======================================================
  Hysteria2 管理脚本 - 用法
======================================================

  hy2                     呼出管理菜单 (推荐)
                          1) 查看节点信息  2) 修改节点配置  0) 退出

  hy2 install    / -i     安装 Hysteria2
  hy2 info       / -n     查看节点信息 (服务状态/节点参数/分享链接)
  hy2 edit       / -e     修改节点配置 (名称/端口/密码/SNI/伪装站点/IP)
  hy2 status     / -s     查看服务状态与当前配置
  hy2 restart    / -r     重启服务
  hy2 log        / -l     查看最近 50 行日志
  hy2 update     / -u     更新脚本到最新版本
  hy2 uninstall           卸载 Hysteria2
  hy2 help       / -h     显示本帮助

  示例:
    hy2
    hy2 info
    hy2 edit

======================================================

HELPEOF
}

# --------------- 入口 ---------------
# 支持参数调用
case "${1:-}" in
    install|-i|--install)   do_install ;;
    uninstall|--remove)     do_uninstall ;;
    info|node|-n|--info)    do_node_info ;;
    edit|config|-e|--edit)  do_edit_config ;;
    status|-s|--status)     do_status ;;
    restart|-r|--restart)   do_restart ;;
    log|-l|--log)           do_log ;;
    update|-u|--update)     do_update_script ;;
    help|-h|--help)         show_help ;;
    menu|--menu)
        check_root
        show_menu
        ;;
    *)
        check_root
        show_menu
        ;;
esac
