# 第三方工具引入政策：PowerShell 优先，够不着才包插件

编号 0007。回答一个赛后扩容时必然出现的问题：「图吧工具箱、驱动精灵这些现成维修工具，能不能直接做成 DSH 插件用？」

背景：竞品调研（2026-08）显示维修师傅的标准组合是 Ventoy + 微PE + 图吧工具箱 + 驱动总裁 + Dism++。把这些搬进 Only-U 看似省力，实则是打别人的主场：图吧们是「无声工具箱」，Only-U 的差异化是「会说话的安全检查单」。

**Status:** accepted

## 决策

**PowerShell 够得着的能力，绝不引入第三方工具。** 只有同时满足以下三条，才考虑把**单个工具**（不是工具箱）包成 Cordis 插件（三层架构的第三层）：

1. **能力不可达**：PowerShell + 系统 CIM/WMI 真做不到（不是「做得麻烦」）；
2. **授权干净**：允许商业重分发（卖 U 盘 = 商业重分发，「个人免费」授权不行），逐个工具核实并留档；
3. **有机器可读接口**：CLI 参数稳定、输出可解析，不需要驱动 GUI。

## 为什么不搬工具箱

| 图吧里的能力 | 我们的等价物 | 状态 |
|---|---|---|
| CPU-Z（CPU/主板信息） | `Win32_Processor` / `Win32_BaseBoard` | 已有 |
| CrystalDiskInfo（硬盘健康） | `Get-PhysicalDisk` + `Get-StorageReliabilityCounter` | #6 |
| 驱动检测 | `Get-PnpDevice` + 错误码翻译 | #7 |
| GPU-Z | `Win32_VideoController` | 一行可得 |
| 温度 | `MSAcpi_ThermalZoneTemperature` | #6 |

拒绝整体引入的理由：
- **GUI 无接口**：包 GUI 工具 = 脆弱的界面自动化，升级即崩；
- **授权雷区**：图吧聚合的工具多为个人免费授权，商业重分发违规；驱动精灵无真开源版，驱动总裁是免费软件非开源；
- **杀软误报**：未签名第三方可执行文件从 U 盘运行会被 Defender/SmartScreen 拦（图吧自身就被误报），我们自己的 node.exe 已经承担了这个风险，不再加码；
- **定位错位**：拼工具广度是图吧主场；我们的主场是「检测得深 + 解释得清 + 删得安全」。

## 赛后候选（全部红级，逐项确认）

| 能力 | 候选工具 | 前置条件 |
|---|---|---|
| 离线驱动安装 | 驱动总裁离线包 | 核实重分发授权；装前备份+装后回滚；ADR-0006 红级逐项确认 |
| GPU 压力测试 | FurMark CLI | 授权核实；仅报告结果不自动跑长时烤机 |
| 底层内存检测 | MemTest86 | 需重启引导，产品形态待定 |
| 蓝屏 dump 分析 | BlueScreenView（NirSoft） | PowerShell 只能读事件日志，dump 符号化真做不到；NirSoft 商业再分发条款需逐项核实留档 |

## 2026-08-22 增补：图吧开源重写版（tubatools）调研结论

对 `luolangaga/tubatools`（图吧工具箱 WinUI3 重构版，GPL-3.0，2026 年起）与 `luolangaga/tubatoolsPlugin`（社区插件库，**无许可证**）的取证结论：

1. **整体仍不引入，四重否决坐实**：GUI 壳无 headless 单工具接口（AGENTS.md 仅有内部 headless 参数）；Tools.zip 收录 AIDA64/UltraISO（付费）、CPU-Z/GPU-Z（禁止打包再分发）等，商业重分发违规；内置 WinRing0 内核驱动 + KMS 激活，杀软误报加码；联网更新/插件下载与离线定位冲突。tubatoolsPlugin 无任何许可证且直接托管第三方二进制，不能随 U 盘分发。
2. **意外收获：42KB《CLI使用文档.md》当调研底稿**。官方逐参数收录 20+ 工具的命令行用法（FurMark 烤机参数、NirSoft 系 CSV 导出、WizTree /export 等）。此后逐工具核实参数不用从零摸，以该文档为起点、再向各工具官方参数核对。仓库本身 GPL 无碍（我们只引用事实，不复制代码）。
3. **纠正一处等价覆盖判断**：「温度 → MSAcpi_ThermalZoneTemperature」在桌面平台常缺失（无此 WMI 命名空间），温度传感器读取是真实的能力缺口，HWiNFO /LOG 可作为候选（商用需 Pro 授权，逐项核实）。

## 落地形态（当某个工具过审后）

```
portable\tools\<工具名>\        ← 二进制，烤盘时进 U 盘
plugins\<工具名>\               ← Cordis 插件：包 CLI 调用 + 输出解析，注册为 agent 工具
.dsh\skills\only-u-ops\        ← skill 增加何时调用该工具的说明（含 ADR-0006 分级）
```

插件必须声明：该操作落在绿/黄/红哪一级、失败时如何退出、输出如何进报告。不满足就退回「只检测不执行」。
