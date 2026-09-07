#!/usr/bin/env bash
# ============================================================
# Hysteria2 一键安装管理脚本
# 支持: Alpine / Debian / Ubuntu
# 架构: x86_64 / aarch64
# 功能: 输入IP、选择端口、自签SNI证书、安装/卸载/管理
# ============================================================

set -euo pipefail

# --------------- 常量 ---------------
HY2_SERVICE="hysteria-server"
HY2_CONFIG="/etc/hysteria/config.yaml"
HY2_CERT_DIR="/etc/ssl/private"
HY2_LOG="/var/log/hysteria2.log"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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
    read -rp "请输入选项 [1-4，默认1]: " ip_choice
    ip_choice=${ip_choice:-1}

    case "$ip_choice" in
        1)
            if [[ -z "$auto_ip4" ]]; then
                err "未检测到 IPv4，请手动输入"
                read -rp "请输入 IPv4 地址: " SERVER_IP4
                SERVER_IP6=""
            else
                SERVER_IP4="$auto_ip4"
                SERVER_IP6=""
            fi
            ;;
        2)
            if [[ -z "$auto_ip6" ]]; then
                err "未检测到 IPv6，请手动输入"
                read -rp "请输入 IPv6 地址: " SERVER_IP6
                SERVER_IP4=""
            else
                SERVER_IP6="$auto_ip6"
                SERVER_IP4=""
            fi
            ;;
        3)
            read -rp "请输入 IP 地址 (支持 IPv4 或 IPv6): " custom_ip
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
                read -rp "请输入 IPv4 地址: " SERVER_IP4
            else
                SERVER_IP4="$auto_ip4"
            fi
            if [[ -z "$auto_ip6" ]]; then
                read -rp "请输入 IPv6 地址 (回车跳过): " SERVER_IP6
            else
                SERVER_IP6="$auto_ip6"
            fi
            ;;
        *)
            SERVER_IP4="${auto_ip4}"
            SERVER_IP6=""
            ;;
    esac

    [[ -n "${SERVER_IP4:-}" ]] && info "IPv4: ${SERVER_IP4}"
    [[ -n "${SERVER_IP6:-}" ]] && info "IPv6: ${SERVER_IP6}"
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
    read -rp "请输入选项 [1-3，默认1]: " port_choice
    port_choice=${port_choice:-1}

    case "$port_choice" in
        1) SERVER_PORT=443 ;;
        2) SERVER_PORT=8443 ;;
        3)
            while true; do
                read -rp "请输入端口号 (1-65535): " SERVER_PORT
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

