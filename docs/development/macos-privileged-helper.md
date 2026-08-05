# macOS TUN 最小权限辅助进程

最后更新：`2026-08-05`

## 当前结论

云渡不会让整个 App 以管理员身份运行。macOS 13 及以上版本使用 `SMAppService` 注册 App 包内的 `LaunchDaemon`，只有独立的 `YundoPrivilegedHelper` 以 root 身份承载 TUN。

当前代码、Xcode 包结构、静态验证和 Apple Development Debug 构建已经完成。本机个人自用验证已确认：

- App 和 helper 使用同一 Apple Development Team 签名后，`SMAppService` 可以注册包内 LaunchDaemon。
- 管理员在“系统设置 -> 通用 -> 登录项与扩展”批准后台项目后，helper 可以由系统以 root 身份启动。
- helper 可以创建 TUN、接管目标路由，并在 App 退出后停止子进程和恢复路由。

ad hoc Debug 包仍只用于代码和包结构验证，不能证明真实注册成功。对外分发则必须使用 Developer ID 签名，并完成 hardened runtime、公证和 stapling；本机 Apple Development 验证不能替代分发验收。

正式签名包生成后先运行只读发行就绪检查：

```bash
export YUNDO_DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
export YUNDO_NOTARY_PROFILE='yundo-notary'
scripts/check_macos_distribution_readiness.sh \
  'build/macos/Build/Products/Release/Yundo.app' --strict
```

也可以把 `--strict` 放在第一个参数：

```bash
scripts/check_macos_distribution_readiness.sh --strict \
  'build/macos/Build/Products/Release/Yundo.app'
```

脚本检查 Developer ID identity、notarytool 凭据可用性、App/helper 同 Team、hardened runtime、深度签名、LaunchDaemon 与 Mach service、包内许可证/条款/隐私资产、Gatekeeper 和 stapling。它只读取公证历史以验证凭据，不会签名、提交公证、注册 helper 或修改网络；未加 `--strict` 时只输出结构化阻塞项，适合证书尚未准备好的本机检查。

## 进程边界

```text
Flutter / 普通用户进程
  |- 完整连接 core、远端出站、规则、日志和流量统计
  |- 仅监听 127.0.0.1 的 mixed 入站
  `- 通过受校验 XPC 请求启动或停止 TUN

YundoPrivilegedHelper / root
  |- 只接受同一 App 包、同一 Bundle ID 的运行中主进程
  |- 只接受一个 TUN 入站 + 本机 SOCKS 出站 + direct 绕行的白名单配置
  |- 把校验后的配置写入 root 私有目录，再启动同一签名 helper 的 raw-run 子进程
  |- 子进程通过包内 hiddify-core 的 `parseCli srun -c` 执行原始 sing-box 配置
  |- 不接收真实节点、账号、激活码或远端密钥
  |- 仅在本机回环地址开放独立的 Clash API 连接观测端口，不接受外部访问
  `- App/XPC 失联时终止 raw-run 子进程、删除活动配置并退出
```

客户端在启动连接前把受管 sing-box 配置拆成两份：

1. 普通 core 配置移除 TUN，保留本机 mixed 入站和真实出站。
2. 特权配置只保留 TUN、本机 SOCKS、direct 和从普通 core 脱敏投影的有效规则顺序。

helper 会再次解析并校验特权配置。远端节点、账号、激活码、节点密钥和任意本地文件路径都会被拒绝；规则投影只允许受限的匹配字段、`route/reject/sniff` 动作、固定的两个出站和经过约束的二进制规则集。

### 规则语义投影

普通 core 的“直连”出站仍发生在 TUN 之后。对使用自带网络库、独立 DNS 或 QUIC 的 App，这种二次接管可能破坏原本可用的连接；2026-07-27 的阿里云盘 `ERR_CONNECTION_CLOSED (-100)` 即为该失败模式。

首轮修复曾使用 `route_exclude_address_set=geoip-cn`，但该系统层排除先于普通 core 生效，会覆盖全局模式、用户“加速访问”和排在 GeoIP 之前的公共加速规则，因此属于 P0 行为冲突，不能作为正式兼容方案。

