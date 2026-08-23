# Only-U 项目完整文档

> **文档性质**：本文由 `docs/` 下全部既有文档（plan / prd / 设计 / ADR / 调研 / 评估 / 协作约定）汇总而成，生成于 2026-08-22，供新成员、合作者与评委快速了解项目全貌。
>
> **本文不是新的开发基线。** 实现与演示以 [`plan.md`](plan.md) + [ADR-0002](adr/0002-canonical-hackathon-scope.md) + [ADR-0005](adr/0005-usb-baked-dsh-runtime.md) 为准；本文内容如与基线文档冲突，以基线文档为准。文档权威链与读序见 [`README.md`](README.md)。

---

## 1. 项目概览

| 项目 | 内容 |
|---|---|
| 项目名称 | Only-U |
| 一句话定位 | 给开发者 / 运维 / 搞机的人用的、合法合规的**即插即用 U 盘运维 Agent** |
| 仓库 | https://github.com/23xxCh/Only-U |
| 赛事 | 赤兔 AI 黑客松 · 产品赛道「单人成军」· 深圳湾万丽 · 一天半开发 + 半天评奖 |
| 需求来源 | 微信群「突击深圳黑客松」聊天记录（2026-08-14 ~ 08-22，812 条），已蒸馏归档 |
| 团队 | 队长（需求调研 + 架构，写 plan / ADR / Issue 正文）+ 两名合作者（写代码、开 PR）：@BugCuddler、@yandifei；第四人可能无法到场，交付不绑定其身上 |
| 目标平台 | Windows 10/11 优先；macOS / Linux 本场不做 |
| 交付形态 | 软件 **U盘包**（`portable/`），无线网卡路径赛后再做 |
| 技术基座 | DeepSeek Harness（npm `@deepseek-ai/dsh`，仓库 `dsh/` 源码快照烤盘用）+ dsh-TUI 终端壳（npm `@deepseek-harness-tui/dsh-tui` 0.8.8，仓库 `dsh-tui/` 为同源 0.8.8 源码快照） |

**产品是什么**：把 DSH 内核与 dsh-TUI 终端壳做成 **U盘包**——用户不会装 Agent、不会配 Skill/MCP，插上就能修常见电脑问题（诊断 + 带误删防护的清理）。

**不是什么**：网安后门、Kali、BadUSB、近源渗透、自媒体爬虫、抖音/小红书全自动运营（群里提过，均已判越界或一天半做不完，见 §4 与 [`plan.md`](plan.md) 第 8 节）。

---

## 2. 背景与需求依据

### 2.1 真实痛点（队长实习/学校修机经历）

队长曾把 Claude Code 放在 U 盘中，在学校和公司处理过几十台电脑（一个月几十台机）。证明「U 盘中的通用 Agent」有真实需求，也证明直接把开发工具复制到 U 盘并不等于产品化：仍需熟练命令行、预配模型与网络、判断权限、控制删除范围。常见故障集中在 **C 盘满、卡死、打印机驱动、蓝屏**。

### 2.2 公开调研数据（详见 [`调研-电脑运维与维修需求.md`](调研-电脑运维与维修需求.md)）

- 维修工单七八成是软件问题，且约 80% 用户自查即可解决——正好是 Only-U「诊断 + 清理」的覆盖区。
- 海外维修来电排行（RESCUECOM）：Windows 系统/应用问题 57%、病毒/弹窗 11.3%、打印机 7.5%、卡顿 7.0%、网络 4.7%、无法开机/蓝屏 3.0%。
- 国内桌面运维最常见：**C 盘满排第一**，其次蓝屏、无声、网络异常。
- 用户最大痛点不是「不会修」，而是**怕删错文件**、被「一键清理」工具反伤（实测误删系统缓存后开机慢 20–40 秒）。
- 专业判断硬指标：C 盘剩余 10%–15% 警戒线、磁盘使用 80% 性能拐点、启动项堆积、驱动冲突（约占卡顿原因 27%）。

### 2.3 需求蒸馏原则

聊天原文既含真实需求，也含比赛讨论、临时想法、越界的后门/网安设想和已被否决的硬件方向。工程蒸馏：保留真实维修痛点、U 盘便携、普通用户易用、驱动/蓝屏/文件/安全等需求；把未购买硬件、无网运行、跨平台和违法高风险能力明确移出 V1 或永久禁止。原始记录归档于 [`requirements-source/突击深圳黑客松_聊天记录.md`](requirements-source/突击深圳黑客松_聊天记录.md)（含敏感信息，处置见 §11，勿复制传播）。

---

## 3. 用户与场景

- **用户结构（设计参考，出自归档长 PRD）**：约 70% 为 IT、桌面运维、开发者等技术用户；约 30% 为普通电脑用户。界面双层：普通用户看得懂（说人话、先结论后证据），技术用户可展开专业细节（命令、退出码、事件 ID、设备实例）。
- **核心场景（MVP 三件事，均只读，除非用户确认清理）**：
  1. C 盘满
  2. 卡顿/内存（进程/启动项线索，不自动杀进程）
  3. 打印机 + PnP 驱动缺失（只列出，不安装）
