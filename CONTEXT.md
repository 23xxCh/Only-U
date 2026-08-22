# Only-U

U盘即插即用的运维 Agent：把 DeepSeek Harness（仓库 `dsh/` 快照，烤成密封运行时）与 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) 终端壳装进 **U盘包**，用户不用安装 Agent、不用配 Skill/MCP，插上就能做 **诊断** 和带 **误删防护** 的 **清理**。

## Language

**U盘包**:
插上即可运行的目录，含 DSH 运行时、插件、启动脚本和离线脚本。
_Avoid_: 安装包, App, 网卡套件

**运维会话**:
一次插盘到拔盘的修机过程。
_Avoid_: 聊天, ticket, 对话

**诊断**:
不调模型也能跑的机器检查（磁盘、内存、服务、近期错误）。
_Avoid_: 扫描全盘, 闲聊, 杀毒

**清理**:
有白名单的空间回收，必须先预览再确认执行。
_Avoid_: 删除, 格式化, 清空 C 盘

**误删防护**:
清理前预览；默认不碰用户文档、桌面、下载。
_Avoid_: 杀毒隔离

**插件**:
一条 DSH Cordis 插件或一条 Only-U skill，对应一类修机能力。
_Avoid_: 工具, MCP

**离线路径**:
无网时只跑本地脚本，不调用 LLM。
_Avoid_: 本地模型

**TUI 路径**:
有网时的终端运维壳，profile 为 `dsh-tui`（npm 插件 [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) 0.8.8）。仍调用 portable 脚本。仓库 `dsh-tui/` 是同源源码快照，不是 U 盘启动入口。
_Avoid_: Web 主入口, headless 一句退出, turtle-ui Git URL, 全局 npm dsh 当客户机依赖

**无线网卡路径**:
后续能力：用免驱 USB 网卡给无网机器上网。比赛期间不做。
_Avoid_: 硬件套件（当前交付）

**烘焙**:
在开发机把便携 Node、扁平 dsh CLI、dsh-tui profile 打进 **U盘包**。客户机不装 Node/pnpm。
_Avoid_: 安装到系统, 拷贝 dsh/node_modules

## Relationships

- 一次 **运维会话** 使用一个 **U盘包**
- **离线路径** 只做 **诊断**；有网走 **TUI 路径**，再把 **清理** 交给 Agent
- **清理** 必须经过 **误删防护**，不得跳过预览
- **无线网卡路径** 不在当前 **U盘包** 交付范围内
- **烘焙** 产出密封运行时；Cordis **插件** 在开发机装进 profile 后再 **烘焙**

## Example dialogue

> **Dev:** "没网的时候 Agent 怎么 **清理** C 盘？"
> **Domain expert:** "没网走 **离线路径**，只跑 **诊断**。有网走 **TUI 路径**，再让 Agent 按预览做 **清理**。不要上本地模型，也不要等无线网卡。"

## Flagged ambiguities

- 「硬件」曾指自制 USB 网卡 + 流量卡。已决议：比赛只做软件 **U盘包**；**无线网卡路径** 赛后再做。
- 「全自动」不是无人确认删文件。**清理** 一律预览 + 确认。
- 长 PRD 把 V1 写成「必须联网、无网禁止诊断」。已决议：本场仍走 **离线路径**；见 `docs/adr/0002-canonical-hackathon-scope.md`。
- 有网 Agent 壳是 **TUI 路径**，不是 headless、也不是 Web 主入口；见 `docs/adr/0003-dsh-tui-agent-shell.md`。
- U 盘 **烘焙** 用 `dsh/` 源码打扁平 CLI，见 `docs/adr/0005-usb-baked-dsh-runtime.md`。不要删除 `dsh/`，也不要整包拷 `dsh/node_modules`。
