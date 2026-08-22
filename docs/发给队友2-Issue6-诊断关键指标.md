# 发给队友 2：Issue #6 诊断关键指标

## 当前状态

- 状态：**已实现，PR 待合并**
- 分支：`feat/6-diagnose-key-metrics`
- PR：[23xxCh/Only-U#10](https://github.com/23xxCh/Only-U/pull/10)
- Issue：[23xxCh/Only-U#6](https://github.com/23xxCh/Only-U/issues/6)（PR 正文含 `Closes #6`）
- 最近验证：2026-08-22，Windows PowerShell 5.1 下 Pester 7/7 通过

## 已交付

- **内存**：显示 `% Committed Bytes In Use`、Commit / Commit Limit、pagefile 使用情况；超过 75% 标「预警」，超过 85% 标「高压」。TOP5 进程按 Commit Size 排序，同时显示 Working Set。
- **关键事件**：只列近 7 天的低虚拟内存（2004）和真实磁盘/存储来源的 7、129、153、157 事件。相同 ID 的 Hyper-V 或网络事件不计入存储故障；详情最多显示 20 条，但红灯统计保留完整命中数。
- **SMART**：尽力读取 `Get-PhysicalDisk` 健康状态和 `Get-StorageReliabilityCounter` 的不可纠正读取错误、温度；不可读时显示「SMART 不可读（跳过）」。
- **报告红灯区**：仅在命中时置于报告顶部。覆盖 C 盘剩余低于 5% 或 1 GB、已提交内存超过 90%、事件 2004、7 天内 129/153 至少 3 次、SMART 异常。
- **阈值精度**：红灯与预警均使用未四舍五入的原始数值判断，显示时才保留一位小数，避免边界漏报。

## 验证与边界

- `Invoke-Pester -Path portable\tests\diagnose.Tests.ps1`：7 项通过。
- 正常实机运行耗时 4.73 秒；本机的提交内存为 93.1%，因此正确显示「提交内存高压」，未将 Hyper-V/网络事件误报为存储红灯。
- 仍保持只读、UTF-8 BOM 与 Issue #5 的单目录 8 秒 / 20,000 文件扫描上限。
- 本票仅修改 `portable/diagnose.ps1` 与 `portable/tests/diagnose.Tests.ps1`；未修改启动器、清理防护、`dsh/` 或 `dsh-tui/`。
