# Yundo / 云渡客户端

Yundo（云渡）是一个面向个人自用和小范围朋友测试的跨平台连接客户端。当前不以盈利为目的，不提供在线支付，也不是 Hiddify 官方发行版。

## 开源来源与归属

本仓库是 [Hiddify App](https://github.com/hiddify/hiddify-app) 的公开 fork，并继续遵守仓库根目录 [Hiddify Extended GNU General Public License v3](./LICENSE.md)。Hiddify 原项目及其贡献者保留原有归属；Yundo / 云渡是基于该项目修改的独立版本。

- 云渡公开源码：<https://github.com/wintion/nimbus-client>
- Hiddify 原始仓库：<https://github.com/hiddify/hiddify-app>
- 许可证正文：[LICENSE.md](./LICENSE.md)
- 开源归属与发布边界：[docs/legal/open-source-compliance.md](./docs/legal/open-source-compliance.md)

## 主要修改

与上游 Hiddify App 相比，云渡目前主要调整：

- 使用 Yundo / 云渡品牌、图标、独立开发版名称与 Bundle ID。
- 将用户体验收敛为账号、激活、套餐、流量、位置、设备和连接状态。
- 接入云渡平台的登录、规则包、连接方案、心跳、问题上报和版本检查 API。
- 在首页展示按平台、时间和语言匹配的服务公告，并支持本次关闭。
- 普通用户界面隐藏节点、协议、订阅和底层网络配置等技术入口。
- 增加 macOS 开机启动、自动连接、菜单栏状态、最小权限 TUN helper 和受邀内测打包校验。
- 保留 Hiddify / sing-box 的跨平台底座，并尽量减少对上游核心代码的改动。

更完整的变更记录以本仓库 Git 历史和 [CHANGELOG.md](./CHANGELOG.md) 为准。

## 源码与安装包对应

发给测试者的安装包必须对应本公开 fork 中已经推送的具体 commit。macOS 内测包由 `scripts/package_macos_internal_test.sh` 生成，附带 SHA-256 和 manifest；manifest 会记录完整源码 commit、clean 状态、版本、构建号、架构、签名和包内合规文档。

本地内测打包不属于正式 release。根据 Extended GPLv3 的附加条件，正式发布必须：

1. 先将对应源码和 tag 推送到本公开 fork。
2. 通过 GitHub Actions 自动化发布。
3. 同时提供源码、许可证、Hiddify 归属和云渡修改说明。
4. 继续保持非商业使用；商业化前先取得许可证要求的书面同意。

未经项目负责人明确确认，不触发 release、App Store 分发或公开下载。

## 法律与隐私文档

- [云渡隐私说明（M3 受邀内测版）](./docs/legal/privacy-policy.md)
- [云渡使用条款（M3 受邀内测版）](./docs/legal/terms-of-service.md)

上述文档当前仅用于受邀内测。正式对外发布前，项目负责人仍需确认服务主体、联系方式、适用地区、责任边界和最终保留策略。

## 开发与构建

macOS 当前是第一优先平台。工具链、生成命令、Debug 构建与内测包步骤见 [macOS 开发版构建基线](./docs/development/macos-debug-build.md)，公告展示与验证见 [首页公告接入](./docs/development/announcements.md)，TUN 权限边界及正式签名包只读预检见 [macOS TUN 最小权限辅助进程](./docs/development/macos-privileged-helper.md)。

核心生成与检查命令：

```bash
flutter pub get
dart run slang
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-warnings --no-fatal-infos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug
```

## Upstream

上游项目的功能介绍、贡献指南和社区信息请直接查看：

- <https://github.com/hiddify/hiddify-app>
- <https://hiddify.com/app/>

Yundo / 云渡的问题请在本 fork 中反馈，不应要求 Hiddify 社区为云渡修改承担支持责任。
