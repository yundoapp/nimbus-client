# 云渡 Hiddify 重建迁移基线

最后更新：`2026-08-08`

## 1. 目标

本分支从 Hiddify 上游提交 `276a7effb0046a039220a745022563740968c0b8` 建立，目标是在保留云渡现有产品功能、界面布局和菜单结构的前提下，把云渡逻辑限制在 Hiddify 标准配置和应用层。

当前云渡 `develop` 仅作为功能、文案、视觉资源和行为的参考实现，不作为新的底层实现来源。

## 2. 不可越界的网络核心

以下能力由 Hiddify 和 sing-box 原有实现负责，云渡业务代码默认不得修改：

- `lib/hiddifycore/`：Core 生命周期、桌面和移动端核心通道
- `lib/singbox/`：核心配置模型和协议实现
- `macos/PrivilegedHelper/`：macOS 特权辅助进程
- `macos/Runner/PrivilegedHelperBridge.swift`：macOS Helper 通道
- `windows/runner/`：Windows 原生进程、服务和网络集成；仅允许独立的产品名、窗口名和图标改动
- `ios/Runner/VPN/`：iOS Packet Tunnel 管理
- `ios/HiddifyPacketTunnel/`：iOS 隧道扩展
- Android 后台 VPN Service 和核心服务实现

云渡只允许通过现有的 Profile、Route Rules、Config Option、Connection Repository 等应用层接口提供数据和发起连接。品牌改名可以调整最终安装包里的可见文件名、进程名、Bundle ID、通知标题和图标，但不得借此改变网络行为。

## 3. 云渡功能迁移范围

以下能力必须迁移，但不得以重写网络底层为代价：

- 登录、长期登录态和账号资料
- 套餐、激活码、设备和流量状态
- 首页加速/停止加速、节点地区、速度和流量展示
- 自动连接、开机启动、托盘和窗口行为
- 访问偏好和自定义访问规则
- 问题上报、公告和版本提示
- 云渡品牌资源、多语言、首页布局、设置页面和菜单顺序

迁移 UI 时优先保留云渡 `develop` 的页面层级、布局、菜单顺序和用户文案；只替换其底层数据来源和连接调用。

## 4. 规则和连接适配原则

1. 后台返回短期连接方案、完整 Hiddify 标准 Profile 和账号规则清单；公共规则项只描述规则集名称、来源 URL、策略和清单版本。
2. 客户端只校验并安装标准 Profile，不消费旧版 `singBoxConfigPatch`；连接前把清单转换为 Hiddify Config Option 的受控入口，不拼装整份运行配置，也不自行实现 SRS 的下载、缓存或更新判断。
3. Hiddify 原有 `ProfileParser`、`ProfileRepository`、`ConnectionRepository`、配置构建器和 Core 生命周期继续负责解析、生成 DNS/inbound/最终路由、启动和停止。
4. 受控入口只允许追加 `route.rules` 和 `route.rule_set`。如果某项云渡能力超出该边界，优先调整产品规则表达或暂缓，不扩大到 DNS、TUN、系统代理或 Helper。
5. 不允许由云渡代码接管系统 DNS，不允许在加速前后直接修改物理网卡 DNS，不允许自行创建或清理系统路由。

公共规则的运行时更新时间以 sing-box remote rule-set 为准。核心负责远程 SRS 的下载、缓存、校验、刷新和加载；云渡后台只维护规则清单，客户端只通过核心已有的本机只读状态接口读取各规则集最后确认时间。构建时随 App 打包的 SRS 只作为核心的离线 fallback，不参与远程版本判断；`publicRulesUpdatedAt` 仅表示云渡清单发布时间。

Hiddify Core 校验 profile 时会使用临时输入文件生成完整运行配置；在部分桌面启动时序下，Core 释放临时输入后可能异步清理校验输出路径。因此云渡适配器使用独立校验路径读取 Hiddify 生成的完整配置，先完成 Hiddify profile 入库并等待 active profile 稳定，再把完整配置写入云渡自己的最终 profile 文件，最后调用原生 `ConnectionRepository.connect`。Hiddify 标准 Profile 解析器会规范化节点内容并丢弃顶层产品路由，所以账号规则不能只写在 Profile 中；客户端必须在连接前把当前规则清单转换成受控 Config Option，由 Hiddify 在生成完整运行配置时追加。不得把后台返回的原始 profile 直接覆盖为最终运行文件，也不得让云渡接管 Core 的 DNS、TUN 或系统代理配置。

服务端可以继续返回旧 `singBoxConfigPatch` 供旧客户端兼容，但新客户端收到缺少 `profileContent` 的响应时必须失败关闭，不得回退消费旧字段。

当前已完成：认证壳、首页/连接按钮、设置页、路由偏好、问题反馈、应用生命周期接入和标准 Profile 适配器；当前尚未完成四端构建、真实节点连接和安装版网络矩阵。

本机 macOS Debug 版本 `202608033` 已使用本地 API 标准 profile 完成自动连接并进入 `CONNECTED`；该结果只证明 Hiddify profile 生命周期和本地连接闭环正常，不替代真实节点、微信开发者工具和四端网络矩阵验收。

macOS Debug 已设置独立 Bundle ID `app.yundo.client.dev` 和安装名 `Yundo Dev.app`，Release 使用 `app.yundo.client`；开发版与正式版不共享登录态、偏好或 Core 数据目录。当前桌面发布层使用 `YundoCore` 文件名和云渡窗口/进程名，不把旧 Helper 带入新分支；源代码目录和上游模块名暂时保留，避免为了改内部名而触碰 Core ABI。构建入口 `scripts/build_install_run_macos_dev.sh` 会拒绝把 Hiddify 名称带入最终 macOS App 包。

品牌验收以最终安装包为准：进程管理器、应用包目录、系统设置里的应用名、通知服务名、快捷方式和应用图标都必须显示云渡品牌；内部源码路径、协议模块名和许可证归属不属于用户产品界面，但不得被复制成用户可见的运行时文件名。

macOS 的正式版和开发版使用不同且带版本后缀的特权 Helper 服务标识（当前均为 `.privileged-helper.v3`）。构建签名脚本必须从 App 的 `YundoPrivilegedHelperService` 读取并校验服务名，不能回退到旧的无版本服务名，以避免旧安装残留的 launchd 注册阻断隧道启动。

桌面 Core 进程隔离和退出清理是应用生命周期边界，不改变 DNS、TUN、路由或代理实现：正式版继续使用既有 Core 通道，macOS 开发版使用独立端口 `17179`，避免接管正式版或旧 Helper 的 Core；桌面退出无论来自窗口、托盘还是 macOS 系统菜单，都必须先调用 Hiddify 原生停止接口并清理云渡连接状态，随后才允许进程退出。macOS 原生终止通过 `yundo.application.lifecycle` 与 Flutter 握手，不能只依赖 `onWindowClose`。

构建链固定使用 `dependencies.properties` 中声明的 Hiddify Core `v4.1.0` 和源码提交 `c9d6f0f00b2eda34e4fb71863e4e0a62b3e931a0`。四端从该源码应用 `patches/hiddify-core/0001-managed-route-options.patch` 后构建，不再混用更新的子模块源码和旧版预编译产物。`CHANNEL=dev` 只决定应用配置和 Dart 入口，不得切换到远程 `draft` Core；升级 Core 必须同步评审补丁、客户端适配、四端构建和网络回归。

移动端 Flutter 与原生之间的内部通道统一使用 `yundo.app/*`，不再用旧的 Hiddify 前缀，也不从 Bundle ID 动态拼接。开发版和正式版可以使用不同 Bundle ID，但必须共享同一组内部通道。移动端核心首次 gRPC 握手必须设置有限超时；Simulator 只跳过真机 VPN 配置加载，不改变真机 Network Extension 路径，底层启动失败时应用仍应进入可诊断的用户界面而不是永久停留在启动页。

开发重建分支的 GitHub Actions 持续构建 Windows x64 内部验收包和 Android Debug APK，并先从锁定源码生成包含受控规则入口的 Core；Apple 平台同时保留本地快速构建和远程签名构建入口。Windows 暂不要求 Authenticode 或 MSIX，Android 使用 Debug 签名。正式发布仍必须另行提供各平台签名材料；不能把日常基线产物当作对外发布包。

### 4.1 页面、品牌和托盘走查（2026-08-03）

