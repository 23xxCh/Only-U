# 驱动清理：pnputil 枚举第三方驱动包（只读）或卸载指定 oem*.inf（写系统，工具层执行前弹确认）
param([string]$Inf = '')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

if ($Inf -eq '') {
  Write-Output '已安装的驱动包（oem*.inf 为第三方/更新驱动）:'
  & pnputil /enum-drivers | Out-String
  Write-Output ''
  Write-Output '卸载驱动：调用时传 Inf 参数（如 oem12.inf）。卸载系统级操作，执行前会向用户弹确认。'
  exit 0
}

if ($Inf -notmatch '^oem\d+\.inf$') {
  Write-Output "Inf 参数必须是 oem 编号格式（如 oem12.inf），收到: $Inf"
  exit 1
}

Write-Output "卸载驱动包 $Inf（/uninstall /force）..."
& pnputil /delete-driver $Inf /uninstall /force | Out-String
$code = $LASTEXITCODE
Write-Output "pnputil 退出码: $code（0 = 成功）"
if ($code -ne 0) {
  Write-Output '失败可能原因: 驱动仍被设备使用（先禁用设备）/ 需要管理员权限。'
  exit 1
}
exit 0
