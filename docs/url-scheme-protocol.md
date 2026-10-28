# macscp:// URL Scheme 协议规范

| | |
|---|---|
| 协议版本 | **v1**（本文档描述 v1 全部语义） |
| 实现方 | macSCP-Revived **≥ 1.2.0**（macOS 15+） |
| 调用环境 | 与 macSCP **同一台 Mac** 上的任意进程（协议经 macOS LaunchServices 路由，不跨机） |
| 通信模式 | **单向、fire-and-forget**：无同步返回值、无回执回调（详见 §7） |
| 用户手册 | [docs/url-scheme.md](url-scheme.md)（面向使用者；语义以本文档为准） |
| 最后更新 | 2026-10-28 |

## 1. 概述

调用方构造一条 `macscp://` URL 并交给系统（`open` 命令、`NSWorkspace`、AppleScript、浏览器等），macSCP 被 LaunchServices 拉起（或激活已运行实例），按 URL 参数打开指定**已保存连接/书签**的文件管理器或终端窗口。

协议设计约束：

- **凭证零暴露**：URL 只携带目标标识（连接名/UUID/书签名），不携带任何主机凭据；密码由 macSCP 在端内从 Keychain 解析。
- **仅限已保存目标**：URL 不能创建到任意主机的临时连接。
- **可禁用**：用户可在 macSCP 设置中关闭 URL 处理（关闭后调用方无法从协议层区分"禁用"与"目标不存在"，均表现为 macSCP 界面弹错误框）。

## 2. URL 语法

```
url        = "macscp://" [ host ] [ "?" params ]
host       = 1*( unreserved / pct-encoded )      ; 规范值为 "open"（大小写不敏感）；空 host 兼容接受；其余值拒绝
params     = param *( "&" param )
param      = name "=" value
name       = "connection" / "bookmark" / "view" / "path" / "new" / <其他>
value      = *( unreserved / pct-encoded )       ; 按 RFC 3986 query 分量编码，UTF-8
```

- scheme 与 host **大小写不敏感**。
- **percent-encoding**：value 中的空格必须编码为 `%20`（`+` 会被当作字面加号）；`&` `%26`、`=` `%3D`、`#` `%23`、`%` `%25` 必须编码；非 ASCII 字符按 UTF-8 编码（如 `项` → `%E9%A1%B9`）。`/` `:` `~` 无需编码。
- 参数顺序无关；同一参数出现多次时，**最后一次出现生效**。
- 未知参数名：**忽略**（写入 macSCP 日志），不影响整条 URL 的处理。

## 3. 参数定义

| 参数 | 类型 | 必填 | 语义 | 非法/边界值处理 |
|---|---|---|---|---|
| `connection` | string | 与 `bookmark` 二选一 | 目标连接。值可解析为 **UUID** → 按 id 全字匹配；否则按连接**名**匹配（大小写不敏感） | 空串视为未提供；未命中 → 错误（§7） |
| `bookmark` | string | 与 `connection` 二选一 | 目标书签。书签名匹配，大小写不敏感，范围是全部连接下的全部书签 | 空串视为未提供；未命中 → 错误 |
| `view` | enum | 否 | `files`（文件管理器，SFTP 与 S3 连接均可用）/ `terminal`（SSH 终端，仅 SFTP 连接） | 缺省 = `files`；大小写不敏感；**其他任何值 → 整条 URL 拒绝** |
| `path` | string | 否 | 远端起始目录。支持绝对路径、`~`、`~/…`；`view=files` 下相对路径按根目录 `/` 解析 | 空串视为未提供；见 §5 的按 view 差异 |
| `new` | enum | 否 | `1` / `true` / `yes`（大小写不敏感）→ 强制新窗口 | 其他任意值（含 `0`/`false`）= 关闭 |

`connection` 与 `bookmark` **同时出现 → 整条 URL 拒绝**；两者都缺失 → 整条 URL 拒绝。

## 4. 目标解析规则（确定性顺序）

1. **UUID 判定**：`connection` 值能被解析为 UUID（`UUID(uuidString:)` 语义，大小写均可）→ 按 id 全字匹配已保存连接；未命中 → 错误。
2. **按名匹配**：否则按连接名匹配（大小写不敏感）。命中 0 个 → 错误；命中 **多于 1 个** → macSCP 弹出**候选选择列表**（列出命中的连接），用户选择后继续，取消则中止——协议层对此无感知（§7）。
3. **书签匹配**：`bookmark` 按名匹配全部书签（大小写不敏感）。0 命中 → 错误；多命中 → 同样弹选择列表（候选按书签所属连接去重）。命中后目标 = 该书签所属连接；连接已删除 → 错误。
4. **协议可行性**：`view=terminal` 且目标为 S3 连接 → 拒绝（错误）；`view=files` 对 SFTP/S3 均有效。