- 静态检查已覆盖全部实际 `goNamed` 调用；发现并修复 `routeHistory` 漏注册问题，并在设置页补回日志入口。当前日志、关于、路由历史、通用设置、路由规则、按应用代理、DNS、入站、TLS、链式代理等路由均有注册路径。
- macOS Dock 和 App 包图标使用云渡蓝底白色 `Y`；macOS 原生状态栏使用同一白色 `Y` 模板图标，并以右上角状态点表示连接状态：连接为绿色、切换中为橙色、未连接为灰色空心点。Windows 托盘也使用云渡 `Y` 图标资源，不再使用旧的图表型托盘图标。
- 托盘初始化已移动到 `runApp` 之后异步执行，避免 macOS 状态栏响应慢时阻塞首页启动。`4.1.2+202608056` 本机安装版启动日志无 `system tray TimeoutException`，退出后系统代理恢复关闭。
- 当前 commit `0b6d9d8` 已完成本机 macOS Debug/Release 安装版、iOS Simulator Debug、GitHub Windows/Linux/Android 构建和测试；GitHub macOS job 仍因仓库缺少 Apple 签名证书密钥而失败，不能据此判断 macOS 源码编译失败。
- 由于本轮验收时 Mac 处于锁屏，Computer Use 无法执行逐页鼠标点击；页面的静态路由和安装版启动已验证，解锁后仍需补做一次真实页面逐项点击及托盘截图验收，完成前不宣称“所有页面已人工打开”。

### 4.2 macOS NavigationRail 红屏修复（2026-08-03）

- 根因：桌面 `StatefulShellRoute` 有首页、可选配置、设置、日志、关于 4/5 个分支，但 `NavigationRail` 只生成首页、可选配置、设置 2/3 个目的地；进入日志或关于时 `currentIndex` 超出 `destinations` 范围，触发 Flutter `selectedIndex` 断言并显示红屏。
- 修复：桌面导航目的地改为复用与 shell 分支完全相同的顺序，移动端继续只保留首页和设置；新增导航数量测试覆盖有无配置两种桌面状态和移动端状态。
- commit `63bf5e5` 已完成完整 Flutter 测试（37 项）、本机 macOS 双版本构建安装、iOS Simulator Debug 构建，以及 GitHub Windows/Linux/Android 构建。安装版启动进程保持存活，系统日志未再出现 `NavigationRail`/`selectedIndex` 断言。
- 本轮仍未完成人工逐页截图：Computer Use 对系统中遗留的旧同名 Bundle 映射错误，无法读取当前 `app.yundo.client.dev` 窗口；这属于验收工具阻塞，不作为页面已人工验收的证据。

## 5. 迁移顺序

### 阶段 A：基线

- 证明干净 Hiddify 在 macOS、Windows、iOS Simulator、Android 的构建和基础生命周期可用。
- 记录加速、停止、异常退出、系统网络恢复和微信开发者工具场景的基线结果。

### 阶段 B：无网络副作用的产品层

- 迁移品牌、多语言、登录页面、首页布局、设置菜单和托盘展示。
- 这些改动不得触碰受保护网络目录。

### 阶段 C：数据和配置适配

- 迁移账号、套餐、激活、设备、流量和访问偏好数据模型。
- 新增云渡适配器，只生成 Hiddify 标准 Profile/Route Rules 输入。

### 阶段 D：连接闭环

- 接入短期连接方案。
- 复用 Hiddify 原有连接仓库和平台通道。
- 逐端验证连接、停止、重启、睡眠、网络切换和异常恢复。

### 阶段 E：替代旧版本

- 新分支通过四端同源构建和真实网络矩阵后，才替代当前 `develop`。
- 当前 `develop` 保留为回退参考，不直接回滚或覆盖。

## 6. 每个迁移提交的验收门槛

- 变更文件通过 `scripts/check_yundo_hiddify_boundary.sh`。
- 确需修改受保护网络文件时，只允许把已完成跨平台审计和定向测试的最终内容以 Git blob 精确哈希登记到边界脚本；路径级放行不能用于网络行为变更。文件后续发生任何变化时，门禁必须重新失败并重新审阅。
- UI 改动保留现有页面层级、菜单结构和多语言要求。
- 连接相关改动必须有 Profile/规则 fixture 和失败路径测试。
- 影响客户端运行的改动必须基于同一 commit 完成四端构建基线。
- 真实安装版必须验证网络可用性，不能只以编译成功作为通过。

### 4.3 加速按钮、标题和桌面主导航调整（2026-08-03）

- 加速按钮不再调用通用 Hiddify 实验功能确认弹窗。该弹窗在根导航上下文尚未就绪时会静默返回拒绝结果，导致用户点击后既没有连接请求也没有错误提示；云渡按钮现在直接调用云渡连接控制器，并以可等待的异步回调启动、停止或重连。
- `MaterialApp` 和桌面窗口标题统一使用现有多语言 `common.devAppTitle`/`common.appTitle`：中文显示“云渡开发版”/“云渡”，其他语言显示“Yundo Dev”/“Yundo”。切换语言时同步更新 macOS 标题栏。
- 桌面主导航固定为“主页、记录、设置”。“记录”直接进入云渡加速记录页；配置文件、通用日志和关于页面不占用主导航位置，避免再次出现 shell 分支与导航目的地数量不一致。
- macOS 本机构建脚本在覆盖 `/Applications/Yundo Dev.app` 和 `/Applications/Yundo.app` 后始终启动并验证开发版；正式版只覆盖安装、不启动，避免两个版本同时接管网络。
- 本轮按项目负责人要求优先执行本地 macOS Debug/Release 和 iOS Simulator 构建；Apple 远程签名入口已加入 `.github/workflows/apple-build.yml`，待 GitHub Secrets 配置后执行签名验收。

### 4.4 macOS 品牌与桌面交互回归（2026-08-03）

- macOS 系统菜单、Dock 悬停名称和菜单栏提示必须跟随当前语言：简体中文为“云渡开发版”，繁体中文为“雲渡開發版”，其他语言为“Yundo Dev”；不能只修改 Flutter 窗口标题。
- 首页点击加速或停止加速后立即展示过渡状态，并保证用户能够看到“正在加速中”或“正在停止加速”，再进入最终状态。

### 4.5 规则提示与节点地区本地化（2026-08-04）

- 规则编辑器根据规则类型分别显示域名、IP 地址和 CIDR 网段的输入提示，避免把三种格式混在一个 placeholder 中；规则类型切换后提示立即更新。
- 内置节点地区使用统一的国家代码映射，同时在桌面首页下拉菜单、移动端地区列表、节点卡片和系统托盘复用国旗与本地化名称。简体中文、繁体中文及其他已支持语言只显示一个本地化国家名，不再拼接英文和中文。
- 服务端返回的非内置地区仍按 API 提供的语言名优先，缺少对应语言时按当前语言的中文或英文兜底；后续新增地区只需补充服务端 displayNames 或客户端内置映射。
- 首页加速模式和节点地区的桌面下拉触发器、菜单统一使用相同的可用宽度，避免菜单比对应卡片窄。
- 设置页打开关于页面时保留返回栈；关于页同时提供明确返回按钮，直接访问时返回设置页。
- 桌面主导航使用短名称“记录”，页面标题继续使用“加速记录”，避免导航项过长。

### 4.5 加速记录数据源与设置菜单修复（2026-08-03）

- 加速记录曾固定连接一套未实际写入运行配置的 `127.0.0.1:19090` 诊断端口，因此页面即使在加速中也只能显示 0 条。修复后直接读取 Hiddify 核心生成的 `data/current-config.json`，复用其中现有的本机 Clash API 地址和临时密钥，不新增端口、不修改 DNS、路由、TUN、Helper 或系统代理。
- 记录数据源只接受 `127.0.0.1`、`localhost` 或 `::1` 回环地址；临时密钥仅用于 App 与本机核心之间的 WebSocket 鉴权，不显示、不记录、不上传。核心重连后会重新读取配置，避免沿用旧端口或旧密钥。
- 桌面路由分支与可见导航同步调整为“主页、记录、设置”；移动端继续从设置页进入记录，保持既有底部导航结构。
- 设置页移除面向普通用户的“日志”入口；日志路由暂时保留给内部诊断和问题上报流程，不再作为设置菜单展示。
- 语言选择中的两个中文选项固定显示为“简体中文”和“繁体中文”。
- 跨平台审计：记录采集与解析位于共享 Dart 层，macOS、Windows、iOS、Android 同因受影响并使用同一修复；本轮 macOS 安装版完成真实请求验收，iOS Simulator完成构建验证，Windows/Android按当前本地优先决策等待后续构建与实体设备验收。

### 4.6 自定义网站规则未进入运行配置（2026-08-03）

