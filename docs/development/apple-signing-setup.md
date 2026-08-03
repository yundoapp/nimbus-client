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

正式版 App ID 需要启用应用当前使用的 App Groups 与 Network Extension 能力；App Groups 应包含 `group.app.yundo.client`。如果需要远程签名开发版，再额外创建开发版的两个 Bundle ID，并启用对应的 `group.app.yundo.client.rebuild.dev`。

远程 iOS IPA 使用 App Store 分发签名，因此需要导出包含私钥的 `Apple Distribution` `.p12`。macOS 产物直接在 App 外分发，使用单独的 `Developer ID Application` `.p12`；本工作流负责签名和校验，暂不自动公证。

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

远程工作流使用“管理员”职能的 API Key，以便 Xcode 在没有预置 profile 时管理 App ID 与分发 profile。iOS Release 的分发身份只配置在 Yundo 主 App 与 Packet Tunnel target 上，Pods 继续使用自己的自动签名配置。证书、`.p12` 密码和 `.p8` 私钥只放 GitHub Secrets，不提交到仓库。

## 使用方式

`.github/workflows/apple-build.yml` 通过 `workflow_dispatch` 触发，同时构建：

- macOS 开发版 ZIP
- macOS 正式版 ZIP
- iOS 正式版 IPA

工作流只上传 Actions artifact，不自动覆盖本机、不自动发布 GitHub Release、不自动上传 TestFlight。构建完成后从同一个 workflow run 下载产物即可。

本地开发仍使用本机工具链，避免为每次调试等待远端：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  scripts/build_install_run_macos_dev.sh
```

iOS Simulator 可以使用 Xcode 登录的本机账号直接构建；真机/IPA 则需要本机已有相应 profile，或改用上面的远程签名流程。远程流程通过 `-allowProvisioningUpdates` 绑定 API Key，profile 不需要进入仓库。

## 验证边界

Apple Developer 计划开通后，仍需要在第一次远程构建前完成 App ID、能力、证书、API Key 和 GitHub Secrets 配置。没有这些 Secrets 时，工作流应明确失败，不能把“源码编译成功”误报为“签名构建完成”。
