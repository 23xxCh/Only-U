# ⑥ 会话编排 Skill（only-u-ops-skill）

## 1. 概述

功能域：**场景调度编排**。一份 SKILL.md 提示词规则，管住整个运维会话的流程：什么时候诊断、什么时候清理预览、什么情况才能执行清理、无网怎么办。它是 01–05、09–15 各功能插件的「总调度」——不实现具体功能，因此与它们不重复。

- 包名：`only-u-ops-skill`
- 开发状态：**已实现**（见 `插件文档\插件\only-u-ops-skill\`；SKILL.md 为插件自有版本，Tools 节已升级为优先 ops_* 工具）
- 插件形态：标准 dsh.bundle 包，通过 `ctx.skills.register` 把 SKILL.md 挂进技能注册表

## 2. 构成

```
plugins\only-u-ops-skill\
  package.json                  # dsh.bundle manifest
  cordis.patch.yml              # insert 行注册插件
  index.js                      # apply(ctx)：读包内 SKILL.md → ctx.skills.register
  skills\only-u-ops\SKILL.md    # 规则正文（插件自有版本，Tools 节含全部 ops_* 工具）
```

`index.js`（已实现）：

```js
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = 'only-u-ops-skill'
// 硬性要求：直取 ctx 服务必须声明 inject（缺了启动失败，见总设计 4.8）
export const inject = ['skills']

