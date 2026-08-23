# AI 编程工具 C 盘占用调研报告

> - **调研日期**：2026-08-23
> - **调研方法**：本机 `C:\Users\yandifei` 只读实测（目录结构逐项统计 + 大小测量）+ 5 个并行联网调研 agent（官方文档、GitHub issue、社区资料交叉验证）
> - **覆盖范围**：Claude Code、OpenAI Codex、腾讯 WorkBuddy/CodeBuddy、Google Antigravity、Gemini CLI、Cursor、Windsurf、Trae/MarsCode、豆包、通义灵码/Qoder、Kilo/Roo Code、Continue、Aider、OpenCode、Google Amp、Warp、CodeGeeX，以及本机残留的其他 harness 痕迹
> - **风险提示**：执行任何删除前请先退出对应工具；会话/聊天历史类数据删除不可恢复，删前按需备份；本报告所有"可删"结论仅代表"删了工具不会坏"，不代表"删了不丢东西"

## 摘要（先说结论）

1. AI 工具在 C 盘的占用分三大类：**会话历史**（最大膨胀源，绝大多数工具不自动清理）、**索引与快照**（代码索引、checkpoint 影子 git 仓库，社区有数十 GB 案例）、**缓存与日志**（模型缓存、更新包残留、运行日志——最安全的回收对象）。
2. 社区已知极端案例：Codex sessions 单任务 731GB、Continue 索引 300GB+、Cursor snapshots 单日 44–180GB、Roo checkpoints 51GB、Qoder index.db 70GB、Trae 对话库 30GB+、Codex computer-use 截图一个项目 165GB。你同事 Codex 的 40GB 属于典型情况。
3. 本机当前 harness 相关占用约 **20GB**（含 VS Code 主体），其中**可立即安全回收约 7–8GB**（详见第二十一节清单）。
4. 有官方搬家环境变量的只有少数：Claude Code（`CLAUDE_CONFIG_DIR`）、Codex CLI（`CODEX_HOME`）、Gemini CLI（`GEMINI_CLI_HOME`）、OpenCode、Amp、Kilo、Aider、CodeBuddy CLI、Trae CLI、Qoder。其余（含 Antigravity）只能 junction（目录联接）或靠关闭功能控增长。
5. 通用必留三件套：**配置、登录态、你还想要的聊天历史**。最安全的通用首删对象：`Cache*`、`GPUCache`、`logs`、`traces`、`*updater` 更新残留。

---

## 一、本机实测总览

| 工具 | 主要路径 | 实测 | 定位 |
|---|---|---|---|
| VS Code（基线） | `%APPDATA%\Code` 3.77GB + `~\.vscode` 2.99GB | **6.76GB** | 所有 fork 型 IDE 的母体 |
| Claude Code | `~\.claude` 1.53GB + `~\.local` 1.26GB | **2.79GB** | 大头是 skills 1.28GB（自己装的技能），会话仅 86MB |
| OpenAI Codex | `~\.codex` 1.15GB + `~\.cache\codex-runtimes` 1.41GB | **2.56GB** | 沙箱运行时占一半 |
| Continue | `~\.continue` | **2.13GB** | 几乎 100% 是索引 index.sqlite |
| npm 全局缓存 | `%LOCALAPPDATA%\npm-cache` | **1.63GB** | Codex/dsh/pnpm 安装与更新残留 |
| 腾讯 WorkBuddy | `~\.workbuddy` 0.47GB + updater 残留 0.40GB + Temp 残留 0.40GB | **1.27GB** | 近 800MB 是纯更新残留 |
| 豆包 | `%LOCALAPPDATA%\Doubao` | **0.71GB** | Electron 客户端 |
| CodeGeeX | `~\.codegeex` | **0.32GB** | 大头是本地运行环境 mamba |
| Google Antigravity | `%LOCALAPPDATA%\Programs\antigravity` 0.52GB + updater 0.27GB + `%APPDATA%\Antigravity` 0.03GB + `~\.gemini\antigravity*` 0.04GB | **0.85GB** | 程序本体 + 更新器暂存是大头 |
| Cursor | `%APPDATA%\Cursor` | **0.05GB** | 很健康 |
| Gemini CLI | `~\.gemini` | **0.04GB** | 被 Antigravity 状态占去大部分 |
| 通义灵码 | `%LOCALAPPDATA%\.lingma` | **0.02GB** | 遥测与性能数据 |
| 其他痕迹 | `~\.dsh`、`~\.agents`、`~\.qoder-cn`、`~\.trae*`、`~\.roo`、`~\.kilocode` 等约 30 个 | 各 <0.1GB | 装过未深用 |

> 另：`%LOCALAPPDATA%\@comfyorgcomfyui-electron-updater` 0.28GB（ComfyUI 桌面版更新残留，非编程 harness，顺手记录）。当前无任何 junction/env 搬家已生效。

---

## 二、Claude Code

### 2.1 数据落在哪

