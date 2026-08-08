# Apple 签名与远程构建

云渡客户端的 Apple 工程使用以下固定标识。开发版与正式版必须分开，避免测试安装包覆盖正式版数据。

| 用途 | App Bundle ID | Packet Tunnel Bundle ID |
| --- | --- | --- |
| 正式版 | `app.yundo.client` | `app.yundo.client.PacketTunnel` |
| 开发版 | `app.yundo.client.rebuild.dev` | `app.yundo.client.rebuild.dev.PacketTunnel` |

当前 Apple Developer Team ID 为 `W684N2R45F`。iOS 工程的旧 Hiddify Team 和旧导出 profile 已移除，导出时由 `xcodebuild` 使用 App Store Connect API Key 自动处理 profile。

本机签名材料统一归档在 `/Users/kandejian/workspace/nimbus资料/Apple Developer`。其中包含证书、CSR、私钥、P12、P12 密码文件和一次性下载的 App Store Connect `.p8` 私钥；该目录不应提交到 Git 或上传到共享存储。

## Apple Developer Portal

至少准备正式版的两个 App ID：

- `app.yundo.client`
- `app.yundo.client.PacketTunnel`

正式版 App ID 需要启用应用当前使用的 App Groups、Personal VPN 与 Network Extension 能力；Network Extension 只启用实际使用的 `packet-tunnel-provider`，不要额外开启 App Proxy、DNS Proxy 或 Content Filter。App Groups 应包含 `group.app.yundo.client`。如果需要远程签名开发版，再额外创建开发版的两个 Bundle ID，并启用对应的 `group.app.yundo.client.rebuild.dev`。

远程 iOS IPA 使用 App Store 分发签名，因此需要导出包含私钥的 `Apple Distribution` `.p12`。macOS 产物直接在 App 外分发，使用单独的 `Developer ID Application` `.p12`。对外版本必须启用 hardened runtime，并完成 Apple 公证和 stapling；本地开发版仍可以使用 Apple Development 身份，不得把它发给朋友。

## GitHub Secrets

在 `yundoapp/nimbus-client` 的 Actions secrets 中配置：

| Secret | 内容 |
| --- | --- |
| `APPLE_MACOS_CERTIFICATE_P12` | Base64 编码的 `Developer ID Application` `.p12`，包含证书和私钥 |
| `APPLE_MACOS_CERTIFICATE_P12_PASSWORD` | macOS `.p12` 导出密码 |
| `APPLE_IOS_CERTIFICATE_P12` | Base64 编码的 `Apple Distribution` `.p12`，包含证书和私钥 |
| `APPLE_IOS_CERTIFICATE_P12_PASSWORD` | iOS `.p12` 导出密码 |
| `APPSTORE_ISSUER_ID` | App Store Connect API Key 的 Issuer ID |
| `APPSTORE_API_KEY_ID` | App Store Connect API Key 的 Key ID |
| `APPSTORE_API_PRIVATE_KEY` | `.p8` 文件的完整文本，不要 Base64 编码 |

远程工作流使用“管理员”职能的 API Key，以便 Xcode 在没有预置 profile 时管理 App ID 与分发 profile。iOS 设备归档阶段保持无签名，最后由 `xcodebuild -exportArchive` 选择 `Apple Distribution` 并完成主 App 与 Packet Tunnel 的分发签名；因此不会把分发身份强行传给 CocoaPods target。证书、`.p12` 密码和 `.p8` 私钥只放 GitHub Secrets，不提交到仓库。

## 使用方式

`.github/workflows/apple-build.yml` 通过 `workflow_dispatch` 触发，同时构建：

- macOS 开发版 ZIP
- macOS 正式版 ZIP
- iOS 正式版 IPA

工作流只上传 Actions artifact，不自动覆盖本机、不自动发布 GitHub Release、不自动上传 TestFlight。构建完成后从同一个 workflow run 下载产物即可。当前远程 macOS 产物先以签名 ZIP 作为基线，DMG 公证链路通过下方脚本执行；正式发布前应把 DMG 作为唯一朋友分发包。