- **覆盖区**：诊断 + 清理（核心）、启动项/后台/驱动冲突排查（只读 + 建议）、蓝屏（只读近期错误，不修）、打印机（只报告）。
- **范围外（明确拒绝 + 引导送修）**：杀毒、重装系统、BIOS/黑屏、硬件维修；硬盘异响/烧焦味/进水要**主动提醒立即断电送修**。

---

## 4. 产品范围（已拍板）

来自 [`plan.md`](plan.md) 第 2 节与 [ADR-0002](adr/0002-canonical-hackathon-scope.md)：

| 做 | 不做（本场） |
|---|---|
| 软件 **U盘包** | **无线网卡路径**（无现货，赛后再做，ADR-0001） |
| Windows 优先 | Mac / Ubuntu 现场适配 |
| CLI / 离线脚本；有网用 **TUI 路径**（dsh-TUI） | 以 Web UI 或 TUI 当无网唯一入口 |
| DeepSeek API（环境变量 Key） | 本地大模型 |
| **诊断** + 带 **误删防护** 的 **清理** | 杀毒全家桶、重装系统、修 BIOS/黑屏显示器 |
| DSH **插件** / skill，不改 harness 内核 | Fork 改 harness 内核、vendor harness 源码 |

**无网边界**：无网走 **离线路径**，只跑本地 **诊断**（`portable\diagnose.cmd`）；有网走 **TUI 路径**（`dsh --profile dsh-tui`），Agent 按预览做 **清理**。不要把「没网就不能诊断」当成产品承诺（该条款出自队友长 PRD，已被 ADR-0002 否决）。

**群聊里砍掉的东西**（避免返工）：免驱网卡 + 流量卡（延期）、跨平台/黑屏/BIOS/重装（超出时间盒）、远程千里修机、自媒体/小红书自动化（合规风险）、后门/网吧破解/BadUSB（不做）、运维 + 自媒体一个安装包（定位不清）。

---

## 5. 产品设计（已批准：Approach B）

来源：gstack `/office-hours`，队长 2026-08-22 批准，见 [`designs/only-u-hackathon.md`](designs/only-u-hackathon.md)。

**Whoa（评委记住的一件事）**：插上，双击，诊断报告出来。这台电脑上没有安装步骤。清理永远先预览。有网才打开 **TUI 路径**，用自然语言走同一套脚本。

| 方案 | 内容 | 本场 |
|---|---|---|
| A 脚本即产品 | 只演 diagnose/clean，Agent 只在讲稿 | 保底 |
| **B 脚本地板 + TUI 调同一脚本** | 双击诊断；有网 `start.cmd` 包装 `dsh --profile dsh-tui` 调同一套 ps1，确认后才 `-Execute`；失败退回 A | **已选** |
| C TUI / 本地 Web 作为无网唯一入口 | 没编过 DSH 就演不了 | 本场不做 |

关键原则：**清理逻辑不写两份**——TUI 里的 Agent 调的就是 `portable\clean.ps1`，与离线预览同一套脚本。B 的地板等于 A，DSH 挂了演示仍成立。

### 3 分钟评委演示（目标流程）

1. 插 U 盘（或打开仓库里的 `portable/`）。
2. 无网或 DSH 没编好：跑 `portable\diagnose.cmd`，当场看到 C 盘空间、临时目录、近期错误、打印机。
3. 跑 `portable\clean.cmd` **预览** 可回收量；说明桌面/文档/下载不会动。
4. 有网且 DSH 能启动：`portable\start.cmd` 拉起 **TUI 路径**（盘上 `runtime\dsh` + `--profile dsh-tui`）。对 Agent 说「C 盘满了，帮我看看」；Agent 读 `CONTEXT.md` 和 skill `only-u-ops`，复述预览，**等人确认才 -Execute**。
5. 讲稿收束：即插即用、普通人不用装 Agent、安全清理。无线网卡是下一阶段。

**成功标准**：任意 Win 机无网能出诊断；清理默认预览、`-Execute` 只打白名单临时目录；DSH 挂了演示仍成立；评委能复述「不用安装、不敢乱删」。

---

## 6. 架构

### 6.1 双路径总体形态

```text
评委/用户
 ├─ 无网（离线路径）: portable\diagnose.cmd / clean.cmd（预览）
 └─ 有网（TUI 路径）: portable\start.cmd
     └─ dsh CLI（盘上密封运行时，不读客户机环境）
         └─ profile: dsh-tui（含插件）
             ├─ bundle: @deepseek-ai/dsh-base（DSH 服务层）
             └─ bundle: @deepseek-harness-tui/dsh-tui（TUI 表面）
                 └─ skill: only-u-ops（Only-U 运维能力）
                     └─ 只调 portable\*.ps1（与离线路径同一套脚本）
```

