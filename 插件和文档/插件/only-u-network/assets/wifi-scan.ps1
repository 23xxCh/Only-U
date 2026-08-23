# Wi-Fi 扫描：附近网络 + 已保存配置（只读，netsh）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

Write-Output '=== 附近 Wi-Fi 网络（SSID / 信号 / 加密） ==='
$nearby = & netsh wlan show networks mode=bssid 2>&1 | Out-String
Write-Output $nearby
if ($LASTEXITCODE -ne 0 -or $nearby -match '没有承载网络|系统上没有无线接口|wlan') {
  Write-Output '提示: 若无输出，本机可能没有无线网卡或无线服务未开启。'
}

Write-Output ''
Write-Output '=== 已保存的 Wi-Fi 配置 ==='
& netsh wlan show profiles 2>&1 | Out-String

Write-Output ''
Write-Output '说明: 查看某个已保存网络的明文密码属于敏感操作，本工具不提供；请用户在 Windows 图形界面查看。'
exit 0
