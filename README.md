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
- **证书伪装 (V0.3 新增)** - 输入域名后自动提取目标站点真实证书，克隆其 Subject / 签发者 / SAN / 有效期，伪装成该域名
- 支持已有证书路径导入
- **版本更新检查 (V0.3 新增)** - 一键检查脚本 / Hysteria2 内核版本，发现新版本可在线升级
- **国内网络优化 (V0.3 新增)** - GitHub 下载自动走国内加速镜像 (gh-proxy / ghproxy 系)，多镜像兜底 + 下载文件完整性校验
- 输出 pinSHA256
- 自动生成含完整证书的 v2rayN 专用链接，以及带 pinSHA256 的 Hysteria 原生链接
- 导出 Xray / sing-box 可信证书出站配置（NekoBox 可使用自定义出站）
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
  8) 检查更新 (脚本 / Hysteria2 内核)
  0) 退出

请输入 [0-8]:
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
  SNI:      www.microsoft.com
  伪装站点: https://www.microsoft.com
  证书:     /etc/ssl/private/www.microsoft.com.crt
  证书类型: 克隆伪装证书 (伪装自 www.microsoft.com，使用完整证书导入)
  证书有效期: Jan 17 08:55:31 2027 GMT
  pinSHA256: 27788D46332B99EE2EF475A347004F7B13D8BFEB93C40CCFA1D505B068D21308
  配置文件: /etc/hysteria/config.yaml
----------------------------------

------------ 可信分享链接 ------------
[→] IPv4 v2rayN 专用链接 (内含证书，关闭跳过验证):
v2rayn://hysteria2/（脚本生成的 Base64URL 配置）
[→] NekoBox/sing-box: hy2 export sing-box，复制 JSON 到自定义出站
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
- 改 SNI 支持重新自签证书（内置 32 个常用伪装域名列表）、指定已有证书路径，或**证书伪装**（输入域名提取并克隆其真实证书）
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
hy2 check        # 检查更新（脚本 / Hysteria2 内核，发现新版本可一键升级）
hy2 upgrade      # 升级 Hysteria2 内核到最新版本
hy2 uninstall    # 卸载 Hysteria2
hy2 help         # 显示帮助
```

`bash hy2.sh install` 等写法同样支持（参数名与上面一致，另有 `-i` `-n` `-e` `-s` `-r` `-l` `-u` `-c` 简写）。

## 🔧 安装流程

1. **检测系统** - 自动识别 Alpine / Debian / Ubuntu 和 CPU 架构
2. **获取 IP** - 自动检测或手动输入 IPv4 / IPv6
3. **选择端口** - 443 / 8443 / 自定义 (1-65535)
4. **SNI 证书** - 自签证书 (bing.com / cloudflare.com / microsoft.com / 自定义)、导入已有证书，或**证书伪装**（输入域名提取并克隆其真实证书）
5. **安装 Hysteria2** - 使用官方安装脚本
6. **生成配置** - 自动写入 `/etc/hysteria/config.yaml`
7. **启动服务** - systemd 或 openrc 自动配置
8. **安装 `hy2` 管理命令** - 之后输入 `hy2` 即可再次进入菜单

## 🎭 证书伪装（V0.3 新增）

安装或修改 SNI 时选择「证书伪装」，输入目标域名（如 `www.microsoft.com`，支持 `host:port`），脚本会：

1. 与目标站点建立 TLS 连接，**提取其真实证书**
2. **克隆证书的 Subject / 签发者(Issuer) / SAN / 密钥类型 / 有效期**，在本地签发一张外观一致的证书
3. 自动把 SNI 与伪装站点设为该域名

克隆只改变证书的展示字段，无法复制原站私钥和 CA 签名，不能保证探针无法识别。

> ⚠️ 私钥无法从目标站点提取（也无法被提取），证书由本地密钥签发，因此不能获得公有 CA 信任；应使用本脚本导出的完整证书配置，或在原生 Hysteria 客户端中使用 `insecure=true` 配合 `pinSHA256` 校验。
> 提取失败时自动回退为该域名的自签证书。

## 🔍 版本更新检查（V0.3 新增）

菜单选 8 或执行 `hy2 check`，一次检查两项：

- **脚本版本**：本地 `SCRIPT_VERSION` 与 GitHub 上最新脚本对比
- **Hysteria2 内核版本**：已装二进制版本与官方最新 Release 对比

发现新版本后询问是否升级，脚本与内核都支持在线一键更新（`hy2 update` / `hy2 upgrade`）。
所有 GitHub 下载在官方源失败时自动改走国内加速镜像（gh-proxy.com / ghproxy.net / ghproxy.cn），并**校验下载文件完整性**（拒绝镜像返回的错误页），国内 VPS 也能顺畅更新。

## ⚠️ 注意

- Hysteria2 使用 **UDP** 端口，请确保防火墙放行；改端口后记得同步放行新端口
- 自签或克隆证书使用完整证书导入，可关闭跳过验证；原生 Hysteria 链接使用 `insecure=1` 配合 `pinSHA256` 固定证书
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

auth:
  type: password
  password: 自动生成的UUID

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
```

