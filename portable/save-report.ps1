# Only-U save-report: 汇总 diagnose 新鲜输出 + 最新 clean 日志，写入 portable\reports\report-<机器名>-<时间>.txt。
# 只读源数据，只写 U 盘内 reports 目录，不联网。不改 diagnose/clean 主脚本。
param()

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$portableDir = $PSScriptRoot

# 机器名清洗：非法文件名字符 [\/:*?"<>|] 一律替换为 '-'
$machine = ($env:COMPUTERNAME -replace '[\\/:*?"<>|]', '-')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportsDir = Join-Path $portableDir 'reports'
$reportName = 'report-{0}-{1}.txt' -f $machine, $timestamp
$reportPath = Join-Path $reportsDir $reportName

Write-Output '正在诊断（约 30-60 秒，只读，不删除任何文件）……'

$diagnoseScript = Join-Path $portableDir 'diagnose.ps1'
if (Test-Path -LiteralPath $diagnoseScript) {
    $diagnoseOutput = (& $diagnoseScript | Out-String)
} else {
    $diagnoseOutput = '未找到 diagnose.ps1，本次无诊断输出。'
}

$logDir = Join-Path $portableDir 'logs'
$latestLog = @()
try {
    $latestLog = @(Get-ChildItem -LiteralPath $logDir -Filter 'clean-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)
} catch {
    $latestLog = @()
}

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

Write-Output ''
Write-Output ('报告已生成：{0}' -f $reportPath)