要点：

- dsh-TUI 本身是 harness 之上的**纯插件**（零内核改动）：会话日志、模型调用、工具执行、fork/resume、compaction、持久化都由 DSH 服务层拥有；TUI 只做终端交互与呈现。
- 会话与数据全部落在 `$DSH_HOME`（U 盘上由 `start.cmd` 指向 `portable\runtime\dsh`），不污染评委机。
- Windows 无沙箱后端时（dsh-TUI 在 win32 回落 `danger-full-access` + 免审批），**安全边界放在脚本层**：白名单 + 预览确认；演示时人盯。

### 6.2 仓库布局

```text
Only-U/
  CONTEXT.md                 领域用语（术语表）
  AGENTS.md                  agent 入口
  docs/plan.md               比赛计划（开发基线）
  docs/adr/                  已拍板决策（ADR 0001–0007）
  docs/agents/               GitHub Issues / triage 约定
  portable/                  U盘包：启动、离线诊断/清理
  .dsh/skills/only-u-ops/    给 DSH 读的运维 skill
  dsh/                       Harness 源码快照，烤盘用（ADR-0005，不要删）
  dsh-tui/                   dsh-TUI 0.8.8 源码快照，默认只读；U 盘跑的是 npm 插件不是这份目录
  wxcontext/                 微信导出，已 gitignore，禁止推 GitHub
  scripts/bake-usb.ps1       烤盘一键脚本
```

### 6.3 U 盘密封运行时（ADR-0005，已采纳的交付方式）

客户机没有 Node、pnpm、全局 `dsh`，且本场 U 盘是 FAT32（不能存 pnpm 符号链接，整包拷 `dsh/node_modules` 会把 1.3GB 涨成数 GB）。

**两台机器，两套目录**：

| | 开发机 | 客户机（评委/修机现场） |
|---|---|---|
| 要什么 | Git、Node 22+、pnpm、已 `pnpm run build` 的 `dsh/` | 只要 Windows + PowerShell |
| 干什么 | 写脚本、写 skill、写 Cordis 插件、烤盘 | 双击 `诊断.cmd` / `启动Agent.cmd` |
| 禁止 | 在客户机 `pnpm install`、TUI 里 `/update` | 往客户机装 Node / 改系统 PATH |

**U 盘目录结构**：

```text
U盘:\Only-U\
  Start-Agent.cmd / 启动Agent.cmd / 诊断.cmd / 清理预览.cmd
  （.cmd 必须是 GBK/ANSI，不能是 UTF-8 BOM，否则 cmd.exe 双击闪退）
  CONTEXT.md
  portable\
    diagnose.cmd  diagnose.ps1
    clean.cmd     clean.ps1
    start.cmd                 ← 只调盘上 Node + 盘上 CLI
    .env                      ← Key，不进 Git
    runtime\
      node\node.exe           ← 便携 Node（不改客户机 PATH）
      dsh\                    ← pnpm deploy 出的扁平 CLI（约 180MB）
        lib\bin.js
        node_modules\         ← 无符号链接的生产依赖
        profiles\dsh-tui\     ← TUI profile（含插件）
        skills\only-u-ops\
```

**start.cmd 核心**（设 `DSH_HOME` 指向盘上 runtime，用盘上 node.exe 启动 `lib\bin.js --profile dsh-tui`）：

```bat
set "PATH=%~dp0runtime\node;%PATH%"
set "DSH_HOME=%~dp0runtime\dsh"
"%~dp0runtime\node\node.exe" "%~dp0runtime\dsh\lib\bin.js" --profile dsh-tui
```

**烤盘流程（只在开发机）**：

1. `cd dsh && pnpm install && pnpm run build`
2. `pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui`
3. 打扁平 CLI：`pnpm --filter @deepseek-ai/dsh deploy --legacy --prod --config.node-linker=hoisted ... %TEMP%\only-u-dsh-deploy`（再把 override 的 vendor 包拷进 deploy 的 `node_modules\@deepseek-ai\`）
4. 拷便携 `node.exe`、拷 `%USERPROFILE%\.dsh\profiles\dsh-tui` → 盘上
5. 一键脚本：`powershell -File scripts\bake-usb.ps1 -Dest F:\Only-U`

`portable/runtime/` 不进 Git。FAT32 不能建 NTFS junction：对盘上 `dsh-app-boot` 的 `ensureSymlink` 在 `EISDIR`/`EPERM` 时跳过（只改 U 盘副本，不改仓库 `dsh/`）。

### 6.4 能力三层挂法（由浅到深）

1. **离线脚本** `portable\*.ps1` — 没 Node 也能跑（诊断地板）
2. **skill** `.dsh/skills/only-u-ops` — TUI 里让 Agent 去调这些脚本
3. **Cordis 组合包**（二次开发）— 独立 npm 包（放 `plugins/<name>/`，声明 `dsh.bundle`），开发机装进 profile 再烤盘，**不改 `dsh/` 内核**

### 6.5 模型与凭据

- Key 只放 `portable\.env`（gitignore；模板 `portable/.env.example`：`DEEPSEEK_API_KEY=` + 可选 `DEEPSEEK_BASE_URL=` 指向 AI Ping）。真实 Key 永不进 Git、日志、文档、会话。
- 归档长 PRD 曾给过发布基线：AI Ping Base URL `https://aiping.cn/api/v1` + 文本模型 `DeepSeek-V3.2`（该文档已降级为需求证据，不是本场基线）。
- 启动器已实现交互式兜底：`portable\.env` 不存在或 Key 为空时，中文提示粘贴 Key（SecureString 隐藏输入），写入 `.env` 后再启动；已有非空 Key 直接启动，不重复询问。