当前实现移除 TUN 系统层排除，将普通 core 已生成的有效规则按原顺序投影到 helper：

- 原规则命中 direct 时，在 helper 内直接交给物理网络，避免再次进入本机 SOCKS。
- 原规则命中加速出站时，在 helper 内转发到 `127.0.0.1` 的普通 core。
- `reject` 和 `sniff` 保留，DNS 劫持仍只由普通 core 负责。
- 未命中规则的流量最终进入普通 core，确保全局模式不会被 GeoIP 提前直连。
- 规则模式会在显式规则之后把未命中的 UDP 兜底送入加速出站，覆盖浏览器尚未识别域名或协议时的首包，避免访问落到普通 core 的直连兜底。

包内 `geoip-cn.srs` 仍使用签名 App 的固定路径。投影需要的其他远程二进制规则集只允许 HTTPS、不得携带 URL 凭据，并固定通过本机 SOCKS 下载。Helper 只接收域名/IP/端口/进程等匹配条件和规则集 URL，不接收真实节点参数；活动配置位于 root 私有目录，停止后删除，不保留配置副本。

### macOS 连接记录

macOS 的 direct 流量在 helper 内物理直连，不会经过普通 core 的 Clash API。为避免记录页因此丢失直连记录，helper 会按开发版/正式版使用独立端口在 `127.0.0.1` 提供连接观测接口，并复用普通 core 的本机随机 secret。客户端只连接 `/connections` 读取当前快照，不开放局域网访问；停止 helper 后端口和活动配置同时消失。

`scripts/verify_macos_privileged_helper.sh` 同时校验规则资源存在、路径替换后的投影配置和 App/helper 签名边界。

## 构建产物

Debug 构建后必须存在：

```text
Yundo Dev.app/Contents/Library/HelperTools/YundoPrivilegedHelper
Yundo Dev.app/Contents/Library/LaunchDaemons/app.yundo.client.rebuild.dev.privileged-helper.v3.plist
```

运行只读校验：

```bash
scripts/verify_macos_privileged_helper.sh
```

脚本会检查：

- helper 独立签名和 Bundle ID。
- LaunchDaemon `Label`、`BundleProgram` 和 `MachServices`。
- helper 能加载包内 `YundoCore.dylib` 的必要符号。
- Swift 安全边界接受最小 TUN 配置基线。
- 签名 App 内包含固定 `geoip-cn.srs` 规则快照，helper 只接受该包内路径；远程规则只接受经本机 SOCKS 下载的 HTTPS 二进制规则集。

这些检查不会注册服务、不会请求管理员权限、不会创建 TUN，也不会修改路由。

## 首次授权流程

1. 用户点击“启用”后，普通 core 先以双栈配置启动本机 mixed 入站，此时尚未启动 helper/TUN，也不接管系统路由。
2. App 通过该 mixed 入站并发探测固定 IPv4/IPv6 公网地址：双通道均成功时保留双栈；IPv4 成功但 IPv6 失败时，仅把本次会话重启为 IPv4 兜底配置；IPv4 失败时停止普通 core 并返回失败。
3. 网络能力判定完成后，App 检查 LaunchDaemon 状态；未注册时调用 `SMAppService.register()`。
4. 如状态为 `requiresApproval`，App 打开系统登录项设置并返回“需要系统授权后才能连接”。
5. 管理员批准后再次点击“启用”，App 通过 privileged XPC 启动最小 TUN 转发器。
6. 普通 core 或 helper 启动失败时，两侧都会执行停止清理，不能留下只接管路由但没有出口的状态。

IPv4/IPv6 探测使用字面量地址，默认最多尝试 3 次、每次 1 秒并间隔 300ms，不依赖尚未接管的系统 DNS。它只判断当前加速出站能否完成 HTTPS 连接，不缓存节点结论；每次开始或重建加速都会重新判定。TUN 配置始终保留 IPv6 接管能力，避免失败路径绕过云渡；IPv4 探测短时无结论时，本次会话继续使用 IPv4 兜底配置，而不是把可恢复抖动误判为启动失败。

