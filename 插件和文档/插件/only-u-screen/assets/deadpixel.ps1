# 坏点检测：所有屏幕全屏循环纯色，Esc/点击结束（只读显示，无任何写操作）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
} catch {
  Write-Output '无法加载 WinForms（可能运行在无桌面会话）。请引导用户在桌面环境手动检测。'
  exit 1
}

$colors = @(
  [System.Drawing.Color]::Red, [System.Drawing.Color]::Green, [System.Drawing.Color]::Blue,
  [System.Drawing.Color]::White, [System.Drawing.Color]::Black, [System.Drawing.Color]::Yellow,
  [System.Drawing.Color]::Cyan, [System.Drawing.Color]::Magenta
)
$names = @('红', '绿', '蓝', '白', '黑', '黄', '青', '品红')

$screens = [System.Windows.Forms.Screen]::AllScreens
if (-not $screens -or $screens.Count -eq 0) {
  Write-Output '未检测到显示器。'
  exit 1
}

$forms = @()
$script:done = $false
$script:i = 0
try {
  foreach ($scr in $screens) {
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $f.StartPosition = 'Manual'
    $f.Location = $scr.Bounds.Location
    $f.Size = $scr.Bounds.Size
    $f.TopMost = $true
    $f.BackColor = $colors[0]
    $f.KeyPreview = $true
    $f.Add_KeyDown({ $script:done = $true })
    $f.Add_Click({ $script:done = $true })
    $f.Show()
    $forms += $f
  }
} catch {
  Write-Output '创建全屏窗口失败（可能无桌面会话）。请引导用户手动检测。'
  exit 1
}

Write-Output "坏点检测已启动：$($screens.Count) 个屏幕全屏循环纯色（红绿蓝白黑黄青品红），按 Esc 或点击屏幕结束。"
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({
  $script:i = ($script:i + 1) % $colors.Count
  foreach ($f in $forms) { $f.BackColor = $colors[$script:i] }
})
$timer.Start()

while (-not $script:done) {
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 50
}

$timer.Stop()
foreach ($f in $forms) { $f.Close(); $f.Dispose() }
Write-Output '检测结束。请汇报结果：在哪种颜色下看到坏点/亮点？（红/绿/蓝/白/黑/黄/青/品红；黑色下白点=亮点，白色下黑点=暗点/坏点）'
exit 0