- 现象：账号已保存 `rawya.ai -> 直连访问`，但新请求仍命中 `final` 并走加速出口。
- 平台根因：声明 `configVersion` 的连接方案会把规则从兼容字段 `singBoxConfigPatch` 中移除，但曾错误地继续用该兼容字段生成 `profileContent`，导致标准 Profile 没有当前用户规则。平台已改为分别生成“标准 Profile 完整快照”和“旧字段兼容快照”。
- 客户端根因：Hiddify 标准 Profile 解析器只保留节点配置，顶层 `route` 不会进入最终运行配置；旧 Flutter `route-rule` 字段在当前 Core 中也没有执行路径。因此只修平台仍不能让规则生效。
- 修复：客户端在每次手动或自动加速前校验规则 manifest，下载并验证同版本账号规则包，按“用户自定义网站 -> 公共规则 -> 本地网络兜底 -> 明确的模式默认路由”生成受控规则数据；Hiddify Core 只新增 `managed-route-rules` 和 `managed-route-rule-sets` 两个 Config Option 字段，把它们追加到原生路由表。直连规则使用 Hiddify 自带的 `direct §hide§` 出站，不新增直连出站，也不覆盖 DNS、inbound、TUN、系统代理或 Helper。
- 规则合并：用户自定义规则放在 Hiddify 地区默认规则之前，保证 `rawya.ai -> 直连访问` 这类明确选择不会被更宽泛规则先命中；规则集在 Hiddify 完成内置地区规则集后按 tag 去重，`geoip-cn`、`geosite-cn` 等重名项由云渡管理的远程来源替换 Hiddify 内置版本，避免同名规则源不一致或 sing-box 因重复 tag 拒绝整份配置。
- macOS 打包：Xcode 的 Core Copy Files 阶段必须在所有构建动作执行；双版本安装脚本每次都删除 App 内旧 Core、复制本轮源码构建的 `YundoCore.dylib`，并在签名前检查 `managed-route-rules` 标记。禁止以“目标文件已存在”为理由复用上轮 Core，否则 Dart 规则已经生成也不会进入实际运行核心。
- 四端构建身份：同一轮基线使用 `pubspec.yaml` 中的统一构建号，每轮构建前递增构建号；App 内所有版本展示统一使用 `MAJOR.MINOR.PATCH+BUILD`，开发版再追加环境标识。macOS 双版本构建脚本默认读取该构建号，并把同一个值写入两个 App 的包元数据；Android Debug 固定使用独立包名 `app.yundo.client.dev`，系统语言为简体中文、繁体中文和其他语言时分别显示“云渡开发版”“雲渡開發版”和“Yundo Dev”。Windows/Android CI 交付文件统一使用 Yundo 名称，不把内部 Flutter package 名带入产物文件名。
- Windows Core 构建从锁定的 `hiddify-core/go.mod` 解析 Cronet 完整伪版本并传给上游 Makefile；不直接使用上游版本文件中的裸 commit hash，避免 Go 模块代理无法解析时漏生成 `libcronet.dll`。该处理只修复依赖寻址，不升级或替换锁定的 Core 依赖。
- 失败策略：首次没有有效缓存且规则包下载失败时不启动加速；已有已验证缓存时可继续使用旧规则，只有新包下载并校验成功后才原子替代。连接方案与规则包版本在准备期间不一致时失败关闭，避免半新半旧配置。
- 跨平台矩阵：规则准备和 Config Option 序列化位于共享 Dart 层，macOS、Windows、iOS、Android 同因受影响并同因修复；Core 补丁由四端同一源码提交和同一补丁生成。macOS 需要安装版真实直连/加速双向请求证据；Windows、iPhone、Android 仍需实体设备补做真实分流，但不能使用旧预编译 Core 作为本轮构建证据。

### 4.7 Apple 签名与远程构建（2026-08-03）

- iOS 工程统一使用 Apple Team `W684N2R45F`；正式版主 App 和 Packet Tunnel 分别为 `app.yundo.client`、`app.yundo.client.PacketTunnel`，开发版分别为 `app.yundo.client.dev`、`app.yundo.client.dev.PacketTunnel`。工程中已清理旧 Hiddify Team、旧 Bundle ID 和旧 profile 名称。
- `scripts/build_macos_remote.sh` 负责远程 macOS Debug/Release 构建、Yundo Core 替换、重签、签名校验和 ZIP 产出，不覆盖 `/Applications`；本地 `scripts/build_install_run_macos_dev.sh` 继续负责快速构建、双版本覆盖安装和启动验收。
- `scripts/build_ios_remote.sh` 负责 Flutter 框架准备、无签名 Xcode 设备归档、App Store Connect API Key 自动 profile 管理、IPA 导出和主 App/Packet Tunnel Bundle ID 校验；iOS 分发身份只在导出阶段通过 `exportOptions.plist` 选择 `Apple Distribution`，不让归档阶段依赖开发设备或覆盖 CocoaPods。`.github/workflows/apple-build.yml` 通过手动触发同时产出 macOS 开发版、macOS 正式版和 iOS 正式版 artifact。
- Apple Developer 计划开通不等于远端已经具备签名材料；首次远程构建前必须按 `docs/development/apple-signing-setup.md` 配置 App ID 能力、证书、`.p12`、App Store Connect API Key 和 GitHub Secrets。配置完成后，commit `c1506ee` 已在 GitHub Actions run `30824938269` 通过 iOS IPA、macOS 开发版 ZIP 和 macOS 正式版 ZIP 的远程签名构建验证。

### 4.8 规则可视化与四端统一主导航（2026-08-03）

- 桌面端和移动端共享同一组四个主菜单，顺序固定为“主页、记录、规则、设置”；路由分支、NavigationRail、NavigationBar 和多语言菜单标题必须保持一一对应，避免再次出现 `selectedIndex` 越界红屏。
- “规则”页面是面向普通用户的清单入口，只展示当前规则、访问方式（加速/直连/拦截）、来源（自定义/公共/本机）、规则版本、软件版本和本机最近成功保存规则包的时间。
- 页面不再展示编译路由、Core 有效配置、规则库详情或原始 JSON；这些实现细节继续留在运行链路和问题诊断数据中，不进入普通用户界面。
- 规则页面读取现有规则清单缓存，并通过 Core 提供的本机 `/providers/rules` 只读接口查询规则集状态；该查询不触发网络规则更新，也不修改 DNS、路由、TUN、系统代理、Helper 或 Core 生命周期。
- 设置页删除整块“加速与访问”分组；自定义网站管理继续从首页“加速模式”入口进入。记录不再作为设置页重复入口，统一使用主导航进入。
- 该导航和规则页面位于共享 Flutter/Dart 路径，macOS、Windows、iOS、Android 必须同步保留实现和翻译。当前验收优先本机 macOS 双版本与 iOS Simulator；Windows/Android 继续由远程四端构建同步覆盖，实体设备验收另列清单。
- 本轮构建策略：本机只优先构建和覆盖安装 macOS、iOS Simulator；远端提交后保持 Windows x64、Android Debug 与 Apple 远程入口可构建。不能因为本轮暂不验收 Windows/Android 而删除或平台化遗漏共享功能。

### 4.9 设备管理首次打开加载状态（2026-08-03）

- 设备管理弹窗或页面首次打开时，账号恢复可能尚未完成；不能把尚未请求设备列表误显示为“暂无设备”。认证恢复中、设备请求中和已有错误必须分别呈现加载、进度或重试状态。
- 设备列表请求绑定到认证 session 就绪事件；首次打开期间即使 session 尚未恢复，恢复完成后也会自动请求，不要求用户关闭窗口再重开。
- 设备接口和设备生命周期未改变；该修复位于共享 Flutter/Dart 展示与请求触发层，macOS、Windows、iOS、Android 使用同一行为。

### 4.10 规则页面信息收敛（2026-08-04）

- 规则页面由多层技术诊断展开改为单一规则清单，保留规则名称、访问方式、来源、规则版本、软件版本和本机更新时间。
- 规则包成功保存后写入 `cachedAt`；页面将其标记为“本机更新”，旧缓存没有该字段时显示暂无记录，不使用页面打开时间推测更新日期。
- 共享 Flutter/Dart 页面和规则包模型同时覆盖 macOS、Windows、iOS、Android；本轮不改变规则生成、下载、路由、DNS、TUN、Helper 或系统代理行为。

### 4.12 登录首屏与品牌资源回归（2026-08-05）

- 云渡账号登录成功后直接进入主页，不再经过旧版首次启动 IntroPage；已有设备如果保存过 `intro_completed=false`，在登录恢复或登录成功时自动迁移为已完成，保证旧数据不会再次把用户拦在已废弃的设置页面。
- App 启动恢复本地会话期间使用独立 `/auth/restoring` 过渡页，复用安装包应用图标和正式版/开发版多语言名称；恢复成功进入首页，恢复结束且无有效会话时才进入 `/auth/login`，不再让登录表单在自动登录前短暂闪现。该逻辑位于共享 Flutter 路由与页面层，macOS、Windows、iOS、Android 同源生效。
- 认证页、关于页和 macOS 原生应用图标统一使用云渡蓝底白色 `Y`；macOS 原生窗口显式设置包内 `AppIcon.icns`，避免窗口或系统缓存显示默认图标。
- 旧 Hiddify 柱状图不再作为用户可见资源：通用托盘 PNG、Android 启动图、Android 应用商店图和旧 banner 已替换为云渡 Logo；Windows 三态托盘继续使用已有的云渡 `Y` 图标和状态点。
- 该变更位于认证路由、品牌展示和资源层，不改变 Core、DNS、TUN、路由、Helper 或系统代理行为；macOS 开发版、正式版以及其他端共享资源需按同一提交重新构建。

### 4.11 主导航记录图标统一（2026-08-04）

- 桌面侧栏和移动端底部导航的“记录”入口统一使用主页同款小飞机图标 `rocket_launch_rounded`；页面内筛选、状态和清空图标保持原有语义，不受影响。