连接状态与延迟探测是两条独立信号。只要普通 core 和 TUN 均已启动，首页就显示“加速已开启”；延迟暂不可用、探测超时或当前配置没有延迟选择组时，只影响延迟显示，不得把成功连接回退成“加速中”。

## 覆盖升级恢复

- 正式版或开发版覆盖升级后，`SMAppService` 可能仍保留旧 App 构建对应的后台项目登记。此时系统状态仍为 `enabled`，但 helper 无法启动，App 会收到 XPC 超时或连接失败。
- App 在首次 XPC 启动失败时会异步注销 helper；由于注销回调可能早于 macOS 后台项目数据库释放旧登记，App 会以 250ms 间隔有限重试注册，最多等待约 3 秒，再按新的系统状态继续：已启用时只重试一次 XPC，要求批准时打开系统登录项设置，重新注册或第二次 XPC 启动仍失败时停止并返回诊断。
- 开发版构建从开始阶段即退出旧 App，覆盖前再次确认进程已结束；没有有效 Apple Development 身份时拒绝覆盖 `/Applications/Yundo Dev.app`，避免把可真实加速的开发版替换为只能做包结构检查的 ad hoc 产物。
- 本机开发版安装每次使用单调变化的 `CFBundleVersion`，使 macOS 能区分 helper 内容或签名已经变化的新构建；用户可见版本号仍沿用仓库版本，不因此改变。
- 2026-08-04 本机 macOS 26 的开发版旧服务登记无法可靠刷新，且开发版 Bundle ID 已迁移为 `app.yundo.client.rebuild.dev`。开发版内部服务标识迁移为 `app.yundo.client.rebuild.dev.privileged-helper.v3`，绕开本机残留的旧登记；正式版继续使用 `app.yundo.client.privileged-helper`，不受迁移影响。
- 同日使用开发版构建 `20260726132726` 完成真实加速验收：新服务登记为 `app.yundo.client.dev.privileged-helper.v2` 并成功启动，公网路由进入 `utun7`（网关 `172.20.0.1`），Google `generate_204` 返回 `204`；随后对 `www.google.com` 发起新请求，路由观察器记录命中 `geosite-google` 并最终走 `nimbus-proxy`。主动停止后首页恢复“开始加速”，TUN 子进程退出，`1.1.1.1` 路由恢复为 `en0`（网关 `192.168.1.1`）。验收结束时保持开发版停止加速。
- 四端同类问题审计结论：本次根因只存在于 macOS 的 `SMAppService`、后台项目数据库与 Launch Constraint 链路，Windows 服务、iOS Packet Tunnel 和 Android VPN Service 均不读取 macOS helper 服务标识，也不经过本次修改的 Swift/LaunchDaemon 实现，因此不受影响；共享 Flutter 连接配置和规则匹配逻辑未因本次修复改变。Windows、iOS、Android 无需针对这个平台专属根因增加实体设备阻断项，后续仍按各自既有真机矩阵验收。
- 正式版本机覆盖安装必须使用有效的 Apple Development 签名身份。无有效身份时停止双版本安装并保留现有 App，因为 ad hoc 签名不能证明真实 helper 注册可用。
- 从 2026-07-26 起，本机 macOS 构建固定同时覆盖安装开发版和正式版。任一版本原先运行时，通过 App 正常退出路径先停止 TUN 并释放路由，安装后恢复该版本；原先未运行则保持未运行。两个版本均要求有效 Apple Development 身份，不再用 ad hoc 产物覆盖。
- 2026-07-25 本机正式版 `1.1.12+10022` 排障确认：系统仍登记旧构建 `+10018`，helper 启动以 `EX_CONFIG` 失败，App 最终收到 `helper_xpc_timeout`；同时旧 Apple Development 签名已不受信任。修复版按当前仓库版本重建为 `1.1.18+10028`，使用新的有效 Apple Development 签名完成备份式覆盖。首次注册后 helper 登记版本已更新为 `+10028`；真实验证完成“加速 -> 停止 -> 网络恢复 -> 再次加速”，加速时公网路由进入 `utun7` 且 Google `generate_204` 返回 `204`，停止后路由恢复 `en0` 且普通网络返回 `200`，最终保持已加速。

