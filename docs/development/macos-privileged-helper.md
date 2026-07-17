# macOS TUN 最小权限辅助进程

最后更新：`2026-07-16`

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
  |- 不开放 TCP/gRPC 管理端口
  `- App/XPC 失联时终止 raw-run 子进程、删除活动配置并退出
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

连接状态与延迟探测是两条独立信号。只要普通 core 和 TUN 均已启动，首页就显示“加速已开启”；延迟暂不可用、探测超时或当前配置没有延迟选择组时，只影响延迟显示，不得把成功连接回退成“加速中”。

## 停止与恢复

- 主动断开：先停止普通 core，再通过 XPC 停止 TUN。
- 主动断开期间首页保持“正在停止加速”并禁用重复点击，至少展示 500ms；helper 返回后继续轮询代表性公网路由和系统代理状态，确认连接资源释放后才恢复“加速”。
- 所有连接入口共用同一断开 Future；断开清理期间收到连接请求时先等待清理完成。断开后立即连接不再依赖固定 300ms/500ms 延时猜测。
- App 正常退出或异常结束：XPC 连接失效，helper 停止 TUN 后退出。
- helper 配置和子进程日志只保存在 root 私有目录，停止后删除活动配置文件。
- 不在 `/Library/LaunchDaemons` 复制自维护 plist；注册状态由 `SMAppService` 管理。

当前 Apple Development 包已完成干净基线下的连接前、连接后、主动断开和异常结束采证。主动断开与 `SIGKILL` 异常结束的严格对比结果均为 `ready`：连接时新增 TUN、目标公网路由命中新接口、结束后默认路由和公网路由恢复、额外 TUN 清理均通过。异常结束后 root helper 与 raw-run 子进程在 2 秒内退出。

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

## 版本边界

- 当前现代权限承载层要求 macOS 13+。
- macOS 12 及更早版本不会回退到已废弃的 `AuthorizationExecuteWithPrivileges` 或让整个 App 使用 `sudo`。
- 若后续必须支持旧系统，应单独评估签名完整的 legacy helper，不在当前 MVP 隐式兼容。
