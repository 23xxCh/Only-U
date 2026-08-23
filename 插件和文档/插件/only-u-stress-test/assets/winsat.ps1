# Windows 系统评估工具 winsat graphics：GPU 图形基准（内置，高负载）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

Write-Output '正在运行 winsat graphics（Windows 自带 GPU 图形基准，约 1-3 分钟，高负载）...'
$output = & winsat graphics -dx11 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Output $output
Write-Output "winsat 退出码: $code（0 = 完成）"
if ($code -ne 0) { exit 1 }
exit 0