# --------------- SNI 域名 / 证书 ---------------
get_sni_domain() {
    echo ""
    echo "=========================================="
    echo "  SNI 证书域名设置"
    echo "  1) 使用自签证书 (自动生成)"
    echo "  2) 使用已有证书 (指定路径)"
    echo "=========================================="
    read -rp "请输入选项 [1-2，默认1]: " cert_choice
    cert_choice=${cert_choice:-1}

    case "$cert_choice" in
        1)
            echo ""
            echo "  推荐域名 (用于SNI伪装):"
            echo "    ---- 科技巨头 ----"
            echo "    1) bing.com               (微软必应)"
            echo "    2) microsoft.com          (微软官网)"
            echo "    3) windows.com            (Windows)"
            echo "    4) outlook.com            (Outlook邮箱)"
            echo "    5) cloudflare.com         (Cloudflare)"
            echo "    6) apple.com              (苹果官网)"
            echo "    7) google.com             (谷歌)"
            echo "    8) github.com             (GitHub)"
            echo "    ---- CDN/云服务 ----"
            echo "    9) amazon.com             (亚马逊)"
            echo "   10) aws.amazon.com         (AWS)"
            echo "   11) azure.com              (Azure)"
            echo "   12) fastly.com             (Fastly CDN)"
            echo "   13) akamai.com             (Akamai)"
            echo "   14) edgekey.net            (Akamai Edge)"
            echo "   ---- 媒体/社交 ----"
            echo "   15) twitter.com            (推特)"
            echo "   16) x.com                  (X/Twitter)"
            echo "   17) youtube.com            (YouTube)"
            echo "   18) facebook.com           (Facebook)"
            echo "   19) instagram.com          (Instagram)"
            echo "   20) tiktok.com             (TikTok)"
            echo "   ---- 中国网站 ----"
            echo "   21) qq.com                 (腾讯QQ)"
            echo "   22) taobao.com             (淘宝)"
            echo "   23) baidu.com              (百度)"
            echo "   24) weibo.com              (微博)"
            echo "   25) jd.com                 (京东)"
            echo "   26) 163.com                (网易)"
            echo "   ---- 其他 ----"
            echo "   27) zoom.us                (Zoom)"
            echo "   28) teams.microsoft.com    (Teams)"
            echo "   29) linkedin.com           (LinkedIn)"
            echo "   30) shopify.com            (Shopify)"
            echo "   31) netflix.com            (Netflix)"
            echo "   32) 自定义域名"
            echo ""
            read -rp "请选择域名 [1-32，默认1]: " domain_choice
            domain_choice=${domain_choice:-1}
            case "$domain_choice" in
                1)  SNI_DOMAIN="bing.com" ;;
                2)  SNI_DOMAIN="microsoft.com" ;;
                3)  SNI_DOMAIN="windows.com" ;;
                4)  SNI_DOMAIN="outlook.com" ;;
                5)  SNI_DOMAIN="cloudflare.com" ;;
                6)  SNI_DOMAIN="apple.com" ;;
                7)  SNI_DOMAIN="google.com" ;;
                8)  SNI_DOMAIN="github.com" ;;
                9)  SNI_DOMAIN="amazon.com" ;;
                10) SNI_DOMAIN="aws.amazon.com" ;;
                11) SNI_DOMAIN="azure.com" ;;
                12) SNI_DOMAIN="fastly.com" ;;
                13) SNI_DOMAIN="akamai.com" ;;
                14) SNI_DOMAIN="edgekey.net" ;;
                15) SNI_DOMAIN="twitter.com" ;;
                16) SNI_DOMAIN="x.com" ;;
                17) SNI_DOMAIN="youtube.com" ;;
                18) SNI_DOMAIN="facebook.com" ;;
                19) SNI_DOMAIN="instagram.com" ;;
                20) SNI_DOMAIN="tiktok.com" ;;
                21) SNI_DOMAIN="qq.com" ;;
                22) SNI_DOMAIN="taobao.com" ;;
                23) SNI_DOMAIN="baidu.com" ;;
                24) SNI_DOMAIN="weibo.com" ;;
                25) SNI_DOMAIN="jd.com" ;;
                26) SNI_DOMAIN="163.com" ;;
                27) SNI_DOMAIN="zoom.us" ;;
                28) SNI_DOMAIN="teams.microsoft.com" ;;
                29) SNI_DOMAIN="linkedin.com" ;;
                30) SNI_DOMAIN="shopify.com" ;;
                31) SNI_DOMAIN="netflix.com" ;;
                32)
                    read -rp "请输入自定义域名: " SNI_DOMAIN
                    if [[ -z "$SNI_DOMAIN" ]]; then
                        SNI_DOMAIN="bing.com"
                        warn "域名为空，使用默认: bing.com"
                    fi
                    ;;
                *) SNI_DOMAIN="bing.com" ;;
            esac

            CERT_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.crt"
            KEY_PATH="${HY2_CERT_DIR}/${SNI_DOMAIN}.key"

            info "生成自签证书: ${SNI_DOMAIN}"
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
            ;;
        2)
            read -rp "请输入证书文件路径 (.crt): " CERT_PATH
            read -rp "请输入密钥文件路径 (.key): " KEY_PATH

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
}

# --------------- 生成密码 ---------------
gen_password() {
    HY2_PASSWORD=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        openssl rand -hex 16)
    info "生成随机密码: ${HY2_PASSWORD}"
}