---

## 7. 关键决策（ADR 一览）

| ADR | 决策 | 状态 |
|---|---|---|
| [0001](adr/0001-software-only-usb-pack.md) | 比赛只交付软件 **U盘包**，**无线网卡路径** 明确延期（无现货、一天半做不完硬件） | accepted |
| [0002](adr/0002-canonical-hackathon-scope.md) | 以队长当前方案为开发基线；队友长 PRD / 设计规格降为需求证据，不覆盖 `plan.md` | accepted |
| [0003](adr/0003-dsh-tui-agent-shell.md) | 有网 Agent 壳用 dsh-TUI 插件（`dsh --profile dsh-tui`），不用 headless、不以 Web 为主入口 | accepted |
| [0004](adr/0004-dev-base-dsh-tui.md) | 开发基座从 vendored harness 切到 dsh-TUI（npm 分发，不 vendor、不本地构建内核） | superseded for USB delivery（被 0005 部分覆盖；`dsh/` 源码快照保留供烤盘） |
| [0005](adr/0005-usb-baked-dsh-runtime.md) | **U 盘密封运行时**：`pnpm deploy` 扁平 CLI + 便携 node.exe；FAT32 约束与烤盘流程（**U 盘交付的已采纳做法**） | accepted |
| [0006](adr/0006-agent-permission-tiers.md) | Agent 权限三级模型：🟢只读全自动 / 🟡可逆会话级授权 / 🔴不可逆逐项确认；按可逆性定门禁，不按危险感 | accepted |
| [0007](adr/0007-third-party-tools-policy.md) | 第三方工具政策：PowerShell 优先，够不着才包单工具插件（能力不可达 + 授权可商业重分发 + 机器可读接口三条件）；不搬图吧工具箱 | accepted |

**ADR-0006 三级模型**（赛后扩容的治理框架，V1 不改代码——现状已符合）：

| 级 | 定义 | 门禁 |
|---|---|---|
| 🟢 绿 | 只读，无副作用 | 全自动，不打扰 |
| 🟡 黄 | 可逆操作（回收站删除、重启服务、禁用启动项等） | 会话级授权一次，之后同类不再问 |
| 🔴 红 | 不可逆 / 系统级改动（永久删除、装驱动、改注册表等） | 逐项确认 + 预览 + 日志 |

三条原则：让动作可逆好过加确认；预览清单即确认材料；门要少而准（门越多用户越盲点确认）。

**文档权威链**（防止漂移）：`CONTEXT.md` → `docs/plan.md` → `docs/designs/only-u-hackathon.md` → `docs/adr/` → `docs/agents/`。显式声明「哪些文档不是实现依据」：长 PRD（`Only-U-项目需求文档.md`）、`prd.md`、`superpowers/specs/` 只作需求证据或路线笔记。

---

## 8. 实现现状（截至 2026-08-22，依据各评估报告复评二）

### 8.1 任务切片与 Issue/PR 状态

plan.md 第 5 节五张切片：便携启动、离线诊断、安全清理、DSH 接线、演示机+讲稿。已知进展：

| 切片 | Issue | 分支 | PR | 状态 |
|---|---|---|---|---|
| 便携启动 | #1 | `feat/1-portable-start-baked-node` | PR #4 | ✅ 已合入 main（bfb5c0f）：fail-fast 检查 node.exe / bin.js / profile、SecureString 隐藏输入 Key、写 `portable\.env`、DSH_HOME 指向盘上 runtime，附 298 行自研测试（csc 编译 StubNode 假 node.exe，GBK 验证 .cmd 编码） |
| 离线诊断（扫描上限） | #2 | `feat/2-diagnose-scan-cap` | PR #5 | ✅ 已合入 main（5c040cf）：TEMP 目录 8 秒 / 20,000 文件上限、可取消 Start-Job、跳过重解析点、拒绝 UNC、PnP 用 `ConfigManagerErrorCode` 精确过滤 |
| 诊断关键指标 | #6 | `feat/6-diagnose-key-metrics` | PR #10 | 🟡 已推送、PR 待合入：提交内存 %（Get-Counter）、pagefile、SMART、事件按 Provider+Id 收紧、顶部红灯区、Pester 7/7 通过，实机 4.4–5.1 秒 |
| 安全清理（白名单+日志重写） | #8 | `feat/8-clean-whitelist-log` | PR #12 | 🟡 已推送、待评审：clean.ps1 重写为 5 类白名单 + 年龄门 + 日志（+324 行），Pester 4/5（1 项失败为评估环境抽取缺文件，非代码问题） |
| DSH 接线 / 烤盘 | — | — | — | 🔴 **从未执行**：`dsh/` 从未 build、`portable/runtime/` 从未生成、盘上 TUI 从未启动——当前最高优先级缺口 |
| 演示机 + 讲稿 | — | — | — | HITL（人在场），进行中 |

