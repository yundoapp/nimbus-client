# Windows 开发与验收

更新时间：2026-07-18

## 当前阶段

M4 Windows MVP 已完成不依赖实体 Windows 的身份隔离、共享业务逻辑、加速权限承载、托盘/窗口、启动项、自动加速、测试和 CI 构建。当前进入 Windows 安装验收：先用 Parallels Windows 11 ARM64 虚拟机验证 x64 安装包的安装、身份与启动，再在实体 Windows x64 机器完成虚拟网卡、路由和长期驻留总验收。

本阶段不授权 GitHub Release、Microsoft Store、正式代码签名或面向用户发布安装包。

## 身份边界

| 构建 | 简体中文用户可见名称 | 其他语言用户可见名称 | 本地数据 ProductName | 单实例身份 | 启动项包名 |
| --- | --- | --- | --- | --- | --- |
| Debug | `云渡开发版` | `Yundo Dev`，繁体中文为 `雲渡開發版` | `Yundo Dev` | `YundoDevMutex` 与独立窗口类 | `Yundo.YundoDev` |
| Release | `云渡` | `Yundo`，繁体中文为 `雲渡` | `Yundo` | `YundoMutex` 与独立窗口类 | `Yundo.Yundo` |

简体中文 Windows 安装正式版时，开始菜单、桌面和开机启动快捷方式统一显示 `云渡`，App 窗口与托盘菜单按 App 语言显示 `云渡`；其他系统语言保留 `Yundo`。Windows 的 `path_provider` 使用可执行文件版本资源中的 CompanyName 与 ProductName 生成应用支持目录，因此这里的内部 ProductName 继续保持稳定英文身份，Debug 与 Release 不共享登录态、数据库、缓存和偏好。两种构建都使用 `Yundo.exe` 文件名，但窗口类、互斥锁、本地数据和启动项身份独立，可以并存。内部权限服务仍沿用上游 core 的固定服务协议；普通用户界面不展示服务名或网络技术细节。

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
flutter build windows --release --target=lib/main_prod.dart --dart-define=NIMBUS_API_BASE_URL=https://api.yundo.app/api/v1
powershell -ExecutionPolicy Bypass -File scripts/verify_windows_bundle.ps1 -Configuration Release -ExpectedProductName "Yundo"
```

上述命令只验证本地 bundle，不生成公开发布物。正式安装包、MSIX、代码签名和分发仍需单独确认。

用于项目负责人 Windows 验收的无签名 EXE 安装包通过 Pull Request 临时生成：

1. 给目标 PR 添加 `ci:windows-acceptance` label。
2. CI 使用 `lib/main_prod.dart` 和生产 API `https://api.yundo.app/api/v1` 构建并校验 Release `Yundo` bundle。
3. CI 生成 `Yundo-Windows-Setup-x64-<version>-build<build>.exe` 及 SHA-256 校验文件；安装器允许在 Windows 11 ARM64 的 x64 模拟环境安装，应用 bundle 仍为 x64 架构。
4. `windows-acceptance` artifact 仅保留 3 天，不创建或更新 GitHub Release。

该入口只用于当前项目内部验收；安装程序尚未经过 Developer ID 等效的 Windows 代码签名，Windows 可能显示未知发布者提示。公开发布、Microsoft Store、正式签名和面向真实用户分发仍需另行确认。

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
5. 默认不上传 artifact；只有带 `ci:windows-acceptance` label 的 PR 才上传保留 3 天的内部验收安装包。
6. 不创建或更新 GitHub Release。

CI 构建不能替代以下真机验收：UAC、虚拟网卡和路由、Windows Defender/安全软件、托盘与任务栏、开机启动、睡眠唤醒、网络切换、卸载残留及真实加速。

## 真机总验收

项目负责人提供 Windows 机器后，按 `nimbus-platform` Issue #81 完成：

