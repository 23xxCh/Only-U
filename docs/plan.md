# Only-U 比赛计划

来源：微信群「突击深圳黑客松」2026-08-14～08-22，加上现场决议「现在没有无线网卡，比赛期间不做」。

赛事：赤兔 AI 黑客松，产品赛道「单人成军」，深圳湾万丽，**一天半开发 + 半天评奖**。仓库：https://github.com/23xxCh/Only-U

**本文是本场开发基线。** 后写入库的长 PRD（`docs/Only-U-项目需求文档.md`）与设计规格不是实现依据，冲突条款见 [ADR-0002](adr/0002-canonical-hackathon-scope.md)。有网 Agent 壳见 [ADR-0003](adr/0003-dsh-tui-agent-shell.md)。已批准设计：[designs/only-u-hackathon.md](designs/only-u-hackathon.md)。

**现在不要扩功能。** 先按本文对齐，再写代码。领域用词以根目录 `CONTEXT.md` 为准。架构决策见 `docs/adr/`。文档索引见 [README.md](README.md)。

---

## 1. 产品是什么

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 做成 **U盘包**：用户不会装 Agent、不会配 Skill/MCP，插上就能修常见电脑问题。

真实依据（队长实习/学校修机）：U 盘里跑过 Claude Code，一个月几十台机。常见问题是 **C 盘满、卡死、打印机驱动、蓝屏**。

一句话定位：**给开发者 / 运维 / 搞机的人用的、合法合规的即插即用运维 Agent。**

不是：网安后门、Kali、BadUSB、近源渗透、自媒体爬虫、抖音/小红书全自动运营。群里提过这些，已判越界或一天半做不完。

---

## 2. 已经拍板的范围

| 做 | 不做（本场） |
|---|---|
| 软件 **U盘包** | **无线网卡路径**（无现货，赛后再做） |
| Windows 优先 | Mac / Ubuntu 现场适配 |
| CLI / 离线脚本；有网用 **TUI 路径**（dsh-TUI） | 以 Web UI 或 TUI 当无网唯一入口 |
| DeepSeek API（环境变量 key） | 本地大模型 |
| **诊断** + 带 **误删防护** 的 **清理** | 杀毒全家桶、重装系统、修 BIOS/黑屏显示器 |
| DSH **插件** / skill，不改 harness 内核 | Fork 改 `dsh/` 内核 |

无网：走 **离线路径**，只跑本地 **诊断**。有网走 **TUI 路径**（`pnpm dsh --profile dsh-tui`），Agent 按预览做 **清理**。不要等网卡，也不要部署本地模型。不要把「没网就不能诊断」当成产品承诺。

详见 [ADR-0001](adr/0001-software-only-usb-pack.md)、[ADR-0002](adr/0002-canonical-hackathon-scope.md)、[ADR-0003](adr/0003-dsh-tui-agent-shell.md)。

---

## 3. 评委 3 分钟演示（目标，不是现状清单）

1. 插 U 盘（或打开仓库里的 `portable/`）。
2. 无网或 DSH 没编好：跑 `portable\diagnose.cmd`，当场看到 C 盘空间、临时目录、近期错误、打印机。
3. 跑 `portable\clean.cmd` **预览** 可回收量；说明桌面/文档/下载不会动。
4. 有网且 DSH 能启动：`portable\start.cmd` 应拉起 **TUI 路径**（`dsh --profile dsh-tui`）。开发机可先 `cd dsh && pnpm dsh --profile dsh-tui`。对 Agent 说「C 盘满了，帮我看看」；Agent 读 `CONTEXT.md` 和 skill `only-u-ops`，复述预览，**等人确认才 -Execute**。
5. 讲稿收束：即插即用、普通人不用装 Agent、安全清理。无线网卡是下一阶段。

---

## 4. 仓库怎么放（写代码时才动）

```
Only-U/
  CONTEXT.md                 领域用语
  AGENTS.md                  agent 入口
  docs/plan.md               本计划
  docs/adr/                  已拍板决策
  docs/agents/               GitHub Issues / triage
  portable/                  U盘包：启动、离线诊断/清理
  .dsh/skills/only-u-ops/    给 DSH 读的运维 skill
  dsh/                       Harness 快照，默认只读
  wxcontext/                 微信导出，已 gitignore，禁止推 GitHub
```

插件挂法（实现阶段二选一，先选阻力小的）：

1. `dsh/packages/ops/<plugin>/`，走 DSH cookbook。
2. 根目录 skill + `portable` 脚本（当前骨架已按这条铺了文档入口）。

密钥只放 `portable/.env`（gitignore）。微信原文、wxid、邮箱不进仓库。

---

## 5. 建议的任务拆分（三人，先认领再写）

先开 GitHub Issue，标 `ready-for-agent` 或 `ready-for-human`，再开 `feat/<issue>-…` 分支。不要直接推 `main`。

| 切片 | 内容 | 类型 |
|---|---|---|
| 便携启动 | `portable/start.cmd`、DSH_HOME 在 U 盘、读 `.env` | AFK |
| 离线诊断 | `diagnose.cmd`：磁盘/内存/临时目录/事件日志/打印机，只读 | AFK |
| 安全清理 | `clean.cmd`：预览默认；`-Execute` 只清白名单临时目录 | AFK / 须人确认演示 |
| DSH 接线 | **TUI 路径**（dsh-TUI）+ skill，让 Agent 去跑上述脚本 | AFK |
| 演示机 + 讲稿 | 人为堆高 `%TEMP%`，3 分钟词 | HITL |

第四人若不能到场、赛规可能算远程作弊，交付不要绑在他身上。

**本场明确不拆这些票：** USB 网卡驱动、流量卡、跨平台、重装系统、自媒体自动化。

---

## 6. 协作约定

- Issue：`23xxCh/Only-U` GitHub Issues（`docs/agents/issue-tracker.md`）。
- 标签：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。
- 给别人的 agent：贴 `docs/发给合作者-如何让他们的agent干活.md` 第 3 节，Issue 必须已是 `ready-for-agent`。
- 改 `dsh/packages` 前读 `dsh/AGENTS.md`。Only-U 用词只用 `CONTEXT.md`。
- Windows 上 DSH 全量 build 可能慢：演示保底是 `portable\diagnose.cmd`，不要卡在 website/e2e。

---

## 7. 实现顺序（文档对齐之后才开始）

1. 三人读完本文 + `CONTEXT.md` + ADR-0001，口头确认演示词。
2. `/to-issues` 把第 5 节五张切片发到 GitHub（无线网卡不要开票）。
3. 按票实现；先保证离线 **诊断** / **清理** 预览在任意 Win 机双击能跑。
4. 再接 **TUI 路径**（dsh-TUI）。接不上就现场只演示脚本，讲「Agent 层用同一套脚本」。TUI 内不要用 `/update`（会找全局 `dsh.cmd`）。
5. 赛后再单独立项 **无线网卡路径**。

---

## 8. 群聊里砍掉的东西（避免返工）

| 提议 | 处理 |
|---|---|
| 免驱网卡 + 流量卡 | 延期，ADR-0001 |
| 跨平台 / 黑屏 / BIOS / 重装 | 超出一天半 |
| 远程千里修机、必须先装 Agent | 与即插即用矛盾，本场不做 |
| 自媒体 / 小红书自动化 | 合规风险 + 做不完 |
| 后门、网吧破解、BadUSB | 不做 |
| 运维 + 自媒体一个安装包 | 定位不清，不做 |
