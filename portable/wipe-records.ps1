# Only-U 清空维修记录（隐私）：只清 reports / logs / DSH 会话的内容，目录保留。
# 绝不动：portable\.env（API Key）、portable\runtime\ 二进制（sessions 除外）、skill、CONTEXT.md。不联网。
param()

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$portableDir = $PSScriptRoot
$reportDir = Join-Path $portableDir 'reports'
$logDir = Join-Path $portableDir 'logs'
$sessionDir = Join-Path $portableDir 'runtime\dsh\sessions'
$dshHomeDir = Join-Path $portableDir '.dsh-home'
$dshHomeSessionDir = Join-Path $dshHomeDir 'sessions'

Write-Output '=== Only-U 清空维修记录 ==='
Write-Output ''

# --- 启动前检测：本盘 TUI（node.exe）在跑则拒绝（判据同 start.cmd 单实例锁：命令行含本盘 bin.js）---
$tasklistOk = $true
$nodeSeen = $false
try {
    $taskOut = @(tasklist.exe 2>$null)
    if ($LASTEXITCODE -ne 0) { $tasklistOk = $false }
    elseif (@($taskOut | Where-Object { $_ -match '(?i)node\.exe' }).Count -gt 0) { $nodeSeen = $true }
} catch { $tasklistOk = $false }

if (-not $tasklistOk) {
    Write-Output '提示：无法检测 node.exe 进程（tasklist 不可用），请自行确认 TUI 已关闭后再继续。'
} elseif ($nodeSeen) {
    $tuiBinCandidates = @(
        (Join-Path $portableDir 'runtime\dsh\lib\bin.js'),
        (Join-Path $env:LOCALAPPDATA 'Only-U\cache\dsh\lib\bin.js')
    )
    $tuiRunning = $false
    $unverified = $false
    try {
        $nodeProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'node.exe'" -ErrorAction Stop)
        foreach ($nodeProcess in $nodeProcesses) {
            if (-not $nodeProcess.CommandLine) { $unverified = $true; continue }
            foreach ($candidate in $tuiBinCandidates) {
                if ($nodeProcess.CommandLine.IndexOf($candidate, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $tuiRunning = $true
                    break
                }
            }
            if ($tuiRunning) { break }
        }
    } catch { $unverified = $true }

    if ($tuiRunning) {
        Write-Output '检测到本盘 TUI（node.exe）正在运行。'
        Write-Output '请先关闭 TUI 窗口，再重新运行本脚本；本次未删除任何文件。'
        exit 1
    }
    Write-Output '提示：检测到 node.exe 在跑，但未识别为本盘 TUI；请确认 TUI 已关闭。'
    if ($unverified) { Write-Output '（部分进程命令行不可读，无法完全确认。）' }
}

Write-Output ''
Write-Output '将删除（只清内容，目录保留）：'
Write-Output '  1. portable\reports\ 下全部维修报告'
Write-Output '  2. portable\logs\ 下全部清理日志'
Write-Output '  3. portable\runtime\dsh\sessions\ 下全部 DSH 会话'
if (Test-Path -LiteralPath $dshHomeDir) { Write-Output '  4. portable\.dsh-home\sessions\ 下会话内容' }
Write-Output ''
Write-Output '将保留：'
Write-Output '  - portable\.env（API Key）'
Write-Output '  - portable\runtime\ 程序与运行时（sessions 除外）'
Write-Output '  - skill 与 CONTEXT.md'
Write-Output ''
Write-Output 'API Key 与程序不受影响。'
Write-Output ''

$answer = Read-Host '确认清空维修记录？输入 Y 继续，N 取消'
if ($answer -notmatch '^[Yy]$') {
    Write-Output '已取消，未删除任何文件。'
    exit 0
}

$wipeTargets = @($reportDir, $logDir, $sessionDir)
if (Test-Path -LiteralPath $dshHomeDir) { $wipeTargets += $dshHomeSessionDir }

$removedFiles = 0
$removedDirs = 0
$failedItems = 0

foreach ($target in $wipeTargets) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Output ('跳过（目录不存在）：{0}' -f $target)
        continue
    }
    $children = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        $childFileCount = 0
        if ($child.PSIsContainer) {
            $childFileCount = @(Get-ChildItem -LiteralPath $child.FullName -Recurse -Force -File -ErrorAction SilentlyContinue).Count
        }
        try {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
            if ($child.PSIsContainer) {
                $removedDirs++
                $removedFiles += $childFileCount
            } else {
                $removedFiles++
            }
        } catch {
            $failedItems++
            Write-Output ('  删除失败（已跳过）：{0}' -f $child.FullName)
        }
    }
}

# 目录结构必须保留（DSH 需要 sessions 目录存在）
foreach ($keepDir in @($reportDir, $logDir, $sessionDir)) {
    if (-not (Test-Path -LiteralPath $keepDir)) {
        New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
    }
}

Write-Output ''
Write-Output '=== 清理摘要 ==='
Write-Output ('已删除 {0} 个文件、{1} 个目录。' -f $removedFiles, $removedDirs)
if ($failedItems -gt 0) {
    Write-Output ('有 {0} 项删除失败（多为被占用），关闭相关程序后重试。' -f $failedItems)
}
Write-Output 'reports / logs / sessions 目录已保留（空）。'
Write-Output 'API Key 与程序不受影响。'
