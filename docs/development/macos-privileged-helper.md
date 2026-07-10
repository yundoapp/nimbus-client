# macOS TUN 最小权限辅助进程

最后更新：`2026-07-10`

## 当前结论

云渡不会让整个 App 以管理员身份运行。macOS 13 及以上版本使用 `SMAppService` 注册 App 包内的 `LaunchDaemon`，只有独立的 `YundoPrivilegedHelper` 以 root 身份承载 TUN。

当前代码、Xcode 包结构、静态验证和 Debug 构建已经完成。真实授权仍需同时满足：

- App 和 helper 使用同一 Apple Developer Team 的 Developer ID 正式签名。
- App 完成 hardened runtime、公证和 stapling。
- 管理员在“系统设置 -> 通用 -> 登录项与扩展”批准后台项目。

ad hoc Debug 包可以验证代码和包结构，但不作为 `SMAppService` 真实注册成功的证据。

正式签名包生成后先运行只读发行就绪检查：

```bash
export YUNDO_DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
export YUNDO_NOTARY_PROFILE='yundo-notary'
scripts/check_macos_distribution_readiness.sh \
  'build/macos/Build/Products/Release/Yundo.app' --strict
```

脚本检查 Developer ID identity、notarytool 凭据可用性、App/helper 同 Team、hardened runtime、深度签名、Gatekeeper 和 stapling。它只读取公证历史以验证凭据，不会签名、提交公证、注册 helper 或修改网络；未加 `--strict` 时只输出结构化阻塞项，适合证书尚未准备好的本机检查。

## 进程边界

```text
Flutter / 普通用户进程
  |- 完整连接 core、远端出站、规则、日志和流量统计
  |- 仅监听 127.0.0.1 的 mixed 入站
  `- 通过受校验 XPC 请求启动或停止 TUN

YundoPrivilegedHelper / root
  |- 只接受同一 App 包、同一 Bundle ID 的运行中主进程
  |- 只接受一个 TUN 入站 + 本机 SOCKS 出站 + direct 绕行的白名单配置
  |- 不接收真实节点、账号、激活码或远端密钥
  |- 不开放 TCP/gRPC 管理端口
  `- App/XPC 失联时停止 TUN 并退出
```

客户端在启动连接前把受管 sing-box 配置拆成两份：

1. 普通 core 配置移除 TUN，保留本机 mixed 入站和真实出站。
2. 特权配置只保留 TUN，并把流量转发到普通 core 的 `127.0.0.1:12334`。

helper 会再次解析并校验特权配置。除 TUN、loopback SOCKS、direct 绕行和固定 route 外的字段都会被拒绝。

## 构建产物

Debug 构建后必须存在：

```text
Yundo Dev.app/Contents/Library/HelperTools/YundoPrivilegedHelper
Yundo Dev.app/Contents/Library/LaunchDaemons/app.yundo.client.dev.privileged-helper.plist
```

运行只读校验：

```bash
scripts/verify_macos_privileged_helper.sh
```

脚本会检查：

- helper 独立签名和 Bundle ID。
- LaunchDaemon `Label`、`BundleProgram` 和 `MachServices`。
- helper 能加载包内 `hiddify-core.dylib` 的必要符号。
- Swift 安全边界接受最小 TUN 配置基线。

这些检查不会注册服务、不会请求管理员权限、不会创建 TUN，也不会修改路由。

## 首次授权流程

1. 用户点击“启用”后，普通 core 先启动本机 mixed 入站。
2. App 检查 LaunchDaemon 状态；未注册时调用 `SMAppService.register()`。
3. 如状态为 `requiresApproval`，App 打开系统登录项设置并返回“需要系统授权后才能连接”。
4. 管理员批准后再次点击“启用”，App 通过 privileged XPC 启动最小 TUN 转发器。
5. 普通 core 或 helper 启动失败时，两侧都会执行停止清理，不能留下只接管路由但没有出口的状态。

## 停止与恢复

- 主动断开：先停止普通 core，再通过 XPC 停止 TUN。
- App 正常退出或异常结束：XPC 连接失效，helper 停止 TUN 后退出。
- helper 配置只保存在 root 私有目录，停止后删除活动配置文件。
- 不在 `/Library/LaunchDaemons` 复制自维护 plist；注册状态由 `SMAppService` 管理。

真实签名包可用后，仍需完成连接前、连接后、断开后三阶段网络采证，以及退出、异常结束、睡眠唤醒和网络切换恢复验证。

## 版本边界

- 当前现代权限承载层要求 macOS 13+。
- macOS 12 及更早版本不会回退到已废弃的 `AuthorizationExecuteWithPrivileges` 或让整个 App 使用 `sudo`。
- 若后续必须支持旧系统，应单独评估签名完整的 legacy helper，不在当前 MVP 隐式兼容。