## 5. 起始路径（优先级从高到低）

| 优先级 | 来源 | 适用 |
|---|---|---|
| 1 | `path` 参数 | 两种 view |
| 2 | 命中书签的 `remotePath` | 仅 `bookmark` 方式 |
| 3 | 连接自身的 Initial Remote Path 设置 | 仅 `view=files` |
| 4 | 服务端默认（home） | 兜底 |

按 view 的差异：

- **`view=files`**：路径原样交给 SFTP/S3 会话解析（`~` 由远端展开）。目录不存在时窗口仍打开，文件列表区显示错误——**启动本身不算失败**。
- **`view=terminal`**：路径经 shell 转义后作为 PTY 首条输入（`cd …`，与用户手敲等价）。路径含控制字符（C0/C1/DEL）时**该路径被忽略**，回退到服务端默认 home（注意：不是回退到书签路径）；其余 shell 元字符由实现方转义，调用方无需处理。

## 6. 窗口与启动行为（契约）

| 场景 | 行为 |
|---|---|
| 未带 `new`，同（连接， view）已有窗口 | **激活**既有窗口置前；本次 `path` **不生效**（窗口保持原位置） |
| 未带 `new`，窗口已关闭 | 以当前参数新开窗口 |
| `new=1` | 总是新开窗口 |
| 终端窗口与文件管理器窗口 | 各自独立跟踪，互不复用 |
| macSCP 未运行（冷启动） | App 启动后处理该 URL（URL 先入队，不丢失） |
| 运行中但无任何主窗口 | 自动重开主窗口后处理 |
| 一次事件携带多条 URL | 按到达顺序逐条处理 |

## 7. 错误与可见性

**v1 无任何回执机制**：调用方拿不到退出码、回调或状态查询接口。结果只体现在 macSCP 的界面上——新窗口、既有窗口激活、错误对话框、或候选选择列表。这是有意为之（不向本机任意进程暴露查询接口）。

错误均以 macSCP 主窗口的对话框呈现。当前版本的错误文案（供支持沟通参考，随版本可能微调）：

| 文案 | 触发条件 |
|---|---|
| The URL must specify a 'connection' or 'bookmark' parameter | 缺少目标 |
| The URL must not specify both 'connection' and 'bookmark' | 目标冲突 |
| Unknown URL scheme '…' (expected 'macscp') | 非 macscp:// 的 URL 被直接投递给 App |
| Unsupported macscp URL '…' (expected 'open') | host 不是 `open` |
| Unknown view '…' (expected 'files' or 'terminal') | view 值非法 |
| No saved connection named '…' / with id … | 连接未命中 |
| No saved bookmark named '…' | 书签未命中 |
| The bookmark '…' belongs to a connection that no longer exists | 书签悬挂 |
| A terminal is only available for SFTP connections | S3 + terminal |
| Launching macSCP from URLs is disabled in Settings | 用户已禁用 |

安全闸门与手动连接完全一致：若用户开启了 Touch ID / App Lock，外部拉起同样被拦截，直到通过认证。

## 8. 版本与兼容性承诺

- 本文档为 **v1**。后续版本的兼容规则：
  - **新增参数**不会改变既有参数语义；
  - 未知参数始终忽略 → 调用方**可以**在 URL 中安全附加自定义参数（不保证生效，不报错）；
  - 已有参数的取值集合只增不减。
- 调用方最佳实践：
  - 只发送本规范定义的参数；
  - **不要**在 URL 中放入任何敏感信息（URL 全文会写入 macSCP 日志，也可能进入调用方的 shell/浏览器历史）；
  - 不要假设连接名稳定——需要防改名请用 UUID（可在 macSCP 设置 → URL Scheme 的示例中获取）。

## 9. 调用方式速查

```sh
# shell
open 'macscp://open?connection=web-prod&view=terminal&path=/var/log'
```

```applescript
open location "macscp://open?connection=web-prod&view=terminal"
```

```swift
NSWorkspace.shared.open(URL(string: "macscp://open?connection=9F0B2A2E-5B13-434E-9FA6-89D75CFF69B4")!)
```

Shortcuts 用 *Open URLs* 动作；Alfred/Raycast 用 open-URL 类命令；浏览器地址栏输入会先弹确认框。

## 10. 参考实现

接收端实现位于 macSCP-Revived 仓库：`macSCP/Core/ExternalLaunch/`（解析 `ExternalLaunchRequest.swift`、队列 `ExternalLaunchQueue.swift`、终端路径转义 `ExternalLaunchSupport.swift`）、`macSCP/App/AppDelegate.swift`（入口）、`macSCP/Features/Connections/ConnectionListViewModel.swift`（解析路由）。