协作管线运转正常的证据：Issue #2→PR #5、Issue #1→PR #4 均已合并；#6→PR #10、#8→PR #12 待评审；各票严格按票面执行、未碰他人文件、未扩到 Web/工单。

### 8.2 诊断脚本能力（`portable/diagnose.ps1`，约 300 行）

- **扫描纪律**：每个 TEMP 类目录 8 秒或 20,000 文件上限；先「正在扫描」再扫，超限「跳过：太大或超时」；全程目标 ≤60 秒（实测 4.4–5.1 秒）；跳过重解析点、拒绝 UNC 根路径；逐数据源降级（读不到写「无法读取」，不崩）。
- **采集段（全部只读）**：磁盘（C 盘 <15% 警告、<10% 高危）、内存（总量/已用、`% Committed Bytes In Use`，>75% 预警、>85% 高压）、TOP5 进程（按 Commit 排序，同时显示 Working Set，不 kill）、启动项数量、近期 System 错误、打印机（驱动版本/服务状态/队列）、PnP 驱动异常（`ConfigManagerErrorCode`，只列出不安装）。
- **关键事件收紧**：只列近 7 天的低虚拟内存（2004）和真实磁盘/存储来源的 7、129、153、157 事件（Provider 白名单 `storahci|stornvme|iaStor.*|Disk`），不把 Hyper-V/网络事件误报为存储故障；展示上限 20 条。
- **SMART**：尽力读 `Get-PhysicalDisk` 健康状态与 `Get-StorageReliabilityCounter`（读错误、温度）；刻意不取序列号等敏感标识；不可读时优雅降级。
- **红灯区（置顶，仅命中时显示）**：C 盘剩余 <5% 或 1GB、已提交内存 >90%、事件 2004、7 天内 129/153 ≥3 次、SMART 异常。阈值用未四舍五入原始值判定，显示才保留一位小数（防边界漏报）。

### 8.3 清理脚本（`portable/clean.ps1`，PR #12 重写版）

- **默认预览**；`-Execute` 才执行；桌面/文档/下载/图片永在保护根（前缀匹配）。
- **5 类白名单 + 年龄门**：TEMP（4 个临时目录，7 天门）、缩略图缓存（系统自动重建）、WER 报告（**建议加年龄门，如 30 天**——崩溃转储是查蓝屏的证据）、Windows Update 下载缓存（注明需重下）、回收站（⚠️ 与 ADR-0006「可逆好过加确认」精神相悖，评审时需拍板去留/降级为默认不勾选）。
- `-Execute` 后写 `portable\logs\clean-时间戳.log`（删除路径清单，留在 U 盘不上传）；计划/实际偏差 >10% 打 WARNING；空目录清理跳过 reparse point；锁定文件跳过计数。

### 8.4 编码与测试规范

- **三种文件三种编码**（已进测试门禁）：`.cmd` GBK/ANSI 无 BOM（UTF-8 BOM 会让资源管理器双击闪退）；`.ps1` UTF-8 带 BOM（PS 5 兼容）；运行期 `[Console]::OutputEncoding = UTF8`。
- **测试**：`portable/tests/diagnose.Tests.ps1`（Pester，7/7）、`clean.Tests.ps1`（5 用例）、启动器 298 行自研测试。已知弱点：个别用例是「源码 grep」型（锁实现细节）且依赖宿主环境；Pester 建议固定用 pwsh 跑（3.4 太老）。
- **已知小问题**：main 上 start.cmd 的 `ping 223.5.5.5` 网络门在酒店/企业网络常被 ICMP 禁用而误判「无网」，且每次启动白等最多 2 秒——**建议烤盘前删掉或改 HTTPS 探测**；bake-usb.ps1 内嵌了一份 start.cmd here-string，与仓库版是两份副本，需同步维护。

---

## 9. 协作模式

本项目采用 **「规范基线 + 票驱动的多智能体协作开发」**：文档权威链（CONTEXT → plan → designs → ADR）→ Issue 分诊看板 → AFK agent 实现 → 分支 + PR 集成 → TDD 保障 → 演示驱动验收。详见 [`项目评估/开发模式分析.md`](项目评估/开发模式分析.md) 与 [`项目评估/开发模式二次评估.md`](项目评估/开发模式二次评估.md)。

