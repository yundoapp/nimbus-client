# 跨平台加速失败诊断

最后更新：`2026-07-19`

## 目标

Windows、macOS、iOS、Android 使用同一条故障处理链路：

1. 将底层失败归类为普通用户能理解的问题。
2. 展示原因和下一步操作，不直接展示底层异常原文。
3. 生成稳定诊断编号、失败码和失败阶段。
4. 首页提供“复制诊断信息”和“上报问题”。
5. 上报前只保留固定白名单字段并再次脱敏。

登录失效、没有套餐和必须更新等明确业务状态继续使用原有产品提示，不作为系统故障上报。

## 诊断编号

平台前缀：

| 平台 | 前缀 |
| --- | --- |
| Windows | `W` |
| macOS | `M` |
| iOS | `I` |
| Android | `A` |
| 未识别平台或跨平台公共错误 | `C` |

当前公共分类：

| 分类 | 编号示例 | 失败阶段 | 用户建议 |
| --- | --- | --- | --- |
| 系统网络权限 | `I-PERM-01` | `SYSTEM_PERMISSION` | 按系统提示授权，未出现提示时检查系统设置 |
| 系统授权 | `M-AUTH-01` | `SYSTEM_AUTHORIZATION` | 完成系统授权，未出现提示时重启设备 |
| 系统组件 | `A-CORE-01` | `CORE_START` | 重启设备后重试 |
| 通知权限 | `A-NOTIFY-01` | `NOTIFICATION_PERMISSION` | 在系统设置中允许通知 |
| 网络冲突 | `M-NET-02` | `NETWORK_CONFLICT` | 退出其他加速类 App 后重试 |
| 连接准备 | `C-PLAN-01` | `PLAN_PREPARATION` | 按 API 产品提示检查网络或登录状态 |
| 配置准备 | `C-CONFIG-01` | `CONFIGURATION` | 检查网络、重新登录后重试 |
| 启动失败 | `W-START-01` | `START` | 重启设备、退出其他加速类 App 后重试 |
| 状态读取 | `I-STATUS-01` | `STATUS` | 停止加速后重试 |

Windows 服务安装、授权、启动和网络组件错误保留更细的既有编号，例如 `W-SVC-01`、`W-SVC-02`、`W-NET-01` 和 `W-NET-02`。

诊断编号用于聚合问题，不包含底层异常原文。已使用的编号不得改变含义；需要细分时新增编号。

## 展示规则

加速启动失败后，首页错误提示必须包含：

- 可理解的原因和建议操作；
- 稳定诊断编号；
- “复制诊断信息”；
- “上报问题”；
- 关闭入口。

用户可见文字不得包含 VPN、TUN、协议、节点配置、订阅或底层服务命令。内部失败码和阶段只出现在复制内容与脱敏上报中。

## 复制与上报

复制内容固定包含：

```text
Yundo acceleration diagnostics
diagnosticCode=I-PERM-01
failureCode=MISSING_SYSTEM_PERMISSION
stage=SYSTEM_PERMISSION
appVersion=1.1.1+10011
platform=ios
osVersion=...
```

配置失败可额外包含稳定、脱敏的结构详情，例如 `detailCode=RULE_SET_INCOMPATIBLE`；不得复制底层解析原文、节点地址或本地路径。Windows 会依据系统注册表 Build 识别 Windows 10/11，避免兼容层产品名造成误判。

问题上报保持与已部署 API 兼容，将诊断元数据写入现有白名单字段 `connectionStatus`：

```text
DISCONNECTED; diagnostic=I-PERM-01; failure=MISSING_SYSTEM_PERMISSION; stage=SYSTEM_PERMISSION
```

同时上报 App 版本、平台、系统版本、规则版本、节点地区代码、套餐状态和流量汇总。客户端不上传密码、令牌、激活码、完整 UUID、连接配置、访问 URL、网页内容、DNS 明细或本机用户路径；自然文本和诊断字段在离开设备前都要经过脱敏与白名单过滤。

问题上报优先使用当前 API 的类别和联系方式字段；若已部署旧 API 明确拒绝这两个新增字段，则自动降级为旧请求结构重试。兼容重试只针对服务端返回的新增字段校验失败，不掩盖其他接口错误。

## 验证

- 平台矩阵单元测试验证同一失败在四个平台得到正确编号。
- 首页组件测试验证错误提示、诊断编号、复制和上报入口。
- 问题上报测试验证诊断序列化及敏感信息过滤。
- App 变更完成后执行全量 Flutter 测试，并完成 macOS 开发版和本机正式版双构建安装验收。
