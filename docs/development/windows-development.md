# Windows 开发与验收

更新时间：2026-07-19

## 当前阶段

M4 Windows MVP 已进入实体 x64 Windows 总验收。Parallels Windows 11 ARM64 已用于早期安装和品牌复验；从 `1.0.0+10004` 起，安装器只允许原生 x64 Windows。2026-07-19 的首轮实体 Windows 11 Pro 验收确认安装、注册、登录和激活通过，同时暴露配置启动、问题上报、系统版本识别和托盘图标阻断项，统一由平台 Issue #88 修复并复测。

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
3. CI 生成 `Yundo-Windows-Setup-x64-<version>-build<build>.exe` 及 SHA-256 校验文件；安装器仅允许原生 x64 Windows，在 ARM64 或 x86 Windows 上会在复制文件前提示不兼容并退出。
4. `windows-acceptance` artifact 仅保留 3 天，不创建或更新 GitHub Release。

该入口只用于当前项目内部验收；安装程序尚未经过 Developer ID 等效的 Windows 代码签名，Windows 可能显示未知发布者提示。公开发布、Microsoft Store、正式签名和面向真实用户分发仍需另行确认。

## 加速权限路径

- Windows 新安装默认使用覆盖全局流量的加速模式。
- 普通 Flutter 进程运行用户态 core；权限服务只承载虚拟网卡到本地 SOCKS 的最小桥接配置。
- 正式 EXE 安装器在管理员安装阶段预装并启动系统加速组件；后续普通用户日常加速不应重复请求管理员授权。
- 从 `1.1.1+10011` 起，安装器在完成前同时检查权限服务处于运行状态且本地控制端口可连接；检查不通过则安装失败并给出重新安装建议，不把可前置发现的环境错误推迟到首次加速。
- 安装阶段只能验证本机文件、服务、权限和控制通道；账号登录后由 API 下发的短期连接配置仍需在运行时校验。Windows 首次配置若因外部远程规则库不可用被 core 拒绝，客户端会自动移除远程规则库并重试，保留本地网站规则和可用的全局加速兜底。
- 非管理员用户提供管理员凭据完成安装后，安装器的“运行云渡”动作会切回最初发起安装的普通用户身份，不继承安装器的管理员令牌；首次启动与后续桌面启动使用同一账号数据和权限边界。
- 开发 bundle、组件被移除或“修复加速权限”后的回退路径仍会在下次加速时请求 UAC；拒绝时显示管理员处理建议和稳定诊断编号。
- “修复加速权限”会停止并卸载权限服务，下次加速时重新请求授权安装。
- 停止加速和退出应用时均请求停止权限服务中的当前虚拟网卡实例。
- 不在仓库、日志或问题上报中保存真实节点配置、短期连接方案或本地用户路径。

## 启动错误与诊断编号

从 `1.0.3+10009` 起，Windows 启动错误不再统一折叠为“稍后重试”：

| 诊断编号 | 类别 | 用户处理建议 |
| --- | --- | --- |
| `W-SVC-01` | 安装包中的系统加速组件缺失 | 重新安装云渡，并在安装时允许管理员授权 |
| `W-PERM-01` | 系统授权未完成 | 由管理员完成一次授权，之后普通用户直接使用 |
| `W-SVC-02` | 系统加速组件未启动或不可访问 | 重启 Windows；仍失败时重新安装 |
| `W-NET-01` | 系统网络组件无法启动 | 重启 Windows；仍失败时重新安装 |
| `W-NET-02` | 其他网络组件发生冲突 | 退出其他加速类 App，重启后重试 |
| `W-START-01` | 未归类的 Windows 启动失败 | 复制诊断信息并上报问题 |

首页错误卡片显示原因、操作建议和诊断编号，并提供“复制诊断信息”和“上报问题”。复制内容只包含诊断编号、失败类别、启动阶段、App 版本和系统版本；问题上报复用既有 `connectionStatus` 允许字段携带这些脱敏信息，不上传节点配置、访问内容、账号凭据或本地路径。平台连接结果同时记录稳定的 `failureCode`，用于统计同类环境问题。

从 `1.1.1+10011` 起，配置失败诊断额外携带不含节点内容的 `detailCode`，用于区分文件、JSON、入站桥接、远程规则库和出站兼容问题。系统版本不再直接使用 Windows 兼容层产品名，而是读取注册表 Build；Build 22000 及以上统一识别为 Windows 11，因此 Build 26200 不再错误显示为 Windows 10。

问题上报同时兼容已部署的旧 API 和新版字段契约：新版优先提交类别、描述、联系方式和诊断；若旧 API 明确以 `VALIDATION_FAILED` 拒绝 `category/contact`，客户端自动使用旧字段重试，并把类别和联系方式合并进脱敏描述。其他校验错误不会被兼容逻辑吞掉。

Windows 系统托盘固定使用独立的多尺寸彩色云渡 Logo；macOS 继续使用适合菜单栏深浅主题的模板图标，两端不再共用同一图标文件。

旧版本只向平台上报 `CLIENT_START_FAILED`，且 UI 丢弃了原始系统错误，因此无法仅凭旧截图确认具体失败类别。安装 `1.0.3+10009` 后复测一次即可依据诊断编号继续定位；这也是实体 Windows #81/#88 的下一步验收依据。

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

## 2026-07-18 原生 x64 安装限制

从正式版 `Yundo 1.0.0+10004` 起，Windows EXE 安装器使用 Inno Setup `x64os` 作为允许架构和 64 位安装模式条件，只允许原生 x64 Windows：

- ARM64 Windows 即使能够模拟运行 x64 用户态程序，也不能继续安装云渡，避免安装完成后才发现虚拟网卡和加速权限链路不可用。
- x86 Windows 同样不能安装；当前 Windows bundle、权限服务和验收范围均为 x64。
- 架构判定在复制文件和修改安装目录前完成，不会覆盖 ARM64 机器上已存在的 `1.0.0+10003` 验收安装。
- ARM64 原生版本只有在 Flutter runner、core、权限服务、虚拟网卡和 CI 构建链路均完成 ARM64 适配后再单独开放。

## 2026-07-18 安装器语言补全

从正式版 `Yundo 1.0.0+10005` 起，Windows EXE 安装器与 App 当前支持语言对齐，覆盖英语、阿拉伯语、西班牙语、波斯语、法语、印尼语、巴西葡萄牙语、俄语、土耳其语、简体中文和繁体中文：

- 英语放在列表首位，无法匹配系统语言时安全回退到英语。
- `ShowLanguageDialog=auto`：Windows UI 语言能够匹配时自动使用对应语言，不再额外打断用户；无法匹配时才显示完整语言列表。
- 阿拉伯语、巴西葡萄牙语、简体中文和繁体中文使用 Inno Setup 官方翻译；Windows runner 缺少官方语言文件时，从固定上游提交下载并校验 SHA256。
- 波斯语和印尼语使用 Inno Setup 官方翻译页提供的贡献翻译，并固定保存在仓库中。
- ARM64/x86 架构拒装提示跟随安装器所选语言显示，仍在复制文件和修改安装目录前结束。