### 9.1 角色分工

- **队长**：需求调研 + 架构（写 plan / ADR / Issue 正文）。
- **两名合作者**：只写代码、开 PR——实际实现交给各自的 agent（Grok / Claude Code / Codex），人负责贴「开工提示词」和 review PR。
- 切片标注 **AFK**（agent 全自动）或 **HITL**（人盯，如演示机 + 讲稿）。

### 9.2 Issue 流水线

```
/grill-with-docs（对齐术语，写入 CONTEXT.md）
→ /to-prd（PRD 发 GitHub Issue）
→ /to-issues（拆垂直切片）
→ /triage（打标签）
→ 认领 → feat/N-短名 分支 → PR（Closes #N）→ review → 合入 main
```

技能基座：[mattpocock/skills](https://github.com/mattpocock/skills)；Issue 用 `gh` CLI 操作（约定见 [`agents/issue-tracker.md`](agents/issue-tracker.md)）。

**标签五态**（agent 靠这个判断能不能动手，见 [`agents/triage-labels.md`](agents/triage-labels.md)）：

| 标签 | 含义 | 别人的 agent 该怎么做 |
|---|---|---|
| `needs-triage` | 还没评估 | 不要做 |
| `needs-info` | 在等补充 | 不要做 |
| `ready-for-agent` | 规格够了 | **可以做** |
| `ready-for-human` | 必须人判断/在场 | 人盯着做 |
| `wontfix` | 不做 | 不要做 |

`ready-for-agent` 门禁：有「做什么」和验收标准；依赖写清（Blocked by #几 或 None）；不需要现场插 U 盘、产品拍板、账号权限等只有人能做的事。

### 9.3 Git 约定

- 不直接推 `main`；一人一条 `feat/N-短英文名` 分支；一张 Issue 一个 PR，描述第一行 `Closes #N`。
- 分支前缀 `feat/` `fix/` `docs/` `chore/`，带 Issue 号；conventional commits（`feat:` `fix:` `test:` `docs:`）。
- 每天开工先 `git pull origin main`；禁 `push --force`；密钥、`.env` 不进 git。
- 交接物是 **GitHub Issue + 文档**，不是聊天记录；换人/换会话用 `/handoff` 生成的文档贴回 Issue 评论。

### 9.4 开工提示词机制

每张票配一份「开工提示词」（整段粘贴给 agent），内含：必读文档清单（AGENTS.md / docs/README.md / plan.md / 相关 ADR / CONTEXT.md）、领域用词约束（只用 CONTEXT.md 术语）、git 流程、「必须做到 / 不要做什么 / 验证 / 交卷」四段。实例见 [`发给队友1-Issue1-启动器.md`](发给队友1-Issue1-启动器.md)、[`发给队友2-Issue2-诊断上限.md`](发给队友2-Issue2-诊断上限.md)、[`发给队友2-Issue6-诊断关键指标.md`](发给队友2-Issue6-诊断关键指标.md)。任务文档已进化为「活的状态页」：新增「当前状态 / 已交付 / 验证与边界 / 未改动」段，把验证报告和范围纪律写进交接物。

### 9.5 领域术语（速查，全文见 [`../CONTEXT.md`](../CONTEXT.md)）

**U盘包**（插上即可运行的目录）· **运维会话**（一次插盘到拔盘的修机过程）· **诊断**（不调模型也能跑的机器检查）· **清理**（白名单空间回收，必须先预览再确认）· **误删防护**（预览 + 默认不碰用户文档/桌面/下载）· **离线路径**（无网只跑本地脚本，不调 LLM）· **TUI 路径**（有网的终端运维壳，profile `dsh-tui`）· **无线网卡路径**（赛后再做）· **烘焙**（开发机把便携 Node + 扁平 CLI + profile 打进 U盘包）。所有人/agent 不得自造同义词。

---

## 10. 质量与安全设计

### 10.1 安全不变量（所有模式生效）

- **清理一律预览 → 确认**：永不碰桌面/文档/下载/图片；永不碰用户个人文件；禁止通配符扩展到未展示范围、禁止递归删除盘符根/用户资料根/Windows 根。
- **诊断只读**：不修改系统、不调模型、不全盘扫描、不跟到网络路径。
- **skill 铁律**（`only-u-ops` + [`only-u-agent-专业提示词.md`](only-u-agent-专业提示词.md)）：会话开始先跑诊断再跑清理预览；只有用户明确说「确认」「执行」或同等确认才 `-Execute`；不自动执行、不推荐第三方一键清理/注册表清理工具；无网时如实告知「只能诊断、不能清理执行」，不假装存在本地模型；范围外明确拒绝并给替代建议；不做后门、不窃取凭据、不做攻击扫描、不伪造检测结果。
- **沟通规范**：说人话（先结论后证据、数字带单位）；动手前说清「我要做什么 / 影响什么 / 不碰什么」；不承诺「修好」。
- **Key 安全**：只在 `portable/.env`；任何日志不得打印 Key 值、`sk-` 全文、Authorization。

### 10.2 提示注入与执行闸门（对抗性验证结论）

诊断输出中的攻击者可控字符串（进程名、USB 设备名）会进入 LLM 上下文，属已知间接提示注入面，经评估置信度低（2/10）：产品由机主本人在场交互使用；DSH 审批面板真实存在、逐条显示完整命令、Esc 即拒绝、无响应失败关闭（fail-closed）；`clean.cmd -Execute` 目标只在白名单临时目录内。两轮代码安全审查（feat/2、feat/6）均未发现达到上报门槛（置信度 ≥8/10）的可利用漏洞，分支可合入。

### 10.3 第三方工具政策（ADR-0007）

PowerShell 够得着的能力（CPU-Z → `Win32_Processor`、CrystalDiskInfo → `Get-PhysicalDisk`、GPU-Z → `Win32_VideoController` 等）绝不引入第三方工具。不搬图吧工具箱的理由：GUI 无接口（界面自动化脆）、授权雷区（多为个人免费授权，商业重分发违规）、杀软误报、定位错位——拼工具广度是图吧主场，Only-U 的主场是「检测得深 + 解释得清 + 删得安全」。

---

## 11. 合规与风险（摘要，详见 [`项目评估/`](项目评估/) 三份报告）

### 11.1 🔴 P0：公开仓库泄露聊天记录中的活跃凭据与个人信息

`docs/requirements-source/突击深圳黑客松_聊天记录.md` 已随历史提交推送到**公开仓库**，含仍在有效期内的凭据与个人信息：ToDesk 远程控制设备码+临时密码、民宿房门/WiFi 密码（事件进行中）、支付交易号、含身份证复印件的快递描述、35 处以上手机号/wxid/邮箱、参与者真实姓名与学校，以及被否决的攻击工具讨论片段。这不是潜在隐患，是**任何人现在就能使用**的公开暴露，违反 PIPL §13/§25、民法典 §1032/§1034。

**处置（立即执行）**：① 失效 ToDesk 凭据、更换房门密码；② 删除文件并**重写 git 历史**（`git filter-repo`，仅删除不够）或仓库临时转私有；③ 重新归档只保留需求蒸馏结论；④ bake 脚本把 `docs\requirements-source` 加入排除列表。（本文件不复述任何具体敏感值。）

### 11.2 其他高风险

| # | 风险 | 状态与对策 |
|---|---|---|
| H2 | **烤盘全链路零验证**：`dsh/` 从未 build、`portable/runtime/` 从未生成，bake 脚本第一步断言就会失败；烤后校验只跑 `--help` 不带 profile | 今天内完成第一次真实烤盘 + 带 profile 冒烟 + 干净机器实测 |
| H3 | 仓库 start.cmd 与 bake 内嵌副本双份漂移 | 合并/修改时同步两处；给仓库版加交互式 Key 兜底后要同步 bake 的 here-string |
| H4 | Key 缺失，TUI 路径无法启动 | 烤盘前把**限额** Key 放入 `portable\.env`；演示 U 盘明文携带团队 Key，**赛后立即轮换** |
| 中/低 | clean.ps1 junction 穿越（pwsh 7）、预览无上限、bake 脚本编码、SmartScreen/Defender 拦截未签名 node.exe、Get-Counter 计数器名本地化 | 演示机逐项实测；见 [`项目评估/风险评估.md`](项目评估/风险评估.md) |

### 11.3 合规基本面（良好）

- **双用途边界清晰**：产品定位、文档与代码一致排除攻击能力（无驻留/自启动/计划任务、无凭据读取、删除有预览+确认+保护根、诊断纯只读）；刑法 §285/§286 责任附着于未授权使用行为而非工具本身——在他人电脑（公司/学校）上运行时，授权义务在操作者，建议启动横幅补一句「仅限在你有权维护的设备上使用」。
- **数据不出境**：AI Ping 与 DeepSeek 均为境内服务，无跨境合规问题。
- **许可**：上游 dsh / dsh-tui / vendor 包均 MIT，烘焙分发合法（需在分发物保留 LICENSE 与版权声明）；⚠️ 仓库根目录缺自身 LICENSE，建议赛前补 MIT/Apache-2.0 + NOTICE。
- **PIPL 缺口（产品化前必补）**：TUI 路径诊断数据（计算机名/用户名/事件日志原文/进程名/设备名）进第三方模型，缺启动告知与字段级脱敏；黑客松演示机为自有设备，风险可控。

---

## 12. 赛前行动清单（按优先级，来自各评估报告）

1. **P0**：处理聊天归档泄露（失效凭据、重写 git 历史或转私有）。
2. **P0**：`cd dsh && pnpm install && pnpm run build` → 放入限额 Key → 第一次真实烤盘 → 带 profile 冒烟 → 干净机器实测。
3. **P1**：烤盘前删掉 start.cmd 的 ping 网络门（一行改动，消除演示期最大误判点）；bake 排除 `docs\requirements-source`；补根 LICENSE + NOTICE。
4. **P1**：演示机实测：Get-Counter 指标、diagnose 总时长、SmartScreen 拦截、TUI 确认面板；确认 AI Ping Key 的共享条款。
5. **P2**：合入 PR #10（feat/6）；评审 PR #12 拍板回收站类别去留与 WER 年龄门，并同步更新 ADR-0002 的白名单定义；bake 的 boot patch 失配改 fail-fast；clean.ps1 逐文件防护与预览上限；提交 `docs\项目评估\` 作备份。

**总体判断**：代码层（离线脚本）已过两轮审查且质量持续上升，是项目最稳的一层；合规暴露的 P0 必须立即处理；最大剩余风险是**从未执行过的烤盘 → TUI 演示链路**。

---

## 13. 文档地图

### 13.1 读这个顺序（基线）

1. 根目录 [`CONTEXT.md`](../CONTEXT.md) — 领域用词
2. [`plan.md`](plan.md) — 黑客松交付与演示（**本场开发基线**）
3. [`designs/only-u-hackathon.md`](designs/only-u-hackathon.md) — 已批准的产品设计（Approach B）
4. [`adr/`](adr/) — 已拍板决策（0005 是 U 盘交付的已采纳做法；0004 不覆盖 0005）
5. [`agents/`](agents/) — Issue / 标签 / 给合作者 agent 的入口
6. [`../AGENTS.md`](../AGENTS.md) — 所有 agent 的入口

### 13.2 需求证据与参考（不是实现依据）

| 文档 | 性质 |
|---|---|
| [`Only-U-项目需求文档.md`](Only-U-项目需求文档.md) | 长 PRD（41 条 FR + NFR + 里程碑），已降级为痛点与需求蒸馏证据 |
| [`prd.md`](prd.md) | dsh-TUI 路线的需求展开（FR-1~5），路线笔记 |
| [`superpowers/specs/2026-08-22-only-u-design.md`](superpowers/specs/2026-08-22-only-u-design.md) | 队友设计规格，「在线-only、Web 主入口」已被 ADR-0002 否决，保留对照 |
| [`requirements-source/突击深圳黑客松_聊天记录.md`](requirements-source/突击深圳黑客松_聊天记录.md) | 原始聊天归档（含敏感信息，处置见 §11） |

### 13.3 调研、协作与评估

| 文档 | 内容 |
|---|---|
| [`调研-电脑运维与维修需求.md`](调研-电脑运维与维修需求.md) | 公开数据的需求调研（问题频率、痛点、阈值、讲稿弹药） |
| [`only-u-agent-专业提示词.md`](only-u-agent-专业提示词.md) | Agent 角色 system prompt 增强层（铁律、阈值、沟通规范、输出模板） |
| [`发给合作者-如何让他们的agent干活.md`](发给合作者-如何让他们的agent干活.md) | 多 agent 协作流水线与开工提示词总说明 |
| [`发给队友1-Issue1-启动器.md`](发给队友1-Issue1-启动器.md) / [`发给队友2-Issue2-诊断上限.md`](发给队友2-Issue2-诊断上限.md) / [`发给队友2-Issue6-诊断关键指标.md`](发给队友2-Issue6-诊断关键指标.md) | 三张票的任务分派与交付状态 |
| [`项目评估/开发模式分析.md`](项目评估/开发模式分析.md) / [`项目评估/开发模式二次评估.md`](项目评估/开发模式二次评估.md) | 开发模式两轮评估（流程执行核对、TDD 偏差分析） |
| [`项目评估/风险评估.md`](项目评估/风险评估.md) | 两轮风险评估（H/M/L 分级、赛前行动清单） |
| [`项目评估/合法性与安全评估报告.md`](项目评估/合法性与安全评估报告.md) | 代码安全审查 + PIPL/许可/双用途合规评估 |
| [`项目评估/痛点难点调研报告.md`](项目评估/痛点难点调研报告.md) | 痛点难点三轮复评（烤盘链路、编码门禁、PR 评估） |
| [`项目评估/Only-U-演示.pptx`](项目评估/Only-U-演示.pptx)（`make-onlyu-ppt.js` 生成） | 演示幻灯片 |

### 13.4 实现前的三条硬规矩

1. 实现前读 `plan.md` 和 ADR，不要直接按 PRD 开票。
2. 不要删除 `dsh/`；改 `dsh-tui/` 前先读 `dsh-tui/ADAPTER.md`。
3. 领域用词只用 `CONTEXT.md`；真实 Key、微信原文、wxid、邮箱不进仓库。
