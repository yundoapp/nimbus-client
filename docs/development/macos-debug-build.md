# macOS 开发版构建基线

最后更新：`2026-07-10`

## 工具链

- Flutter `3.38.5`
- Dart `3.10.4`
- Xcode 位于 `/Applications/Xcode.app`
- Swift 使用 Xcode 随附版本

如果系统 `xcode-select -p` 仍指向 Command Line Tools，命令前增加：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

无需修改系统全局的 Xcode 选择。

## 生成与检查

在仓库根目录依次执行：

```bash
flutter pub get
dart run slang
dart run build_runner build --delete-conflicting-outputs
swift scripts/generate_yundo_logo_assets.swift
flutter analyze --no-fatal-warnings --no-fatal-infos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter build macos --debug
```

Debug 产物应位于：

```text
build/macos/Build/Products/Debug/Yundo Dev.app
```

产物身份必须为：

- 显示名：`Yundo Dev`
- Bundle ID：`com.wintion.yundo.dev`
- 版本：`1.0.0+10000` 或后续递增版本

Android Debug 使用 `com.wintion.yundo.dev`，并通过独立的 Debug 应用名和 Application ID 与正式版隔离。本阶段只校验身份配置，不开始 Android 功能开发。

## 内测包

只有源码工作区 clean 时，才生成可追踪内测包：

```bash
scripts/package_macos_internal_test.sh
```

脚本会检查显示名、Bundle ID、版本、架构和签名，生成 ZIP、SHA-256 与 manifest。验收时 manifest 必须包含：

```text
source_state=clean
```

`build/` 下的 App、ZIP、校验文件和 manifest 均为本地产物，不提交到仓库。