## 停止与恢复

- 主动断开：先停止普通 core，再通过 XPC 停止 TUN。
- 主动断开期间首页保持“正在停止加速”并禁用重复点击，至少展示 500ms；helper 返回后继续轮询云渡自有公网路由，确认本机加速资源释放后才恢复“加速”。服务端会话上报为尽力而为的后台步骤，不阻塞本机停止状态。
- 所有连接入口共用同一断开 Future；断开清理期间收到连接请求时先等待清理完成。断开后立即连接不再依赖固定 300ms/500ms 延时猜测。
- 自动加速同时要求设置开关已开启，且本次 App 运行未被用户手动停止。用户手动停止时会取消已排队的启动、恢复和重试任务，因此当前进程保持停止；完全退出并重新打开 App 后，本次运行状态会重置，继续按“自动加速”开关自动恢复。
- 原生冲突检查同时读取代表性 IPv4/IPv6 路由的接口和网关。只有固定 TUN 网关 `172.20.0.1` 或 `fdfe:dcba:9876::1` 命中时才认定为云渡自有路由；其他连接工具的 TUN、系统代理或企业代理只按连接冲突处理，云渡不会停止或修改它们。
- 开始加速前若发现云渡自有残留路由，App 会先重新连接 helper 执行停止，并只等待云渡路由释放后再继续；停止加速后的首轮复查若仍有云渡路由，也会再执行一次同样的定向清理。`stopTunnel` 不再依赖当前 App 内存中已有 XPC 连接，因此 App 重启后仍能清理旧 helper 会话。
- App 正常退出或异常结束：XPC 连接失效，helper 停止 TUN 后退出。
- helper 配置和子进程日志只保存在 root 私有目录，停止后删除活动配置文件。
- 不在 `/Library/LaunchDaemons` 复制自维护 plist；注册状态由 `SMAppService` 管理。

当前 Apple Development 包已完成干净基线下的连接前、连接后、主动断开和异常结束采证。主动断开与 `SIGKILL` 异常结束的严格对比结果均为 `ready`：连接时新增 TUN、目标公网路由命中新接口、结束后默认路由和公网路由恢复、额外 TUN 清理均通过。异常结束后 root helper 与 raw-run 子进程在 2 秒内退出。

2026-07-25 自适应 IPv6 与自有残留路由修复已通过 24 项定向测试、181 项全量 Flutter 测试、定向静态分析，以及 macOS Debug/Release 双构建、签名和 helper 校验。经明确授权完成 `/Applications/Yundo.app` 备份式覆盖后，首次自动加速、同进程停止/再加速、`⌘Q` 完全退出/重开自动加速三次都重新探测并记录 `ipv4=true, ipv6=false`，仅为当次会话应用 IPv4 兜底。Google 默认与 IPv4 请求返回 `204`，强制 IPv6 请求落到 IPv4-mapped 地址，真实 IPv6 字面量探测仍被当前出口重置；Chrome Google 首页与已登录账号页在三轮验证中均正常加载。停止和完全退出后 `--run-tunnel` 子进程结束，IPv4/IPv6 路由恢复 `en0` 且普通网络返回 `200`；重开后 helper/TUN 与 `utun7` 路由恢复，日志未出现残留路由或清理重试告警。最终保持正式版已加速。

2026-07-26 修复正式版 `1.1.19+10029` 手动停止接近 10 秒且随后立即自动恢复的问题。根因分别为停止流程同步等待服务端会话上报，以及启动、恢复和重试定时任务只检查“自动连接”开关、没有检查用户最近一次连接意图。修复后手动开始/停止先更新当前进程的连接意图，所有自动恢复入口在真正连接前再次校验；停止界面只等待本机 core、helper 和云渡自有路由释放，服务端断开上报转为后台尽力执行。15 项停止与自动恢复定向测试、187 项全量 Flutter 测试、定向静态分析和 33 项 Windows 相关定向测试通过；iOS arm64 无签名 Debug 构建、macOS 开发版/正式版双产物及 helper 校验通过。日常流程仅覆盖 `/Applications/Yundo Dev.app` 并保持未运行，没有改动正式版。

