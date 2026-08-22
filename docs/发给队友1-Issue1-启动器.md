# 发给队友 1：Issue #1 启动器

队长只做需求/架构。你（或你的 agent）只写代码，开 PR，不要直推 `main`。

- 仓库：https://github.com/23xxCh/Only-U
- Issue：https://github.com/23xxCh/Only-U/issues/1
- 负责人：@BugCuddler
- 协作：`docs/发给合作者-如何让他们的agent干活.md`
- 架构：ADR-0002、ADR-0003、[ADR-0005](adr/0005-usb-baked-dsh-runtime.md)
- **不要**按 `docs/Only-U-项目需求文档.md` 或 `docs/prd.md` 扩成 Web / 工单系统
- **不要**删 `dsh/`，不要改 `dsh-tui/` 源码

对方如果还没 clone，先做协作说明第 0 节。`git pull origin main` 后再开写。

---

## 开工提示词（整段粘贴）

```text
请按本仓库的 Matt Pocock 工程技能配置，实现 GitHub Issue #1。
新开会话，只做这一张票。做完开 PR，不要直接推 main。

仓库：https://github.com/23xxCh/Only-U
Issue：https://github.com/23xxCh/Only-U/issues/1
负责人 BugCuddler。标签必须是 ready-for-agent。如果不是，停下来告诉我。

队长负责需求与架构。你只改启动器代码。不要写新 ADR、不要删 dsh/、不要动 diagnose.ps1。

====================
开工前必读
====================
1. AGENTS.md
2. docs/README.md
3. docs/plan.md
4. docs/adr/0005-usb-baked-dsh-runtime.md
5. CONTEXT.md
6. docs/adr/0002-canonical-hackathon-scope.md
7. docs/adr/0003-dsh-tui-agent-shell.md
8. 当前文件：portable/start.cmd、portable/.env.example、.gitignore
9. gh issue view 1 --comments

领域用词只用 CONTEXT.md。U盘包、运维会话、诊断、清理、误删防护、离线路径、TUI 路径、烘焙。

====================
Git
====================
git checkout main && git pull origin main
开分支 feat/1-portable-start-baked-node
不要在 main 上改

====================
产品意图（有网只要一次双击）
====================
运维双击 Start-Agent.cmd / portable\start.cmd → TUI。
TUI 起来后的「自动诊断 + 预览」是 skill（Issue #2），你不要做。
你负责：能启动 TUI、Key 好填、缺件指向 diagnose.cmd。

====================
必须做到
====================
只改：portable/start.cmd、.gitignore、portable/.env.example
（可加盘根 Start-Agent.cmd 包装器，GBK 编码）

1. 路径全部 %~dp0 / 相对路径。禁止写死 F:\ E:\ D:\。

2. 用 portable\runtime\node\node.exe（若存在）插到当前窗口 PATH 最前。不改系统 PATH。

3. 不要 pnpm，不要 --profile headless。
   启动：portable\runtime\node\node.exe portable\runtime\dsh\lib\bin.js --profile dsh-tui
   DSH_HOME=portable\runtime\dsh
   不要 TUI /update。不要拷 dsh\node_modules。不要从 %APPDATA%\npm 拷全局包。

4. Key（这是本票重点，比「空 Key 直接失败」更重要）：
   - 若 portable\.env 不存在或 DEEPSEEK_API_KEY 为空：中文提示「请粘贴 DeepSeek API Key，回车」；输入不要 echo 明文到屏幕（能隐藏更好）；写入 portable\.env 的 DEEPSEEK_API_KEY= 行；再启动 TUI。
   - 已有非空 Key：直接启动，不要每次都问。
   - 任何日志不得打印 Key 值、不得打印 sk- 全文、不得打印 Authorization。

5. 下列情况立刻失败（非 0），中文指向 portable\diagnose.cmd，然后 pause 以免闪退：
   - 找不到 portable\runtime\node\node.exe
   - 找不到 portable\runtime\dsh\lib\bin.js
   - 找不到 portable\runtime\dsh\profiles\dsh-tui\package.json
   - 空 Key 提示后用户仍没贴（或贴了仍空）

6. .cmd 必须是 GBK/ANSI，禁止 UTF-8 BOM。UTF-8 BOM 会让资源管理器双击闪退。
   盘根可同时有 Start-Agent.cmd（英文名，最稳）。

7. .gitignore 必须有 portable/.env、portable/runtime/、portable/.dsh-home/
   .env.example 保留：DEEPSEEK_API_KEY= 和可选 DEEPSEEK_BASE_URL=

====================
不要做什么
====================
- 不要改 diagnose.ps1 / clean.ps1 / skill（Issue #2）
- 不要改 dsh/ 或 dsh-tui/ 源码
- 不要做 Web UI、工单系统、全局 npm install -g
- 不要提交真实 .env、Node zip、node_modules
- 不要 push --force 到 main

====================
验证（写进 PR）
====================
1. 没有 runtime\node\node.exe 时跑 start.cmd：快失败，提到 diagnose.cmd，pause，退出码非 0。
2. 空 .env：应提示粘贴 Key，不得把 Key 打印出来（findstr 搜不到完整 sk-）。
3. 文件头两字节不能是 EF BB BF。
4. 启动器逻辑里没有盘符字面量 F: E:。
5. type .gitignore 含 portable/.env 和 portable/runtime/

====================
交卷
====================
git push -u origin feat/1-portable-start-baked-node
gh pr create ，第一行 Closes #1
```
