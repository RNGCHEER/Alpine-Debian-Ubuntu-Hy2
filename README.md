# 🚀 Hysteria2 一键安装管理脚本

支持系统： Alpine / Debian / Ubuntu
支持架构： x86_64 / aarch64 / armv7

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RNGCHEER/Alpine-Debian-Ubuntu-Hy2/main/hy2.sh) install
```

或交互菜单：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RNGCHEER/Alpine-Debian-Ubuntu-Hy2/main/hy2.sh)
```

## ✨ 功能

- 安装 / 卸载 Hysteria2
- 自动检测 IPv4 / IPv6
- **手动输入 IP 地址**
- **选择端口号** (443 / 8443 / 自定义)
- **自签 SNI 证书** (bing.com / cloudflare.com / microsoft.com / 自定义域名)
- 支持已有证书路径导入
- 输出 pinSHA256
- 自动生成 hysteria2:// 分享链接
- 支持 systemd / openrc (进程守护 + 开机自启)
- 查看状态、日志、重启服务

## 📖 使用方式

### 交互模式

```bash
bash hy2.sh
```

显示菜单：安装 / 卸载 / 查看状态 / 重启 / 查看日志

### 命令行参数

```bash
bash hy2.sh install      # 安装
bash hy2.sh uninstall    # 卸载
bash hy2.sh status       # 查看状态和链接
bash hy2.sh restart      # 重启
bash hy2.sh log          # 查看日志
```

## 🔧 安装流程

1. **检测系统** - 自动识别 Alpine / Debian / Ubuntu 和 CPU 架构
2. **获取 IP** - 自动检测或手动输入 IPv4 / IPv6
3. **选择端口** - 443 / 8443 / 自定义 (1-65535)
4. **SNI 证书** - 自签证书 (bing.com / cloudflare.com / microsoft.com / 自定义) 或导入已有证书
5. **安装 Hysteria2** - 使用官方安装脚本
6. **生成配置** - 自动写入 `/etc/hysteria/config.yaml`
7. **启动服务** - systemd 或 openrc 自动配置

## ⚠️ 注意

- Hysteria2 使用 **UDP** 端口，请确保防火墙放行
- 自签证书需要客户端设置 `insecure: true`
- VPS 内存低于 128M 建议在客户端设置合适带宽
- 服务管理信息保存在 `/etc/hysteria/.install_info`

## 📋 配置文件

安装后的配置位于 `/etc/hysteria/config.yaml`：

```yaml
listen: :443

tls:
  cert: /etc/ssl/private/bing.com.crt
  key: /etc/ssl/private/bing.com.key
  sni: bing.com
  insecure: true

auth:
  type: password
  password: 自动生成的UUID

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
```

## 📜 License

AGPL-3.0
