# 客户机兼容：本场只保 Win10/11 x64，其余先探测后补

编号 0008。回答：「所有电脑插上这支 U 盘会不会有兼容 / 依赖问题？那些不兼容怎么处理？」

背景：U 盘密封运行时（[ADR-0005](0005-usb-baked-dsh-runtime.md)）已经做到客户机零安装——盘上自带 x64 `node.exe` + 扁平 dsh，离线诊断只用系统自带的 PowerShell 5.1。主路径是修机现场的普通 Win10/11 x64。评委机和演示按这条交。下列边缘机型**本场不实现能力补齐**，赛后按阶段做。

**Status:** accepted

## 决策

1. **本场交付范围不变。** 正式支持 = Windows 10/11、64 位 Intel/AMD。不装 VC++、不改 Defender、不提权、不改系统 PATH、不重定向 `USERPROFILE`/`HOME`。
2. **TUI 起不来时，离线诊断必须还能用。** `诊断.cmd` / `清理预览.cmd` 是地板，不依赖 Node。
3. **先探测 + 中文说明，再考虑双份运行时。** 多数现场用不到第二份 `node.exe`。
4. **不要为了兼容去关安全软件或自动 UAC。**

跟踪票：[#53](https://github.com/23xxCh/Only-U/issues/53)。**本场不实现下面任何阶段的代码。**

## 本场已成立、不要再当缺口

| 点 | 现状 |
|---|---|
| 客户机依赖 | 不需要 Node / pnpm / Git / Python；TUI 用盘上运行时 |
| 盘符 | `%~dp0`，不写死 `F:` |
| 技能 / 插件隔离 | `DSH_HOME` 钉在盘上；`DSH_AGENTS_HOME` 钉在 `portable\.agents-home`，不读客户机 `~/.agents` |
| 没网 | `start.cmd` 已 ping 后拒绝进 TUI，指向 `诊断.cmd` |
| 非管理员 | 诊断能跑；SMART 等读不到就写「无法读取」 |
| 缓存失败 | `%LOCALAPPDATA%\Only-U\cache` 拷失败则 fail-open，直接从 U 盘跑 |

盘上 `node.exe` 是 **x64**。U 盘文件系统是 **FAT32**（刻意）：盘上不能建 junction，缓存建在客户机 C 盘 NTFS。

## 边缘场景与赛后阶段

### 阶段 A — 只报原因（先做，不增加盘上文件）

在 `portable\start.cmd` 启动 Node 前探测，失败原因一句话 + 指向 `诊断.cmd`，不要白屏闪退。

| 探测 | 对用户说 |
|---|---|
| `PROCESSOR_ARCHITECTURE=x86` 且没有 `PROCESSOR_ARCHITEW6432` | 32 位系统，AI 终端不能用。请改用「诊断.cmd」 |
| `PROCESSOR_ARCHITECTURE=ARM64` | ARM 电脑，AI 终端未正式支持。可先试，不行请用「诊断.cmd」 |
| 产品名 / 版本含 S 模式 | 请先退出 Windows S 模式，或用「诊断.cmd」 |
| `node.exe --version` 被拒绝或文件消失 | 杀毒或公司策略拦住了。把 U 盘加入排除后重试；否则用「诊断.cmd」 |
| 没网 | 保持现状，不要改成半残 Agent |

非管理员、中文版 Windows：**不要拦启动**。

验收：Pester 用环境变量 / 假节点模拟上述分支，断言中文提示含 `诊断.cmd`。`.cmd` 仍是 GBK 无 BOM。

### 阶段 B — 中文版性能计数器

`diagnose.ps1` 里 `\Memory\% Committed Bytes In Use` 在中文 Windows 上会找不到。改用 Win10+ 的英文计数器 API（`PdhAddEnglishCounter`），或退回不依赖本地化名字的 CIM。不要维护中英对照表。

验收：中文系统上这条不再无故打印「无法读取」。

### 阶段 C — ARM 双运行时（有 ARM 真机再做）

烤盘同时带 `portable\runtime\node-x64\` 与 `portable\runtime\node-arm64\`。`start.cmd`：ARM64 优先 arm64，失败再试 x64 模拟。Intel/AMD 只用 x64。盘大约 +90MB，FAT32 可接受。没真机不做。

### 阶段 D — 签名与公司机（产品化再做）

给 `node.exe` 和启动器做 Authenticode（EV 更好，减 SmartScreen）。文档写清 Defender 排除与公司机放行。

**禁止**：脚本里关 Defender、自动加排除、一启动就 UAC。

S 模式无法绕过，只能提示退出 S（单向、免费）或走离线诊断。

32 位：Node 新版本基本不再提供 win-x86。阶段 A 说清楚即可，不为 32 位再烤一份运行时，除非以后有明确统计需求。

### 阶段 E — 没网菜单与管理员提示（可选）

没网时 `start.cmd` 出三选一（诊断 / 清理预览 / 退出），不要只 `pause`。不要做本地模型。

诊断结束可加一句「若要看硬盘健康，可右键诊断.cmd → 以管理员运行」。不要强制提权。

## 开工顺序（赛后）

1. 阶段 A（探测文案）
2. 阶段 B（中文计数器）
3. 阶段 E 的没网菜单（若还觉得生硬）
4. 有 ARM 真机再做 C
5. 要上架 / 给陌生客户再用 D

## 明确不做

- 为兼容而在客户机安装运行库或改系统
- 重定向 `USERPROFILE` / `HOME` 来隔离技能（会弄坏对真实用户目录的诊断 / 清理）
- 把「没网开 TUI」做成半残在线 Agent
- 本场为 ARM / 32 位 / S 模式扩正式支持面

## 与既有 ADR 的关系

- [0005](0005-usb-baked-dsh-runtime.md) 仍是烤盘与零安装的准绳；本 ADR 只补「哪些机器正式支持、边缘怎么降级」。
- [0001](0001-software-only-usb-pack.md) 的软件-only 范围不变。
- [0006](0006-agent-permission-tiers.md) 的绿/黄/红不变；兼容探测是启动器的绿级只读检查，不是新的确认门。
