# 云渡 Hiddify 重建迁移基线

最后更新：`2026-08-03`

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

1. 后台返回短期连接方案、完整 Hiddify 标准 Profile 和同版本的账号规则包。
2. 客户端只校验并安装标准 Profile，不消费旧版 `singBoxConfigPatch`；连接前按版本校验并缓存规则包，只把规则条目交给 Hiddify Config Option 的受控入口，不拼装整份运行配置。
3. Hiddify 原有 `ProfileParser`、`ProfileRepository`、`ConnectionRepository`、配置构建器和 Core 生命周期继续负责解析、生成 DNS/inbound/最终路由、启动和停止。
4. 受控入口只允许追加 `route.rules` 和 `route.rule_set`。如果某项云渡能力超出该边界，优先调整产品规则表达或暂缓，不扩大到 DNS、TUN、系统代理或 Helper。
5. 不允许由云渡代码接管系统 DNS，不允许在加速前后直接修改物理网卡 DNS，不允许自行创建或清理系统路由。

Hiddify Core 校验 profile 时会使用临时输入文件生成完整运行配置；在部分桌面启动时序下，Core 释放临时输入后可能异步清理校验输出路径。因此云渡适配器使用独立校验路径读取 Hiddify 生成的完整配置，先完成 Hiddify profile 入库并等待 active profile 稳定，再把完整配置写入云渡自己的最终 profile 文件，最后调用原生 `ConnectionRepository.connect`。Hiddify 标准 Profile 解析器会规范化节点内容并丢弃顶层产品路由，所以账号规则不能只写在 Profile 中；客户端必须在连接前把同版本规则包转换成受控 Config Option，由 Hiddify 在生成完整运行配置时追加。不得把后台返回的原始 profile 直接覆盖为最终运行文件，也不得让云渡接管 Core 的 DNS、TUN 或系统代理配置。

服务端可以继续返回旧 `singBoxConfigPatch` 供旧客户端兼容，但新客户端收到缺少 `profileContent` 的响应时必须失败关闭，不得回退消费旧字段。

当前已完成：认证壳、首页/连接按钮、设置页、路由偏好、问题反馈、应用生命周期接入和标准 Profile 适配器；当前尚未完成四端构建、真实节点连接和安装版网络矩阵。

本机 macOS Debug 版本 `202608033` 已使用本地 API 标准 profile 完成自动连接并进入 `CONNECTED`；该结果只证明 Hiddify profile 生命周期和本地连接闭环正常，不替代真实节点、微信开发者工具和四端网络矩阵验收。

macOS Debug 已设置独立 Bundle ID `app.yundo.client.rebuild.dev` 和安装名 `Yundo Dev.app`，Release 使用 `app.yundo.client`；重建开发版与旧云渡开发版不共享登录态、偏好或 Core 数据目录。当前桌面发布层使用 `YundoCore` 文件名和云渡窗口/进程名，不把旧 Helper 带入新分支；源代码目录和上游模块名暂时保留，避免为了改内部名而触碰 Core ABI。构建入口 `scripts/build_install_run_macos_dev.sh` 会拒绝把 Hiddify 名称带入最终 macOS App 包。

品牌验收以最终安装包为准：进程管理器、应用包目录、系统设置里的应用名、通知服务名、快捷方式和应用图标都必须显示云渡品牌；内部源码路径、协议模块名和许可证归属不属于用户产品界面，但不得被复制成用户可见的运行时文件名。

桌面 Core 进程隔离和退出清理是应用生命周期边界，不改变 DNS、TUN、路由或代理实现：正式版继续使用既有 Core 通道，macOS 开发版使用独立端口 `17179`，避免接管正式版或旧 Helper 的 Core；桌面退出无论来自窗口、托盘还是 macOS 系统菜单，都必须先调用 Hiddify 原生停止接口并清理云渡连接状态，随后才允许进程退出。macOS 原生终止通过 `yundo.application.lifecycle` 与 Flutter 握手，不能只依赖 `onWindowClose`。

构建链固定使用 `dependencies.properties` 中声明的 Hiddify Core `v4.1.0` 和源码提交 `c9d6f0f00b2eda34e4fb71863e4e0a62b3e931a0`。四端从该源码应用 `patches/hiddify-core/0001-managed-route-options.patch` 后构建，不再混用更新的子模块源码和旧版预编译产物。`CHANNEL=dev` 只决定应用配置和 Dart 入口，不得切换到远程 `draft` Core；升级 Core 必须同步评审补丁、客户端适配、四端构建和网络回归。

移动端 Flutter 与原生之间的内部通道统一使用 `yundo.app/*`，不再用旧的 Hiddify 前缀，也不从 Bundle ID 动态拼接。开发版和正式版可以使用不同 Bundle ID，但必须共享同一组内部通道。移动端核心首次 gRPC 握手必须设置有限超时；Simulator 只跳过真机 VPN 配置加载，不改变真机 Network Extension 路径，底层启动失败时应用仍应进入可诊断的用户界面而不是永久停留在启动页。