### 4.12 记录条目加速图标统一（2026-08-04）

- 记录列表中代表“加速访问”的条目图标与主页、主导航统一使用 `rocket_launch_rounded`；“直连访问”继续使用 `language_rounded`。
- 图标选择集中到共享 Flutter/Dart 函数并补充单元测试，macOS、Windows、iOS、Android 使用同一映射。

### 4.13 自定义网站图标与数量一致性（2026-08-04）

- 自定义网站弹窗中的加速访问也统一使用小飞机图标。
- 加速模式弹窗通过共享的路由偏好数据源显示网站数量，并在登录态恢复完成以及网站增删改后重新加载，避免模式弹窗和自定义网站列表展示不同快照。

### 4.14 账号与位置请求失败时的加载状态（2026-08-04）

- 桌面托盘只消费已经加载好的位置列表，不再在每次认证状态变化后自动重试位置请求；位置请求失败时必须停在可再次手动触发的失败状态，不能形成后台重试循环。
- 位置列表属于首页辅助数据，不占用账号全局 `isLoading`；账号资料失败时，主页的账号重试按钮和主操作按钮必须在请求结束后恢复可点击。
- 账号资料刷新增加并发合并，主页手动重试、自动加速准备和其他恢复流程共享同一个请求，不重复发起互相覆盖状态的请求。
- 该修复位于共享 Flutter/Dart 认证与托盘状态层，macOS、Windows、iOS、Android 同源生效；本机 API 未启动时应显示明确失败状态，而不是永久转圈。

### 4.15 设置菜单分组与关于入口（2026-08-05）

- 设置页继续隐藏分组标题，仅通过组间留白表达层级；菜单顺序统一为通用、账号与设备、支持与反馈、平台维护项（仅适用平台显示）、退出登录。
- “诊断日志”和“上报问题”归入同一支持与反馈组；“设备管理”和“修改密码”归入账号与设备组；退出登录保持底部独立危险操作。
- 设置里的“关于”复用现有内容，桌面端以弹窗打开，移动端以可返回的新页面打开；关于页的更新检查、工作目录、复制版本和外部链接行为不变。
- 该调整位于共享 Flutter/Dart 设置层，macOS、Windows、iOS、Android 使用同一菜单顺序和自适应打开策略；构建号 `202608093` 用于本轮 macOS 验证。

### 4.16 全局加速规则优先级与 CI 边界检查（2026-08-05）

- 全局模式不只是忽略云渡账号规则，还必须覆盖 Hiddify 原生的地区规则。否则 `geosite-cn` 等内置直连规则仍可能先命中，导致国内站点在全局模式下绕过加速。
- 全局模式现在通过受控的 IPv4/IPv6 全覆盖 `route -> nimbus-proxy` 规则实现；规则包中的我的规则、通用规则和 Hiddify 内置地区规则都不会改变全局模式的出口。规则模式继续按“我的规则、通用规则、本地网络兜底”执行。
- CI 的 Hiddify 边界检查只比较当前 push 相对上一个提交，或当前 Pull Request 相对目标分支基线；不能固定比较 `main`，因为 `develop` 已包含经过评审的云渡重建历史，整段比较会把历史核心迁移误报为当前越界修改。
- 该规则生成逻辑位于共享 Flutter/Dart 层，macOS、Windows、iOS、Android 同源覆盖；全局模式需要重新构建对应平台 Core/客户端后再做真实请求验证。

### 4.17 加速诊断核心阶段拆分与顺序标识（2026-08-05）

- 加速诊断按编号从上到下执行，步骤列表直接通过编号表达阅读顺序，避免增加重复的进度说明。
- 启动流程将核心服务拆成“校验加速配置、准备核心服务、启动核心进程、确认核心状态”四个独立阶段；每个阶段分别记录开始、成功或失败、耗时、详情和错误码。
- “确认核心状态”必须确认 Core 返回运行中后，才继续进入网络、隧道和路由阶段；Core 启动请求成功但状态异常时，诊断会明确停在该阶段。
- 停止流程将核心服务拆成“停止核心进程、确认核心已停止”两个阶段，之后再记录隧道释放、路由恢复和清理，避免把核心未停止误归类为网络问题。
- 规则加载阶段只显示通用规则版本和我的规则数量，不在用户界面展示账号规则包 SHA 摘要；旧版本已保存的 `core` 诊断步骤继续兼容解码，新记录不再把整个核心生命周期合并成一个黑盒步骤。
- 成功的加速或停止诊断不再把“加速已开启/已停止”作为红色错误详情显示；只有失败过程显示错误码和错误详情。诊断日志界面最多展示当前过程和最近 9 次历史记录，共 10 次。
- 历史诊断记录支持展开查看完整步骤；已知的成功阶段详情在展示时按当前语言重新渲染，避免用户切换语言后标题是英文、详情仍是旧语言。
- 诊断日志只维护简体中文、繁体中文和英文三套文案：简体中文与繁体中文使用对应中文，其他应用语言统一使用英文；诊断过程写入历史记录时也使用同一策略，避免新旧记录混用语言。

### 4.18 品牌图标与按需跨端构建（2026-08-05）

- 关于页直接复用 `assets/images/app_icon.png`，与 macOS AppIcon 使用同一品牌资源，不再同时维护一份独立的 SVG Logo。
- macOS AppIcon 在图标画布内增加透明安全边距，降低 Dock 中视觉尺寸偏大的问题；Flutter 页面内的品牌图标不缩放、不改色。
- `ci.yml` 的日常 push/PR 默认只执行共享测试和云渡/Hiddify 边界检查，不再等待 Windows/Android Core 或安装包构建。需要验收 Windows 或 Android 时，在 GitHub Actions 手动运行 CI 并分别勾选 `build_windows`、`build_android`；两个端仍保留完整同源构建链路和 artifact 上传。构建号 `202608105` 用于本轮 macOS/iOS 本地验证。

### 4.19 SRS 规则库可观测性与根域匹配（2026-08-05）

- 远程 SRS 规则库现在记录“从缓存加载、开始下载、下载失败、更新完成/未修改”完整生命周期；生命周期事件使用 Core 默认 `warn` 级别，确保不会被用户的日志级别偏好过滤；四端构建脚本统一应用 `0002-rule-set-observability-and-root-domain.patch`，构建退出时自动还原 Core 子模块源码。
- 没有可用缓存且首轮 SRS 下载失败时，Core 启动失败并在诊断日志中保留具体规则库标签和错误详情，客户端不会再把规则未加载的状态报告成“已加速”。已有缓存时允许继续使用缓存；后台更新失败会在“加载规则库”阶段显示为告警并留下 Core 日志，但不会因一次更新失败立即中断已有连接。
- 诊断日志增加独立“加载规则库”阶段，列出规则库加载成功、失败或状态未确认；规则库失败会使用 `RULE_SET_DOWNLOAD_FAILED` 或 `RULE_SET_STATUS_UNKNOWN` 错误码，并阻断后续网络、隧道和路由阶段。
- macOS 诊断读取配置准备完成后生成的最终 Core 配置，而不是配置生成前的原始 profile，确保公共规则库和账号规则库不会被错误统计为 0 个。
- 远程规则库匹配先执行原始域名匹配；原始匹配失败时，按可注册根域及其父域逐级回退，例如 `support.weixin.qq.com` 会依次检查 `weixin.qq.com`、`qq.com`，直到公开后缀为止。每一级都只会命中规则库中明确存在的条目，不会因为域名属于 `qq.com` 就自动改变路由。用户自定义的 `qq.com` 已通过 `domain_suffix` 覆盖其子域名，不依赖 Core 的根域回退。
- 本轮 macOS Debug/Release 已基于构建号 `202608105` 完成编译、签名、覆盖安装和启动；iOS Core 与 Simulator Debug App 的本地构建因 Go 模块冷缓存下载中断尚未完成，Windows/Android 继续保留同源脚本和远程按需构建入口。
- 同日修复 macOS 正式版规则库状态误判：Core 已将 12 个规则库写入 `data/box.log`，但 App 重建 gRPC 日志监听后仍可能收不到实时事件，导致诊断错误地以 `Y-RULE-001 / RULE_SET_STATUS_UNKNOWN` 中止加速。现在启动前记录 Core 日志文件偏移，启动后把本次新增日志与实时流合并解析；只有本次启动明确出现规则库下载失败才阻断。正式版构建 `202608105` 复测 14 个阶段全部完成，耗时 6.9 秒，Google、X 和百度的 CLI 请求均返回成功。

### 4.20 UDP、默认路由与记录最终出口（2026-08-06）