本地开发仍使用本机工具链，避免为每次调试等待远端：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/build_install_run_macos_dev.sh
```

## 本地正式版与朋友分发

先把归档目录中的 `macos-developer-id.p12` 导入当前登录用户的钥匙串，并设置身份变量。正式版构建会使用 `Developer ID Application`、hardened runtime 和不含 `get-task-allow` 的分发 entitlement：

```bash
export YUNDO_DEVELOPER_ID_APPLICATION='Developer ID Application: Shanghai Yunshang Wanwei Technology Co., Ltd. (W684N2R45F)'
scripts/build_macos_distribution.sh
```

脚本会构建并覆盖安装 `/Applications/Yundo.app`，然后在 `client-builds/<version>-build<build>-<commit>/` 生成 DMG 和 `SHA256SUMS`。如已配置本机公证凭据，可执行：

```bash
export YUNDO_NOTARY_PROFILE='Yundo GitHub Actions'
YUNDO_NOTARIZE=1 scripts/build_macos_distribution.sh
```

公证完成后，朋友的安装方式是：双击 DMG，把 `Yundo.app` 拖到 `/Applications`，推出 DMG，再从 `/Applications/Yundo.app` 启动。不要让朋友直接从 DMG 内运行，也不要把带有“无法验证开发者”提示的未公证包作为正式版本发送。升级时用新 DMG 覆盖 `/Applications/Yundo.app` 即可；首次启动或加速时仍可能需要用户批准云渡的后台辅助项目。

发行前只读检查：

```bash
scripts/check_macos_distribution_readiness.sh --strict \
  'build/macos/Build/Products/Release/Yundo.app'
```

## 正式版验收

正式版至少需要在一台干净 macOS 用户环境和本机升级环境各验证一次：DMG 拖拽安装、首次启动、登录、启动/停止加速、浏览器访问、终端 `curl`、规则模式、全局模式、直连/拦截规则、退出后网络恢复、再次打开、诊断日志、语言切换、深色模式、后台辅助项目授权和升级覆盖。开发版与正式版都必须能在设置中打开诊断日志，且诊断内容遵循中文显示中文、其他语言显示英文的策略。

iOS Simulator 可以使用 Xcode 登录的本机账号直接构建；真机/IPA 则需要本机已有相应 profile，或改用上面的远程签名流程。真机 Debug 构建必须使用开发版 Bundle ID、`Yundo Dev` 显示名和 Apple Development 身份，且主 App 与 Packet Tunnel 必须绑定同一个开发版 App Group。远程流程在无签名归档后，通过 `-allowProvisioningUpdates` 绑定 API Key 完成导出签名，profile 不需要进入仓库。

iOS 客户端只支持标准竖屏。签名或真机调试时不得为了绕过工程报错恢复横屏方向，也不得为未使用的 Network Extension 类型扩大 entitlement；相关约束由 `test/ios/ios_branding_test.dart` 固化。

## 验证边界

Apple Developer 计划开通后，仍需要在第一次远程构建前完成 App ID、能力、证书、API Key 和 GitHub Secrets 配置。没有这些 Secrets 时，工作流应明确失败，不能把“源码编译成功”误报为“签名构建完成”。

2026-08-03 已在 commit `c1506ee` 完成远程验证：GitHub Actions run `30824938269` 的 iOS IPA、macOS 开发版 ZIP 和 macOS 正式版 ZIP 均成功产出。该验证覆盖证书导入、App Store Connect API Key、自动 profile 管理、导出签名和产物校验。

### 2026-08-08 本机 iPhone Debug 签名与安装

- Xcode 登录团队 `W684N2R45F` 后，通过 Apple Development 身份创建并使用 `Apple Development: dejian gan (975VAJC383)`；不导出证书私钥，不用于对外分发。
- `xcodebuild` 使用 `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` 自动生成开发 profile，主 App 与 Packet Tunnel 分别绑定开发版 Bundle ID `app.yundo.client.rebuild.dev` 和 `app.yundo.client.rebuild.dev.PacketTunnel`，两者均包含已配对 iPhone 的开发设备权限。
- iPhone 16 Pro Max（iOS 26.5.2）已安装并启动 `Yundo Dev` `4.1.2+202608137`。`codesign --verify --deep --strict`、主 App/扩展 TeamIdentifier 和 embedded profile 校验通过。
- 本地 Flutter 调试构建使用 Mac 局域网 API `http://192.168.1.223:4000/api/v1`；该地址从宿主机返回 API health `200`，不能在真机上使用 `127.0.0.1` 或 `localhost`。
- 本节只证明开发签名、profile、安装和启动；首次系统 VPN 配置授权、Packet Tunnel 真实加速、停止恢复和前后台/锁屏/网络切换矩阵仍需在实体 iPhone 上完成，不得用 Simulator 或签名成功替代。
