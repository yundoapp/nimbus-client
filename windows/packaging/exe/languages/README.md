# Windows 安装器补充语言文件

云渡 Windows EXE 安装器与 App 当前支持的 11 种语言保持一致。波斯语和印尼语属于 Inno Setup 官方翻译页列出的贡献翻译，因此固定随仓库保存。

- 上游仓库：`jrsoftware/issrc`
- 固定提交：`c495623a97376d524f298b1b160e8fd612375c62`
- 文件：`Files/Languages/Unofficial/Farsi.isl`、`Files/Languages/Unofficial/Indonesian.isl`
- 许可证：见同目录 `LICENSE.txt`

`scripts/prepare_windows_installer_languages.ps1` 会在构建 EXE 前将这两个文件复制到 Inno Setup 的 `Languages\Unofficial` 目录。GitHub Windows runner 预装的 Inno Setup 不一定包含全部官方翻译；脚本发现官方语言文件缺失时，会从上述固定提交下载，并通过仓库内固定的 SHA256 校验后使用。