- UDP 全量加速规则曾由云渡 Flutter 层临时加入，代码提交 `3da075ab` 可追溯；Hiddify 原生默认规则没有这条规则。现已删除该硬编码，UDP 与 TCP 一样按用户规则、通用规则和模式默认路由执行。
- 规则模式和全局模式不再追加无匹配条件的兜底规则，也不再扩展 Core 的 `managed-route-final`。Hiddify 生成的主 Core `route.final` 保持原样；macOS 由特权 Helper 按投影后的规则决定直连、拦截或送入本机 Core，加速流量进入 Core 后只使用 Hiddify 原生主出站，避免 Helper 与用户 Core 对同一请求重复分流。
- Hiddify/sing-box Clash API 原先在负载均衡出站时计算了真实叶子出口，却序列化了旧的 `t.Chain`；本轮 Core 补丁 `0003-connection-observability-and-actual-outbound.patch` 同时输出包含真实叶子出口的 `chains` 和明确的 `outbound`。客户端记录优先使用 `outbound`，旧数据只有明确的直连/加速标签时才兼容判断，无法确认时显示“无法确认”，不再把所有 `final` 记录默认为加速。
- Core 补丁由四端构建脚本统一应用并在构建退出时还原子模块源码；对应 Dart 规则生成、路由记录和 Core JSON 行为均有定向测试。

### 4.21 SRS 本地反解快照（2026-08-06）

- 当前正式配置引用的 12 个 SRS 已按原始 SHA-256 固定保存，并反解为 JSON，目录为 `/Users/kandejian/workspace/nimbus资料/yundo-rule-sets`；`manifest.json` 记录规则标签、来源 URL、哈希和解码工具版本。
- `scripts/archive_yundo_rule_sets.sh` 优先复用本机缓存，缓存不存在时按当前配置的 HTTPS URL 下载；规则更新不会覆盖旧快照，后续只需比较 manifest 和同名规则 JSON。
- 已核对当前 `geosite-cn` 快照明确包含 `qq.com`。因此 `res.wx.qq.com`、`support.weixin.qq.com` 等请求在规则库加载成功且命中逻辑生效时应归入国内直连；若记录仍显示默认路由，诊断日志应优先检查对应 SRS 加载状态和实际 `outbound`。

### 4.22 规则源权威、缓存隔离与根域回溯开关（2026-08-06）

- 公共规则库由平台发布的 `sourceUrl` 作为唯一权威来源。用户不需要下载、替换或维护本地 SRS；客户端只在加速准备阶段按平台返回的 URL 使用远程规则，并在成功校验后由 Core 缓存。
- 同名规则集采用“云渡来源优先”：同一个 tag 如果同时出现在 Hiddify 默认配置和云渡管理配置中，最终 Core 配置必须保留云渡 URL。缓存键同时包含 tag 和 URL 哈希，换源后不会把旧 Hiddify 缓存误当成云渡规则。
- 客户端启动前会读取最终交给 Core 的配置，逐一核对公共规则的 tag、类型和 URL。实际来源与平台返回值不一致时，以 `Y-RULE-002` 失败关闭，并把期望来源、实际来源写入诊断日志，不继续带着未知规则加速。
- 规则 manifest 的公共更新时间来自平台规则包发布记录（`publishedAt` / `publicRulesUpdatedAt`）；历史发布记录缺失发布时间时由服务端回退到该规则集创建时间，不使用每次检查或本机缓存时间伪装成规则库更新。
- 客户端不再在“加速成功”时写入 `publicRulesLoadedAt`，避免把连接成功时间冒充 SRS 实际加载时间。规则中心优先读取 Core 的规则集状态；Core 状态暂不可用时，只有同版本的内置清单才提供 `bundledAt`（兼容旧包的 `generatedAt`）离线兜底，历史字段仅为兼容旧缓存保留。
- 规则 manifest 额外携带公共规则来源指纹，覆盖规则内容、动作和 `sourceUrl`；同一发布版本更换远程来源时客户端会更新一次，来源未变时不会在每次加速时重复下载。
- 根域回溯由 Core 内部变量 `yundoRootDomainFallbackEnabled` 控制，默认值为 `true`。它不是 App 设置项，也不由用户配置；研发排查时可以在 Core 内部切换为 `false`，重新构建即可关闭，后续无需改变产品 UI 或规则数据。
- 回溯只在完整域名未命中时逐级检查可注册根域及其父域，例如 `support.weixin.qq.com` 依次检查 `weixin.qq.com`、`qq.com`；它不会凭域名后缀直接改变路由。全局模式由平台隧道层的明确 IPv4/IPv6 匹配规则覆盖全部公网流量，规则模式仍按用户规则、公共规则和最终出口执行。
- 规则加载诊断至少记录公共规则数量、我的规则数量、每个公共规则的来源 URL/版本摘要、Core 实际远程规则集和下载/缓存生命周期。这样 SRS 下载失败、来源错配、同名规则覆盖失效、根域回溯关闭等问题都能在一次诊断记录内定位。

### 4.23 构建期公共规则快照与启动兜底（2026-08-06）

- 每次客户端构建先调用平台 `GET /api/v1/rules/public-package`，按响应中的 `sourceUrl` 下载全部公共 `rule_set`，写入 `assets/rules/manifest.json` 和同目录 SRS 文件；下载全部成功后才原子替换快照，任一失败都保留上一份可用快照。远程公共规则包暂时不可用时，构建脚本会使用仓库中上一份已提交且带 SHA-256 的可信清单重新下载和校验全部 SRS，避免构建产物因为一次接口故障没有可用规则。
- 构建脚本以平台发布的 `publicRulesUpdatedAt` 阻止快照降级；远程候选缺少有效发布时间或早于仓库内置快照时，直接保留已验证快照，不下载或覆盖文件。只有同时间或更新的候选才进入完整下载与原子替换流程。
- macOS、Windows、iOS 和 Android 的构建脚本都接入同一缓存步骤。Windows/Android 仍由 GitHub Actions 按需构建，但不会绕过规则快照步骤；macOS/iOS 本地构建直接复用同一份工作区快照。
- 运行时把构建产物内的 SRS 作为 Core 的 `fallback_path`。Core 先加载内置快照，再异步检查远程更新；远程规则包、单个 SRS 或网络失败不会阻断已有快照的首次加速。账号“我的规则”仍按账号缓存，账号缓存不可用时才会在诊断中明确失败。
- 当前生产 `api.yundo.app` 尚未提供 `rules/public-package`（现状是 HTTP 404），所以正式版构建会先用上一份已验证清单刷新快照；平台端点部署后下一次构建才会自动刷新到生产发布版本。可信清单兜底只能保证构建可用，不能冒充生产最新发布版本；客户端对旧生产 API 不认识 `publicRulesSourceVersion` 的情况保留一次精确兼容重试，避免平台灰度部署期间无法连接。
- 构建日志必须记录公共规则版本、来源指纹、每个 SRS 的 URL 和 SHA-256；诊断日志必须区分“使用内置快照”“使用 Core 缓存”“后台更新失败”和“无任何可用规则”，不能把远程检查失败显示成规则已更新。
- macOS IPv4 兜底不再替换 Hiddify 生成的 DNS 服务器、最终 DNS 或域名解析器，只把本次会话的地址策略限制为 IPv4。这样降级不会把系统解析强制改成 Cloudflare，也不会引入一套脱离 Hiddify 的 DNS 路径。
- 旧版线上 API 对新增来源指纹字段返回 400 时，客户端只在该字段确实发送过的情况下无副作用地重试一次旧请求；第二次响应仍按真实错误处理，不会把其他参数校验错误吞掉。

### 4.24 macOS 路由所有权与失败关闭（2026-08-06）

