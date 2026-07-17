# macOS 开发版构建基线

最后更新：`2026-07-17`

## 工具链

- Flutter `3.38.5`
- Dart `3.10.4`
- Xcode 位于 `/Applications/Xcode.app`
- Swift 使用 Xcode 随附版本

如果系统 `xcode-select -p` 仍指向 Command Line Tools，命令前增加：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

无需修改系统全局的 Xcode 选择。

## 生成与检查

在仓库根目录依次执行：

```bash
flutter pub get
dart run slang
dart run build_runner build --delete-conflicting-outputs
swift scripts/generate_yundo_logo_assets.swift
flutter analyze --no-fatal-warnings --no-fatal-infos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug
scripts/verify_macos_privileged_helper.sh
```

Developer ID 和公证包就绪后，使用 `scripts/check_macos_distribution_readiness.sh` 做只读验收；该脚本不是签名或发布命令，详见 [macOS TUN 最小权限辅助进程](./macos-privileged-helper.md)。

需要联调本地平台 API 时，在构建命令增加：

```bash
--dart-define=NIMBUS_API_BASE_URL=http://127.0.0.1:4000/api/v1
```

Debug 产物应位于：

```text
build/macos/Build/Products/Debug/Yundo Dev.app
```

产物身份必须为：

- macOS App 包名：`Yundo Dev.app`
- 简体中文用户可见名称：`Yundo · 云渡开发版`
- 繁体中文用户可见名称：`Yundo · 雲渡開發版`
- 其他语言用户可见名称：`Yundo Dev`
- Bundle ID：`app.yundo.client.dev`
- 版本：`1.0.0+10000` 或后续递增版本
- 包内包含独立签名的最小权限 helper 和对应 LaunchDaemon plist

正式版对应的用户可见名称为简体中文 `Yundo · 云渡`、繁体中文 `Yundo · 雲渡`、其他语言 `Yundo`，macOS App 包名为 `Yundo.app`，Bundle ID 为 `app.yundo.client`。登录页、首页、关于页、窗口标题和菜单栏必须统一使用当前环境的用户可见名称。

macOS TUN helper 的进程边界、签名要求和授权流程见 [macOS TUN 最小权限辅助进程](./macos-privileged-helper.md)。只读 helper 校验通过不等于 ad hoc Debug 包可以完成真实系统注册。

Android Debug 使用 `app.yundo.client.dev`，并通过独立的 Debug 应用名和 Application ID 与正式版隔离。本阶段只校验身份配置，不开始 Android 功能开发。

## 日常开发构建、安装与启动

只要修改会影响运行中 App 的源码、多语言、资源、依赖或 macOS 原生配置，在完成必要生成与测试后执行：

```bash
scripts/build_install_run_macos_dev.sh
```

如果 `flutter` 不在 `PATH` 中，通过 `FLUTTER_BIN` 传入本机 Flutter 可执行文件：

```bash
FLUTTER_BIN=/path/to/flutter scripts/build_install_run_macos_dev.sh
```

脚本会使用本地 API 基线 `http://127.0.0.1:4000/api/v1`，也可通过 `NIMBUS_API_BASE_URL` 显式覆盖。它会依次完成：

1. 构建 macOS Debug 版 `Yundo Dev`。
2. 在 helper 与登录启动组件写入包内后，优先使用钥匙串中的 Apple Development 身份从内向外重签，同时保留主 App 和登录项原有 entitlement，再执行严格的完整签名和特权辅助进程校验。可通过 `MACOS_CODESIGN_IDENTITY` 指定签名身份；本机没有开发签名身份时才回退到 ad hoc 签名，并可能在 helper 更新后要求重新授权。
3. 退出正在运行的已安装开发版，完整替换 `/Applications/Yundo Dev.app`，避免已删除资源因目录合并而残留。
4. 比对构建产物与已安装可执行文件的 SHA-256，并再次校验已安装 App 的完整签名和 helper。
5. 启动 `/Applications/Yundo Dev.app` 并确认进程存活。

如果 macOS 的 Apple Event 退出请求未及时返回，脚本会在 5 秒后结束该请求，再使用进程级退出兜底，避免自动验收流程无限等待。

Debug 版登录会话保存在开发版独立 Bundle ID 的 `UserDefaults` 中，避免 ad hoc 签名随每次重建变化时反复触发钥匙串授权弹窗。该存储仅用于本机开发便利，正式构建仍使用 macOS Keychain；首次切换到本方案后需要重新登录一次。

正式构建写入 Keychain 时优先更新现有会话项，仅在项目不存在时新增，避免通过“先删除再新增”制造短暂丢失或额外授权失败。服务端已完成注册但本地安全存储异常时，客户端必须保持当前内存登录态并提示下次启动需要重新登录，不得把已经创建的账号误报为注册失败；诊断日志只记录平台错误码，不记录令牌或会话内容。

任一步失败时脚本立即退出，不应宣布客户端任务已完成。这是本机 Debug 验收，不会生成内测 ZIP、发布安装包或触发 GitHub Actions release。

## 路由决策诊断

`Yundo Dev` 在本机 `127.0.0.1:19090` 开启带密钥的 sing-box Clash API，用于读取当前活动连接的目标、命中规则和出站链；正式版不启用该接口。诊断数据只存在于本机运行内存，不上传平台，也不写入业务数据库。

验证某个站点时，先执行：

```bash
dart run scripts/watch_nimbus_routes.dart cloud.jichuangip.com
```

再通过浏览器或 `curl` 访问该站点。输出示例：

```text
直连  cloud.jichuangip.com:443  规则：rule_set=geoip-cn => route(nimbus-direct)  出站：nimbus-direct
加速  www.google.com:443  规则：rule_set=geosite-google => route(nimbus-proxy)  出站：nimbus-proxy
```

路由验收以 `规则` 和 `出站` 为准，不再用访问耗时推断。省略域名参数时显示全部新连接；按 `Ctrl+C` 结束监听。

## 内测包

只有源码工作区 clean 时，才生成可追踪内测包：

```bash
scripts/package_macos_internal_test.sh
```

脚本会检查显示名、Bundle ID、版本、架构、签名和禁用品牌字符串，生成 ZIP、SHA-256 与 manifest。验收时 manifest 必须包含：

```text
source_state=clean
forbidden_branding_scan=passed
compliance_assets=passed
privileged_helper_assets=passed
```

脚本会拒绝从 dirty 工作区打包，并校验 App 和解包后的 ZIP 都包含 `LICENSE.md`、隐私说明、使用条款、特权 helper 和 LaunchDaemon plist。manifest 同时记录完整源码 commit，便于对应公开 fork 中的精确版本。

正式分发前使用只读检查：

```bash
scripts/check_macos_distribution_readiness.sh --strict \
  'build/macos/Build/Products/Release/Yundo.app'
```

该检查要求 Developer ID 签名、公证凭据、hardened runtime、Gatekeeper、stapling、helper 与 LaunchDaemon 绑定，以及包内合规文档全部通过。

`build/` 下的 App、ZIP、校验文件和 manifest 均为本地产物，不提交到仓库。
