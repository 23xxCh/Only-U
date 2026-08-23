# NVIDIA GPU 快查：调用系统已装的 nvidia-smi（不随包分发任何 NVIDIA 组件）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $smi) {
  Write-Output '未找到 nvidia-smi：无 NVIDIA GPU 或 NVIDIA 驱动未安装。'
  Write-Output '可改用 ops_diagnose 查看显卡基本信息（Win32_VideoController）。'
  exit 0
}

& nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,driver_version --format=csv
$code = $LASTEXITCODE
if ($code -ne 0) {
  Write-Output "nvidia-smi 查询失败（退出码 $code）：可能是权限或多 GPU 环境问题。"
  exit 1
}
exit 0