- macOS 拆分架构明确只有特权 Helper 持有产品级路由、直连、拦截和规则库决策；用户 Core 只保留本机 mixed 入站、真实加速出站、Hiddify 原生最终出站及 DNS 规则依赖的规则库定义，不再重复执行云渡路由动作。Windows、iOS、Android 继续使用各自原生隧道和共享规则配置，不进入该 macOS 专属拆分路径。
- 加速出站能力探测改为三态：IPv4、IPv6 都可用时使用双栈；只有 IPv4 可用时使用 IPv4 兜底；IPv4 不可用时拒绝启动 Helper/TUN，确保探针失败不会先接管系统网络再留下无出口路由。探测必须复用 Helper 真正消费的 SOCKS5 地址、端口和认证信息，使用字面量 HTTP 目标验证 IPv4/IPv6；不得再通过另一套 HTTP CONNECT/TLS 路径推断真实隧道能力。
- IPv4 兜底沿用 Hiddify DNS，只调整地址策略，不再构造云渡专用 Cloudflare DNS。该修复不增加微信、SSH、腾讯会议或 QQ 音乐等域名特判。
- Helper 启动前必须清理并验证旧 worker；停止和退出必须确认 worker、活动配置、固定 TUN 地址、系统路由和 DNS 状态均已释放。任一残留都会让停止流程失败并写入诊断日志，不再提前把界面标记为“已停止”。
- macOS 产品路由规则库由 Helper 实际加载，诊断日志从 root 私有 Core 日志中只读取脱敏后的 `rule-set` 生命周期行；缓存、内置快照、远程更新和下载失败均以真实路由持有者为准，不把用户 Core 为 DNS 初始化保留的定义误判为第二套路由决策。
- 四端同类问题审计：本次 `Y-NETWORK-001` 误判只存在于 macOS 桌面拆分架构的 Helper 启动前探测；Windows 使用桌面原生服务但不进入 `Platform.isMacOS` 探测分支，iOS Packet Tunnel 与 Android VPN Service 也不经过该路径，因此三端不受此次根因影响。共享连接方案、规则生成和 Core 配置没有因本修复改变；iOS 仍需完成同一提交的 Simulator 构建，Windows/Android 保留各自自动构建和实体设备回归要求。
- 本机构建 `4.1.2+202608117` 已完成 macOS 开发版/正式版签名覆盖和 iOS Simulator Debug 构建安装。正式版连续三次启动均记录 `ipv4=true, ipv6=true` 并成功进入 Helper/TUN；两次正常退出后 Core、TUN worker 和云渡路由全部释放，`1.1.1.1`、`8.8.8.8` 恢复到物理网卡，系统 DNS 保持原值。每轮加速后 Google、百度、`servicewechat.com`、`cube.weixinbridge.com` HTTPS 均成功，`github.com:22` TCP 建连成功。
- `4.1.2+202608118` 收紧 macOS 双层架构的出口与观测边界：用户 Core 的 `selector / urltest / fallback / balancer / loadbalance` 组在接管系统网络前统一剔除 `direct / block / dns` 终端成员，Helper 判定为加速的流量不再于用户 Core 二次落入直连；任一加速组没有代理成员时失败关闭。记录页在 macOS 只读取 Helper 的完整 `/connections` 快照，以 `yundo-direct / yundo-socks` 作为最终访问方式，不再把用户 Core 的中间 `balance / select` 链重复显示为“无法确认”。Windows、iOS、Android 保持单 Core 采集。134 项全量 Flutter 测试通过；macOS 双版本已签名覆盖，正式版按原状态恢复加速，运行时 `select / balance / lowest` 均无直连成员，Google、`servicewechat.com`、npm HTTPS 建连成功；同构建号 iOS Simulator Debug 已构建、安装并启动。

### 4.25 精确路由三态与可控 Core 补丁（2026-08-07）

- `patches/hiddify-core/0004-exact-route-decision-history.patch` 是独立、可逆的 Core 观测补丁，不修改路由规则、出站选择算法或普通 Hiddify `/connections` 返回。它跟踪 TCP/UDP 最终选中的终端出站，并在拒绝规则执行时记录 `rejected`，最近关闭的短连接也保留在 500 条有界内存历史中。
- 云渡只通过 `/connections?yundo_exact_history=1` 读取精确历史；结果必须具有 `accelerated`、`direct`、`rejected` 之一。Dart 层不再从 `final`、selector、chain、规则名或目标 IP 猜测，缺少最终结果的旧格式行不会出现在精确记录页。
- 内部编译开关 `YUNDO_EXACT_ROUTE_HISTORY` 默认开启；使用 `--dart-define=YUNDO_EXACT_ROUTE_HISTORY=false` 可让客户端回到原生连接接口。需要完全撤销 Core 修改时可从 `apply_yundo_core_patches.sh` 和四端 Core 构建脚本中省略 `0004`；两种开关必须成对使用，不能让旧 Core 配合精确客户端。
- macOS 只监听特权 Helper 内 Core，Windows、iOS、Android 监听各自最终 Core。拒绝请求没有相反规则快捷操作，DNS 请求不进入访问明细，记录仍只在当前进程内存保存且不上传。

### 4.26 访问记录详情字段（2026-08-07）

- 访问记录详情直接展示 Core 已提供的 `metadata.destinationIP`、`destinationPort`、`sourceIP`、`sourcePort`、`type` 和 `network`，分别对应远程 IP、远程端口、来源 IP、来源端口、入口来源（如 `tun`）和网络类型。
- 这项改动只扩展 Dart 数据模型、详情页和多语言文案，不修改 Core、sing-box 路由、TUN 或连接追踪逻辑。
- 旧记录或平台未提供某个字段时隐藏对应行，不猜测来源和地址；详情页仍以 Core 的最终决策为准。

### 4.27 规则中心统一列表与弹窗稳定性（2026-08-07）

- 规则中心将我的规则与通用规则合并为一个列表。我的规则排在前面，因为它们优先于通用规则执行；每一行都显示规则来源、规则类型、访问方式和更新时间。
- 规则中心支持按规则名称或内容搜索，并按加速、直连、拦截以及我的规则、通用规则快速筛选。列表首屏显示前 25 条，继续滚动时自动追加下一页。
- 我的规则可以点击进入编辑和删除流程；通用规则可以点击查看只读详情，不允许直接修改。页面同时明确说明通用规则对所有账号生效，以及我的规则会跟随账号保存到云端。
- 修复规则编辑/添加弹窗显示灰色空白的问题。原因是 `AlertDialog.actions` 的 `OverflowBar` 直接承载 `Spacer`，在部分桌面和移动端约束下导致弹窗子树布局异常；现在按钮统一放在单行 `Row` 中，保留删除、取消和保存操作。

### 4.28 规则中心分页与用户规则更新时间（2026-08-07）

- 规则中心使用单列表，首屏渲染25条，滚动接近底部后自动追加下一页，不再提供折叠/展开入口。
- 我的规则仍进入编辑弹窗，删除按钮和二次确认逻辑保持不变；通用规则继续进入只读详情弹窗。
- 规则包携带用户规则的 `updatedAt`，客户端优先使用修改时间，其次使用创建时间和本地规则包缓存时间，避免已加载规则显示为空时间。

### 4.29 自定义规则保存不重载当前连接（2026-08-07）

- 编辑规则时先比较标准化后的规则内容、规则类型和访问方式；没有发生变化时直接关闭弹窗，不调用保存接口、不刷新规则缓存，也不触碰当前连接。
- 新增、修改或删除规则只写入账号云端并刷新规则页面展示，不调用 `reapplyIfConnected`，不重启或重载 Core/TUN；操作成功后提示“下次启动加速时生效”。
- 规则变更在下一次启动加速时随连接方案重新生成并加载，避免编辑规则时影响正在使用的网络连接；该行为位于共享 Flutter/Dart 应用层，不改变 sing-box/Hiddify 的运行时规则热更新逻辑。

### 4.30 节点地区列表缓存（2026-08-07）

- 节点地区列表在登录后进入首页时预加载；同一登录会话内优先复用认证状态中的内存缓存，不因每次打开首页下拉框重复请求 `locations` 接口。
- 下拉框只负责展示缓存并切换已加载的地区；缓存尚未就绪时才等待一次进行中的请求。控制器保留内部 `force` 刷新入口，供账号切换或明确刷新场景使用，不做定时轮询。

### 4.31 当前节点延时展示（2026-08-07）

- 首页显示当前实际活动节点的延时，复用 Hiddify 原生 `ActiveProxyDelayIndicator`、`activeProxyNotifierProvider`、核心 `urlTestDelay` 和现有 URLTest 调用。
- 当前活动出口首次出现或重新连接后，展示组件主动调用一次现有 URLTest，避免等待 Hiddify 默认的长周期检测才出现首个延时；同一活动出口不会因为页面重绘重复触发。
- 延时只代表当前已经选中的活动节点，不把后台探测机到节点的延时冒充为用户本机延时，也不为节点地区列表生成虚假的逐节点延时。
- 原生 URLTest 的自动检测周期继续由 Hiddify/sing-box 配置控制；用户点击延时区域时使用现有的手动测速和节流逻辑。
- 本次只增加首页展示层接入，不修改连接方案、核心进程、DNS 或规则匹配逻辑。macOS Helper 的系统 TUN 会排除配置中明确写成 IP 的代理服务器地址，避免核心探测自己的节点服务器时被同一个 TUN 捕获；节点填写域名时不在此处解析，避免引入新的 DNS 策略。

### 4.32 App 恢复后的节点延时订阅（2026-08-07）

- 桌面端 App 恢复时会重新初始化 Core gRPC 通道；原有 `activeProxyNotifierProvider` 为常驻数据流，但没有监听 Core 重启信号，导致它继续订阅已关闭的旧通道。此时 Core 已能测得当前节点延时，首页仍会一直显示“测试中”。
- 当前节点数据流现在与连接状态流一样监听 `coreRestartSignalProvider`；连接启动前重绑通道和 macOS IPv4 兜底重启后的重绑也会明确发送该信号。Core 通道重建后会自动取消旧订阅并连接新通道，不修改 Hiddify URLTest 算法、测速周期、连接方案、DNS、路由或 sing-box 配置。
- 新增回归测试，验证 Core 重启信号变化后当前节点数据流会重新订阅。该修复位于共享 Flutter/Riverpod 层：macOS 已复现并修复；Windows 使用相同桌面 Core 初始化路径，同因受影响并同源修复，等待实体机验证；iOS、Android 共享同一数据流重建行为，但移动端 Core 生命周期不同，需在 Simulator/真机继续验证。

### 4.33 快速切换节点的探测恢复与延时占位（2026-08-07）