| 位置 | 放什么 | 本机实测 |
|---|---|---|
| `~\.claude\skills\` | **手动安装的技能**（自定义资产，不是垃圾） | **1.28GB（本机最大头）** |
| `~\.claude\plugins\` | 插件安装与缓存 | 180.6MB |
| `~\.claude\projects\<项目路径>\<会话id>.jsonl` | **会话记录**：每轮对话 + 工具调用的明文 JSONL | 86.2MB |
| `~\.claude\file-history\` | 文件历史快照（供 /rewind） | 4.1MB |
| `~\.claude\shell-snapshots\` | 命令执行后的目录快照 | 0.1MB |
| `~\.claude\todos\`、`statsig\`、`telemetry\`、`tmp\`、`debug\`、`backups\` 等 | 任务清单、遥测、临时、备份 | 均 <1.5MB |
| `~\.claude\settings.json` | 用户设置（含 `cleanupPeriodDays` 等） | **必留** |
| `~\.claude\credentials*` | OAuth 登录凭证 | **必留** |
| `~\.claude.json` | 用户状态（全局配置，与凭证关联） | **必留** |
| `~\.local\bin\claude.exe` | 程序入口（原生安装器） | 0.31GB |
| `~\.local\share\claude\versions\` | 各版本程序目录 | 0.97GB |

### 2.2 增长点

- 通用规律：`projects\` 会话记录随使用线性增长，是其他机器上 Claude Code 的最大头；**但本机大头是 skills（自己装的），会话反而只有 86MB**——装技能多的人要留意 skills 目录。
- 默认保留 30 天自动清理；如果把 `cleanupPeriodDays` 调大或关掉，会话记录会无限累积。
- `~\.local\share\claude\versions\` 每次升级留一个版本目录，旧版本不自动删。

### 2.3 清理清单

- ✅ **可安全删**：`~\.local\share\claude\versions\` 下旧版本目录（保留当前版本即可，官方卸载步骤即删此目录）；`~\.claude` 下 `tmp\`、`debug\`、`telemetry\`、`backups\`、`settings.json.backup.*`
- ⚠️ **有损**：`projects\` 下旧会话 .jsonl（失去对应 /resume 能力，不可逆；官方推荐 `claude project purge --dry-run` 预览后再执行）
- ❌ **勿删**：`settings.json`、`~\.claude.json`、`credentials*`（删了要重新登录、重配 MCP 与权限）；`skills\` 除非确认不再需要
- **内置机制**：`cleanupPeriodDays`（默认 30 天，到期自动删旧会话记录）；`claude project purge [--all]`（按项目清全部本地状态）；`/clear` 只清上下文窗口、**不删磁盘数据**

### 2.4 搬家

- 官方：环境变量 `CLAUDE_CONFIG_DIR` 搬整个 `~\.claude`（会话记录随之落到新位置）。操作顺序：退出 → robocopy 复制验证 → `setx CLAUDE_CONFIG_DIR` → 确认正常 → 删原目录。
- 程序本体（`~\.local`）无官方变量，只能 junction。
- 注意：VS Code 插件、JetBrains 插件、桌面 App 都会往 `~\.claude` 写数据，只要还装着，删了也会重建。

---

## 三、OpenAI Codex

### 3.1 数据落在哪（本机 1.15GB 细分）

| 路径 | 放什么 | 本机 | 风险 |
|---|---|---|---|
| `~\.codex\config.toml` | 全部配置（模型、provider、history、信任级别） | **必留** | 低 |
| `~\.codex\auth.json` | 登录凭据缓存/API key | **必留** | 低 |
| `~\.codex\sessions\YYYY\MM\DD\rollout-*.jsonl` | **会话完整转录**，append-only JSONL；computer-use 截图以 base64 存于其中 | 179MB | **极高** |
| `~\.codex\plugins\` | 插件安装与缓存（`.plugin-appserver`、`cache\openai-*`） | 402MB | 中 |
| `~\.codex\.sandbox-bin\` | 沙箱辅助二进制（本机是 codex.exe 副本） | 280MB | 中 |
| `~\.codex\.tmp\` | 插件暂存、市场捆绑包 | 146MB | 中 |
| `~\.codex\logs_2.sqlite`（+`-wal`/`-shm`） | SQLite 事件日志（streamed-event、MCP TRACE） | 121+4MB | **中** |
| `~\.codex\cache\` | 远程插件目录缓存 | 31MB | 低 |
| `~\.codex\thread_history_1.sqlite` | 线程/对话历史 | 14MB | 低 |
| `~\.codex\state_5.sqlite` | 会话/线程上下文状态 | 0.9MB | 低 |
| `~\.codex\archived_sessions\` | `codex archive` 移入的会话（.tar.zst，约省 62%） | 2.1MB | 低 |
| `~\.codex\history.jsonl` | 每机 prompt 历史（跨会话搜索用） | 0.2MB | 低 |
| `~\.cache\codex-runtimes\codex-primary-runtime\dependencies\` | **沙箱运行时**：native 517MB / node 391MB / python 419MB | 1.33GB | 中 |
| `~\.cache\codex-runtimes\codex-runtime-install-*\` | 运行时安装暂存残留 | **114.6MB** | 可删 |
| `%APPDATA%\npm\` | npm 方式安装的包体 + shim（本机即此方式） | — | — |

### 3.2 增长点（社区案例）

- `sessions\` 是头号膨胀源：单任务生成 2393 个子会话文件共 **731GB**（issue #34061）；computer-use 截图让一个项目吃掉 **165GB**；compaction 不省盘，反而因重复拷贝截图 ~213 倍放大（issue #24948）。你同事的 40GB 即此类。
- `logs_2.sqlite` 案例 1.39GB（99 万行）；**WAL 文件可膨胀数百 GB，且被挂起/残留进程锁住时删了也不释放空间**（issue #22444）——删前必须杀干净 codex 进程。
- 本机实测增长主力排序：plugins 402M ＞ .sandbox-bin 280M ＞ sessions 179M ＞ .tmp 146M ＞ logs_2.sqlite 121M。

### 3.3 清理清单

- ✅ **可安全删（自动重建/重新下载）**：`logs_2.sqlite` 及 `-wal`/`-shm`（先杀进程）、`.tmp\`、`plugins\` 缓存、`.sandbox-bin\`、`cache\`、`codex-runtime-install-*` 暂存目录、`config.toml.backup.*`、`sandbox.*.log`、`generated_images\`、`attachments\`、`history.jsonl`、`models_cache.json`
- ⚠️ **有损**：旧 `sessions\*.jsonl`、`archived_sessions\`（失去 `codex resume` 能力，不可逆，先备份）
- ❌ **勿删**：`config.toml`、`auth.json`、还想 resume 的 sessions + `session_index.jsonl`（删了会话从列表消失）
- 沙箱运行时 `dependencies\` 1.33GB：删了下次进沙箱会**重新下载**——不属于"垃圾"，建议 junction 搬走而非删
- **没有内置 cleanup 命令**；官方只有 `codex delete <会话>`、`codex archive/unarchive`、TUI `/delete`；社区第三方：`npx codex-cleaner`（归档孤儿 rollout、VACUUM sqlite、截断 WAL）

### 3.4 搬家

- CLI：`CODEX_HOME` 官方支持（目标目录须**预先存在**）；另有 `CODEX_SQLITE_HOME` 单独搬 SQLite 状态。
- **坑（官方承认）**：Windows 桌面 App 硬编码 `%USERPROFILE%\.codex`，**忽略 CODEX_HOME**（issue #34070）——要连桌面版一起搬只能 `mklink /J`。
- 本机实测 runtimes 在 `~\.cache\codex-runtimes`（不在 ~\.codex 内），官方文档未明确该缓存随 CODEX_HOME 走——稳妥做法是对它单独 junction。

---

## 四、腾讯 WorkBuddy（即你口中的 "workbaddy"）

**身份确认**：搜索全部拼写变体后锁定为**腾讯 WorkBuddy**（workbuddy.ai）——媒体所称"Harness"（五层执行中间层）的产品；出自 CodeBuddy 团队，其 CLI 即 `npm i -g @tencent-ai/codebuddy-code`。已排除：buddy.works 的 CI/CD 平台（非 coding harness）、"Warp Buddy"（不存在该产品）。本机 `~\.workbuddy`、`%LOCALAPPDATA%\WorkBuddy`、`@genieworkbuddy-desktop-updater` 佐证。

### 4.1 数据落在哪（本机实测）

| 路径 | 放什么 | 本机 |
|---|---|---|
| `~\.workbuddy\binaries\` | 内置运行时：PortableGit 132M / node 100M / python 53M（**路径硬编码**） | 284MB |
| `~\.workbuddy\plugins\`（含 `cache\`） | 已装插件 + 插件缓存 | 124MB |
| `~\.workbuddy\connectors-marketplace\` | 连接器市场缓存 | 32MB |
| `~\.workbuddy\app\` | Electron 应用数据（Crashpad、session、window-state） | 17MB |
| `~\.workbuddy\logs\` / `traces\` | 按日期运行日志 / OpenTelemetry 追踪 | 7.1 / 1.9MB |
| `~\.workbuddy\projects\`、`sessions\`、`plans\`、`memory\`、`skills\`、`shell-snapshots\` 等 | 项目会话记录、计划、记忆、技能、沙箱快照 | 各 <1MB |
| `~\.workbuddy\` 根文件 | `SOUL.md`/`IDENTITY.md`/`USER.md`/`BOOTSTRAP.md`（人格记忆）、`settings.json`、`models.json`、`workbuddy.db`、`edge-sync-mapping-v2.db` | **必留** |
| `~\.workbuddy-key-fallback\connector-keys\` | 连接器密钥兜底 | **必留** |
| `%LOCALAPPDATA%\WorkBuddy\` | 客户端日志（main.log/main.old.log/renderer.log） | 6.3MB |
| `%LOCALAPPDATA%\@genieworkbuddy-desktop-updater\installer.exe` | **自动更新安装包残留** | **396MB** |
| `%TEMP%\workbuddy-update-x64\` | **解压的更新包残留** | **396MB** |
| `%USERPROFILE%\WorkBuddy\`、`WorkBuddy-temp\` | 默认主工作区；任务时间戳快照缓存（藏历史版本） | 小 |
| 项目级 `{workspace}\.workbuddy\` | 项目记忆（MEMORY.md）、plans、settings.local.json | 随项目 |

### 4.2 清理清单

- ✅ **立即回收 792MB**：`@genieworkbuddy-desktop-updater\installer.exe` + `%TEMP%\workbuddy-update-x64\`——纯更新残留（本调研未删，仅只读确认）
- ✅ `logs\`/`traces\` 旧日期子目录、`plugins\cache\`、`%LOCALAPPDATA%\WorkBuddy\` 旧日志；`WorkBuddy-temp\`（**先确认无要找回的历史版本**）
- ⚠️ 有损：`sessions\`/`projects\`/`memory\` 等记忆与历史
- ❌ 勿删：`SOUL.md`/`IDENTITY.md`/`USER.md`/`BOOTSTRAP.md`、`settings.json`、`workbuddy.db`、`connector-keys\`、`%APPDATA%\WorkBuddy\` 的 `config.json`/`auth_tokens.enc`（若存在）
- 社区定位：把 `~\.workbuddy` 当**大脑**而非缓存——只清缓存和更新残留，别动记忆

### 4.3 搬家

- 官方：`WorkBuddy.exe --user-data-dir="D:\..."`（首次启动自动重建目录结构，**不自动迁移旧数据**）；2026.3 起内置"帮助 → 高级工具 → 存储路径迁移"图形化向导（带 SHA256 校验）
- 社区：`mklink /J` 联接 `.workbuddy` 与 `.skillhub`；**仅改环境变量不够（binaries 路径硬编码）**；更新器按默认路径找数据，路径不符可能导致数据"丢失"
- 更新解压大量写系统 `%TEMP%`——把 TEMP/TMP 环境变量指到别的盘可根治"更新时 C 盘爆满"

### 4.4 同族：CodeBuddy（腾讯云代码助手，同一团队）

- CLI 数据目录 `~\.codebuddy`（本机仅 4KB skills 空壳）：`projects\`（各项目会话 .jsonl + 子代理 tool-results）、`sessions\`、`plans\`、`logs\`、`traces\`、`file-history\`（供 /rewind）、`history.jsonl`（供 /resume）、`blobs\`（图片/截图）、`plugins\`（含 marketplaces 临时 zip）、`shell-snapshots\`、`computer-use\`、`usage-data\`
- **必留**：`settings.json`、`CODEBUDDY.md`、`agents\`、`rules\`、`skills\`、`mcp.json`；删 `history.jsonl` 失去 /resume、删 `file-history\` 失去 /rewind
- 环境变量 `CODEBUDDY_CONFIG_DIR` 可改配置目录；v2.107.0 起自动清超过 1 小时的插件市场孤儿临时文件
- IDE 版：`%APPDATA%\CodeBuddy CN`（缓存/配置）、`%APPDATA%\@genie`（后端）、`%LOCALAPPDATA%\CodeBuddyExtension`

---

## 五、Google Antigravity 与 Gemini CLI

> 背景：**Gemini CLI 已被 Google 退役**（2026-05-19 宣布过渡到 Antigravity CLI，2026-06-18 起个人账户停服）；Antigravity CLI（`agy`）是继任者。Antigravity 桌面 IDE、IDE 扩展、CLI 三者与 Gemini CLI **共用 `~\.gemini` 目录体系**。

### 5.1 数据落在哪（本机实测）

| 位置 | 放什么 | 本机 |
|---|---|---|
| `%LOCALAPPDATA%\Programs\antigravity\` | **程序本体**（Antigravity.exe、app.asar、Chromium 运行时） | **520MB** |
| `%LOCALAPPDATA%\antigravity-updater\` | 更新器暂存：installer.exe、`pending\Antigravity-x64.exe`（每次更新存完整安装包） | **266MB** |
| `%APPDATA%\Antigravity\` | Chromium/Electron 用户数据：`Cache\` 24MB、`Code Cache`、`GPUCache`、`Dawn*Cache`、`Local Storage`、`logs\`（main.log / language_server.log）、`Preferences`、`Local State`、`app_storage.json`、`bin\agy-node.cmd` | 27MB |
| `~\.gemini\antigravity\` | 主数据目录：`conversations\<brain-id>.db`（**SQLite 会话库** + -wal/-shm）、`brain\<id>\`（上传的知识）、`builtin\skills\`、`knowledge\`、`annotations\`、`crashes\`、`bin\webm_encoder.exe`（13MB 录制编码器）、`installation_id`、`agyhub_summaries_proto.pb` | 14MB |
| `~\.gemini\antigravity-ide\` | IDE 扩展变体的状态（结构同上） | 14MB |
| `~\.gemini\antigravity-backup\` | 安装/升级时创建的备份 | 14MB |
| `~\.gemini\config\` | `config.json`、**`mcp_config.json`（MCP 全局配置的官方位置）** | <0.1MB |

> 本机没有 `~\.antigravity`、`%LOCALAPPDATA%\Antigravity` 目录；**凭证不落盘**——token 存 Windows 凭据管理器（Credential Manager）。

### 5.2 Gemini CLI（已退役，若还在用）

- `~\.gemini\` 其余内容：`settings.json`、`trustedFolders.json`、`GEMINI.md`、`tmp\<项目hash>\chats\`（**会话历史**）、`tmp\...\shell_history`、`checkpoints\`、`history\<项目hash>\`（checkpointing 影子 git 快照）、`extensions\`、`skills\`、`bin\litert\`
- 官方环境变量：**`GEMINI_CLI_HOME`**（改用户级根目录）、`GEMINI_CLI_TRUSTED_FOLDERS_PATH` 等；**`GEMINI_HOME` 不是受支持变量**
- 会话保留策略：`general.sessionRetention`（maxAge 默认 30 天）；手动清理 `gemini --list-sessions` → `--delete-session`

### 5.3 清理清单

- ✅ 可安全删：`%LOCALAPPDATA%\antigravity-updater\`（266MB 更新暂存，含 pending 完整安装包）；`%APPDATA%\Antigravity\` 下的 `Cache`、`Code Cache`、`GPUCache`、`Dawn*Cache`、`logs`、`Dictionaries`；`~\.gemini\antigravity\crashes\`；`~\.gemini\antigravity-backup\`（保留最近一份更稳妥）
- ⚠️ 有损：`~\.gemini\antigravity\conversations\*.db`（删单个会话也可用 Agent 面板垃圾桶；永久不可撤销）
- ❌ 勿删：`%LOCALAPPDATA%\Programs\antigravity\`（程序本体，卸载走设置→应用）；`~\.gemini\config\mcp_config.json`（MCP 配置）；`%APPDATA%\Antigravity\User\settings.json`（若存在）
- 卸载注意：常规卸载**不删用户数据**，需手动删 `%APPDATA%\Antigravity` + updater + Programs 目录；凭证在凭据管理器里删 "antigravity" 条目
- 无内置缓存清理命令；官方文档没有数据目录/卸载清理页，清理流程均来自社区

### 5.4 搬家

- **Antigravity 无任何官方路径环境变量**（社区实测 `GEMINI_HOME`/`GEMINI_CLI_HOME` 均被忽略）——只能 `mklink /J` 联接 `~\.gemini` 与 `%APPDATA%\Antigravity`；安装目录可在安装时用 `/DIR="..."` 参数选盘
- Gemini CLI：`GEMINI_CLI_HOME` 官方支持
- Antigravity CLI（agy）：数据 `~\.gemini\antigravity-cli\settings.json`，安装 `%LOCALAPPDATA%\agy\bin`；可用 `AGY_CLI_DISABLE_AUTO_UPDATE=true` 关自动更新

---

## 六、Cursor

### 6.1 数据落在哪

| 位置 | 放什么 |
|---|---|
| `%APPDATA%\Cursor\User\workspaceStorage\<哈希>\state.vscdb` | **每工作区一份的聊天历史库**（目录名是文件夹路径哈希，改路径即失联） |
| `%APPDATA%\Cursor\User\globalStorage\state.vscdb` | 全局会话库（token 统计等） |
| `%APPDATA%\Cursor\User\` | settings.json、keybindings.json、snippets、History |
| `%APPDATA%\Cursor\` 根层 | `Cache`、`CachedData`、`CachedExtensionVSIXs`、`Code Cache`、`GPUCache`、`Dawn*Cache`、`Crashpad`、`logs`、`blob_storage`、`Local Storage`、`machineid`、`Local State` 等（Electron 全套） |
| `%LOCALAPPDATA%\Cursor` | 崩溃日志、GPU 缓存、Code Cache |
| `~\.cursor`（Cursor 2.x） | `argv.json`、`extensions\`、`projects\`、`worktrees\`、`index\`；**CLI 会话** `chats\<id>\<uuid>\store.db`（SQLite，与 IDE 不互通、无自动删除）；ACP 模式 `acp-sessions\` |
| 程序 | `%LOCALAPPDATA%\Programs\cursor`（或 %ProgramFiles%\Cursor；系统级安装另写 C:\ProgramData\Cursor） |

### 6.2 增长点

- `workspaceStorage` 聊天史随用量线性增长，有用户 `User\` 超 32GB
- **已知 bug**：`snapshots\roots` 与 `snapshots\codebases` 在重启后以 ~1GB/s 膨胀，单日 44–180GB（版本相关，2.5 版修复）
- 代码库索引 `~\.cursor\index`

### 6.3 清理清单

- ✅ 可安全删：`Cache`、`Code Cache`、`CachedData`、`CachedExtensionVSIXs`、`GPUCache`、`Crashpad`、`logs`、`Backups`、`blob_storage`、`Dictionaries`（自动重下）
- ⚠️ 删前备份：`User\workspaceStorage`（**聊天史仅存本地，删除不可恢复**）
- ❌ 勿删：`User\settings.json`、`User\keybindings.json`、`User\globalStorage\state.vscdb`（登录态）、`Local State`、`machineid`
- 控增长：设置 `"cursor.codebaseIndexing.enabled": false` 关索引

### 6.4 搬家

- **无官方搬家变量**（CLI chats 受 XDG_CONFIG_HOME 影响，Windows 上不实用）。干净重装 = 删 `%APPDATA%\Cursor` + `%LOCALAPPDATA%\Cursor` + `~\.cursor`；想保留数据搬盘 = junction。
- 本机 45MB，非常健康，不用管。

---

## 七、Windsurf（本机未安装，要点备用）

| 位置 | 放什么 |
|---|---|
| `%APPDATA%\Windsurf\` | `User\settings.json`、`User\globalStorage\`（state.vscdb 登录态）、logs、Cache、GPUCache、Code Cache、CachedData、CachedExtensionVSIXs |
| `%LOCALAPPDATA%\Windsurf` | 崩溃/GPU 缓存 + 程序本体 |
| `~\.codeium\windsurf\cascade\` | **Cascade 对话历史**（.pb 文件，核心增长点）；`memories\`（记忆）；`hooks.json` |
| `~\.windsurf\extensions` | 扩展 |

- 删 Cascade `.pb` 可解决约 80% Cascade 报错，但**丢对话史**；`User\globalStorage` 勿删（登录态）
- 无官方搬家变量

---

## 八、Trae / MarsCode（字节系）

> 品牌关系：2025 年 4 月豆包 MarsCode 编程助手并入 Trae 品牌（Trae 桌面端 + Trae 插件 + MarsCode Cloud IDE，同账号体系）。本机 `.trae`、`.trae-cn` 基本为空（装过未深用）。

### 8.1 数据落在哪（默认全在 C 盘，与安装位置无关）

| 位置 | 放什么 |
|---|---|
| `%APPDATA%\Trae`（国际版）/ `%APPDATA%\Trae CN`（国内版） | 用户数据根：`User\workspaceStorage`（项目索引）、`ModularData\ai-agent\database.*`（**AI 对话库，有用户 30GB+**）、`Cache\ModelCache`（**模型缓存 15–30GB**）、`logs`（**无轮转，半年十几 GB**） |
| `~\.trae\` | `extensions\`（几 GB）、`snapshots\`（项目快照 10–20GB）、`cache\entire_cache_v2`（上下文缓存）、`memory\` |
| `~\.trae-cn\memory\` | 国内版全局记忆 user_profile.md + 各项目 project_memory.md |

### 8.2 清理清单

- ✅ 可安全删：`logs\`（C 盘爆满主因）、`Cache\ModelCache`、旧 snapshots（30 天前）、`workspaceStorage`（重建索引）、`entire_cache_v2`（删后 /clear context）
- ⚠️ 有损：`ModularData`（丢对话历史）、memory 文件（丢记忆）
- ❌ 勿删：`User\` 下设置、快捷键、代码片段、登录态
- **内置清理**：帮助 → 进程管理器 → 磁盘 标签（可视化清理 + 自动清理日志开关）；命令面板 `Trae: Clear Cache`；CLI：`trae model prune --keep-latest 2`、`trae cache clean`

### 8.3 搬家

- IDE：官方无路径设置，只能 `mklink /J` 联接 `%APPDATA%\Trae CN`
- CLI：官方环境变量 `TRAE_HOME`

---

## 九、豆包 Doubao（本机 0.71GB）

- `%LOCALAPPDATA%\Doubao\`：`Application\` + `User Data\`（10,543 个文件，Electron 应用）；`%APPDATA%\Doubao` 仅 public_config.json
- 与 Trae 同厂商（字节）但独立产品
- 无官方搬家，`mklink /J` 可迁移；卸载后 AppData 残留需手动删

---

## 十、通义灵码 Lingma 与 Qoder（阿里系）

> 两者**共用同一后端引擎**：本机 `%LOCALAPPDATA%\.lingma`（ai_tracker/env/i18n/profiler/workingSpace）与 `%LOCALAPPDATA%\.qoder-cn\shared_client\` 结构完全同构。

### 10.1 通义灵码（本机 15.1MB，轻量）

| 位置 | 放什么 |
|---|---|
| `~\.lingma\` | `bin\`、`extension\`、`model\`、`tmp\`、`logs\`、`cache\`（completion/embedding/metrics）、**`index\`**（`index\meta\v4\index.db` 是最大头，社区单文件 3GB、总占用 10GB 案例；`project_xxx\` AST/向量；`knowledgebases\` 数 GB）、`history\`（会话上下文）、`config.json` |
| `%LOCALAPPDATA%\.lingma\` | 遥测与性能数据 |

- 清理：先任务管理器结束 `lingma.exe`/`LingmaService`（锁 index.db）→ **整删 `~\.lingma`**（只删子目录会立刻重建膨胀）→ 重启 IDE 重新登录
- 可删：cache/、logs/、tmp/、history/archive、index/（重建，损失加速）、本地模型 `~\.qwen-models`
- **无官方搬家**；社区方案改插件 extension.js（更新即失效）

### 10.2 Qoder（本机 2.9MB，轻量）

| 位置 | 放什么 |
|---|---|
| `%APPDATA%\Qoder\` | settings.json；**`indexdb\`**（全局索引库，删时**保留 `schema_version.json`** 否则重建失败）；`SharedClientCache`（会话缓存，`.info.json` 记 pid/port） |
| `~\.qoder\` / 项目 `{项目}\.qoder\` | 配置、记忆快照、符号索引、向量库 |
| `%LOCALAPPDATA%\.qoder-cn\shared_client\` | 用户缓存（2 个月可到 5GB） |

- 官方搬家：`QODER_CONFIG_DIR`；CLI 另有 `--config-dir`/`--data-dir`
- 清理：`qoder cache flush --project --force`；项目根 `.qoderignore`（.gitignore 语法）排除 node_modules 从源头控索引；`memory_persistence: false` 零缓存运行；远程开发场景 `index\meta\v7\index.db` 有 70GB 案例
- 删前先结束 Qoder/lingma.exe 进程

---

## 十一、Kilo Code 与 Roo Code（VS Code 扩展型）

> 扩展型工具数据挂在 VS Code 的 `%APPDATA%\Code\User\globalStorage\<扩展ID>\` 下；本机 `.kilocode` 4KB、`.roo` 空——基本未使用。

### 11.1 共享结构

- `tasks\<taskId>\`：`ui_messages.json`（界面消息）、`api_conversation_history.json`（原始 API 交换）、`task_metadata.json`
- **checkpoints**：每工作区一个 shadow git 仓库（不在项目 .git 里）——最大的膨胀源

### 11.2 Roo Code

- 内置历史保留策略 **90/60/30/7/3 天**（默认 Never，启动时自动删旧任务）；checkpoint 30 天未触碰自动后台清理（只删快照保留对话）
- `enableCheckpoints: false` 关闭快照；社区有 checkpoints 膨胀到 51GB、单任务 5GB 案例
- 直接删整个 globalStorage 目录可行（丢全部历史）

### 11.3 Kilo Code

- 新架构：配置 `~\.config\kilo\kilo.jsonc`；数据 `~\.local\share\kilo\`（auth.json 0600）；**快照仓库** `~\.local\share\kilo\snapshot\<project-id>\<worktree-hash>\`（不碰项目 .git）
- 自动清理：`git gc --prune=7.days` 每小时清 7 天前不可达对象；可 `"snapshot": false` 关闭
- 搬家：`KILO_CONFIG_DIR`（仅配置）、`XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_CACHE_HOME`（完整隔离）

---

## 十二、Continue（本机 2.13GB，重点处理对象）

### 12.1 数据落在哪

| 位置 | 放什么 | 本机 |
|---|---|---|
| `~\.continue\index\index.sqlite`（+WAL） | **代码库嵌入索引** | **2,130MB（本机 100%）** |
| `~\.continue\index\autocompleteCache.sqlite` | 补全缓存 | 小 |
| `~\.continue\config.yaml` | 配置（contextProviders 等） | 必留 |
| `~\.continue\skills\` | 技能 | 小 |

### 12.2 核心问题

- 索引**无大小上限、无 GC**——社区报告 20–51GB，极端 300GB+（issue #4309，2026-02 仍被重开）
- 本机 2.13GB 全部来自 index.sqlite

### 12.3 清理与根治

- ✅ 立即回收：删 `~\.continue\index\`（重开 VS Code 自动重建）
- 根治：`config.yaml` 的 `contextProviders` 去掉 `codebase` 项即彻底停止索引；`.continueignore`（支持全局 `~\.continue\.continueignore`）排除 node_modules 等
- 搬家：`CONTINUE_GLOBAL_DIR`（Linux 验证可用，**Windows 不保证**）

---

## 十三、Aider（本机未安装，要点备用）

- 缓存：`~\.aider.cache\`（需 `--cache` 启用；hash.json 提示词精确匹配缓存，**永不过期、无自动清理**）——可整体删
- 项目内（散落在各仓库）：`.aider.chat.history.md`（聊天史）、`.aider.model.settings.yml`、`.aider.input.history`
- 搬家：`AIDER_CACHE_DIR` / `--cache-dir`；`AIDER_CONFIG`

---

## 十四、OpenCode（本机未安装，要点备用）

- 数据目录 `~\.local\share\opencode\`：`auth.json`（**必留**）、`log\`、`project\<slug>\storage\` → `session\`/`message\`/`part\` JSON（会话与消息，**无自动清理**，有单日志 2.6GB 案例）
- 搬家：`OPENCODE_DATA_DIR`（最高优先级）、`OPENCODE_DB`
- 清理：`storage\` 可删（丢会话史）

---

## 十五、Google Amp（本机未安装，要点备用）

- CLI 数据 `~\.local\share\amp\`：`threads\T-<uuid>.json`（每线程一个 JSON，服务器为真源、本地是同步镜像且**永不自动清理**）、`secrets.json`（token）、`history.jsonl`、`session.json`、`device-id.json`
- 日志 `~\.cache\amp\logs\cli.log`；搬家：`AMP_DATA_DIR`
- 清理：本地文件可手删（服务器侧 30 天内删线程数据）；`~\.cache\amp` 可整体删
- 注意区分：Sourcegraph 时代旧 CLI 用 `~\.amp` 与 `~\.config\amp`

---

## 十六、Warp（本机未安装，要点备用）

- `%APPDATA%\warp\Warp\data\`（themes、workflows）；`%LOCALAPPDATA%\warp\Warp\config\`（settings.toml、keybindings.yaml）；`%LOCALAPPDATA%\warp\Warp\data\`（logs、**`warp.sqlite`**、Codebase Context 索引、MCP 日志）；`~\.warp\.mcp.json`、`~\.agents\`（Agent 配置）
- **`warp.sqlite` 的 blocks 表（会话回放缓冲）无上限、无 TTL**，实测 200MB–1GB+，导致启动卡死（issue #8835）
- 清理：`sqlite3 warp.sqlite "DELETE FROM blocks; VACUUM;"`（约 400MB→30MB，保留窗口/对话/命令历史）；`cache\`、`logs\` 可删
- 无搬家变量

---

## 十七、CodeGeeX（本机 0.32GB，实测结构）

| 路径 | 放什么 | 本机 |
|---|---|---|
| `~\.codegeex\mamba\` | **本地模型运行环境**（micromamba 类环境，CodeGeeX 本地推理依赖） | **309.6MB** |
| `~\.codegeex\agent\` | Agent 配置与数据 | 8.4MB |

- 不用 CodeGeeX 的本地模型功能则可整体删；只用云端补全则可删 `mamba\`（重装插件会重新下载环境）

---

## 十八、其他本机痕迹（简要）

| 目录 | 实测 | 说明 |
|---|---|---|
| `~\.dsh\`（DeepSeek） | 24.5MB | `profiles\` 20.1M、`sessions\` 4.4M；`.credentials.yaml`、`settings.yaml` 勿删 |
| `~\.agents\`（Warp Agent） | 12.2MB | `skills\` |
| `~\.hf-cli\`（HuggingFace） | 43.7MB | `venv\` 虚拟环境，可删（重新初始化） |
| `~\.codegeex\` | 0.32GB | 见上节 |
| `~\.qwen\`、`~\.grok\`、`~\.openhands\`、`~\.augment\`、`~\.tabnine\`、`~\.vibe\`、`~\.kode\`、`~\.pi\`、`~\.moxby\`、`~\.kiro\`、`~\.roo\`、`~\.kilocode\` 等约 30 个 | 各 <0.01GB | 装过未深用的空壳，确认不再用可直接删目录 |
| `%LOCALAPPDATA%\claude-cli-nodejs\`、`cloud-code\`、`CodeBuddyExtension\` | <0.01GB | 相关工具残留 |

---

## 十九、跨工具通用清理规则

### 19.1 Electron / VS Code fork 统一可安全删除清单

所有基于 Electron 或 VS Code fork 的工具（Antigravity、Cursor、Windsurf、Trae、Doubao、CodeBuddy IDE、Kilo/Roo 挂载的 VS Code 等）通用：

```
Cache、Code Cache、CachedData、CachedExtensionVSIXs、CachedProfilesData、
GPUCache、Dawn*Cache、Crashpad、logs、Backups、blob_storage、Dictionaries
```

### 19.2 统一勿删清单（删 = 重新登录/重配）

```
User\settings.json、User\keybindings.json、state.vscdb / storage.json（登录态）、
machineid、Local State、auth.json / credentials* / secrets.json（各 CLI 凭证）、
config.toml / config.yaml / settings.yaml（各工具主配置）
```

### 19.3 三条铁律

1. **先杀进程再删**：索引库（index.db、index.sqlite）和 SQLite 日志被运行中的进程独占锁定；Codex 的 WAL 文件被挂起进程锁住时删了也不释放空间。
2. **聊天史删前备份**：workspaceStorage（Cursor）、Cascade .pb（Windsurf）、tasks\（Roo/Kilo）、sessions（Codex/WorkBuddy/dsh）、history.jsonl（CodeBuddy）——全是本地唯一副本。
3. **索引类"可删但会重建"**：删了释放空间、损失加速，工具下次启动重建；想根治要关功能（.continueignore、codebaseIndexing.enabled=false、.qoderignore、checkpoints: false）。

---

## 二十、搬家方法汇总表

| 工具 | 官方搬家途径 | 备注 |
|---|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` | 搬整个 ~\.claude；程序本体 .local 只能 junction |
| Codex CLI | `CODEX_HOME`、`CODEX_SQLITE_HOME` | 桌面 App 硬编码路径不认（只能 junction）；runtimes 在 ~\.cache 需单独 junction |
| CodeBuddy CLI | `CODEBUDDY_CONFIG_DIR` | 运行时数据目录未见官方变量 |
| Trae CLI | `TRAE_HOME` | IDE 无，只能 junction |
| Qoder | `QODER_CONFIG_DIR`、`--config-dir/--data-dir` | 官方 |
| WorkBuddy | `--user-data-dir` 参数、内置迁移向导 | binaries 路径硬编码，向导最稳妥 |
| Gemini CLI | `GEMINI_CLI_HOME` | 官方；注意 `GEMINI_HOME` 不受支持 |
| Antigravity | 无 | 桌面 IDE 忽略一切路径变量；安装时 `/DIR` 可选盘，数据只能 junction |
| OpenCode | `OPENCODE_DATA_DIR`、`OPENCODE_DB` | 官方 |
| Amp | `AMP_DATA_DIR` | 官方 |
| Kilo | `XDG_DATA_HOME` 等、`KILO_CONFIG_DIR` | 仅配置 |
| Aider | `AIDER_CACHE_DIR` | 仅缓存 |
| Continue | `CONTINUE_GLOBAL_DIR` | Windows 不保证 |
| **无官方途径** | Cursor、Windsurf、Roo、Warp、灵码、Comate、ZCode、豆包、Antigravity | 只能 `mklink /J` 或关功能控增长 |