# --------------- 安装依赖 ---------------
install_deps() {
    local extra="${1:-}"
    info "安装依赖..."
    if [[ "$PKG" == "apk" ]]; then
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
        read -rp "是否重新安装? [y/N]: " reinstall
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
    HY2_VER="2.6.2"
    api_result=$(curl -fsSL --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/apernet/hysteria/releases/latest" 2>/dev/null) || true
    if [ -n "$api_result" ]; then
        detected=$(echo "$api_result" | grep '"tag_name"' | head -1 | sed 's/.*"v//;s/".*//') || true
        if [ -n "$detected" ]; then
            HY2_VER="$detected"
        fi
    fi

    bin_url="https://github.com/apernet/hysteria/releases/download/v${HY2_VER}/hysteria-linux-${HY2_ARCH}"
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
    url: https://${SNI_DOMAIN}
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

# --------------- 生成链接 ---------------
generate_link() {
    echo ""
    echo "============================================================"
    echo "  Hysteria2 安装完成!"
    echo "============================================================"
    echo ""

    local port="$SERVER_PORT"
    local pwd="$HY2_PASSWORD"
    local sni="$SNI_DOMAIN"
    local insecure_flag="1"

    if [[ -n "${SERVER_IP4:-}" ]]; then
        local link4="hysteria2://${pwd}@${SERVER_IP4}:${port}?sni=${sni}&insecure=${insecure_flag}#HY2-IPv4"
        tip "IPv4 链接: ${link4}"
        echo ""
    fi

    if [[ -n "${SERVER_IP6:-}" ]]; then
        local link6="hysteria2://${pwd}@[${SERVER_IP6}]:${port}?sni=${sni}&insecure=${insecure_flag}#HY2-IPv6"
        tip "IPv6 链接: ${link6}"
        echo ""
    fi

    # 通用配置信息
    echo "------------ 客户端配置信息 ------------"
    tip "地址:     ${SERVER_IP4:-${SERVER_IP6}}"
    tip "端口:     ${port}"
    tip "密码:     ${pwd}"
    tip "SNI:      ${sni}"
    tip "证书:     自签 (客户端需开启 insecure)"
    [[ -n "${PIN_SHA256:-}" ]] && tip "pinSHA256: ${PIN_SHA256}"
    echo "----------------------------------------"
    echo ""
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
    mkdir -p /etc/hysteria
    cat > /etc/hysteria/.install_info <<EOF
SERVER_IP4=${SERVER_IP4:-}
SERVER_IP6=${SERVER_IP6:-}
SERVER_PORT=${SERVER_PORT}
HY2_PASSWORD=${HY2_PASSWORD}
SNI_DOMAIN=${SNI_DOMAIN}
CERT_PATH=${CERT_PATH}
KEY_PATH=${KEY_PATH}
EOF

    info "安装信息已保存至: /etc/hysteria/.install_info"
    info "配置文件位置: ${HY2_CONFIG}"
    echo ""
}

# --------------- 卸载 ---------------
do_uninstall() {
    check_root
    detect_os
    detect_init

    warn "即将卸载 Hysteria2，此操作不可撤销!"
    read -rp "确认卸载? [y/N]: " confirm
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

    info "Hysteria2 已卸载"
}

# --------------- 查看状态 ---------------
do_status() {
    detect_init
    echo ""
    if [[ "$INIT" == "systemd" ]]; then
        systemctl status ${HY2_SERVICE} --no-pager 2>/dev/null || warn "服务未运行"
    else
        rc-service ${HY2_SERVICE} status 2>/dev/null || warn "服务未运行"
    fi
    echo ""

    if [[ -f "$HY2_CONFIG" ]]; then
        echo "------------ 当前配置 ------------"
        cat "$HY2_CONFIG"
        echo "----------------------------------"
    fi

    if [[ -f /etc/hysteria/.install_info ]]; then
        echo ""
        echo "------------ 安装信息 ------------"
        source /etc/hysteria/.install_info
        echo "  IPv4:   ${SERVER_IP4:-无}"
        echo "  IPv6:   ${SERVER_IP6:-无}"
        echo "  端口:   ${SERVER_PORT}"
        echo "  密码:   ${HY2_PASSWORD}"
        echo "  SNI:    ${SNI_DOMAIN}"
        echo "----------------------------------"

        local sni="$SNI_DOMAIN"
        local pwd="$HY2_PASSWORD"
        local port="$SERVER_PORT"
        echo ""
        [[ -n "${SERVER_IP4:-}" ]] && tip "IPv4 链接: hysteria2://${pwd}@${SERVER_IP4}:${port}?sni=${sni}&insecure=1#HY2-IPv4"
        [[ -n "${SERVER_IP6:-}" ]] && tip "IPv6 链接: hysteria2://${pwd}@[${SERVER_IP6}]:${port}?sni=${sni}&insecure=1#HY2-IPv6"
        echo ""
    fi
}

# --------------- 重启服务 ---------------
do_restart() {
    check_root
    detect_init
    if [[ "$INIT" == "systemd" ]]; then
        systemctl restart ${HY2_SERVICE}
        info "服务已重启"
    else
        rc-service ${HY2_SERVICE} restart
        info "服务已重启"
    fi
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
    echo ""
    echo "======================================================"
    echo "  Hysteria2 管理脚本"
    echo "  支持: Alpine / Debian / Ubuntu"
    echo "======================================================"
    echo ""
    echo "  1) 安装 Hysteria2"
    echo "  2) 卸载 Hysteria2"
    echo "  3) 查看状态 & 链接"
    echo "  4) 重启服务"
    echo "  5) 查看日志"
    echo "  0) 退出"
    echo ""
    read -rp "请选择 [0-5]: " choice

    case "$choice" in
        1) do_install ;;
        2) do_uninstall ;;
        3) do_status ;;
        4) do_restart ;;
        5) do_log ;;
        0) exit 0 ;;
        *)
            err "无效选项"
            ;;
    esac
}

# --------------- 入口 ---------------
# 支持参数调用
case "${1:-}" in
    install|-i|--install)  do_install ;;
    uninstall|--remove)    do_uninstall ;;
    status|-s|--status)    do_status ;;
    restart|-r|--restart)  do_restart ;;
    log|-l|--log)          do_log ;;
    *)
        check_root
        show_menu
        ;;
esac
