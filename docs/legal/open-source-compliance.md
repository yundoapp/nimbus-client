# 云渡客户端开源归属与发布边界

最后更新：`2026-07-14`

## 当前来源

- 云渡客户端仓库：<https://github.com/yundoapp/nimbus-client>
- 原始项目：<https://github.com/hiddify/hiddify-app>
- GitHub 状态：云渡仓库是原始项目的公开 fork。
- 许可证：仓库根目录 [LICENSE.md](../../LICENSE.md) 保留 Hiddify Extended GNU General Public License v3 原文，本任务不修改许可证正文。

## 云渡主要修改

- 用户侧品牌、图标、开发版身份与多语言资源。
- 面向普通用户的极简账号、激活、套餐、流量、位置、设备和问题上报体验。
- 云渡平台 API、规则包、连接方案、心跳和版本检查适配。
- macOS 菜单栏、开机启动、自动连接、内测打包与验证工具。
- 隐藏普通用户不需要理解的配置、协议和节点管理入口。

## Extended GPLv3 对应措施

1. **公开 fork**：安装包对应源码必须先存在于公开的 `yundoapp/nimbus-client` fork。
2. **自动化发布**：正式 release 只能通过 GitHub Actions 发布；本地 `package_macos_internal_test.sh` 仅用于受邀开发内测，不是正式 release，也不得用于 App Store 或公开发布。
3. **归属**：README、App 关于页和安装包内许可证均明确指向 Hiddify App 与原始许可证。
4. **变更说明**：README 和本文记录云渡主要修改范围。
5. **名称与界面区分**：用户可见名称为 Yundo / 云渡，界面按云渡产品需求调整，不冒充 Hiddify 官方版本。
6. **非商业边界**：当前仅个人自用和朋友测试，不销售、不投放广告、不接在线支付；商业化前必须先取得许可证要求的书面同意并重新评估合规。
7. **同许可证开源**：发布的修改版客户端继续按相同许可证公开对应源码。

## 安装包与源码对应

每个发给测试者的 macOS 包必须由 clean 工作区生成，并附带 manifest。manifest 至少记录：

- `version` 与 `build_number`
- `source_commit` 与 `source_commit_full`
- `source_state=clean`
- `license_asset=LICENSE.md`
- 隐私说明与使用条款的包内路径
- SHA-256、架构和签名类型

分发前确认 `source_commit_full` 已推送到公开 fork。正式 release 还必须使用对应 tag，并通过 `.github/workflows/release.yml` 触发自动化构建；触发 release 属于高风险操作，需要项目负责人另行明确确认。

## 内测前检查

- [ ] `LICENSE.md` 未被修改。
- [ ] README 的原始项目、许可证、修改说明和源码获取方式可访问。
- [ ] App 关于页的源码、许可证、使用条款和隐私说明可打开。
- [ ] 注册页默认未勾选，用户可分别打开条款和隐私说明后主动同意。
- [ ] App 包内包含许可证、隐私说明和使用条款。
- [ ] manifest 对应 clean 且已推送的具体 commit。
- [ ] 构建产物禁用品牌字符串扫描通过。
- [ ] 正式发布前，项目负责人已确认最终用户协议和隐私说明。
