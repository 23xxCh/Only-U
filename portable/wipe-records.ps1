# Only-U 清空维修记录：两档。Y=只清会话（留 reports+history）；A=全清（会话+reports+history+logs）。
# 绝不动：portable\.env（API Key）、portable\runtime\ 二进制（sessions 除外）、skill、CONTEXT.md。不联网。
param(
    [string]$PortableDir = $PSScriptRoot,
    [ValidateSet('Y', 'A', 'N', '')]
    [string]$Mode = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$reportDir = Join-Path $PortableDir 'reports'
$logDir = Join-Path $PortableDir 'logs'
$sessionDir = Join-Path $PortableDir 'runtime\dsh\sessions'
$dshHomeDir = Join-Path $PortableDir '.dsh-home'
$dshHomeSessionDir = Join-Path $dshHomeDir 'sessions'

Write-Output '=== Only-U 清空维修记录 ==='
Write-Output ''

# --- 启动前检测：本盘 TUI（node.exe）在跑则拒绝（判据同 start.cmd：命令行含本盘 bin.js）---
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
        (Join-Path $PortableDir 'runtime\dsh\lib\bin.js'),
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

# 统计 A 模式额外清除的文件数（展示用）
$extraCount = 0
if (Test-Path -LiteralPath $reportDir) {
    $extraCount += @(Get-ChildItem -LiteralPath $reportDir -Force -ErrorAction SilentlyContinue).Count
}
if (Test-Path -LiteralPath $logDir) {
    $extraCount += @(Get-ChildItem -LiteralPath $logDir -Force -ErrorAction SilentlyContinue).Count
}
$extraCount += @(Get-ChildItem -LiteralPath $PortableDir -Filter 'history-*.md' -File -ErrorAction SilentlyContinue).Count

Write-Output ''
Write-Output '请选择清空级别：'
Write-Output ''
Write-Output '【Y = 只清会话（默认，回车即 Y）】'
Write-Output '  本次清除：'
Write-Output '    - portable\runtime\dsh\sessions\ 内容（保留目录）'
if (Test-Path -LiteralPath $dshHomeDir) {
    Write-Output '    - portable\.dsh-home\sessions\ 内容（若有）'
}
Write-Output '  保留：reports\、history-*.md、logs\、.env、程序'
Write-Output ''
Write-Output '【A = 全清（换盘/交盘前才用）】'
Write-Output '  上述会话 + 额外清除：'
Write-Output ('    - portable\reports\、portable\logs\、portable\history-*.md（当前约 {0} 项）' -f $extraCount)
Write-Output '  维修履历将一并清除，仅换盘/交盘前使用。'
Write-Output ''
Write-Output '【N = 取消】'
Write-Output ''
Write-Output '始终保留：portable\.env（API Key）、runtime 二进制、skill、CONTEXT.md。'
Write-Output 'API Key 与程序不受影响。'
Write-Output ''

if ([string]::IsNullOrWhiteSpace($Mode)) {
    $answer = Read-Host '请输入 Y / A / N（直接回车 = Y）'
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = 'Y' }
} else {
    $answer = $Mode
}

if ($answer -match '^[Nn]$') {
    Write-Output '已取消，未删除任何文件。'
    exit 0
}

$wipeAll = $false
if ($answer -match '^[Yy]$') {
    $wipeAll = $false
} elseif ($answer -match '^[Aa]$') {
    $wipeAll = $true
} else {
    Write-Output '已取消，未删除任何文件。'
    exit 0
}

$sessionTargets = @($sessionDir)
if (Test-Path -LiteralPath $dshHomeDir) { $sessionTargets += $dshHomeSessionDir }

if ($wipeAll) {
    $wipeTargets = @($reportDir, $logDir) + $sessionTargets
} else {
    $wipeTargets = $sessionTargets
}

function Remove-Children {
    param([string]$Target)
    $removedFiles = 0
    $removedDirs = 0
    $failedItems = 0
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        Write-Output ('跳过（目录不存在）：{0}' -f $Target)
        return @{ Files = 0; Dirs = 0; Failed = 0 }
    }
    $children = @(Get-ChildItem -LiteralPath $Target -Force -ErrorAction SilentlyContinue)
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
    return @{ Files = $removedFiles; Dirs = $removedDirs; Failed = $failedItems }
}

$removedFiles = 0
$removedDirs = 0
$failedItems = 0

foreach ($target in $wipeTargets) {
    $r = Remove-Children -Target $target
    $removedFiles += [int]$r.Files
    $removedDirs += [int]$r.Dirs
    $failedItems += [int]$r.Failed
}

if ($wipeAll) {
    $historyFiles = @(Get-ChildItem -LiteralPath $PortableDir -Filter 'history-*.md' -File -ErrorAction SilentlyContinue)
    foreach ($hf in $historyFiles) {
        try {
            Remove-Item -LiteralPath $hf.FullName -Force -ErrorAction Stop
            $removedFiles++
        } catch {
            $failedItems++
            Write-Output ('  删除失败（已跳过）：{0}' -f $hf.FullName)
        }
    }
}

foreach ($keepDir in @($reportDir, $logDir, $sessionDir)) {
    if (-not (Test-Path -LiteralPath $keepDir)) {
        New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
    }
}

Write-Output ''
Write-Output '=== 清理摘要 ==='
if ($wipeAll) {
    Write-Output '档位：A（全清）'
    Write-Output ('已删除 {0} 个文件、{1} 个目录。' -f $removedFiles, $removedDirs)
    Write-Output '会话、报告、清理日志与维修履历已清除；目录结构已保留。'
} else {
    Write-Output '档位：Y（只清会话）'
    Write-Output ('已删除 {0} 个文件、{1} 个目录。' -f $removedFiles, $removedDirs)
    Write-Output '已清除客户机上的对话记录。你的维修履历（reports + history）已保留。'
}
if ($failedItems -gt 0) {
    Write-Output ('有 {0} 项删除失败（多为被占用），关闭相关程序后重试。' -f $failedItems)
}
Write-Output 'API Key 与程序不受影响。'
