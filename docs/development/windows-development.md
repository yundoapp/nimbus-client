# Windows 开发与验收

更新时间：2026-07-18

## 当前阶段

M4 Windows MVP 已启动。当前先完成不依赖实体 Windows 的身份隔离、共享业务逻辑、加速权限承载、托盘/窗口、启动项、自动加速、测试和 CI 构建；项目负责人提供 Windows 机器后，再完成真实安装、虚拟网卡、路由和长期驻留总验收。

本阶段不授权 GitHub Release、Microsoft Store、正式代码签名或面向用户发布安装包。

## 身份边界

| 构建 | 用户可见名称 | 窗口标题 | 本地数据 ProductName | 单实例身份 | 启动项包名 |
| --- | --- | --- | --- | --- | --- |
| Debug | `Yundo Dev`，中文界面运行后显示云渡开发版名称 | `Yundo Dev` 启动后按 App 语言更新 | `Yundo Dev` | `YundoDevMutex` 与独立窗口类 | `Yundo.YundoDev` |
| Release | `Yundo`，中文界面运行后显示云渡正式版名称 | `Yundo` 启动后按 App 语言更新 | `Yundo` | `YundoMutex` 与独立窗口类 | `Yundo.Yundo` |

Windows 的 `path_provider` 使用可执行文件版本资源中的 CompanyName 与 ProductName 生成应用支持目录，因此 Debug 与 Release 不共享登录态、数据库、缓存和偏好。两种构建都使用 `Yundo.exe` 文件名，但窗口类、互斥锁、本地数据和启动项身份独立，可以并存。内部权限服务仍沿用上游 core 的固定服务协议；普通用户界面不展示服务名或网络技术细节。

## 构建入口

Windows 构建必须在 Windows 10/11 x64 环境完成，使用仓库锁定的 Flutter `3.38.5`。

开发版：

```powershell
make windows-install-deps
make windows-prepare
flutter build windows --debug --target=lib/main.dart
powershell -ExecutionPolicy Bypass -File scripts/verify_windows_bundle.ps1 -Configuration Debug -ExpectedProductName "Yundo Dev"
```

正式版无签名构建验证：

```powershell
flutter build windows --release --target=lib/main_prod.dart
powershell -ExecutionPolicy Bypass -File scripts/verify_windows_bundle.ps1 -Configuration Release -ExpectedProductName "Yundo"
```

上述命令只验证本地 bundle，不生成公开发布物。正式安装包、MSIX、代码签名和分发仍需单独确认。

## 加速权限路径

- Windows 新安装默认使用覆盖全局流量的加速模式。
- 普通 Flutter 进程运行用户态 core；权限服务只承载虚拟网卡到本地 SOCKS 的最小桥接配置。
- 首次加速时如服务不存在，系统弹出 UAC 授权；拒绝时返回产品化的权限提示。
- “修复加速权限”会停止并卸载权限服务，下次加速时重新请求授权安装。
- 停止加速和退出应用时均请求停止权限服务中的当前虚拟网卡实例。
- 不在仓库、日志或问题上报中保存真实节点配置、短期连接方案或本地用户路径。

## 自动化边界

Pull Request 会运行严格的 Windows 无签名验证任务：

1. 下载匹配版本的 core 依赖。
2. 运行 Flutter 全量测试。
3. 构建并校验 Debug `Yundo Dev` bundle。
4. 构建并校验 Release `Yundo` bundle。
5. 不上传 artifact，不创建或更新 GitHub Release。

CI 构建不能替代以下真机验收：UAC、虚拟网卡和路由、Windows Defender/安全软件、托盘与任务栏、开机启动、睡眠唤醒、网络切换、卸载残留及真实加速。

## 真机总验收

项目负责人提供 Windows 机器后，按 `nimbus-platform` Issue #81 完成：

- Yundo Dev 安装、启动和开发版身份隔离。
- 注册/登录、激活、设备、加速、停止加速、节点地区、加速模式和访问偏好。
- 虚拟网卡、路由、UAC 拒绝恢复、权限修复和异常退出后清理。
- 系统托盘、关闭窗口后台运行、开机启动、静默启动、自动加速和退出断开。
- 速度、流量、套餐、心跳、服务端强制断开和问题上报。
- Windows 100%、125%、150% 缩放，浅色/深色和主要语言。
