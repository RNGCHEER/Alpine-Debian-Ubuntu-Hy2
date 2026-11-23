#!/usr/bin/env bash
set -euo pipefail
export MSYS2_ARG_CONV_EXCL='/CN='
cd "$(dirname "$0")/.."
# 仅加载函数，绝不执行安装入口或修改系统服务。
source <(sed '/^# --------------- 入口 ---------------/,$d' hy2.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
HY2_CERT_DIR="$work"
CERT_PATH="$work/server.crt"
KEY_PATH="$work/server.key"
SNI_DOMAIN=example.com
SERVER_IP4=192.0.2.1
SERVER_IP6=2001:db8::1
SERVER_PORT=8443
HY2_PASSWORD='test:"quote"\slash&?#@'
NODE_NAME='中文 "节点" & test'
generate_self_signed_cert >/dev/null
case "$(uname -s)" in
    MINGW*|MSYS*) ;; # NTFS does not expose POSIX mode bits.
    *) [[ "$(stat -c %a "$KEY_PATH")" == 600 ]] ;;
esac
# 不读取真实服务器的安装元数据。
load_install_info() { :; }
show_links > "$work/links.txt"
export_client sing-box 4 > "$work/sing-box.json"
export_client xray 6 > "$work/xray.json"
cp "$CERT_PATH" "$work/trusted.pem"
openssl req -x509 -nodes -newkey rsa:2048 -keyout "$work/other.key" -out "$work/other.pem" -days 1 -subj /CN=example.com -addext subjectAltName=DNS:example.com >/dev/null 2>&1
SNI_DOMAIN=wrong.example
if client_certificate >/dev/null 2>&1; then echo 'Accepted wrong SNI'; exit 1; fi
SNI_DOMAIN=example.com
CERT_PATH="$work/missing.pem"
if client_certificate >/dev/null 2>&1; then echo 'Accepted missing certificate'; exit 1; fi
openssl req -x509 -nodes -newkey rsa:2048 -keyout "$work/legacy.key" -out "$work/legacy.pem" -days 1 -subj /CN=example.com >/dev/null 2>&1
CERT_PATH="$work/legacy.pem"
if client_certificate >/dev/null 2>&1; then echo 'Accepted CN-only certificate'; exit 1; fi
if export_client unknown >/dev/null 2>&1; then exit 1; fi
if export_client xray 5 >/dev/null 2>&1; then exit 1; fi
python tests/verify_exports.py "$work"
go run tests/verify_trust.go "$work"
# 模拟克隆模式：叶证书由本地临时 CA 签发，只分发叶证书作为信任锚。
openssl req -x509 -nodes -newkey rsa:2048 -keyout "$work/ca.key" -out "$work/ca.pem" -days 1 -subj /CN=LocalCloneCA >/dev/null 2>&1
openssl req -new -key "$KEY_PATH" -out "$work/leaf.csr" -subj /CN=example.com >/dev/null 2>&1
printf 'basicConstraints=CA:FALSE\nsubjectAltName=DNS:example.com\nextendedKeyUsage=serverAuth\n' > "$work/ext.cnf"
openssl x509 -req -in "$work/leaf.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" -CAcreateserial -days 1 -extfile "$work/ext.cnf" -out "$work/server.crt" >/dev/null 2>&1
CERT_PATH="$work/server.crt"
cp "$CERT_PATH" "$work/trusted.pem"
show_links > "$work/links.txt"
export_client sing-box 4 > "$work/sing-box.json"
export_client xray 6 > "$work/xray.json"
python tests/verify_exports.py "$work"
go run tests/verify_trust.go "$work"
echo 'PASS: cloned issuer certificate exports and trust'
