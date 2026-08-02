# 云渡 Hiddify 重建迁移基线

最后更新：`2026-08-02`

## 1. 目标

本分支从 Hiddify 上游提交 `276a7effb0046a039220a745022563740968c0b8` 建立，目标是在保留云渡现有产品功能、界面布局和菜单结构的前提下，把云渡逻辑限制在 Hiddify 标准配置和应用层。

当前云渡 `develop` 仅作为功能、文案、视觉资源和行为的参考实现，不作为新的底层实现来源。

## 2. 不可越界的网络核心

以下能力由 Hiddify 和 sing-box 原有实现负责，云渡业务代码默认不得修改：

- `lib/hiddifycore/`：Core 生命周期、桌面和移动端核心通道
- `lib/singbox/`：核心配置模型和协议实现
- `macos/PrivilegedHelper/`：macOS 特权辅助进程
- `macos/Runner/PrivilegedHelperBridge.swift`：macOS Helper 通道
- `windows/runner/`：Windows 原生进程、服务和网络集成
- `ios/Runner/VPN/`：iOS Packet Tunnel 管理
- `ios/HiddifyPacketTunnel/`：iOS 隧道扩展
- Android 后台 VPN Service 和核心服务实现

云渡只允许通过现有的 Profile、Route Rules、Config Option、Connection Repository 等应用层接口提供数据和发起连接。

## 3. 云渡功能迁移范围

以下能力必须迁移，但不得以重写网络底层为代价：

- 登录、长期登录态和账号资料
- 套餐、激活码、设备和流量状态
- 首页加速/停止加速、节点地区、速度和流量展示
- 自动连接、开机启动、托盘和窗口行为
- 访问偏好和自定义访问规则
- 问题上报、公告和版本提示
- 云渡品牌资源、多语言、首页布局、设置页面和菜单顺序

迁移 UI 时优先保留云渡 `develop` 的页面层级、布局、菜单顺序和用户文案；只替换其底层数据来源和连接调用。

## 4. 规则和连接适配原则

1. 后台返回短期连接方案和完整 Hiddify 标准 Profile 内容。
2. 客户端只校验并安装标准 Profile，不消费旧版 `singBoxConfigPatch`，不在本地拼装运行时配置。
3. Hiddify 原有 `ProfileParser`、`ProfileRepository`、`ConnectionRepository` 和 Core 生命周期继续负责解析、启动和停止。
4. 如果某项云渡规则无法表达为 Hiddify 标准配置，优先调整后台配置生成或暂缓该项能力，不修改 DNS、TUN、路由、系统代理或 Helper。
5. 不允许由云渡代码接管系统 DNS，不允许在加速前后直接修改物理网卡 DNS，不允许自行创建或清理系统路由。

服务端可以继续返回旧 `singBoxConfigPatch` 供旧客户端兼容，但新客户端收到缺少 `profileContent` 的响应时必须失败关闭，不得回退消费旧字段。

当前已完成：认证壳、首页/连接按钮、设置页、路由偏好、问题反馈、应用生命周期接入和标准 Profile 适配器；当前尚未完成四端构建、真实节点连接和安装版网络矩阵。

## 5. 迁移顺序

### 阶段 A：基线

- 证明干净 Hiddify 在 macOS、Windows、iOS Simulator、Android 的构建和基础生命周期可用。
- 记录加速、停止、异常退出、系统网络恢复和微信开发者工具场景的基线结果。

### 阶段 B：无网络副作用的产品层

- 迁移品牌、多语言、登录页面、首页布局、设置菜单和托盘展示。
- 这些改动不得触碰受保护网络目录。

### 阶段 C：数据和配置适配

- 迁移账号、套餐、激活、设备、流量和访问偏好数据模型。
- 新增云渡适配器，只生成 Hiddify 标准 Profile/Route Rules 输入。

### 阶段 D：连接闭环

- 接入短期连接方案。
- 复用 Hiddify 原有连接仓库和平台通道。
- 逐端验证连接、停止、重启、睡眠、网络切换和异常恢复。

### 阶段 E：替代旧版本

- 新分支通过四端同源构建和真实网络矩阵后，才替代当前 `develop`。
- 当前 `develop` 保留为回退参考，不直接回滚或覆盖。

## 6. 每个迁移提交的验收门槛

- 变更文件通过 `scripts/check_yundo_hiddify_boundary.sh`。
- UI 改动保留现有页面层级、菜单结构和多语言要求。
- 连接相关改动必须有 Profile/规则 fixture 和失败路径测试。
- 影响客户端运行的改动必须基于同一 commit 完成四端构建基线。
- 真实安装版必须验证网络可用性，不能只以编译成功作为通过。