开发重建分支的 GitHub Actions 只构建 Windows x64 内部验收包和 Android Debug APK，并先从锁定源码生成包含受控规则入口的 Core；macOS 与 iOS Simulator 固定在本机构建。Windows 暂不要求 Authenticode 或 MSIX，Android 使用 Debug 签名。正式发布仍必须另行提供各平台签名材料；不能把日常基线产物当作对外发布包。

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
- 本轮仍未完成人工逐页截图：Computer Use 对系统中遗留的旧同名 Bundle 映射错误，无法读取当前 `app.yundo.client.rebuild.dev` 窗口；这属于验收工具阻塞，不作为页面已人工验收的证据。

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
- UI 改动保留现有页面层级、菜单结构和多语言要求。
- 连接相关改动必须有 Profile/规则 fixture 和失败路径测试。
- 影响客户端运行的改动必须基于同一 commit 完成四端构建基线。
- 真实安装版必须验证网络可用性，不能只以编译成功作为通过。

### 4.3 加速按钮、标题和桌面主导航调整（2026-08-03）

- 加速按钮不再调用通用 Hiddify 实验功能确认弹窗。该弹窗在根导航上下文尚未就绪时会静默返回拒绝结果，导致用户点击后既没有连接请求也没有错误提示；云渡按钮现在直接调用云渡连接控制器，并以可等待的异步回调启动、停止或重连。
- `MaterialApp` 和桌面窗口标题统一使用现有多语言 `common.devAppTitle`/`common.appTitle`：中文显示“云渡开发版”/“云渡”，其他语言显示“Yundo Dev”/“Yundo”。切换语言时同步更新 macOS 标题栏。
- 桌面主导航固定为“主页、记录、设置”。“记录”直接进入云渡加速记录页；配置文件、通用日志和关于页面不占用主导航位置，避免再次出现 shell 分支与导航目的地数量不一致。
- macOS 本机构建脚本在覆盖 `/Applications/Yundo Dev.app` 和 `/Applications/Yundo.app` 后始终启动并验证开发版；正式版只覆盖安装、不启动，避免两个版本同时接管网络。
- 本轮按项目负责人要求优先执行本地 macOS Debug/Release 和 iOS Simulator 构建；Apple 证书准备完成前不以 GitHub 远端 macOS 构建作为验收门槛。

### 4.4 macOS 品牌与桌面交互回归（2026-08-03）

- macOS 系统菜单、Dock 悬停名称和菜单栏提示必须跟随当前语言：简体中文为“云渡开发版”，繁体中文为“雲渡開發版”，其他语言为“Yundo Dev”；不能只修改 Flutter 窗口标题。
- 首页点击加速或停止加速后立即展示过渡状态，并保证用户能够看到“正在加速中”或“正在停止加速”，再进入最终状态。
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
- 修复：客户端在每次手动或自动加速前校验规则 manifest，下载并验证同版本账号规则包，按“用户自定义网站 -> 公共规则 -> 本地网络兜底”生成受控规则数据；Hiddify Core 只新增 `managed-route-rules` 和 `managed-route-rule-sets` 两个 Config Option 字段，把它们追加到原生路由表。直连规则使用 Hiddify 自带的 `direct §hide§` 出站，不新增直连出站，也不覆盖 DNS、inbound、TUN、系统代理、Helper 或最终出站。
- 规则合并：用户自定义规则放在 Hiddify 地区默认规则之前，保证 `rawya.ai -> 直连访问` 这类明确选择不会被更宽泛规则先命中；规则集在 Hiddify 完成内置地区规则集后按 tag 去重，`geoip-cn`、`geosite-cn` 等重名项直接复用 Hiddify 内置版本，避免 sing-box 因重复 tag 拒绝整份配置。
- macOS 打包：Xcode 的 Core Copy Files 阶段必须在所有构建动作执行；双版本安装脚本每次都删除 App 内旧 Core、复制本轮源码构建的 `YundoCore.dylib`，并在签名前检查 `managed-route-rules` 标记。禁止以“目标文件已存在”为理由复用上轮 Core，否则 Dart 规则已经生成也不会进入实际运行核心。
- 四端构建身份：同一轮基线使用 `pubspec.yaml` 中的统一构建号；Android Debug 固定使用独立包名 `app.yundo.client.dev`，系统语言为简体中文、繁体中文和其他语言时分别显示“云渡开发版”“雲渡開發版”和“Yundo Dev”。Windows/Android CI 交付文件统一使用 Yundo 名称，不把内部 Flutter package 名带入产物文件名。
- Windows Core 构建从锁定的 `hiddify-core/go.mod` 解析 Cronet 完整伪版本并传给上游 Makefile；不直接使用上游版本文件中的裸 commit hash，避免 Go 模块代理无法解析时漏生成 `libcronet.dll`。该处理只修复依赖寻址，不升级或替换锁定的 Core 依赖。
- 失败策略：首次没有有效缓存且规则包下载失败时不启动加速；已有已验证缓存时可继续使用旧规则，只有新包下载并校验成功后才原子替代。连接方案与规则包版本在准备期间不一致时失败关闭，避免半新半旧配置。
- 跨平台矩阵：规则准备和 Config Option 序列化位于共享 Dart 层，macOS、Windows、iOS、Android 同因受影响并同因修复；Core 补丁由四端同一源码提交和同一补丁生成。macOS 需要安装版真实直连/加速双向请求证据；Windows、iPhone、Android 仍需实体设备补做真实分流，但不能使用旧预编译 Core 作为本轮构建证据。