**junction 标准操作**（不需要管理员权限）：

```cmd
:: 先退出工具 → 复制数据 → 建联接 → 验证 → 删原目录
robocopy "C:\Users\你\.codex" "D:\AI-Tools\.codex" /E
mklink /J "C:\Users\你\.codex" "D:\AI-Tools\.codex"
```

---

## 二十一、本机立即回收清单（按大小排序，2026-08-23 实测）

| # | 路径 | 大小 | 操作 | 风险 |
|---|---|---|---|---|
| 1 | `~\.continue\index\` | **2.13GB** | 删（重开 VS Code 自动重建）；根治：config 去掉 codebase provider | ✅ 无 |
| 2 | `%LOCALAPPDATA%\npm-cache\` | **1.63GB** | `npm cache clean --force` 或 `npm config set cache D:\npm-cache` | ✅ 无 |
| 3 | `~\.cache\codex-runtimes\codex-runtime-install-*\` | **114.6MB** | 删（安装暂存残留） | ✅ 无 |
| 4 | `~\.cache\codex-runtimes\...\dependencies\` | **1.33GB** | 不建议删（会重下）；junction 搬走 | ⚠️ 会重新长回 |
| 5 | `%LOCALAPPDATA%\@genieworkbuddy-desktop-updater\installer.exe` | **396MB** | 删（更新包残留） | ✅ 无 |
| 6 | `%TEMP%\workbuddy-update-x64\` | **396MB** | 删（解压残留） | ✅ 无 |
| 7 | `~\.codex\plugins\`（缓存部分） | **402MB** | 删（重下） | ✅ 重下 |
| 8 | `~\.codex\.sandbox-bin\` | **280MB** | 删（自动重建） | ✅ 重建 |
| 9 | `~\.codex\.tmp\` | **146MB** | 删 | ✅ 无 |
| 10 | `~\.codex\logs_2.sqlite`（含 -wal/-shm） | **121MB** | 先杀干净 codex 进程再删 | ✅ 无 |
| 11 | `%LOCALAPPDATA%\@comfyorgcomfyui-electron-updater\` | **0.28GB** | 删（非 harness，顺手发现） | ✅ 无 |
| 12 | `%LOCALAPPDATA%\antigravity-updater\` | **0.27GB** | 删（更新器暂存：installer.exe + pending 完整安装包）；顺带 `~\.gemini\antigravity-backup\` 14MB 可删（保留最近一份） | ✅ 无 |
| 13 | `~\.local\share\claude\versions\` 旧版本 | 约 0.7–0.9GB | 删旧版本目录（保留当前） | ✅ 无 |
| 14 | `~\.codegeex\mamba\` | **309.6MB** | 不用本地模型可删 | ⚠️ 功能损失 |
| 15 | `~\.claude\plugins\` 缓存 | **180MB** | 谨慎（含你装的插件） | ⚠️ 重下 |
| 16 | 约 30 个空壳点目录（.grok/.openhands/.vibe 等） | 合计 <0.1GB | 确认不用后整目录删 | ✅ 无 |

**合计：立即可回收约 6.5GB（#1+2+3+5+6+9+10+11+12+13），再谨慎处理 #4/#7/#8/#14 可到 ~8.5GB。**
其中 #1、#5+6、#11 是纯浪费，建议优先。（Antigravity 程序本体 520MB 在 `%LOCALAPPDATA%\Programs\antigravity`，属安装本体——想省只能卸载或重装时 `/DIR` 选别的盘。）

---

## 附录：主要来源

**官方文档**：Claude Code 官方 docs（setup.md / sessions.md / data-usage.md / settings-reference.md，code.claude.com）；Codex 官方环境变量文档（learn.chatgpt.com/docs/config-file/environment-variables）；CodeBuddy 目录结构文档（codebuddy.cn/docs/cli/codebuddy-dir）；Trae 官方环境变量（docs.trae.cn/cli_environment-variables）与记忆文档（docs.trae.cn/ide_memories）；Qoder 官方 FAQ/排障/CLI 参考（docs.qoder.com）；WorkBuddy 卸载文档（tencentcloud.com/techpedia/144211）；Kilo 官方 checkpoints 文档（kilo.ai/docs）；Warp 官方 file locations（docs.warp.dev）；Sourcegraph 本地索引文档；Aider 缓存文档；Antigravity 官方 CLI 文档与迁移页（antigravity.google/docs/cli/gcli-migration/）；Gemini CLI 官方文档（github.com/google-gemini/gemini-cli/docs/reference/configuration.md）。

**关键社区案例**：Codex issue #34061（单任务 731GB）、#24948（compaction 213 倍放大）、#22444（WAL 数百 GB）、#33644（日志 1.39GB）、#34070（桌面 App 硬编码路径）；Continue issue #4309（索引 300GB）；Warp issue #8835（blocks 无 TTL）；Roo PR #9262（checkpoint 自动清理）；Kilo issue #536（快照 100GB）；Qoder 论坛 index.db 70GB 帖；Trae 论坛与腾讯云社区日志清理帖；头条 Codex 165GB 截图案例；php.cn / CSDN / 知乎的国产工具清理与迁移教程；Gemini CLI 退役公告（github discussions/27274）；Antigravity 卸载指南（agentpedia.codes）与 Google AI 论坛清理帖（discussions 114671 / 122093）。

---

*报告完。执行任何删除前请退出对应工具；本报告未对任何文件做修改，全部为只读调研。*
