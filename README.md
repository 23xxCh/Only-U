# Only-U · U盘即插即用电脑运维 Agent

把 DeepSeek Harness 内核与 AI Agent 装进一支普通 U 盘，插上双击即可用，不用安装任何开发环境。

仓库：https://github.com/23xxCh/Only-U

## 作品简介

### 1. 产品基本信息

Only-U 是一款搭载在普通 U 盘内的即插即用电脑运维工具，内置 DeepSeek Harness 内核与 AI Agent，插入设备后双击即可使用，普通用户无需安装任何开发环境。

### 2. 功能特性

（1）无网状态下可离线诊断 C 盘空间、临时文件、系统错误与打印机故障。

（2）有网状态下支持通过自然语言驱动 Agent 执行同一套运维脚本。

### 3. 安全说明

所有清理操作均先展示预览内容，经用户确认后才会执行，白名单范围之外绝不会误删用户资料，可让电脑运维操作像插入 U 盘一样简单。

## 操作说明

1. **插入 U 盘**：把 Only-U 拷入任意普通 U 盘（或直接打开仓库里的 `portable\` 目录），目标电脑需为 Windows 10/11。

2. **离线诊断**：双击 `portable\diagnose.cmd`，无网也能用。自动检查 C 盘空间、临时目录、近期系统错误与打印机故障，并输出诊断报告。

3. **清理预览**：双击 `portable\clean.cmd`，先只预览可回收空间与文件清单，不删除任何文件；核对无误后再运行 `portable\clean.cmd -Execute` 执行清理（或使用 `-Interactive` 逐项确认）。桌面、文档、下载等用户资料默认不在清理范围内。

4. **启动 AI Agent（有网时）**：双击 `portable\start.cmd`（或盘根 `启动Agent.cmd`），拉起 dsh-TUI。本点击不整包拷贝运行时：本地缓存的 BAKE-ID 与 U 盘一致就用缓存，否则直接从 U 盘跑。没有 Key 时粘贴一次即写入 `portable\.env`。TUI 打开后**自己跑**诊断 + 清理预览（不经模型，全文写入 `portable\logs\boot-latest.txt`）；看完三行「能清多少 / 不碰什么 / 说确认才删」后，输入「确认」或「执行」才会真正清理。没网仍可输入 `/clean` 选确认清理，或用盘根 `诊断.cmd`。也可以在 TUI 里输入 `/provider` 换成自己的模型。

**TUI 常用命令**

| 命令 | 作用 |
|---|---|
| 直接说话 | Agent 自动调用工具排查问题 |
| `!命令`（如 `!ipconfig`） | 本地执行命令，结果只给你看 |
| `!!命令` | 本地执行命令，结果同时发给 Agent 分析 |
| `/chajian` | 查看已安装的插件、命令与模型工具 |
| `/diagnose` | 运行完整诊断，报告存入 `portable\logs\` |
| `/clean` | 清理预览（只算可回收空间，不删除），确认后执行 |
| `/space` / `/空间` | 全屏查看 CPU / 内存 / 磁盘 / GPU 面板（`r` 刷新，`Esc` 退出；拼音别名 `/kongjian`） |
| `/provider` | 更换模型：自定义 OpenAI 兼容地址与 Key，凭据保存在 U 盘 |
| `/preset only-u-repair` | 切换维修模式（只挂 PowerShell 与 Only-U 工具） |
| `/preset standard` | 切回标准模式（默认） |

## 注意事项

- 仅支持 Windows 10/11，Mac / Ubuntu 本场不提供。
- 清理默认只预览，执行必须显式确认（`-Execute` / `-Interactive`）。
- `portable\.env` 里保存 API Key，不要发到 GitHub 或聊天。
- TUI 内不要输入 `/update`。启动器本点击不 robocopy、不 ping、不查进程；缓存未就绪就直接用 U 盘上的 Node。
- 客户机无需安装 Node、npm 或任何开发环境，运行时随 U 盘提供。
- TUI 只加载 U 盘上的 skill / 插件（不读客户机 `~/.agents`）。诊断脚本仍使用本机用户目录，以便清理真正的临时文件。

## 免责声明

Only-U 仅用于获得授权的本机电脑运维。执行清理前请核对预览清单，重要数据请自行备份；因用户误操作造成的数据损失，项目不承担责任。

## 相关项目

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) —— Agent 内核
- [dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) —— 终端运维壳

## 版权与商业化

Only-U 原创代码（`portable/`、`plugins/`、`.dsh/`、`scripts/`、盘根启动器及本仓库文档）采用 [MIT](LICENSE) 许可，版权所有 © 2026 陈熙贤。

允许个人使用、二次开发，也允许**商业销售烤好的 U 盘**。再分发（含卖盘）必须保留本仓库的 `LICENSE`、`NOTICE`，以及 `dsh/LICENSE` 与 `dsh-tui/LICENSE`。本许可不授予 Only-U 商标；API Key 不随仓库分发。第三方清单见 [NOTICE](NOTICE)。

## 问题反馈

问题与建议请提交 [GitHub Issues](https://github.com/23xxCh/Only-U/issues)。