## v2rayN / NekoBox 的证书验证（V0.3.2）

参考 [ArgoX](https://github.com/fscarmen/ArgoX/blob/main/argox.sh) 的完整证书分发方式：将本机服务器的公开证书随节点配置一起导入，而非关闭验证。自签和克隆证书不会因此成为公有 CA 证书，也不需要把它们安装为操作系统的全局根证书。

### v2rayN（Xray 或 sing-box）

1. 更新脚本后运行 `hy2 info`。
2. 复制完整的 `v2rayn://hysteria2/...` 链接，从剪贴板导入支持此格式的新版 v2rayN。
3. 检查节点的完整证书字段已有 PEM，跳过证书验证为 `false`，SNI 与证书 SAN 匹配。

配置包含 `ConfigType=7`、`ConfigVersion=4`、`Cert` 和 `AllowInsecure=false`。v2rayN 为 Xray 生成 `certificates[].usage=verify`，为 sing-box 生成 `tls.certificate`。证书、密码和名称均按 JSON 转义，IPv4/IPv6 分别生成节点。

### NekoBox / sing-box

不同 NekoBox 分支、版本对链接里的指纹或证书参数支持不同，不保证一条通用 URI 能保留这些字段。推荐运行：

```bash
hy2 export sing-box        # 单个 sing-box outbound JSON，优先 IPv4，无 IPv4 时使用 IPv6
hy2 export sing-box 6      # 指定 IPv6
hy2 export xray            # 单个 Xray outbound JSON
```

在提供“自定义出站”的 NekoBox 中粘贴对应内核的 JSON。若版本只支持完整配置，应把这段 JSON 放入现有配置的 `outbounds` 数组并按其界面配置路由；它不是包含入站、DNS 和路由的完整客户端配置。若界面提供 CA/证书字段，也可把服务器证书 PEM 填入该字段，SNI 保持一致，关闭跳过验证。没有相应功能的版本需要使用支持完整证书配置的客户端。

### 已安装节点与证书更新

- V0.3.1 默认自签证书只有 CN，无法通过现代 Go TLS 的域名验证。脚本会拒绝导出，并提示 `hy2 edit` → `4) 修改 SNI / 证书` → 重新生成，之后重新导入客户端。此操作会更换证书并重启服务。
- 新生成的自签证书带 SAN，私钥权限为 600，不再递归修改整个 `/etc/ssl/private` 的权限。
- 克隆证书仍使用本机签发的证书；客户端显式信任的是本机证书。已有克隆证书只要有效且 SAN 匹配即可导出。
- 每次导出均读取当前证书。更换或续签证书后，重新导入链接或 JSON。
- 原生 Hysteria 链接的 `pinSHA256` 是**整张叶证书 DER 的 SHA-256 十六进制摘要**，不是 sing-box 的 Base64 公钥摘要。`insecure=1` 配合指纹使用；不识别指纹的客户端会失去验证，请使用上面的完整证书方案。
- 通过可信渠道传递链接、证书和 JSON；其中包含节点密码。导出不会读取或传递私钥。

实现依据：[v2rayN 配置生成代码](https://github.com/2dust/v2rayN/blob/master/v2rayN/ServiceLib/Services/CoreConfig/V2ray/V2rayOutboundService.cs)、[Xray TLS 文档](https://xtls.github.io/en/config/transports/tls.html)、[sing-box TLS 文档](https://sing-box.sagernet.org/configuration/shared/tls/)。

### 开发验证

```bash
bash -n hy2.sh
bash tests/client-export.sh
```

测试需要 OpenSSL、Python 3、Go，所有测试证书都在临时目录生成，不安装服务。覆盖双栈链接、中文及特殊字符、导入证书内容、缺失证书、旧版 CN-only 证书和错误 SNI。Go x509 验证会确认指定证书可被信任，并拒绝替换证书和错误域名。测试未代替具体版本客户端的实际 QUIC 联机验证。

## 📣 版本历史

- **V0.3.2** 新增完整证书 v2rayN 导入与 Xray/sing-box 出站导出；自签证书增加 SAN；修正证书权限和服务端 TLS 字段
- **V0.3.1** 修复: 剔除失效下载镜像 (ghfast.top / github.moeyy.cn)，新增下载文件完整性校验 (拒绝 200 + 错误页)，修正版本号重复前缀与版本显示为空
- **V0.3** 新增: 证书伪装 (提取域名证书并克隆)、脚本 / Hysteria2 版本更新检查、国内镜像加速

## 📜 License

AGPL-3.0
