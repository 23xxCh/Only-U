# DirectX 运行库修复：从微软官方下载 dxwebsetup 并静默安装（写系统，工具层执行前弹确认）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

$url = 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe'
$out = Join-Path $env:TEMP 'dxwebsetup.exe'

try {
  Write-Output '正在从微软官方下载 DirectX Web 安装程序 ...'
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
  if (-not (Test-Path $out)) { throw '下载文件不存在' }
} catch {
  Write-Output '下载失败（离线或网络受限）。离线环境请引导用户使用便携工具或说明本功能需联网。'
  exit 1
}

Write-Output '下载完成，开始静默安装 DirectX 运行库（/Q，可能需要 UAC 提权确认）...'
$p = Start-Process -FilePath $out -ArgumentList '/Q' -Wait -PassThru
Write-Output "dxwebsetup 退出码: $($p.ExitCode)（0 = 成功）"
exit 0
