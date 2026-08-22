# 如何把活发给合作者的 Agent

仓库：https://github.com/23xxCh/Only-U

三人共用**一个 GitHub 仓库 + 一套 GitHub Issues**。技能装在每人自己的电脑上；真正用来交接的不是聊天记录，而是 Issue。

一句话：**你把票写清楚并标成 `ready-for-agent`，对方新开一个 agent 会话，把下面的「开工提示词」贴进去。**

---

## 0. 每个人电脑上先做完这些

只做一次。

1. 被加进 GitHub 仓库 Collaborators，并接受邀请
2. 克隆仓库（不要自己新建一份）

```bash
git clone https://github.com/23xxCh/Only-U.git
cd Only-U
```

3. 配 Git 身份

```bash
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"
```

4. 在自己的 agent（Grok / Claude Code / Codex）里安装 [mattpocock/skills](https://github.com/mattpocock/skills)

- Claude Code：`claude plugins install mattpocock-skills`
- 其他 agent：`npx skills@latest add mattpocock/skills`（务必包含 `setup-matt-pocock-skills`）

5. **不要再跑** `/setup-matt-pocock-skills`。仓库里已经配好了：

- Issue 在 GitHub：`23xxCh/Only-U`
- 标签：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`
- 领域文档：根目录 `CONTEXT.md` + `docs/adr/`（single-context）
- 本场范围：`docs/plan.md` + `docs/designs/only-u-hackathon.md`。长 PRD 不是开发基线，见 ADR-0002。有网 Agent 壳是 dsh-TUI，见 ADR-0003。

agent 会读 `AGENTS.md` 和 `docs/agents/`。

6. 本机要能用 `gh`（GitHub CLI），并登录到有这个仓库权限的账号。

---

## 1. 发活的人怎么准备（你）

不要把微信长消息、截图、半截对话丢给对方。按这个顺序做：

```
/grill-with-docs   → 对齐需求，术语写入 CONTEXT.md
/to-prd            → PRD 发到 GitHub Issue
/to-issues         → 拆成可独立领取的垂直切片
/triage            → 能交给 agent 的票标 ready-for-agent
在 Issue 下评论「@某人 请做 #N」
把「开工提示词」发给对方
```

标 `ready-for-agent` 的票必须同时满足：

- 有「做什么」和验收标准
- 依赖写清（Blocked by #几，或写 None）
- 不需要现场插 U 盘、产品拍板、账号权限等只有人能做的事  
  （那些标 `ready-for-human`，人盯着做）

同一张票只发给一个人。评论里写「我发给 B 了」，避免两个人的 agent 同时改同一张。

---

## 2. 你发给对方的消息（复制即用）

把 `#12` 和分支名换成实际值。微信 / 飞书直接贴：

```text
请你的 agent 做 GitHub Issue #12。

仓库：https://github.com/23xxCh/Only-U
Issue：https://github.com/23xxCh/Only-U/issues/12

请：
1. 拉最新 main
2. 开新分支 feat/12-<短名>
3. 新开一个 agent 会话，工作目录放到仓库根目录
4. 把「开工提示词」整段贴给 agent（见仓库 docs/发给合作者-如何让他们的agent干活.md 第 3 节）
5. 做完提 PR，描述第一行写 Closes #12
6. 不要直接推 main
```

对方如果还没 clone，把第 0 节一起发过去。

---

## 3. 对方贴给自己 Agent 的开工提示词

**新开会话**，不要接在别的任务后面。把 `N` 换成 Issue 号。

```text
请按本仓库的 Matt Pocock 工程技能配置实现 GitHub Issue #N。

开工前必读：
- AGENTS.md
- docs/README.md（哪份文档是基线）
- docs/plan.md
- docs/designs/only-u-hackathon.md
- docs/agents/issue-tracker.md
- docs/agents/triage-labels.md
- docs/agents/domain.md
- CONTEXT.md
- docs/adr/ 里和本票相关的 ADR（必读 0001、0002）
不要把 docs/Only-U-项目需求文档.md 当实现规格。

然后：
1. 用 gh 读取 Issue #N 的正文、评论、标签（gh issue view N --comments）
2. 若标签不是 ready-for-agent：停下来告诉我，不要开写
3. 若有 Blocked by 且阻塞票未关闭：停下来告诉我，不要开写
4. git checkout main && git pull origin main
5. 从 main 开分支 feat/N-<短英文名>，不要在 main 上改
6. 领域用词必须用 CONTEXT.md 里的术语，不要自造同义词
7. 实现时走 /tdd：先写失败测试，再写最小实现，再重构
8. 只做这一张票的验收标准，不顺手做相邻功能
9. 自测通过后提交，推分支，用 gh pr create 开 PR
10. PR 描述第一行写 Closes #N，并写：怎么验证、改了什么、没改什么
11. 不要 push --force 到 main，不要改 docs/agents 里的 tracker/标签约定，除非票就是改这个

仓库：https://github.com/23xxCh/Only-U
```

对方的 agent 若支持 skill，也可以先说：

```text
/tdd 实现 https://github.com/23xxCh/Only-U/issues/N
请先读 AGENTS.md 和 docs/agents/，用 gh 拉 Issue 全文。
```

两段等价，上面那段更完整，推荐用完整版。

---

## 4. 日常 git（三人同一套）

```
拉最新 main → 开自己的分支 → 干活 → commit → push 分支 → 开 PR → 别人看一眼 → 合进 main
```

```bash
git checkout main
git pull origin main
git checkout -b feat/12-usb-scan

# 做完
git add -p
git commit -m "feat: 扫描 U 盘并列出设备"
git push -u origin feat/12-usb-scan
gh pr create --fill
```

硬规矩：

- 不直接往 `main` 推
- 一人一条功能分支，不要共用 `feat/xxx`
- 分支尽量短，一张 Issue 一个 PR
- 每天开工先 `git pull origin main`
- 密钥、`.env` 不进 git

分支名：`feat/` `fix/` `docs/` `chore/`，带 Issue 号，例如 `feat/12-usb-scan`。

---

## 5. Issue 标签（agent 靠这个判断能不能动手）

| 标签 | 含义 | 别人的 agent 该怎么做 |
|---|---|---|
| `needs-triage` | 还没评估 | 不要做 |
| `needs-info` | 在等补充 | 不要做 |
| `ready-for-agent` | 规格够了，可以交给 agent | **可以做** |
| `ready-for-human` | 必须人判断或人在场 | 人盯着做，或不要全权交给 AFK agent |
| `wontfix` | 不做 | 不要做 |

每天可以让任意一个人的 agent 跑：

```text
/triage 有什么需要我看的？哪些票 ready-for-agent？
```

---

## 6. 一张票从发到收（例子）

1. 你：`/grill-with-docs 做 U 盘接入后的设备扫描` → 更新 `CONTEXT.md`，开 PR 合进 main
2. 你：`/to-prd` → `/to-issues` → 得到 `#12 扫描并列出设备`、`#13 弹出前校验占用`（#13 blocked by #12）
3. 你：`/triage`，#12 标 `ready-for-agent`
4. 你把第 2、3 节发给 B
5. B 的 agent 拉 main、开 `feat/12-usb-scan`、按验收标准做、提 PR（`Closes #12`）
6. 你或 C 看 PR，合入
7. 这时才能把 #13 发给 C

---

## 7. 换人 / 换会话

不要转发聊天记录。正确交接物只有：

- GitHub Issue（正文 + 评论里的 agent brief）
- 已合入的 `CONTEXT.md` / `docs/adr/`
- 未完成时：对方本地跑 `/handoff`，把生成的文档贴回 Issue 评论

下一任 agent 仍然用第 3 节提示词，从 Issue 接着做。

---

## 8. 不要做的事

- 用微信/网盘互传 zip 当同步
- 三人各建一个 GitHub 仓库
- 不标 `ready-for-agent` 就把活丢给别人的 agent
- 两个人的 agent 同时做同一张 Issue
- 在 `main` 上直接改
- 不 pull 就 push，或对 `main` 使用 `push --force`
- 跳过 `/grill-with-docs` 让三个 agent 各自发明术语
- 把只有人能做的事（真机插盘、产品拍板、云账号）标成 `ready-for-agent`

---

## 9. 相关文件

| 文件 | 谁读 |
|---|---|
| `AGENTS.md` | 所有 agent 的入口 |
| `docs/agents/issue-tracker.md` | Issue 怎么读写 |
| `docs/agents/triage-labels.md` | 标签含义 |
| `docs/agents/domain.md` | `CONTEXT.md` / ADR 怎么用 |
| `CONTEXT.md` | 项目术语（grill 之后才会出现） |
| `docs/adr/` | 架构决策（有了才建） |

技能说明：https://github.com/mattpocock/skills

改标签、改 tracker、改领域布局：直接改 `docs/agents/*.md`，不必重跑 setup。
