# 电池健康报告：powercfg /batteryreport + 解析摘要（只读）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

$reportPath = Join-Path $env:TEMP ('battery-report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.html')
& powercfg /batteryreport /output $reportPath 2>$null | Out-Null
if (-not (Test-Path $reportPath)) {
  Write-Output '生成失败：powercfg 无法生成电池报告（设备无电池或命令不可用）'
  exit 1
}

$html = Get-Content -Raw -Encoding UTF8 $reportPath
# 去标签后按字段抓取
$text = $html -replace '<script[\s\S]*?</script>', ' ' -replace '<style[\s\S]*?</style>', ' ' -replace '<[^>]+>', ' '
$text = $text -replace '\s+', ' '

function Get-MWhField([string]$label) {
  $m = [regex]::Match($text, "$label[^\d]*([\d,\.]+)\s*mWh")
  if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}
$name = ''
$nm = [regex]::Match($text, 'NAME\s+([A-Za-z0-9\-_ ]+?)\s+MANUFACTURER')
if ($nm.Success) { $name = $nm.Groups[1].Value.Trim() }

$design = Get-MWhField 'DESIGN CAPACITY'
$full   = Get-MWhField 'FULL CHARGE CAPACITY'
$cycleM = [regex]::Match($text, 'CYCLE COUNT[^\d]*([\d,]+)')
$cycle = if ($cycleM.Success) { $cycleM.Groups[1].Value } else { '未知' }

$health = $null
if ($design -and $full) {
  $d = [double]($design -replace ',', '')
  $f = [double]($full -replace ',', '')
  if ($d -gt 0) { $health = '{0:P1}' -f ($f / $d) }
}

Write-Output '=== 电池健康报告（摘要） ==='
if (-not $design -and -not $full) {
  Write-Output '未解析到电池容量数据：本机可能没有电池（台式机）或报告格式变化。'
  Write-Output "完整报告(HTML): $reportPath"
  Write-Output '此检测只读，无任何修改。'
  exit 0
}
if ($name) { Write-Output "电池型号: $name" }
Write-Output "设计容量: $design mWh"
Write-Output "完全充电容量: $full mWh"
if ($health) { Write-Output "健康度: $health" }
Write-Output "循环次数: $cycle"
Write-Output "完整报告(HTML): $reportPath"
Write-Output '说明: 健康度低于 80% 建议考虑更换电池；此检测只读，无任何修改。'
exit 0
