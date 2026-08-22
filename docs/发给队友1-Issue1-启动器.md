# 发给队友 1：Issue #1 启动器

把下面「开工提示词」整段复制给对方的 **新开** agent 会话。不要接在别的任务后面。

- 仓库：https://github.com/23xxCh/Only-U
- Issue：https://github.com/23xxCh/Only-U/issues/1
- 协作说明：`docs/发给合作者-如何让他们的agent干活.md`
- 本场基线：`docs/plan.md`、`docs/prd.md`、`docs/designs/only-u-hackathon.md`、ADR-0001、ADR-0002、ADR-0003、ADR-0004
- **不要**按 `docs/Only-U-项目需求文档.md` 做 Web / 在线-only

对方如果还没 clone，先让他做协作说明第 0 节。

---

## 开工提示词（整段粘贴）

```text
请按本仓库的 Matt Pocock 工程技能配置，实现 GitHub Issue #1。
新开会话，只做这一张票。做完开 PR，不要直接推 main。

仓库：https://github.com/23xxCh/Only-U
Issue：https://github.com/23xxCh/Only-U/issues/1
标签必须是 ready-for-agent。如果不是，停下来告诉我，不要开写。

====================
开工前必读（按这个顺序）
====================
1. AGENTS.md
2. docs/README.md（哪份文档是开发基线）
3. docs/plan.md
4. docs/designs/only-u-hackathon.md
5. CONTEXT.md
6. docs/adr/0001-software-only-usb-pack.md
7. docs/adr/0002-canonical-hackathon-scope.md
8. docs/adr/0003-dsh-tui-agent-shell.md
9. docs/agents/issue-tracker.md
10. docs/agents/triage-labels.md
11. docs/agents/domain.md
12. 当前文件：portable/start.cmd、portable/.env.example、.gitignore

不要把 docs/Only-U-项目需求文档.md 或 docs/superpowers/specs/ 当实现规格。
那是归档。本场是软件 U盘包：脚本地板 + DSH 调同一套脚本。不要做 Web UI、不要做「必须联网才能诊断」。

领域用词只用 CONTEXT.md：U盘包、运维会话、诊断、清理、误删防护、离线路径、插件。不要自造同义词。

====================
先做 Git
====================
1. gh issue view 1 --repo 23xxCh/Only-U --comments
2. git checkout main && git pull origin main
3. 从 main 开分支：feat/1-portable-start-baked-node
4. 不要在 main 上改

====================
这张票要改什么
====================
只改这些文件（可以新建 README 片段，但不要扩范围）：
- portable/start.cmd
- .gitignore
- portable/.env.example

目标：评委电脑没有全局 Node/pnpm 时，只要 U 盘上已经烘焙了运行时，就能 start.cmd 拉起 DSH；缺东西时不能假死，必须用人话指向离线诊断。

必须做到：

1. 所有路径用 %~dp0 / 相对路径。源码里禁止出现 F:\、E:\ 或任何写死盘符。烘焙盘可能是 F:\Only-U，但代码不能写死它。

2. 如果存在 `portable\runtime\node\node.exe`，把它加到「当前 cmd 窗口」的 PATH 前面。不要改用户机器的系统 PATH。

3. 启动命令不要再用 `pnpm dsh`，也不要用 `--profile headless`。评委机没有全局 pnpm。用盘上的 node.exe 跑：
   `portable\runtime\dsh\lib\bin.js --profile dsh-tui`
   这是 **烘焙** 出的扁平 CLI（[ADR-0005](../adr/0005-usb-baked-dsh-runtime.md)），不是仓库里的 `dsh\apps\cli\lib\bin.js`。
   `DSH_HOME` 设为 `portable\runtime\dsh`。烘焙时把本机 `%USERPROFILE%\.dsh\profiles\dsh-tui` 拷到 `%DSH_HOME%\profiles\dsh-tui`。
   **禁止**把 `dsh\node_modules` 整包拷上 U 盘（FAT32 + pnpm 符号链接会复制爆炸）。运行时用 `scripts\bake-usb.ps1` 或同等的 `pnpm --filter @deepseek-ai/dsh deploy --prod --legacy --config.node-linker=hoisted`。不要调用 TUI 的 `/update`。不要从 `%APPDATA%\npm` 拷全局 node_modules。

4. 下面任一情况，立即失败退出（非 0），屏幕用中文人话说明原因，并告诉用户改跑 `portable\diagnose.cmd`：
   - 找不到 portable\runtime\node\node.exe
   - 找不到 portable\runtime\dsh\lib\bin.js（还没烘焙）
   - 找不到 portable\runtime\dsh\profiles\dsh-tui\package.json
   - 没有 portable\.env，或里面 DEEPSEEK_API_KEY 为空
   - 不要在缺 Key 时把 DSH 丢进去转圈

5. 任何 echo、报错、日志都不得打印 Key 的值，也不得打印 Authorization 头。检查 Key 只判断「非空」，不要输出内容。

6. .gitignore 必须忽略：
   - portable/.env
   - portable/runtime/
   - portable/.dsh-home/（如果还没有）
   不要忽略 .env.example。

7. portable/.env.example 保留空模板，并注明：
   - DEEPSEEK_API_KEY=
   - DEEPSEEK_BASE_URL= 用于 AI Ping（例如 https://aiping.cn/api/v1）
   - 真实 Key 只写在 U 盘 .env，永不进 Git

不要改成 Web 产品，不要 headless 一句退出。TUI 起来后由用户说话；skill only-u-ops 负责诊断/清理脚本。

====================
不要做什么
====================
- 不要改 `dsh-tui/` 源码或 fork 内核
- 不要改 portable/diagnose.ps1（那是 Issue #2）
- 不要改 portable/clean.ps1
- 不要做本地 Web UI、联网门禁产品、41 条 FR；不要 `github:deepseek-harness/turtle-ui`
- 不要提交 Node zip、node_modules、真实 .env
- 不要 push --force 到 main

====================
怎么验证（证据写进 PR）
====================
在仓库根目录：

1. 确保没有 portable\runtime\node\node.exe（或临时改名）。运行 portable\start.cmd。必须很快失败，文案提到 diagnose.cmd，退出码非 0。
2. 造一个空的 portable\.env（或 DEEPSEEK_API_KEY=）。若有 node 也会因空 Key 失败。屏幕上用 findstr /i 搜不到 sk-、Bearer、完整 key。
3. 在改过的文件里搜索 `F:` `E:` `D:` 盘符字面量，启动器逻辑里不能有。
4. type .gitignore，确认 portable/.env 和 portable/runtime/ 被忽略。

Windows 上 PowerShell 5 可能把无 BOM 的 UTF-8 脚本读坏。本次主要改 .cmd 和 .example，若必须改 ps1，用 UTF-8 BOM。start.cmd 已有的「优先 pwsh」模式不要拆掉。

实现可以走 /tdd：先写最小可重复的失败检查（哪怕是一个 cmd 探测脚本），再改 start.cmd。没有现成测试框架就不要新造 Jest/Pester 工程；用手工命令输出当证据即可。

====================
交卷
====================
自测通过后：
- git commit（只 stage 上述文件）
- git push -u origin feat/1-portable-start-baked-node
- gh pr create
- PR 第一行：Closes #1
- PR 正文写：怎么验证、改了什么、没改什么、Key 不会被打印

仓库：https://github.com/23xxCh/Only-U
```