2026-07-27 回归确认上述连接意图不应持久化：手动停止只代表当前 App 运行期间保持停止，完全退出并重新打开后，如果“自动加速”仍开启，应再次自动加速。连接意图现改为进程内会话状态，新进程默认允许自动加速；手动停止仍会同步取消当前进程已排队的启动、恢复和重试任务，手动开始也会立即重新放开。macOS、Windows、iOS、Android 共用该 Flutter 状态与调度路径，因此通过共享层一次修复。新增共享测试模拟两个独立 App 会话，确认当前会话手动停止后禁用自动恢复，新会话重新允许自动加速；216 项全量 Flutter 测试和定向静态分析通过。macOS 开发版与正式版完成 Apple Development 签名、helper 校验和双版本覆盖安装；正式版重启日志记录 `auto connect [connection wrapper ready]` 后进入 `CONNECTED`，系统路由为 `utun7 / 172.20.0.1`，新的 Google 请求命中 `geosite-google` 并最终走 `nimbus-proxy`，返回 HTTP 204。Windows、iOS、Android 尚未基于本次修复形成同一 commit 的构建基线，实体设备生命周期回归继续保留。

同日完成正式版真实“停止 -> 驻留 -> 再次手动加速”验收：日志记录本机资源停止耗时 `500ms`，停止后持续超过 90 秒未自动恢复；TUN 子进程退出、公网路由恢复 `en0`，普通网络返回 `200`。再次手动加速后 TUN 子进程恢复、公网路由进入 `utun7`，Google `generate_204` 返回 `204`，最终保持已加速。

四端同类问题审计确认：macOS、Windows、iOS、Android 共用手动连接意图、自动恢复调度、首页开始/停止入口和服务端断开上报，因此四端此前都有同因风险，现已通过共享层一次修复。macOS 的自有路由释放、Windows 的系统服务停止、iOS/Android 的原生通道停止继续使用各自适配层，未发现与服务端上报阻塞相同的平台层根因。macOS 正式版真实验收已通过；实体 Windows 复测和真实 iPhone Packet Tunnel 停止仍待设备验收；Android 共享测试已通过，但本机没有 Android SDK，APK 构建和 M6 真机验证保留。

2026-07-27 国内地址系统层直连修复的跨平台审计结论：

| 平台 | 结论 | 证据与后续 |
| --- | --- | --- |
| macOS | 受影响并已修复 | 根因位于 `YundoPrivilegedHelper` 的最小 TUN 配置；登录 IP 已由 `utun7` 切换为 `en0`，阿里云盘彻底重启后登录页正常。 |
| Windows x64 | 不受本次平台根因影响 | Windows 使用 `WindowsTunnelService`，不会加载 macOS helper 或包内 macOS 路由排除配置；仍需按同源快照完成实体机构建和既有网络矩阵。 |
| iOS | 不受本次平台根因影响 | iOS 使用 Packet Tunnel，不经过桌面 `splitMacOSTunnelConfig` 的特权 helper 分支；模拟器构建不能替代真实 iPhone 验收。 |
| Android | 不受本次平台根因影响 | Android 使用 VPN Service，不读取 macOS Swift helper 与本地路由快照；仍需完成 Debug APK 同源构建和实体设备矩阵。 |

本轮 A/B 先后排除了 TUN `stack` 和 MTU：切换到 `gvisor`、把 MTU 从 `9000` 改为 `1500` 都未消除阿里云盘错误；仅系统路由排除恢复登录。最终代码未保留这两项实验改动。

正式工作区 `1.2.0+10030` 的最终验证结果：

