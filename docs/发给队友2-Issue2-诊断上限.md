# 发给队友 2：Issue #2 诊断报告 + TUI 首轮

## 当前状态

- 状态：**已实现，PR 待合并**
- 分支：`feat/2-diagnose-scan-cap`
- PR：[23xxCh/Only-U#5](https://github.com/23xxCh/Only-U/pull/5)
- Issue：[23xxCh/Only-U#2](https://github.com/23xxCh/Only-U/issues/2)（PR 正文含 `Closes #2`）
- 最近验证：2026-08-22，Windows PowerShell 5.1 下 Pester 4/4 通过

已交付：

- TEMP 类目录扫描上限为每个目录 8 秒或 20,000 个文件；扫描前显示「正在扫描」，超限显示「跳过：太大或超时」。
- 目录扫描使用可终止后台作业，拒绝 UNC 根路径并跳过重解析点，避免沿链接扩大扫描范围。
- 保留磁盘、内存、近期 System 错误和打印机段；新增占内存进程、启动项数量和 PnP 驱动错误码线索，全部只读。
- PnP 异常依据 `Win32_PnPEntity.ConfigManagerErrorCode`，避免把普通 `Unknown` 状态误报成驱动故障。
- `only-u-ops` 要求 TUI **运维会话**先跑 **诊断**，再跑 **清理**预览；只有用户明确说「确认」「执行」或同等确认后才允许 `-Execute`。
- `portable\clean.cmd` 验证仍为预览模式，桌面、文档、下载和图片不在删除候选；`diagnose.ps1` 仍为 UTF-8 BOM。

未改动：`portable/start.cmd`、`portable/clean.ps1`、`dsh/`、`dsh-tui/`。

以下内容保留为原始开工记录。

队长只做需求/架构。你（或你的 agent）只写代码，开 PR，不要直推 `main`。

- 仓库：https://github.com/23xxCh/Only-U
- Issue：https://github.com/23xxCh/Only-U/issues/2
- 负责人：@yandifei
- 调研笔记（只读，不扩范围）：`docs/调研-电脑运维与维修需求.md`、`docs/only-u-agent-专业提示词.md`
- 架构：[ADR-0005](adr/0005-usb-baked-dsh-runtime.md)、ADR-0002
- **不要**再删除 `dsh/`，不要改 `portable/start.cmd`（Issue #1），不要直推 main

`git pull origin main` 后再开写。

---

## 开工提示词（整段粘贴）

```text
请按本仓库的 Matt Pocock 工程技能配置，实现 GitHub Issue #2。
新开会话，只做这一张票。做完开 PR，不要直接推 main。

仓库：https://github.com/23xxCh/Only-U
Issue：https://github.com/23xxCh/Only-U/issues/2
负责人 yandifei。标签必须是 ready-for-agent。

队长负责需求与架构。你只改诊断脚本和 skill。不要写新 ADR、不要删 dsh/、不要改 start.cmd。

====================
开工前必读
====================
1. AGENTS.md
2. docs/README.md
3. docs/plan.md
4. CONTEXT.md
5. docs/adr/0002-canonical-hackathon-scope.md
6. docs/adr/0005-usb-baked-dsh-runtime.md
7. docs/调研-电脑运维与维修需求.md（只取阈值和「只报告不修」，不扩成工单系统）
8. docs/only-u-agent-专业提示词.md（可并入口吻，铁律不要削弱）
9. portable/diagnose.ps1、portable/diagnose.cmd、portable/clean.ps1（只读 clean 的防护）
10. .dsh/skills/only-u-ops/SKILL.md
11. gh issue view 2 --comments

领域用词只用 CONTEXT.md。

====================
Git
====================
git checkout main && git pull origin main
开分支 feat/2-diagnose-scan-cap
不要在 main 上改
不要改 portable/start.cmd

====================
产品意图
====================
MVP 三件事（都只读，除非用户之后确认清理）：
1. C 盘满
2. 卡顿/内存（进程/启动项线索，不自动杀进程）
3. 打印机 + PnP 驱动缺失（只列出，不安装）

有网 TUI：启动后自动跑诊断 + 清理预览，等人打「确认」或「执行」才 -Execute。
没网：用户自己双击 diagnose.cmd。你的脚本两处都要用。
软件打不开/软件卡顿：本票不做。

====================
必须改
====================
主文件：portable/diagnose.ps1
必须改：.dsh/skills/only-u-ops/SKILL.md
不要改：start.cmd、clean.ps1、dsh/、dsh-tui/

A) diagnose.ps1
1. 每个 TEMP 类目录限时约 8–15 秒或最多约 20000 文件。超时打印路径 + 中文「跳过：太大或超时」。整个 diagnose.cmd 约 60 秒内结束。
2. 先 echo「正在扫描 xxx」再扫。
3. 保留：磁盘（C 盘 <15% 警告）、内存、近期 System 错误、打印机。
4. 新增只读段（失败就写「无法读取」，不要崩）：
   - 内存：总量/已用；占内存前几名进程名（不要 kill）
   - 若能低成本读到启动项数量，可给一行；读不到就跳过
   - 打印机（已有则加强）+ 即插即用设备里 Driver 状态异常/缺失的列表（Get-PnpDevice 之类，最多列出前 N 条）。不安装驱动、不禁用设备。
5. 只读。不删文件。不调 LLM。不全盘扫 C:\。不跟 UNC。
6. 保持 UTF-8 BOM。diagnose.cmd 优先 pwsh 不要拆掉。

B) skill only-u-ops
1. TUI 会话一开始就跑 diagnose.cmd，再跑 clean.cmd（无参数，预览）。把两段输出给人看。
2. 只有用户明确说「确认」「执行」或同等确认，才 clean.cmd -Execute。
3. 不要自动 -Execute。不要推荐第三方一键清理/注册表清理。
4. 没网告诉人改跑 diagnose.cmd。
5. 可用 docs/only-u-agent-专业提示词.md 的口吻，但工具清单仍只准这两个脚本。

====================
不要做什么
====================
- 不要改 start.cmd / .gitignore / .env
- 不要删除 dsh/
- 不要做 Web、工单、杀毒、装驱动、重装系统
- 不要直推 main、不要 force-push

====================
验证（写进 PR）
====================
1. portable\diagnose.cmd 打出磁盘/内存/进程/打印机或驱动异常/事件；有「正在扫描」。
2. 大 TEMP 会 skip，不要卡住 >2 分钟；尽量 60 秒内结束。
3. clean.cmd 无参数仍只预览，桌面/文档/下载不在删除候选。
4. git diff 无 start.cmd、无 dsh/、无 clean.ps1 防护被拆。
5. diagnose.ps1 文件头 EF BB BF。

====================
交卷
====================
git push -u origin feat/2-diagnose-scan-cap
gh pr create ，第一行 Closes #2
```
