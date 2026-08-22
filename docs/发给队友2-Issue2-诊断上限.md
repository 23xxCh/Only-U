# 发给队友 2：Issue #2 诊断不卡死

把下面「开工提示词」整段复制给对方的 **新开** agent 会话。不要接在别的任务后面。

- 仓库：https://github.com/23xxCh/Only-U
- Issue：https://github.com/23xxCh/Only-U/issues/2
- 协作说明：`docs/发给合作者-如何让他们的agent干活.md`
- 本场基线：`docs/plan.md`、`docs/designs/only-u-hackathon.md`、ADR-0001、ADR-0002
- **不要**按 `docs/Only-U-项目需求文档.md` 做 Web / 在线-only

对方如果还没 clone，先让他做协作说明第 0 节。

这张票不要改 `portable/start.cmd`（那是 Issue #1，会打架）。

---

## 开工提示词（整段粘贴）

```text
请按本仓库的 Matt Pocock 工程技能配置，实现 GitHub Issue #2。
新开会话，只做这一张票。做完开 PR，不要直接推 main。

仓库：https://github.com/23xxCh/Only-U
Issue：https://github.com/23xxCh/Only-U/issues/2
标签必须是 ready-for-agent。如果不是，停下来告诉我，不要开写。

====================
开工前必读（按这个顺序）
====================
1. AGENTS.md
2. docs/README.md
3. docs/plan.md
4. docs/designs/only-u-hackathon.md
5. CONTEXT.md
6. docs/adr/0001-software-only-usb-pack.md
7. docs/adr/0002-canonical-hackathon-scope.md
8. docs/agents/issue-tracker.md
9. docs/agents/triage-labels.md
10. docs/agents/domain.md
11. 当前文件：portable/diagnose.ps1、portable/diagnose.cmd、portable/clean.ps1（只读 clean，确认你没改它的防护）

不要把 docs/Only-U-项目需求文档.md 当实现规格。
本场 whoa 是：插上双击 portable\diagnose.cmd，无网也能出诊断。脚本卡死 = 演示翻车。

领域用词只用 CONTEXT.md：诊断是只读、不调模型；清理是另一张票的脚本；误删防护是预览 + 不碰用户文档。

====================
先做 Git
====================
1. gh issue view 2 --repo 23xxCh/Only-U --comments
2. git checkout main && git pull origin main
3. 从 main 开分支：feat/2-diagnose-scan-cap
4. 不要在 main 上改
5. 不要改 portable/start.cmd（那是 Issue #1，会冲突）

====================
这张票要改什么
====================
主文件：portable/diagnose.ps1
必要时：.dsh/skills/only-u-ops/SKILL.md（只加一句：诊断走 diagnose.ps1，扫描可能跳过过大目录）
不要改：portable/start.cmd、portable/clean.ps1、dsh-tui/

问题：Get-DirSize 会递归整个 TEMP。评委电脑临时目录可能有几十万小文件，屏幕几分钟没输出，看起来像死机。

必须做到：

1. 对每个候选目录（TEMP/TMP/Windows\Temp\LocalAppData\Temp\SoftwareDistribution\Download 等现有列表）做限时或限文件数。建议：
   - 单目录最多扫描约 8–15 秒，或最多 N 个文件（例如 20000）
   - 超时/超限：打印该路径 + 「skipped: too large or timed out」或中文等价说明
   - 不要让整个 diagnose.cmd 超过大约 60 秒还没结束（打印机和事件日志仍要跑）

2. 超时是跳过，不是报崩溃退出。磁盘、内存、近期 System 错误、打印机段落必须还在。C 盘免费空间 <15% 的提示保留。

3. 仍然只读。不要删除文件。不要调用 LLM。不要全盘扫描 C:\。不要跟随到未授权的网络路径。

4. 先输出「正在扫描 xxx」再扫描，避免长时间空白。

5. 不要改 clean.ps1。你可以手动跑一次 portable\clean.cmd（不要加 -Execute），确认桌面/文档/下载不会进入删除候选；如果发现被破坏，停下来开评论，不要「顺手修」成大重构。

6. PowerShell 5 会把无 BOM 的 UTF-8 当成 ANSI，导致缺引号解析失败。diagnose.ps1 必须保持 UTF-8 BOM。diagnose.cmd 已经优先 pwsh，不要删掉这条。

====================
不要做什么
====================
- 不要改 start.cmd / .gitignore / .env（Issue #1）
- 不要做 Web UI、杀毒引擎、SFC 全量、WinPE
- 不要引入新的大依赖
- 不要 push --force 到 main
- 不要把「没网就不能诊断」写进文案；这张票就是离线路径

====================
怎么验证（证据写进 PR）
====================
1. 直接运行 portable\diagnose.cmd，应打印：time/computer、disk、memory、reclaim candidates、recent System errors、printers（如果现在已有打印机段）。
2. 人为造一个大目录压力（例如在 %TEMP%\only-u-cap-test 里快速建很多空文件，或对一个已知很大的 TEMP 跑）。对应行应出现 skip/timeout，而不是卡住 >2 分钟。
3. 全过程尽量在 60 秒内出完整报告（事件日志权限不足时可以打印 need elevation，这是已有行为）。
4. git diff 确认没有改 start.cmd、clean.ps1。
5. 用编辑器或 Format-Hex 确认 diagnose.ps1 仍是 UTF-8 BOM（EF BB BF）。

没有测试框架就不要新搭。把上述命令的输出摘要贴进 PR。

实现可以走 /tdd：先写一个最小的「超时应跳过」断言（如果太重就用手工复现步骤）。改动保持最小。

====================
交卷
====================
自测通过后：
- git commit（只 stage diagnose.ps1 和你确实改过的 skill）
- git push -u origin feat/2-diagnose-scan-cap
- gh pr create
- PR 第一行：Closes #2
- PR 正文写：怎么验证、限时/限量用的具体数字、改了什么、没改什么

仓库：https://github.com/23xxCh/Only-U
```
