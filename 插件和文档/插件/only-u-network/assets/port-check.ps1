# 端口检查：指定 host:port 连通性测试，或列出本机监听端口（只读）
param([string]$TargetHost = '', [int]$Port = 0)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

if ($TargetHost -ne '' -and $Port -gt 0) {
  Write-Output "测试 $TargetHost`:$Port 连通性（约 5-10 秒）..."
  $r = Test-NetConnection -ComputerName $TargetHost -Port $Port -WarningAction SilentlyContinue
  Write-Output ("可达: {0}" -f $r.TcpTestSucceeded)
  if (-not $r.TcpTestSucceeded) {
    Write-Output '可能原因: 目标未监听该端口 / 防火墙拦截 / 主机不可达。'
  }
  exit 0
}

if ($TargetHost -eq '' -and $Port -eq 0) {
  Write-Output '本机监听端口（端口 地址 进程）:'
  $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Sort-Object LocalPort |
    ForEach-Object {
      $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
      $pname = '?'
      if ($proc) { $pname = $proc.ProcessName }
      '{0,-7} {1,-22} {2}' -f $_.LocalPort, $_.LocalAddress, $pname
    }
  if ($listeners) { $listeners } else { Write-Output '无监听端口（或需要管理员权限查看全部）' }
  exit 0
}

Write-Output '用法: 指定 -TargetHost 与 -Port 测试连通性；都不指定则列出本机监听端口。'
exit 1