- macOS 快速切换节点时，用户 Core 可能已经进入运行状态，但 SOCKS5 出口对字面量 IPv4 HTTP 目标的首次探测仍短暂命中 1.5 秒超时。此前会被直接判定为 `Y-NETWORK-001`；同一节点几秒后的完整重试又能成功，属于启动时序中的瞬时误判。
- 保留“IPv4 未确认时不接管系统网络”的失败关闭原则。首次 IPv4 探测失败后等待 400 毫秒，仅复核 IPv4；复核成功后继续原有 IPv4 兜底/双栈流程，复核仍失败才终止。正常启动不增加探测次数，也不修改 Hiddify/sing-box 的 Core、TUN、路由或 DNS 实现。
- 首页延时区域以真实连接状态为准：未加速时即使 Core 仍常驻或保留上一轮测速值，也固定显示 `-- ms`；加速测速中显示原有骨架动画，获得结果后显示实际延时。三个状态使用相同宽高，避免启停加速导致首页内容上下跳动。
- 平台审计：恢复探测只在 `Platform.isMacOS` 的 Helper 接管前执行，Windows、iOS、Android 不进入该分支；延时占位位于共享 Flutter UI，四端同步生效，其他平台仍需对应实体设备或 Simulator 验收。

### 4.34 App 恢复后的托管连接所有权同步（2026-08-08）

- App 恢复或 Core 通道重建时，底层连接状态可能先短暂上报 `Disconnected`，随后才上报真实的 `Connected`。云渡必须监听后续状态与活动配置变化，不能只在 Controller 首次创建时恢复连接所有权，否则界面会把仍在工作的云渡隧道显示为未加速，用户再次点击后还会被 `Y-CONNECTION-001` 立即拒绝。
- 恢复所有权必须同时满足三项证据：底层状态为 `Connected`、`startedByUser` 仍为真、当前活动配置 ID 为 `yundo-managed-profile`。任一证据缺失都保持未接管，避免误认其他 Hiddify 配置或其他连接工具。
- 已确认属于云渡的活动连接再次收到加速请求时按幂等成功处理，不重复请求连接方案、不重启 Core、不改 TUN、DNS、路由或 Helper。若底层处于其他连接或过渡状态，诊断日志明确显示存在其他活动连接，不再错误显示“未发现正在运行的连接”。
- 根因位于共享 Flutter Controller，macOS、Windows、iOS、Android 共用修复；平台原生隧道实现未修改。macOS 需回归 App 恢复及反复启停，iOS Simulator 需完成同源构建，Windows 和 Android 在同源提交形成后由 GitHub Actions 构建验证。

### 4.35 当前节点延时的连接后即时刷新（2026-08-08）

- 首页继续复用 Hiddify Core 的活动节点 URLTest 数据，不自建测速协议、不从后台节点列表读取延时，也不改变 sing-box 的自动测速周期。
- 连接状态进入已加速、节点切换或 Core 通道重建后，客户端调用 Core 已有的 `UrlTestActive`；若 Core 尚未完成测速初始化，在约 10 秒的有界窗口内最多重试三次，收到带新测速时间戳的结果后立即停止。
- 自动测速不触发震动；用户点击延时区域仍触发一次手动测速和轻触反馈。未加速时保持 `-- ms`，加速后测速中保持固定尺寸占位，结果到达后显示真实毫秒值。
- 活动节点数据流不再用上一轮 Core 的缓存值预填，避免切换节点后把旧节点延时短暂显示成当前节点延时。该修改只位于共享 Dart/Core 调用层，不修改 DNS、路由、TUN、Helper、连接方案或测速算法。
- macOS IPv4 兜底会在连接过程中重启用户 Core，旧的活动节点 gRPC 长连接会随之断开。客户端现在会对该数据流做有界重连，并在每次活动节点测速后读取一次当前活动出站快照；即使旧流在 Core 重启窗口内中断，新的延时结果也能直接写回首页，不再长期停留在“测试中”。
- 正式版实机已完成新加坡、日本、美国及恢复新加坡的连续切换验证；每次切换后均恢复加速并显示新的真实毫秒值，最后恢复为新加坡。日志中的旧流中断仍会作为可诊断事件保留，但不会再阻断延时展示。

### 4.36 Core 管理端口隔离与启动前状态对账（2026-08-08）

- macOS 正式版、macOS 开发版以及 iOS/Android 移动端不再共用 Hiddify 旧的 `17078` 管理端口，分别使用独立端口。iOS Simulator 与 macOS App 同时运行时，不得连接到对方的 Core 管理服务或改变对方的连接状态。
- 已确认旧实现可出现以下故障链：iOS Simulator 占用 `17078` 后，macOS 正式版的状态流连接到模拟器 Core；正式版用户 Core 仍监听 mixed 入站，但 App 错误显示未连接；再次加速时第二个 Core 绑定 `12334`，最终以 `Y-CORE-003 / address already in use` 失败。
- macOS 启动新连接前增加状态对账。若当前 Core 管理服务确认仍有用户 Core 在运行，客户端先调用现有 Core 停止接口和 Helper 停止接口，确认 Core、TUN 与系统路由都已释放后再准备新连接；清理无法确认时以 `Y-CORE-005 / STALE_CORE_CLEANUP_FAILED` 失败关闭，不并行启动第二份 Core。
- 端口隔离和状态对账只调整云渡应用层 Core 生命周期编排，不修改 sing-box 路由、DNS、规则、节点选择或隧道实现。Windows 采用独立桌面进程空间但继续接受同源端口隔离；iOS、Android 的前后台 Core 端口随 Flutter 传给现有原生服务。iOS Simulator 已完成同机并发验证，真实 iPhone、Android 和 Windows 仍需对应实体设备验证。
- 本机构建 `4.1.2+202608132` 已完成 macOS 开发版/正式版签名覆盖和 iOS Simulator Debug 构建安装。正式版按覆盖前状态恢复加速并监听 `127.0.0.1:17178`，Simulator 同时启动后监听 `127.0.0.1:17278`；旧共享端口 `17078` 无监听，正式版仍保持 `utun7`、活动延时和 Google、百度、`servicewechat.com` HTTPS 连通。Android 仍待 CI 构建，Windows 仍待 CI 与实体设备验证。

### 4.37 首页节点地区图标统一（2026-08-08）

- 首页“加速模式”和“节点地区”使用相同的 `28 x 28` 图标槽，保证桌面端与移动端的图标尺寸、中心位置和文字起始位置一致。
- 节点地区图标不再增加卡片、边框或阴影；“自动选择”的地球仪与国家或地区国旗使用相同边界，节点下拉菜单和移动端地区列表复用同一组件。
- 该调整只修改共享 Flutter 展示层，不改变地区缓存、节点选择、连接重启或网络行为。
- 本机构建 `4.1.2+202608133` 已完成 macOS 开发版/正式版签名覆盖以及 iOS Simulator Debug 构建安装。macOS 正式版实机界面已确认首页与地区下拉列表图标等大、对齐且无外层卡片，覆盖后按原状态恢复加速；iOS 共用同一 Flutter 组件并通过 `28 x 28` 尺寸测试，登录后首页视觉仍待 Simulator 登录态或真实 iPhone 验收。Windows 与 Android 共用该组件，仍待提交后由 CI 构建及对应平台验收。

### 4.38 移动端品牌资源与启动流程统一（2026-08-08）

- 应用内登录页、自动登录加载页、关于页和旧引导页统一通过 `YundoBrandLogo` 使用 `assets/images/app_icon.png`，不再分别引用独立 SVG。iOS 标准 `AppIcon.appiconset/Icon-1024.png` 与该文件保持字节一致，避免应用内 Logo 与系统图标继续分叉。
- iOS 删除会覆盖标准 AppIcon 的 Icon Composer `AppIcon.icon`。旧资源曾对 Logo 做裁切和位移，导致主屏只显示蓝色块；工程现在只编译标准 `AppIcon.appiconset`。
- iOS 原生 LaunchScreen 使用与 AppIcon 字节一致的云渡 Logo 和跟随浅色/深色模式的背景，不再显示旧 Hiddify `LaunchImage`。Flutter 引擎可用后立即切换到云渡自动登录加载页，显示同一 Logo、当前语言的软件名和正在登录状态；初始化完成后再进入登录页或主页。
- 移动端初始化较快时补足约 `0.9` 秒的加载页展示时间，确保云渡 Logo、软件名和登录动画稳定可见；初始化本身超过该时间时不额外等待。
- iOS 构建阶段根据开发版/正式版身份生成简体和繁体 `InfoPlist.strings`：开发版为“云渡开发版 / 雲渡開發版”，正式版为“云渡 / 雲渡”，其他系统语言继续使用 `Yundo Dev / Yundo`。Android 已有同等语言资源，本轮同时移除旧图形启动内容并复用 Flutter 加载页。
- iOS 主 App 与扩展只声明实际使用的 `packet-tunnel-provider`，删除 App Proxy、DNS Proxy 与 Content Filter entitlement；移动端方向锁定为标准竖屏，并由 iOS 品牌测试固定开发版身份、显示名、方向和最小权限边界。
- 跨平台审计：Logo 组件和加载页位于共享 Flutter 层，macOS、Windows、iOS、Android 同源生效；iOS 系统图标和系统显示名为本轮平台专项修复。macOS 需完成双版本构建安装回归，iOS Simulator 需验证主屏图标、中文显示名和启动过渡；Windows、Android 在同源提交后由 GitHub Actions 构建，实体设备继续按平台矩阵验收。

