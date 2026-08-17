# WireGuard-KSU

在 Android 设备上使用内核级 WireGuard VPN，通过 KernelSU/APatch 内建 WebUI 管理。

## 特点

- **内核态 WireGuard**：利用 Linux 5.6+ 内核内置的 WireGuard 模块，性能最优、最省电
- **无守护进程**：不需要后台常驻进程，只有一个 668KB 的 `wg` 配置工具
- **多接口支持**：可同时运行 wg0、wg1 等多个隧道
- **WebUI 管理**：在 KernelSU/APatch Manager 中直接管理
- **兼容三大框架**：Magisk、KernelSU、APatch

## 功能

- 命令行管理（start/stop/restart/status/enable/disable/genkey）
- KernelSU/APatch WebUI 管理界面
  - 多接口标签切换，支持新建和删除接口
  - 新建接口时自动生成密钥对
  - 接口状态（IP、端口、公钥）
  - Peer 列表（endpoint、最后握手、收发流量、Allowed IPs）
  - 配置文件在线编辑，保存并重启
  - 密钥对生成工具
  - 开机自启动开关
  - 错误日志查看
- 首次安装自动生成密钥对和配置模板
- 兼容标准 wg-quick 配置格式
- 开机自动启动所有配置的接口
- KSU 模块列表显示运行状态和 IP
- Endpoint 自动钉扎到底层物理网络，避免外层 WireGuard UDP 流量被其他 VPN/TUN 路由接管
- 网络重建后自动修复 Endpoint 路由，改善 Wi-Fi/移动网络切换后的恢复速度
- 可选 Stay Awake 模式，在息屏时保持 WireGuard 可达（会增加耗电）

## 前提条件

内核需要支持 WireGuard（`CONFIG_WIREGUARD=y`）。安装时会自动检测。

大多数运行 KernelSU 的内核（Linux 5.6+）都已内置支持。

Endpoint 路由锁需要支持文件描述符模式的 `flock`。模块优先使用
Magisk/KernelSU/APatch 的 BusyBox applet，也会自动尝试系统提供的兼容实现；
如果两者都不可用，接口启动会明确失败，而不会在未钉扎 Endpoint 路由的情况下继续。

## 安装

1. 从 [Releases](../../releases) 下载 zip
2. 在 Magisk/KSU/APatch Manager 中刷入
3. 首次安装会自动生成密钥对和 `wg0.conf` 模板，安装日志中会显示公钥
4. 编辑 `/data/adb/wireguard/wg0.conf`，填入服务器信息（或在 WebUI 中编辑）
5. 运行 `wgksu start` 或重启设备

也可以在 WebUI 中点击 "＋" 新建接口，会自动生成密钥对并进入编辑模式。

## 管理

```bash
wgksu start              # 启动所有接口
wgksu stop               # 停止所有接口
wgksu restart             # 重启所有接口
wgksu start wg0           # 启动指定接口
wgksu stop wg0            # 停止指定接口
wgksu status              # 查看所有接口状态
wgksu enable              # 开启开机自启
wgksu disable             # 关闭开机自启
wgksu stay-awake enable wg0   # 让 wg0 运行时持有 wakelock 并启用 Wi-Fi hi-perf
wgksu stay-awake disable wg0  # 关闭 wg0 的 Stay Awake
wgksu genkey              # 生成新的密钥对
```

KernelSU/APatch 用户可在 Manager 中打开模块 WebUI 进行管理。

## 配置

配置文件位于 `/data/adb/wireguard/`，标准 WireGuard 配置格式：

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = server.example.com:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

支持多个配置文件（`wg0.conf`、`wg1.conf` 等），每个文件对应一个接口。

### Endpoint 路由钉扎

模块启动接口时会等待可用的物理网络和 DNS，然后为 Peer `Endpoint` 添加更具体的 host route，让 WireGuard 外层 UDP 流量走物理网络（优先 `wlan`，其次 `eth`，再其次移动网络），避免设备上同时存在其他 Android VPN/TUN 时把 WireGuard endpoint 套进另一个隧道。

如果网络在息屏、Wi-Fi 开关、移动网络切换等场景中被系统重建，模块会对运行中的接口定期检查当前 peer endpoint 的底层路由，并在路由丢失或指向错误设备时重新钉扎。该轻量检查默认约 30 秒一次，不做 DNS 查询。

对于域名 Endpoint，模块仍会通过 DNS re-resolve 循环处理域名解析结果变化。该循环默认间隔为 120 秒，可在 WebUI 的 DNS re-resolve 设置中调低；更短间隔会增加息屏唤醒和 DNS 查询频率。

