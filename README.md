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

安装完成后会自动装好 `hy2` 命令，**之后只要在终端输入 `hy2` 就能随时呼出管理菜单**：

```bash
hy2
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
- **安装后输入 `hy2` 即可再次进入管理菜单**（查看节点信息 / 修改节点配置）
- 查看状态、日志、重启服务

## 🛠️ 安装后管理：输入 `hy2`

安装脚本会把自身副本放到 `/usr/local/lib/hy2/hy2.sh`，并生成 `/usr/local/bin/hy2` 命令。
以后随时输入 `hy2`（无需再记一长串 curl 命令）即可呼出菜单：

```text
======================================================
  Hysteria2 管理脚本
  支持: Alpine / Debian / Ubuntu
======================================================

  1) 查看节点信息
  2) 修改节点配置
  3) 重启服务
  4) 查看日志
  5) 重新安装 / 覆盖安装
  6) 卸载 Hysteria2
  7) 更新脚本
  0) 退出

请输入 [0-7]:
```

### 1) 查看节点信息

一次性显示服务状态、全部节点参数和最新分享链接（配置有改动后无需重装即可查新链接）：

```text
======================================================
  Hysteria2 节点信息
======================================================

------------ 服务状态 ------------
  运行状态: 运行中 (PID 12345)
  开机自启: 已启用
  版本:     v2.12.2
----------------------------------

------------ 节点参数 ------------
  🏷️  节点名称: 香港-01
  IPv4:     1.2.3.4
  IPv6:     2001:db8::1
  端口:     443 (UDP)
  密码:     11111111-2222-3333-4444-555555555555
  SNI:      bing.com
  伪装站点: https://bing.com
  证书:     /etc/ssl/private/bing.com.crt
  证书类型: 自签 (客户端需设置 insecure: true)
  证书有效期: Aug 23 09:26:39 2127 GMT
  pinSHA256: 27788D46332B99EE2EF475A347004F7B13D8BFEB93C40CCFA1D505B068D21308
  配置文件: /etc/hysteria/config.yaml
----------------------------------

------------ 分享链接 ------------
[→] IPv4 链接: hysteria2://密码@1.2.3.4:443?sni=bing.com&insecure=1#香港-01-IPv4
[→] IPv6 链接: hysteria2://密码@[2001:db8::1]:443?sni=bing.com&insecure=1#香港-01-IPv6
----------------------------------
```

### 2) 修改节点配置

```text
======================================================
  修改节点配置
======================================================

  当前: 🏷️ 香港-01 | 端口 443 | SNI bing.com

  1) 修改节点名称
  2) 修改端口
  3) 修改密码 (重新生成随机密码)
  4) 修改 SNI / 证书
  5) 修改伪装站点 (masquerade)
  6) 修改 IP 地址 (影响分享链接)
  7) 直接编辑 config.yaml (高级)
  0) 返回上级菜单

请输入 [0-7]:
```

- 改端口 / 密码 / SNI / 伪装站点后，脚本会**自动重写 `/etc/hysteria/config.yaml`、重启服务并打印新链接**
- 改端口时会提示防火墙放行 **UDP**
- 改 SNI 支持重新自签证书（内置 32 个常用伪装域名列表）或指定已有证书路径
- 伪装站点若原本跟随 SNI，改 SNI 时会自动同步更新
- 改节点名称 / IP 只影响分享链接里的显示，不重启服务
- 选 7 可用 `nano / vim / vi` 直接编辑配置文件，退出后自动把配置同步回 `/etc/hysteria/.install_info` 并可选择重启
- 所有改动都会同步保存到 `/etc/hysteria/.install_info`

## 📖 使用方式

### 交互模式

```bash
hy2              # 推荐：呼出管理菜单
bash hy2.sh      # 直接运行脚本文件同样进入菜单
```

### 命令行参数

```bash
hy2 install      # 安装 Hysteria2
hy2 info         # 查看节点信息（服务状态 / 参数 / 分享链接）
hy2 edit         # 修改节点配置
hy2 status       # 查看状态和链接
hy2 restart      # 重启服务
hy2 log          # 查看日志
hy2 update       # 更新脚本到最新版本
hy2 uninstall    # 卸载 Hysteria2
hy2 help         # 显示帮助
```

`bash hy2.sh install` 等写法同样支持（参数名与上面一致，另有 `-i` `-n` `-e` `-s` `-r` `-l` `-u` 简写）。

## 🔧 安装流程

1. **检测系统** - 自动识别 Alpine / Debian / Ubuntu 和 CPU 架构
2. **获取 IP** - 自动检测或手动输入 IPv4 / IPv6
3. **选择端口** - 443 / 8443 / 自定义 (1-65535)
4. **SNI 证书** - 自签证书 (bing.com / cloudflare.com / microsoft.com / 自定义) 或导入已有证书
5. **安装 Hysteria2** - 使用官方安装脚本
6. **生成配置** - 自动写入 `/etc/hysteria/config.yaml`
7. **启动服务** - systemd 或 openrc 自动配置
8. **安装 `hy2` 管理命令** - 之后输入 `hy2` 即可再次进入菜单

## ⚠️ 注意

- Hysteria2 使用 **UDP** 端口，请确保防火墙放行；改端口后记得同步放行新端口
- 自签证书需要客户端设置 `insecure: true`
- VPS 内存低于 128M 建议在客户端设置合适带宽
- 服务管理信息保存在 `/etc/hysteria/.install_info`（权限 600，含密码）
- 修改配置后客户端需要重新导入新链接（端口 / 密码 / SNI 变化时）
- Alpine 需要 bash：脚本安装时会自动 `apk add bash`
- 卸载会一并删除 `hy2` 命令与脚本缓存

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