- 24 项 macOS TUN/helper/构建脚本定向测试与 217 项全量 Flutter 测试全部通过，变更 Dart 文件静态分析无问题。
- macOS Debug `Yundo Dev` 与 Release `Yundo` 使用 Apple Development 身份完成构建、helper 校验、双版本覆盖安装和原运行状态恢复；两个安装包内的 `geoip-cn.srs` SHA-256 均为 `bc1a9eb66f9c6a0fe9fc5300cf5b5e885e0f9eadd7213b085b767a95d6af3d2a`。
- 正式版保持加速时，`39.156.169.125` 路由为 `en0 / 192.168.1.1`。阿里云盘于 17:26 完整启动，远端配置返回 HTTP 200，日志进入 `show login page` 且没有新的 `ERR_CONNECTION_CLOSED`；其 IPv4 连接源地址为物理网卡地址 `192.168.1.216`，不再是 TUN 地址 `172.20.0.1`。
- 新的 Google 请求返回 HTTP 204，路由观察器记录命中 `geosite-google` 并最终走 `nimbus-proxy`，证明国内系统层直连没有破坏境外加速。
- iOS 模拟器 Debug 构建通过。Android 生成 `app.yundo.client.dev`、`1.2.0+10030` 通用 Debug APK，使用 Android Debug 证书和 v2 签名；网盘产物 SHA-256 为 `88aaddd28d9242ea7f32e21da084a9de3b59cd10cc66ccac4323fccd50b9da27`，目标端 `shasum -c` 通过。
- 实体 Windows x64 主机在线，但 SSH 与 WinRM 均不可用；可自动控制的 Parallels Windows 为 ARM64，且没有 Flutter/Visual Studio，不能作为 x64 构建证据。本轮 Windows x64 同源构建保持未完成。

睡眠/唤醒和网络切换也已完成真机验证：

- Mac 睡眠约 13 分钟并完整唤醒后，App、root helper、raw-run 子进程和 TUN 路由均保持，首页继续显示“加速已开启”。
- Wi-Fi 链路连续中断约 15 秒期间，helper 子进程与 TUN 路由保持；Wi-Fi 恢复后首页仍显示“加速已开启”并继续刷新流量。
- 测试时临时开启的自动连接已恢复为测试前的关闭状态。

2026-07-16 交互补充验收：

- 点击“加速”后立即显示不可重复点击的“加速中”和旋转状态环；普通 core 先返回 `CONNECTED` 时仍保持该状态，helper/TUN 就绪后才切换为“加速已开启”。
- 首页圆形按钮统一使用小火箭加速图标；加速中和停止中使用旋转状态环，加速已开启时保留常驻细环，并使用低强度呼吸环和图标缩放表达加速仍在工作。浅色和深色主题均未出现遮挡或尺寸跳动。
- 真实日本节点完成“连接 -> 断开 -> 按钮恢复后立即连接”，第二次连接成功，未出现其他连接冲突、helper 错误或失败弹窗；最终断开后公网路由恢复物理接口，TUN 子进程为 0。

这些结果验证的是 `direct-mock` 下的系统权限、进程和路由恢复，不替代真实节点连通、节点切换和远端流量验收。

三阶段快照完成后运行只读对比：

```bash
scripts/check_macos_tun_evidence.sh \
  build/tun-evidence/<before-tun> \
  build/tun-evidence/<connected-tun> \
  build/tun-evidence/<disconnected-tun> \
  --strict
```

对比器检查连接阶段新增 `utun` 和对应路由、断开后默认出口/公网路由恢复、额外 `utun` 清理，并在断开目录生成不含网关、DNS、IP 或接口名的 `verification-summary.txt`。它只读取三阶段快照，不修改系统网络。

## CLI 与内置规则基线

macOS 的系统代理只影响会主动读取系统代理环境的应用，终端中的 `curl`、Git、部分
命令行运行时和后台进程可能直接建立 TCP/HTTPS 连接。因此云渡开发版和正式版在
macOS 上统一以 TUN 作为加速承载层：用户 core 继续运行原始完整配置并提供本地
SOCKS，特权 helper 只运行一个最小化的本地 TUN 配置，把未被规则判定为直连或拦截的
流量送入本地 SOCKS。停止加速时 helper 负责释放 TUN，系统代理保持关闭，避免退出后
残留网络接管。

TUN 的国内 IP 直连依赖包内 `assets/rules/geoip-cn.srs` 基线快照。它用于首次启动和
规则包尚未下载完成的场景；登录后获取到新的规则包时，用户 core 仍按云端版本更新，
不会把网络可用性绑定在远程规则下载成功上。当前内置快照 SHA-256 为
`bc1a9eb66f9c6a0fe9fc5300cf5b5e885e0f9eadd7213b085b767a95d6af3d2a`。