### 息屏保持可达

内核态 WireGuard 没有 Android `VpnService` 前台服务。部分设备会在息屏后让 Wi-Fi/CPU 进入低功耗，导致外部无法主动连接隧道地址，即使 `PersistentKeepalive` 已配置也可能立即不可达。

需要息屏仍可从外部连入时，可为接口开启 Stay Awake：

```bash
wgksu stay-awake enable wg0
```

开启后，如果对应接口正在运行会立即生效；如果接口尚未运行，则下次启动该接口时生效。模块会写入 `/sys/power/wake_lock` 并执行 `cmd wifi force-hi-perf-mode enabled`。停止接口或关闭 Stay Awake 后会释放 wakelock，并关闭模块启用过的 Wi-Fi hi-perf。

`cmd wifi force-hi-perf-mode` 需要 Android 10+。Android 9 上该命令可能不可用，此时会记录失败日志，但 wakelock 仍会尝试生效。

该模式会阻止设备正常深睡，明显增加耗电。建议只在开发、远程维护或固定供电设备上开启。

### 生成密钥对

在任意有 `wg` 工具的设备上：

```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

## 兼容性

- Magisk ≥ v20.4
- KernelSU ≥ 0.6.7
- APatch
- Android ≥ 9 (API 28)
- 内核需要 `CONFIG_WIREGUARD=y`（Linux 5.6+）
- arm64 设备

## IPv6 优先 / NATMap IPv4 回退 Endpoint

在 Peer 中保留标准 `Endpoint` 作为原生 IPv6 域名和固定 WireGuard 端口，再增加 `EndpointFallbackTXT`：

```ini
[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = ipv6.rannj.top:51820
EndpointFallbackTXT = ipv4.rannj.top
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

`EndpointFallbackTXT` 存在时会启用动态选择。启动或底层默认网络变化时，模块先用短超时执行 `ping -6 ipv6.rannj.top`；成功后解析 AAAA，并进入 `NATIVE_V6`。失败时读取 `ipv4.rannj.top` 的 TXT，要求内容严格为 `IPv4:port`（例如 `203.0.113.7:45678`），并进入 `NATMAP_V4`。优先级始终为 `NATIVE_V6 > NATMAP_V4`。

周期刷新沿用原 DNS re-resolve 间隔：`NATIVE_V6` 重新解析 AAAA，`NATMAP_V4` 重新读取 TXT。Endpoint 比较包含地址和端口。切换时会先钉扎新 Endpoint 的物理 host route，再调用 `wg set peer ... endpoint ...`，成功后才删除旧 route。状态保存在 `/data/adb/wireguard/dynamic-endpoint.<接口>`，变更日志位于 `dynamic-endpoint.log`。

隧道的 `AllowedIPs` 应只包含需要访问的家庭内网 IPv4 网段，不要配置 `0.0.0.0/0` 或 `::/0`；这样 IPv6 探测和 WireGuard 外层流量均走底层网络。

### OpenWrt NATMap TXT 更新脚本

仓库中的 `scripts/natmap-notify-cloudflare.sh` 接收 NATMap 官方的 notify 参数，其中 `$1` 为公网地址、`$2` 为公网端口，并把 TXT 写成无空格的 `IPv4:port`。第一版使用 Cloudflare DNS API。在 OpenWrt 创建 `/etc/natmap-wireguard.conf`：

```sh
CF_API_TOKEN='仅允许编辑该 Zone DNS 的 API Token'
CF_ZONE_ID='Cloudflare Zone ID'
CF_DNS_RECORD_ID='ipv4.rannj.top 这条 TXT 的 Record ID'
CF_RECORD_NAME='ipv4.rannj.top'
CF_TTL=60
```

把脚本复制到 OpenWrt（例如 `/usr/bin/natmap-notify-wireguard`）、设置 `chmod 700`，并作为 NATMap 的 `-e` 脚本。NATMap 会按 `{public-addr} {public-port} {ip4p} {private-port} {protocol} {private-addr}` 调用它。脚本依赖 `curl`，配置文件建议设为 `chmod 600`。

## License

本项目（模块脚本、WebUI）采用 [MIT License](LICENSE)。

`wg` 工具由 CI 从 [wireguard-tools](https://git.zx2c4.com/wireguard-tools) 编译，受 [GPL-2.0](https://git.zx2c4.com/wireguard-tools/about/) 约束。
