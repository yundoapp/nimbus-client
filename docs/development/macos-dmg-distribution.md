# macOS DMG 对外分发

最后更新：`2026-07-17`

## 目标

为朋友或其他测试者生成可追踪的 `Yundo.dmg`。正式 DMG 必须包含 Developer ID 签名、hardened runtime、Apple 公证和 stapling；Apple Development 或 ad hoc 签名只能用于本机开发，不能替代对外分发验收。

DMG 只负责安装载体，打开后把 `Yundo.app` 拖入 `Applications`。首次启用加速时，macOS 仍会要求用户批准云渡后台项目，这是最小权限 helper 的系统授权流程，不是安装失败。

## 前置条件

1. 加入 Apple Developer Program，并为正式 Bundle ID `app.yundo.client` 创建 `Developer ID Application` 证书。
2. 将证书及私钥安装到当前用户钥匙串。
3. 使用 `notarytool store-credentials` 创建钥匙串凭据配置。
4. 将 `pubspec.yaml` 构建号递增；任何发给测试者的安装包都不能复用上一个构建号。
5. 确保源码工作区 clean，且最终法律文本已经人工确认。

公证凭据示例：

```bash
xcrun notarytool store-credentials yundo-notary \
  --apple-id '<Apple ID>' \
  --team-id '<TEAM ID>' \
  --password '<App 专用密码>'
```

凭据只写入本机钥匙串，不得提交到仓库。

## 构建正式 App

```bash
export YUNDO_DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
export YUNDO_NOTARY_PROFILE='yundo-notary'
scripts/build_macos_distribution_app.sh
```

脚本使用正式 API `https://api.yundo.app/api/v1` 构建 Release App，对 App、特权 helper 和登录项执行 Developer ID 与 hardened runtime 签名，并运行公证前只读检查。

## 生成 DMG

```bash
scripts/package_macos_distribution_dmg.sh
```

脚本依次执行：

1. 检查 clean 工作区、正式 Bundle ID、版本、Developer ID identity 和 notarytool 凭据。
2. 提交签名 App 公证，staple App，并执行 Gatekeeper 检查。
3. 生成包含 `Yundo.app` 和 `Applications` 快捷方式的压缩 DMG。
4. 签名并提交 DMG 公证，staple DMG，并执行 Gatekeeper 检查。
5. 只读挂载 DMG，再次校验包内 App、helper、合规文档和 stapling。
6. 输出 DMG、SHA-256 和 manifest；不会创建 GitHub Release 或发布下载链接。

默认产物目录为 `build/distribution/`。只有 manifest 同时包含以下字段时，安装包才可以进入异机验收：

```text
signature=developer-id
notarization=accepted
app_stapling=passed
dmg_stapling=passed
gatekeeper=passed
source_state=clean
```

## 异机验收

在另一台没有 Flutter、Xcode、开发证书和旧版云渡数据的 Mac 上完成：

1. 双击 DMG，将 `Yundo.app` 拖入 `Applications`。
2. 从 Launchpad 或 Finder 正常打开，不使用 `xattr`、终端命令或“仍要打开”绕过 Gatekeeper。
3. 登录、激活并点击加速，在系统设置中批准后台项目。
4. 验证真实节点连接、流量刷新、停止加速和退出后的路由恢复。
5. 重启 Mac，验证开机启动和自动连接设置。
6. 删除 App 前先退出云渡，确认 helper 和连接子进程已经结束。

异机验收通过前，不发布正式下载链接，也不关闭 #48。
