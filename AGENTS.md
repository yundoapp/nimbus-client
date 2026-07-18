# Yundo/Nimbus 客户端仓库协作补充规范

最后更新：`2026-07-18`

## App 修改后的必做流程

- 所有沟通、计划、评审、提交说明和代码注释优先使用简体中文。
- 只要修改会影响运行中 App 的 Flutter/Dart 源码、多语言、资源、依赖或 macOS 原生配置，必须在完成必要测试后执行 `scripts/build_install_run_macos_dev.sh`。
- 该脚本必须同时构建 `Yundo Dev` 和本机正式版 `Yundo`，分别完成特权辅助进程校验并覆盖 `/Applications/Yundo Dev.app` 与 `/Applications/Yundo.app`。正式版覆盖前必须备份，失败时恢复；安装后保持未运行。开发版必须重新启动并确认进程存活。任一环节失败时，任务不得宣布完成。
- 本机正式版使用生产入口、生产 Bundle ID 与生产 API，可使用 ad hoc 签名完成本机验收；不得把这条流程表述为 Developer ID 签名、公证、DMG 或对外发布。
- 不能只检查源码、测试或 `build/` 目录中的 App；验收对象必须包含实际安装在 `/Applications` 的开发版和正式版。
- 这是本机双版本验收流程，不等于生成内测包、发布安装包或触发 release；纯文档或纯测试文件修改不触发该流程。