export function apply(ctx) {
  const pkgDir = dirname(fileURLToPath(import.meta.url))
  const content = readFileSync(join(pkgDir, 'skills', 'only-u-ops', 'SKILL.md'), 'utf8')

  // 技能注册表挂载（source: 'runtime'，随会话注入给模型）
  ctx.skills.register({
    name: 'only-u-ops',
    description: 'Only-U USB 运维会话。Windows 上做只读诊断和带误删防护的清理预览；无网用便携脚本。',
    source: 'runtime',
    content,
  })
}
```

注册接口依据：`dsh\packages\skill\tool-skill\tests\tool-skill.spec.ts`（`ctx.skills.register({ name, description, source: 'runtime', content })`）。

## 3. SKILL.md 规则（插件自有版本）

frontmatter：`name: only-u-ops`、`description: Only-U USB 运维会话。Windows 上做只读诊断和带误删防护的清理预览；无网用便携脚本。`

规则正文：
1. 先读仓库根 `CONTEXT.md`，用里面的术语，不发明同义词。
2. 优先调用 Only-U 注册的工具（见 Tools 节），而不是临时拼 shell 命令。
3. 运维会话一开始：先调 `ops_diagnose`，再调 `ops_clean`（execute=false 仅预览），两段输出都展示给人。
4. 诊断只读：不结束进程、不装驱动、不改系统。
5. 清理默认只预览。只有用户明确说「确认」「执行」后才调 `ops_clean`（execute=true）。确认条是最终门：模型说了不算，用户没在确认条上允许就不执行。不推荐第三方一键清理或注册表清理。
6. 永不删除桌面/文档/下载/图片（误删防护）。
7. 无网或模型不可达：告诉用户走离线路径 `portable\diagnose.cmd`，不假装有本地模型。
8. 无线网卡路径不做。

Tools 节：优先 `ops_diagnose` / `ops_clean`；第三方调度工具（装了对应插件才有）：`diag_tool_list`/`diag_tool_run`、`disk_tool_list`/`disk_tool_run`、`sys_tool_list`/`sys_tool_run`、`dbench_tool_list`/`dbench_tool_run`、`mon_tool_list`/`mon_tool_run`、`stress_tool_list`/`stress_tool_run`、`net_tool_list`/`net_tool_run`、`screen_tool_list`/`screen_tool_run`、`peri_tool_list`/`peri_tool_run`、`maint_tool_list`/`maint_tool_run`；内置脚本工具：`mon_battery_report`/`mon_nvidia_smi`、`stress_winsat`、`net_wifi_scan`/`net_port_check`、`screen_deadpixel`、`peri_usb_verify`、`maint_driver_clean`/`maint_dx_repair`（写盘/压测/写系统类走确认条）；工具缺失（旧 profile）才回退 `portable\*.cmd`。

## 4. 应用场景（场景调度总表）

用户一句话 → 走哪个插件：

| 用户的话 | 走哪个插件 | 动作 |
|----------|------------|------|
| 「C 盘满了」 | 01 诊断 + 02 清理预览 | ops_diagnose → ops_clean(execute=false) → 等确认 |
| 「电脑很卡」 | 01 诊断 | ops_diagnose 联合诊断 |
| 「刚蓝屏了」 | 01 诊断 | ops_diagnose 近 7 天事件取证 |
| 「帮我清下垃圾」 | 02 清理 | 先预览，等确认 |
| 「帮我验机」 | 01 诊断（不够细再 03/10） | ops_diagnose → 硬件细节再 mon_* / diag_tool_* |
| 「内置诊断看不出问题」 | 03 诊断工具调度 | diag_tool_list → diag_tool_run |
| 「怀疑硬盘坏了」 | 04 磁盘修复 | disk_tool_list → disk_tool_run（确认门） |
| 「系统文件损坏」 | 05 系统修复 | sys_tool_list → sys_tool_run（确认门） |
| 「测测硬盘速度」 | 09 磁盘基准 | dbench_tool_list → dbench_tool_run（写盘类确认门） |
| 「电池不耐用了」 | 10 硬件监测 | mon_battery_report（只读快查） |
| 「显卡温度多少」 | 10 硬件监测 | mon_nvidia_smi（NVIDIA）；Intel 走 mon_tool_run |
| 「烤个机看看稳不稳」 | 11 压测烤机 | stress_winsat / stress_tool_run（确认门） |
| 「网速好慢」 | 12 网络工具 | net_wifi_scan / speedtest 类 net_tool_run |
| 「某端口通不通」 | 12 网络工具 | net_port_check（host+port） |
| 「帮我查坏点」 | 13 屏幕工具 | screen_deadpixel（全屏纯色） |
| 「屏幕太亮/刺眼」 | 13 屏幕工具 | screen_tool_run（DDC/CI 亮度、色温） |
| 「新 U 盘验下容量」 | 14 外设工具 | peri_usb_verify（写盘类确认门） |
| 「键盘有键失灵？」 | 14 外设工具 | peri_tool_run（kbt） |
| 「启动项太多」 | 15 系统维护 | maint_tool_run / go-autoruns（只读清单） |
| 「缺 DLL 打不开游戏」 | 15 系统维护 | maint_dx_repair（确认门，需联网） |
| 「驱动有残留」 | 15 系统维护 | maint_driver_clean（先列清单；卸载走确认门） |
| 没网 | 离线脚本 | 引导 `diagnose.cmd`，不调 AI |

**会话开场提示词（可直接用）**：
> 你是一名有 10 年经验的 Windows 桌面运维工程师，服务怕删错文件的普通用户。工作纪律：先跑诊断再给清理建议；诊断只读；清理先预览、我明确确认才执行；桌面/文档/下载/图片永不清理；先结论后证据，数字带单位；动手前说清「我要做什么 / 影响什么 / 不碰什么」。

## 5. 使用方法

- 装好插件后启动 `dsh --profile dsh-tui`，直接说人话（上表左列），skill 规则自动接管会话流程。
- 各场景的完整提示词见 01/02/03/04/05/09/10/11/12/13/14/15 分册第 4 节，复制即用。

## 6. 安装方法

```bat
cd dsh
pnpm dsh plugin --profile dsh-tui add ..\plugins\only-u-ops-skill
pnpm dsh --profile dsh-tui --dump-config     :: 出现 "# == only-u-ops-skill" 层即成功
```

纯 harness：`dsh plugin --profile ops add ..\plugins\only-u-ops-skill`。

> 兼容说明：现有离线包还依赖 `.dsh\skills\only-u-ops\SKILL.md` 文件（bake 拷贝进盘）。两个来源并存：profile 里的本插件（新） + 盘上 skills 目录（旧）。确认新方式稳定后，旧文件可退役。

## 7. 开发任务（全部已完成）

1. ✅ 把 SKILL.md 拷入包内 `skills\only-u-ops\`（并升级为插件自有版本）。
2. ✅ 落地三件套 + index.js。
3. ✅ Tools 节更新：优先 `ops_diagnose`/`ops_clean` + 全部第三方调度工具名与内置脚本工具名（31 个工具全覆盖）；确认条是最终门。
4. ✅ 场景关键词 → 工具选择映射（第 4 节总表）已内置规则。
5. ✅ 接线冒烟通过（skill 注册成功、`source: 'runtime'`、内容含全部 31 个工具名；测试脚本 `temp\smoke-test-wiring.mjs`，2026-08-23）。
6. 可选硬堵：如需阻止模型用通用 `pwsh` 绕过 `ops_clean`，可用 profile patch 的 toolFilter 收窄通用 shell 工具。
