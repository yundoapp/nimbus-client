# iOS 开发与真机验证基线

最后更新：`2026-07-17`

## 当前目标与边界

M5 的目标是在项目负责人的真实 iPhone 上完整体验云渡。现阶段只进行本地开发构建、模拟器检查和受控真机调试，不上传 TestFlight、App Store 或 GitHub Release，也不修改生产节点、生产数据库和真实用户状态。

iOS 继续复用现有 Flutter 页面、Nimbus API 与 Hiddify Core/Network Extension 底座，不单独维护另一套客户端。

## App 身份隔离

| 环境 | App Bundle ID | Packet Tunnel Bundle ID | App Group | Keychain service |
| --- | --- | --- | --- | --- |
| 开发版 | `app.yundo.client.dev` | `app.yundo.client.dev.PacketTunnel` | `group.app.yundo.client.dev` | `app.yundo.client.dev.secure-session` |
| 正式版 | `app.yundo.client` | `app.yundo.client.PacketTunnel` | `group.app.yundo.client` | `app.yundo.client.secure-session` |

开发版和正式版因此不会共享 App 容器、偏好设置、连接扩展数据或登录会话。iOS 登录会话存放在 Keychain，并使用 `AfterFirstUnlockThisDeviceOnly` 可访问级别；升级前普通偏好中存在的旧会话会在首次读取时迁移并删除。

`SERVICE_IDENTIFIER=com.hiddify.app` 目前只作为 Flutter 与原生层之间的内部 MethodChannel 前缀保留，不是用户可见品牌，也不参与 App 身份或数据隔离。

## 本机工具链

本机同时存在 Command Line Tools 和完整 Xcode 时，不修改全局 `xcode-select`，而是在 iOS 命令前显式指定：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Xcode 工程的 Flutter 构建阶段还会把 `scripts/xcode-bin` 放到当前进程的
`PATH` 前端。该目录中的 `xcrun` 包装器只为本项目补充上述
`DEVELOPER_DIR`，用于兼容 Flutter 原生资源钩子，不会修改系统级设置。

当前依赖把 `objective_c` 固定在 `9.1.0`。`9.2.0` 起改用 Native Assets，
但本仓库使用的 Flutter `3.38.5` 会把 iOS framework 嵌入 `Frameworks/`
后仍按 App 根目录解析，导致启动时无法加载 `DOBJC_initializeApi`。该固定版本
保留传统 Flutter plugin 嵌入路径，已通过模拟器启动和 arm64 无签名构建验证；
升级 Flutter 后应重新验证并优先解除固定版本。

构建阶段会按 Debug/非 Debug 自动写入简体中文和繁体中文的系统显示名：
Debug 为“云渡开发版/雲渡開發版”，其他语言回退为 `Yundo Dev`；正式配置为
“云渡/雲渡”，其他语言回退为 `Yundo`。

最低前置：

- 完整 Xcode 和对应 iOS SDK；
- Flutter `3.38.5` 兼容工具链；
- CocoaPods；
- `ios/Frameworks/HiddifyCore.xcframework`；
- 用于本地真机调试的 Apple Development 证书和具备 Network Extension 能力的 Apple Developer Team；
- 已解锁、信任本机并启用开发者模式的 iPhone。

## 本地签名配置

仓库不提交个人 Apple Team、证书、Provisioning Profile 或私钥。复制示例文件并只在本机填写 Team ID：

```bash
cp ios/Local.xcconfig.example ios/Local.xcconfig
```

`ios/Local.xcconfig` 已被 Git 忽略。内容格式：

```xcconfig
YUNDO_IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

App 与 Packet Tunnel target 都使用自动签名。Apple Developer 后台必须为开发版 App、开发版 Packet Tunnel 和 App Group 开通与工程 entitlement 一致的能力。当前只保留实际使用的 `packet-tunnel-provider`、App Group 与 VPN 控制能力，不申请 App Proxy、DNS Proxy、Content Filter 或推送权限。

2026-07-17 已验证：免费 Personal Team 不能为 App 和 Packet Tunnel 创建包含 Network Extension/Personal VPN 能力的 iOS App Development provisioning profile。因此，iOS 真机完整体验需要 Apple Developer Program 付费团队，且该团队必须能为开发版 App ID、Packet Tunnel App ID 和 App Group 配置上述能力。macOS 的 Developer ID 只影响 macOS 对外分发签名，不解决 iOS 真机描述文件问题。

## 生成依赖与模拟器构建

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang
make CHANNEL=prod ios-libs
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  flutter build ios --simulator --debug
```

模拟器可以验证 Flutter 页面、原生编译、Bundle ID 和 Keychain 通道，但不能代替 Packet Tunnel 系统授权和真实加速验证。

## 真机调试流程

1. 用数据线连接 iPhone，解锁并在手机上选择“信任此电脑”。
2. 如系统提示，在 iPhone 打开“设置 → 隐私与安全性 → 开发者模式”，按提示重启并确认。
3. 确认 `flutter devices` 能识别该 iPhone。
4. 使用开发版身份构建并运行：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     flutter run --debug -d <DEVICE_ID>
   ```

5. 首次点击“加速”时允许系统添加连接配置；随后验证加速、停止加速、切换 Wi-Fi/蜂窝网络、前后台切换和杀掉后重开 App。
6. 使用测试账号验证注册或登录、设备绑定、激活、短期连接方案、登录态恢复与服务端强制断开。日志和截图必须脱敏。

## 2026-07-17 自动验证记录

- Flutter 全量测试：95 项全部通过。
- 本次修改文件静态检查：0 个问题；全仓检查仍有 217 条既有上游告警，未由 M5 新增。
- iPhone 17 Pro 模拟器：Debug 构建、安装和启动通过；简体中文开发版名称、浅色/深色首页、登录态恢复和窄屏滚动已检查。
- iOS arm64：`flutter build ios --debug --no-codesign` 通过，App 与 Packet Tunnel 均为 arm64，开发版 Bundle ID 分别为 `app.yundo.client.dev` 与 `app.yundo.client.dev.PacketTunnel`。
- iOS 真机签名前置检查：`flutter build ios --debug` 已触发 Xcode 自动签名，但当前 Personal Team 无法创建包含 Network Extension/Personal VPN 能力的描述文件，签名安装不能继续。
- macOS 共享代码回归：`Yundo Dev` 已完成构建、特权辅助进程校验、覆盖安装和启动。
- 平台隔离端到端验收：18 项 HTTP 闭环通过，问题类型和可选联系方式能够写入、返回并在后台处理。

上述结果不包含真实 iPhone 的系统授权和加速能力，不能替代 #70 真机验收。

## 当前外部阻塞

当前还有两个外部前置没有满足：

1. Mac 侧未识别到真实 iPhone。`flutter devices`、`xcrun xctrace list devices`、`xcrun devicectl list devices` 和 USB 设备列表均未发现实体 iPhone。
2. 当前 Apple Team 为免费 Personal Team，不能创建包含 Network Extension/Personal VPN 能力的 iOS App Development provisioning profile。

在这两个前置满足前，无法完成以下验收：

- App 与 Packet Tunnel 的真机签名、安装和启动；
- 首次系统连接授权与拒绝后的恢复；
- Wi-Fi/蜂窝网络切换及前后台连接状态；
- 真实节点加速、停止加速和杀进程后的登录态恢复；
- 付费 Apple Developer Team 对 Network Extension/App Group 能力的实际授权结果。

这些项目必须以真机结果为准，模拟器构建成功不能替代。
