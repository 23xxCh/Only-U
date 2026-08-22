# U 盘密封运行时：扁平 dsh + 便携 Node

编号 0005：远程已占用 0004 为 dsh-TUI 源码快照提案。本 ADR 才是 **U 盘交付** 的已采纳做法。`dsh/` 源码快照保留，供 `scripts/bake-usb.ps1` 使用。

客户机没有 Node、pnpm、全局 `dsh`。不能把开发仓库的 `dsh/node_modules` 拷上 U 盘：pnpm 用几千个符号链接，FAT32 不能存链接，跟拷会把 1.3GB 涨成数 GB。

**Status:** accepted

## 两台机器，两套目录

| | 开发机（你 / 队友） | 客户机（评委 / 修机现场） |
|---|---|---|
| 要什么 | Git、Node 22+、pnpm、已 `pnpm run build` 的 `dsh/` | 只要 Windows + PowerShell |
| 干什么 | 写脚本、写 skill、写 Cordis **插件**、烤盘 | 双击 `诊断.cmd` / `启动Agent.cmd` |
| 禁止 | 在客户机 `pnpm install`、TUI 里 `/update` | 往客户机装 Node / 改系统 PATH |

仓库里的 `dsh/` 是源码快照，给开发用。U 盘上的 Agent 跑的是烤出来的 **密封运行时**，不读客户机环境。

## U 盘上必须有的（密封运行时）

```
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
      dsh\                    ← pnpm deploy 出的扁平 CLI（约 180MB 文件）
        lib\bin.js
        node_modules\         ← 无符号链接的生产依赖
        profiles\dsh-tui\     ← TUI profile（含插件）
        skills\only-u-ops\
```

`start.cmd`：

```bat
set "PATH=%~dp0runtime\node;%PATH%"
set "DSH_HOME=%~dp0runtime\dsh"
"%~dp0runtime\node\node.exe" "%~dp0runtime\dsh\lib\bin.js" --profile dsh-tui
```

缺 Node / 缺 CLI / 缺 profile / 缺 Key：立刻失败，中文指向 `诊断.cmd`。

## 怎么烤（只在开发机）

开发机先：

```bat
cd dsh
pnpm install
pnpm run build
pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui
```

然后打扁平 CLI（不要 robocopy `dsh\node_modules`）：

```bat
cd dsh
pnpm --filter @deepseek-ai/dsh deploy --legacy --prod --config.node-linker=hoisted --config.auto-install-peers=false --config.link-workspace-packages=true %TEMP%\only-u-dsh-deploy
```

把 `vendor/cosmokit`、`vendor/schemastery` 等 override 的包拷进 deploy 的 `node_modules\@deepseek-ai\`（deploy 不会跟 `link:` 覆盖）。再把 deploy 目录拷到 U 盘 `portable\runtime\dsh`。

Node：拷贝开发机的 `node.exe` 到 `portable\runtime\node\node.exe`（`^22.19 || >=24`）。

Profile：拷 `%USERPROFILE%\.dsh\profiles\dsh-tui` → `portable\runtime\dsh\profiles\dsh-tui`。

一键脚本：`scripts/bake-usb.ps1 -Dest F:\Only-U`。

`portable/runtime/` 不进 Git。

## FAT32

本场 U 盘是 FAT32。后果：

- 不能存 pnpm 符号链接 → 必须用上面的 deploy，禁止整包拷 `dsh/node_modules`
- 不能建 NTFS junction。dsh 启动时会尝试在 `$DSH_HOME/profiles/node_modules` 建 junction。烤盘时把 `DSH_HOME` 设成 `portable\runtime\dsh`，让模块解析走到旁边的真实 `node_modules`；并对盘上那份 `dsh-app-boot` 的 `ensureSymlink` 在 `EISDIR`/`EPERM` 时跳过（只改 U 盘副本，不改仓库 `dsh/`）

Windows 专用盘以后可转 NTFS，junction 就能用；本场不格式化已有盘。

## 后续运维插件往哪挂

DSH 是 **everything is a plugin**。客户机不装 pnpm，所以**不能在修机现场 `dsh plugin add`**。插件在开发机装进 profile，再烤进盘。

三层，由浅到深：

1. **离线脚本** `portable\*.ps1` — 没 Node 也能跑（诊断地板）
2. **skill** `.dsh/skills/only-u-ops` — TUI 里让 Agent 去调这些脚本
3. **Cordis 组合包**（二次开发）— 独立 npm 包，声明 `dsh.bundle`，不要改 `dsh/` 内核

组合包放仓库 `plugins/<name>/`（在 `dsh/` 外面）：

```
plugins/only-u-example/
  package.json          # "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
  cordis.patch.yml
  index.js
```

开发机安装进 TUI profile：

```bat
cd dsh
pnpm dsh plugin --profile dsh-tui add ..\plugins\only-u-example
```

然后重新 `scripts/bake-usb.ps1`。新插件随 `profiles\dsh-tui` 进盘。

教程：`dsh/docs/user/develop/basic/publish.zh.md`。不要 fork `dsh/`，不要 vendor dsh-TUI 源码，不要 TUI `/update`。

## Do

- 客户机零安装：双击盘上 cmd
- 运行时用 deploy 扁平树 + 便携 `node.exe`
- 运维能力优先脚本 + skill；Cordis 插件在开发机装进 `dsh-tui` 再烤盘

## Do not

- 把 `dsh/node_modules` 整包拷到 FAT32
- 指望客户机有 pnpm / 全局 `dsh.cmd`
- 在 U 盘上现场 `plugin add` 或 `/update`
- 把运行时、`.env`、profile 推进 Git