验证 CLI 流量时必须清除命令自身的代理环境变量，避免把系统代理或 shell 配置误当成
TUN 结果：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  curl --noproxy '*' --max-time 20 -i https://x.com
```

2026-08-04 修复特权 helper 首次启动超时：旧隧道清理通过 `Process` 执行 `ps` 时，先等待子进程退出、再读取标准输出；当进程列表超过管道缓冲区时，`ps` 会等待输出被读取而 helper 同时等待 `ps` 退出，最终导致 XPC 启动请求一直不返回。现在先持续读取管道再等待退出，旧 root 隧道可以完成清理，随后再启动新的 TUN 子进程。该修复不改变普通 core、规则投影、DNS 或路由策略。

2026-08-04 增加 macOS 加速启动阶段的网络能力有限重试：用户 core 启动后，节点代理可能还需要短暂时间完成首个可用连接；IPv4/IPv6 探测现在各自最多尝试 5 次、每次间隔 1 秒，避免把短暂的节点准备延迟直接显示为连接失败。超过约 20 秒仍不可用时才结束本次启动并交给既有自动恢复机制重试。

2026-08-05 排查反复启停的间歇性失败：发现 App 恢复前台时会重新执行 core setup，旧逻辑会删除正在等待网络探测的 `yundo-user-core-ipv4-fallback.json`，随后用户 core 重启收到 `no such file or directory`。现已取消 setup 阶段对活动临时配置的清理，并在探测前校验、必要时从内存恢复 IPv4 兜底配置。IPv4 探测默认最多 3 次，每次 1 秒，间隔 300ms；短时探测失败会继续使用 IPv4 兜底配置，避免把探测抖动误判为无法加速。开发版首页增加“加速过程”诊断，可逐步查看账号、套餐、规则、连接方案、core、网络探测、系统通道、路由和清理阶段；诊断结果只保存脱敏状态、时间和错误码，不保存节点密钥或访问内容。构建 `202608508` 完成双版本签名覆盖安装后，连续两轮停止/开启均在约 5.1 秒内完成，`utun7` 路由、Google/X CLI 请求和 Chrome Google 页面均通过。

2026-08-05 构建 `202608515` 细化加速诊断：启动流程固定展示连接状态、账号、套餐、规则、连接方案、核心服务、网络、系统通道、路由和清理共十个可定位阶段；成功阶段使用绿色勾选，失败阶段使用红色叉号，异常回收也会记录清理结果。开发版与正式版均完成 Apple Development 签名、helper 校验、覆盖安装和原运行状态恢复；开发版保持加速，路由为 `utun7 / 172.20.0.1`。

2026-08-05 规则加载与诊断日志补强：规则中心以本机已验证规则包为首屏数据源，并异步刷新账号规则包；`route-preferences` 请求失败时不再把“我的规则”静默显示为 0 条，账号规则与规则包按目标合并展示。加速诊断的规则阶段记录通用规则数量、公共规则版本、我的规则数量和账号规则版本；连接成功后依次完成核心服务、节点网络、系统加速通道和系统路由阶段，停止加速时对应记录核心停止、通道释放和路由恢复。未捕获异常按实际仍在运行的阶段归因，不再统一误报为核心服务失败。设置页新增“诊断日志”入口，桌面使用弹窗，移动端使用可返回的独立页面；复制内容保留完整脱敏诊断快照。构建号 `202608091` 已固化到 `pubspec.yaml`。

2026-08-05 首页诊断入口收敛：移除首页“查看加速过程”按钮和启动失败红色提示卡片。首页只负责加速状态与主要操作；启动、停止及失败的完整过程统一从设置页“诊断日志”查看，问题上报仍保留在设置页。构建号 `202608092` 用于本轮 macOS 验证。

## 版本边界

- 当前现代权限承载层要求 macOS 13+。
- macOS 12 及更早版本不会回退到已废弃的 `AuthorizationExecuteWithPrivileges` 或让整个 App 使用 `sudo`。
- 若后续必须支持旧系统，应单独评估签名完整的 legacy helper，不在当前 MVP 隐式兼容。