### 4.39 用户名与密码规则统一（2026-08-08）

- 新注册用户名为 `4-32` 位英文字母或数字，不再接受下划线。登录与临时密码完成入口继续兼容历史含下划线账号，避免旧用户被锁定，但客户端注册输入和服务端注册 DTO 都会拒绝新下划线用户名。
- 新密码至少 `8` 位，并且必须同时包含大写字母、小写字母、数字和 ASCII 特殊字符；空格不计为特殊字符，仍保留最多 `72` 个 UTF-8 字节和拒绝控制字符的 bcrypt 边界。
- 注册、临时密码完成和设置页改密复用同一客户端校验；服务端注册、临时密码完成和用户改密复用同一强度判断。登录只验证现有密码，不用新强度规则拒绝历史密码。
- 用户可见提示和具体校验错误同步到全部现有语言资源。该实现位于共享 Flutter/Dart 和用户 API 路径，macOS、Windows、iOS、Android 同因受影响；不修改 Core、连接方案、DNS、路由、TUN 或平台原生网络实现。

### 4.40 云渡法律入口统一（2026-08-08）

- 注册页、关于页和旧引导页原先共用上游 `Constants` 中的 Hiddify 使用条款与隐私政策地址，导致云渡用户点击后进入 Hiddify 法律页面。
- 两个统一入口现在固定指向公开 `yundoapp/nimbus-client` 仓库中已经存在的云渡使用条款与隐私说明版本；正式云渡官网法律页面发布后，只替换统一常量，不在各页面分别维护链接。
- 新增常量回归测试，要求法律链接必须使用 HTTPS、属于云渡公开仓库、位于 `docs/legal`，并明确禁止回退到 `hiddify.com`。
- 注册、关于和旧引导页均复用该常量，macOS、Windows、iOS、Android 四端同源修复；不修改 Hiddify/Sing-box Core、DNS、路由、TUN、Helper 或加速生命周期。

### 4.41 规则中心完整国际化与过期登录恢复（2026-08-08）

- 规则中心的 `nimbus.rules` 命名空间在阿拉伯语、西班牙语、波斯语、法语、印尼语、巴西葡萄牙语、俄语和土耳其语中原本缺失，slang 因此回退为英文。现在 11 种已支持语言均定义完整的 59 个规则词条，并由结构测试固定键集合和非空值。
- 规则页可以从账号级缓存展示“我的规则”，但编辑需要带规则 ID 的最新账号数据。access token 过期时，旧实现的规则包和规则列表读取直接返回 `401 AUTH_INVALID_TOKEN`；页面继续显示缓存，点击条目则只能提示重试。
- 规则包和账号规则列表现在共用一次性鉴权读取恢复：首次 `401` 后复用认证控制器刷新会话，仅当 access token 确实更新时重试原请求一次；其他错误、刷新未完成或第二次请求失败均不循环重试。refresh token 同样失效时沿用现有安全退出流程，不继续用过期会话执行编辑。
- 该修复位于共享 Flutter/Riverpod 与多语言资源层，macOS、Windows、iOS、Android 同因受影响并同源修复；不修改规则优先级、规则内容、Core、DNS、路由、TUN、Helper 或当前加速连接。macOS 需验证安装版语言切换和缓存规则编辑，iOS Simulator 需完成同源构建，Windows 与 Android 由同一提交的 GitHub Actions 构建后继续实体设备验收。

### 4.42 iPhone 真机签名安装基线（2026-08-08）

- 客户端 `b84f8c5a29c172e4e699397e328ce3c332b16fb8`、版本 `4.1.2+202608137` 已完成 macOS、iOS Simulator、Windows x64 和 Android Debug 四端同源构建归档；本机 Apple Development 团队为 `W684N2R45F`。
- iPhone 16 Pro Max（iOS 26.5.2）已开启开发者模式并通过 Xcode 配对；开发版主 App 与 Packet Tunnel 使用独立 Bundle ID，签名校验、profile 能力和真机安装启动均通过。应用显示名为“云渡开发版”，保持标准竖屏。
- 真机调试使用 Mac 局域网 API `http://192.168.1.223:4000/api/v1`，宿主机与局域网地址的 `/health` 均返回 `200`。真机不得使用 `127.0.0.1`，它只指向手机自身。
- 当前实体设备验收停在“手机端登录提交后点击加速并批准系统 VPN 配置”之前；VPN 授权、Packet Tunnel 连接/停止、网络恢复、锁屏/后台和 Wi-Fi/蜂窝切换仍是待完成证据，不能以真机 App 已安装或启动替代。

### 4.43 iPhone 启动崩溃修复与开发/正式 API 分流（2026-08-09）

- 真机启动崩溃证据为 `Runner-2026-08-09-000509.ips`：`EXC_BREAKPOINT` 位于 `AppDelegate.registerHandlers()`，原因是自定义通道在 `GeneratedPluginRegistrant` 注册前强制解包空 registrar。现在先注册生成插件，再注册自定义通道；每个 registrar 均使用可选绑定，避免启动阶段直接触发 SIGTRAP。
- 旧顺序修复在真实 iPhone 上继续暴露 `Runner-2026-08-09-004905.ips` / `004908.ips`：`EXC_BAD_ACCESS/SIGSEGV` 位于 `AppLinksIosPlugin.register`。最终启动顺序改为先完成 `FlutterAppDelegate.super.application`，再注册生成插件和云渡自定义通道；Simulator 与真机均需按该顺序验证。
- 根因为锁定的 `app_links 6.4.0` 在 Flutter Debug 真机启动时对空 registrar 直接调用 `messenger()`。依赖已升级并锁定到 `app_links 6.4.1`，使用其 iOS Debug registrar 保护；Pod 依赖与启动测试同步更新。
- `app_links 6.4.1` 保护后，真机继续在 `InAppReviewPlugin.register` 暴露同一空 registrar 边界；生成插件和云渡自定义通道现改为 `super.application` 返回后的下一轮主线程异步注册，覆盖全部 Swift 插件。
- 异步注册后，直接从主屏启动 Debug 包仍在 Flutter `VSyncClient` 初始化处崩溃；该路径需要 Flutter 调试 runner，不能作为脱离电脑的真机安装包。真机开发版改用 Profile 构建并保留 `app.yundo.client.dev`，正式版使用 Release 构建和 `app.yundo.client`。
- `ios/Shared/FilePath.swift` 在本地签名 profile 暂无 App Group 能力时回退到应用支持目录，保证 App 可以启动；正式 Packet Tunnel 仍必须配置并签署对应 App Group，回退目录不作为真实加速验收证据。
- 正式版使用 `app.yundo.client` / `app.yundo.client.PacketTunnel`，开发版使用 `app.yundo.client.dev` / `app.yundo.client.dev.PacketTunnel`，开发版 App Group 为 `group.app.yundo.client.dev`。旧的 `app.yundo.client.rebuild.dev` 标识已退役，不得出现在新构建、安装脚本或签名配置中。
- 开发版（Debug/Profile、`Yundo Dev`）只连接本地 API，默认 `http://127.0.0.1:4000/api/v1`，真机通过构建参数注入 Mac 局域网地址；正式版（Release、`Yundo`）只连接生产 API `https://api.yundo.app/api/v1`。`NIMBUS_API_BASE_URL` 仅由对应构建脚本显式注入，不允许开发版回退到生产 API。
- 跨平台审计：生产 API 默认值位于共享 Dart 鉴权路径，macOS、Windows、iOS、Android 同源生效；Bundle ID 与 Helper/App Group 是平台配置差异，macOS 开发版 Helper 已同步使用 `app.yundo.client.dev`，Android 原有 `app.yundo.client.dev` 不变。真实 iPhone 的 Packet Tunnel 授权、加速/停止和前后台网络矩阵仍需实体设备验收。

### 4.44 Windows/Android CI 构建触发边界（2026-08-09）

- 当前阶段优先 iOS 与 macOS 双版本真机/模拟器验收；Windows x64 与 Android Debug 不在普通 push 上自动构建，也不下载产物。
- `workflow_dispatch` 仍保留 `build_windows` / `build_android` 开关，待 iOS/macOS 验收稳定后按需触发；普通 Pull Request 继续只运行共享测试和边界门禁。
- 暂缓构建和下载只影响当前验收执行，不改变四端同源开发要求；任何共享 Flutter/Dart、API、认证、业务功能或平台适配变更，仍须同步检查 macOS、Windows、iOS、Android，并在同一提交中保持可构建、可测试的实现。
