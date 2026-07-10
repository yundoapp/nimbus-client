# 首页公告接入

最后更新：`2026-07-10`

## 行为

首页按当前运行平台和 App 语言请求：

```http
GET /api/v1/announcements/current?platform=macos&language=zh-CN
```

服务端负责平台、启停和有效时间过滤，也负责中文/英文回退。客户端只展示响应中的一条当前公告；请求失败或 `item` 为空时不展示，也不阻塞首页其他功能。

公告位于首页内容顶部，标题最多一行、正文最多三行。关闭按钮复用现有多语言“关闭”语义，关闭状态只保存在当前页面生命周期；重新进入页面或服务端切换公告后可以再次展示，不写本地已读记录。

## 验证

模型与仓库单元测试：

```bash
flutter test test/features/nimbus/announcement_model_test.dart
```

完整客户端回归与 macOS 构建：

```bash
flutter test
flutter analyze --no-fatal-warnings --no-fatal-infos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  flutter build macos --debug \
  --dart-define=NIMBUS_API_BASE_URL=http://127.0.0.1:4000/api/v1
scripts/verify_macos_privileged_helper.sh
```

公告展示不依赖真实节点、TUN 授权或 Remnawave 环境。
