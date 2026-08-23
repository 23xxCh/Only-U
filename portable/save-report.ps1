# Only-U save-report: 汇总 diagnose + 最新 clean 日志 → reports\report-<机器名>-<时间>.txt，并追加 history-<机器名>.md。
# 只读源数据，只写 U 盘内 reports/history，不联网。不改 diagnose/clean 主脚本。
param(
    [string]$PortableDir = $PSScriptRoot,
    [switch]$SkipDiagnose
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 机器名清洗：非法文件名字符 [\/:*?"<>|] 一律替换为 '-'
$machine = ($env:COMPUTERNAME -replace '[\\/:*?"<>|]', '-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$nowText = Get-Date -Format 'yyyy-MM-dd HH:mm'
$reportsDir = Join-Path $PortableDir 'reports'
$n = 0
do {
    if ($n -eq 0) { $reportName = 'report-{0}-{1}.txt' -f $machine, $timestamp }
    else { $reportName = 'report-{0}-{1}-{2}.txt' -f $machine, $timestamp, $n }
    $reportPath = Join-Path $reportsDir $reportName
    $n++
} while (Test-Path -LiteralPath $reportPath)
$historyPath = Join-Path $PortableDir ('history-{0}.md' -f $machine)

Write-Output '正在诊断（约 30-60 秒，只读，不删除任何文件）……'

$diagnoseScript = Join-Path $PortableDir 'diagnose.ps1'
if ($SkipDiagnose) {
    $diagnoseOutput = '（测试/跳过：未重新跑 diagnose.ps1）'
} elseif (Test-Path -LiteralPath $diagnoseScript) {
    $diagnoseOutput = (& $diagnoseScript | Out-String)
} else {
    $diagnoseOutput = '未找到 diagnose.ps1，本次无诊断输出。'
}

$logDir = Join-Path $PortableDir 'logs'
$latestLog = @()
try {
    $latestLog = @(Get-ChildItem -LiteralPath $logDir -Filter 'clean-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)
} catch {
    $latestLog = @()
}

$logText = ''
if ($latestLog.Count -gt 0) {
    $logFile = $latestLog[0]
    try {
        $logText = [System.IO.File]::ReadAllText($logFile.FullName)
    } catch {
        $logText = '（日志读取失败）'
    }
    $cleanSection = ('最新一次清理日志：{0}' -f $logFile.Name) + [Environment]::NewLine + $logText
} else {
    $cleanSection = '本次未执行清理（portable\logs\ 中没有 clean 日志）。'
}

$nl = [Environment]::NewLine
$lines = @(
    ('machine: {0}' -f $machine),
    ('time: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    ('user: {0}' -f $env:USERNAME),
    '',
    '=== 诊断输出（diagnose.ps1，只读） ===',
    $diagnoseOutput.TrimEnd(),
    '',
    '=== 清理记录（portable\logs\ 最新日志） ===',
    $cleanSection.TrimEnd(),
    '',
    '=== 主人白话版（占位——AI 在 TUI 里按 REPORT-FORMAT.md 生成后粘贴到这里） ===',
    '这台电脑的主要问题是____。',
    '我们已经____。（没有删除您的任何个人文件。）',
    '建议____。',
    ''
)
$content = $lines -join $nl

if (-not (Test-Path -LiteralPath $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
}
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($reportPath, $content, $utf8Bom)

# --- 从 diagnose/clean 文本抽 3-6 行要点写入 history（宁粗勿错）---
function Get-HistoryBullets {
    param([string]$Diag, [string]$Clean, [string]$ReportName)
    $bullets = New-Object System.Collections.Generic.List[string]
    $bullets.Add(('- 报告：{0}' -f $ReportName))

    $reds = @()
    if ($Diag) {
        $reds = @([regex]::Matches($Diag, '(?m)^!\s+(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 3)
    }
    if ($reds.Count -gt 0) {
        $bullets.Add(('- 红灯/主要问题：{0}' -f ($reds -join '；')))
    } else {
        $bullets.Add('- 红灯/主要问题：本次未见红灯项（或诊断跳过）')
    }

    if ($Clean -and ($Clean -match 'total actual bytes:\s*(\d+)')) {
        $bytes = [long]$Matches[1]
        $human = if ($bytes -ge 1GB) { '{0:N1} GB' -f ($bytes / 1GB) }
                 elseif ($bytes -ge 1MB) { '{0:N1} MB' -f ($bytes / 1MB) }
                 else { '{0:N0} B' -f $bytes }
        $bullets.Add(('- 执行动作：已执行清理，约回收 {0}' -f $human))
    } elseif ($Clean -and ($Clean -match '本次释放：约\s*([^\r\n]+)')) {
        $bullets.Add(('- 执行动作：已执行清理，{0}' -f $Matches[1].Trim()))
    } elseif ($Clean -and ($Clean -match 'mode:\s*EXECUTE')) {
        $bullets.Add('- 执行动作：已执行清理（详见 clean 日志）')
    } else {
        $bullets.Add('- 执行动作：本次未执行清理（仅诊断/预览）')
    }

    $advice = $null
    if ($Diag) {
        $m = [regex]::Match($Diag, '(?ms)=== 接下来怎么办 ===\s*\r?\n\s*1\.\s*(.+)')
        if ($m.Success) { $advice = $m.Groups[1].Value.Trim() }
    }
    if ($advice) {
        if ($advice.Length -gt 120) { $advice = $advice.Substring(0, 120) + '…' }
        $bullets.Add(('- 遗留建议：{0}' -f $advice))
    } else {
        $bullets.Add('- 遗留建议：详见本次报告全文')
    }

    return @($bullets | Select-Object -First 6)
}

$existingHistory = ''
$sectionCount = 0
if (Test-Path -LiteralPath $historyPath) {
    $existingHistory = [System.IO.File]::ReadAllText($historyPath)
    $sectionCount = ([regex]::Matches($existingHistory, '(?m)^## ')).Count
}
$sectionNum = $sectionCount + 1
$bullets = Get-HistoryBullets -Diag $diagnoseOutput -Clean $logText -ReportName $reportName
$historyEntry = @(
    ('## {0} 维修 #{1}' -f $nowText, $sectionNum)
) + $bullets + @('')
$historyEntryText = $historyEntry -join $nl

if (-not (Test-Path -LiteralPath $historyPath)) {
    $header = @(
        ('# {0} 维修履历' -f $machine),
        '',
        '本文件是该机器的维修履历，每次维修追加一节，勿手改。',
        '',
        $historyEntryText
    ) -join $nl
    [System.IO.File]::WriteAllText($historyPath, $header, $utf8Bom)
} else {
    if (-not $existingHistory.EndsWith($nl)) { $existingHistory = $existingHistory + $nl }
    [System.IO.File]::WriteAllText($historyPath, ($existingHistory + $historyEntryText), $utf8Bom)
}

Write-Output ''
Write-Output ('报告已生成：{0}' -f $reportPath)
Write-Output ('履历已追加：{0}（维修 #{1}）' -f $historyPath, $sectionNum)