- Yundo Dev 安装、启动和开发版身份隔离。
- 注册/登录、激活、设备、加速、停止加速、节点地区、加速模式和访问偏好。
- 虚拟网卡、路由、UAC 拒绝恢复、权限修复和异常退出后清理。
- 系统托盘、关闭窗口后台运行、开机启动、静默启动、自动加速和退出断开。
- 速度、流量、套餐、心跳、服务端强制断开和问题上报。
- Windows 100%、125%、150% 缩放，浅色/深色和主要语言。

## 2026-07-18 Parallels 初验

已在 Windows 11 Pro ARM64 Parallels 虚拟机完成正式版 `Yundo 1.0.0+10001` 的安装前初验：

- PR #23 的 CI run `29641135139` 通过 124 项测试、Debug/Release 双 bundle 校验、EXE 打包和短期 artifact 上传。
- 安装器改用 Inno Setup `x64compatible`，在 Windows 11 ARM64 通过 x64 模拟完成 64 位安装模式安装；实体 Windows x64 仍是主要交付目标。
- 正式构建和 Windows 打包入口显式编译生产 API `https://api.yundo.app/api/v1`，避免回退到开发默认地址 `http://localhost:4000/api/v1`。
- 最终安装包 SHA-256 为 `59e19ba5f1215a3c0be4379d3ea9580aa0ca8eee76e3287adf8a854a7491924e`；虚拟机复制后校验一致。
- 安装日志确认安装成功且不要求重启；程序文件身份为 `Yundo 1.0.0+10001`，未签名状态符合内部验收边界，卸载入口和桌面快捷方式已生成。
- 安装后的 `app.so` 已检出生产 API 地址；虚拟机访问生产 health 返回 HTTP 200，数据库依赖正常。
- `Yundo.exe` 在当前用户 Console 会话启动、进程响应正常，窗口标题与登录页显示 `Yundo · 云渡`。
- 初验同时发现 Windows runner 仍引用旧版柱状图标，且安装器快捷方式固定显示 `Yundo`；后续修复还发现升级安装可能只删除旧快捷方式而不重建。三项均属于验收缺陷，不作为正式身份基线，已转入 `1.0.0+10003` 修复并重新验收。

本次未执行登录后的 UAC、虚拟网卡、路由和真实加速；这些操作会改变 Windows 网络状态，且仍需在实体 Windows x64 机器按平台 Issue #81 完成总验收。

## 2026-07-18 简体中文品牌复验

已在系统语言为简体中文的 Windows 11 Pro ARM64 Parallels 虚拟机完成正式版 `Yundo 1.0.0+10003` 覆盖安装复验：

- PR #24 的 CI run `29644717857` 通过 124 项测试、Debug/Release 双 bundle 校验、Inno Setup 打包和短期 artifact 上传。
- Windows runner 的多尺寸 `app_icon.ico` 已由云渡统一 SVG 品牌源生成，安装器和应用不再使用旧版柱状图图标。
- 正式版简体中文应用标题为 `云渡`；繁体中文为 `雲渡`；其他语言为 `Yundo`。开发版继续使用对应的独立开发版名称。
- 安装器按 Windows 当前 UI 语言生成开始菜单、桌面和开机启动快捷方式名称；桌面快捷方式在安装和升级时固定重建，避免旧版升级后只删除旧快捷方式而不创建新快捷方式。
- 最终安装包 SHA-256 为 `180263682a2c7578a2258436336b55b55d64f3d75127b2230e60e1980dffc9ee`；Mac 与 Windows 共享路径复核一致，安装日志记录成功且无需重启。
- 覆盖安装后旧 `Yundo.lnk` 不存在，新 `云渡.lnk` 指向 `C:\Program Files\Yundo\Yundo.exe` 并显式使用该程序的新版图标。
- 实际桌面、窗口标题、登录页和任务栏均已目视确认显示 `云渡` 与新版蓝色 Y 图标，进程版本为 `1.0.0+10003` 且保持响应。

本次复验仍未触发 UAC、虚拟网卡、路由或真实加速；实体 Windows x64 的网络链路和长期驻留总验收边界不变。
