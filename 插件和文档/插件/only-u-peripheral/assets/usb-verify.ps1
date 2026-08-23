# U盘扩容检测：写满测试数据 → 读回校验（写盘类，工具层执行前弹确认）
param([string]$Drive = '', [int]$SizeMB = 100)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

if ($Drive -eq '') {
  $removable = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' | Select-Object -ExpandProperty DeviceID
  if (-not $removable) {
    Write-Output '未找到可移动磁盘（U盘/移动硬盘）。可指定盘符重试：-Drive E:'
    exit 1
  }
  $Drive = $removable[0]
  Write-Output "自动选择可移动磁盘: $Drive"
}
if ($Drive -notmatch '^[A-Za-z]:$') { Write-Output "盘符格式错误: $Drive（应为 E: 形式）"; exit 1 }
if ($SizeMB -lt 50) { $SizeMB = 50 }
if ($SizeMB -gt 1000) { $SizeMB = 1000 }

$root = "$Drive\"
if (-not (Test-Path $root)) { Write-Output "盘符不存在: $Drive"; exit 1 }
$testFile = Join-Path $root 'OnlyU-verify-test.bin'

try {
  # 4KB 数据块：前 4 字节写入块序号，其余为固定伪随机填充
  $pattern = New-Object byte[] 4096
  (New-Object Random).NextBytes($pattern)
  $blockCount = [int]($SizeMB * 1MB / 4096)

  Write-Output "写入 ${SizeMB} MB 测试数据到 $Drive ..."
  $md5w = [System.Security.Cryptography.MD5]::Create()
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $fs = [System.IO.File]::Create($testFile, 1MB, [System.IO.FileOptions]::WriteThrough)
  for ($k = 0; $k -lt $blockCount; $k++) {
    $idx = [BitConverter]::GetBytes([uint32]$k)
    [Array]::Copy($idx, 0, $pattern, 0, 4)
    $fs.Write($pattern, 0, 4096)
    $md5w.TransformBlock($pattern, 0, 4096, $null, 0) | Out-Null
  }
  $fs.Flush()
  $fs.Close()
  $sw.Stop()
  $writeSec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
  $writeMBs = [Math]::Round($SizeMB / $sw.Elapsed.TotalSeconds, 1)
  Write-Output "写入完成: ${writeSec}s（${writeMBs} MB/s）"

  Write-Output '读回并校验 ...'
  $md5r = [System.Security.Cryptography.MD5]::Create()
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $fs = [System.IO.File]::OpenRead($testFile)
  $block = New-Object byte[] 4096
  $mismatch = $null
  $k = 0
  while (($n = $fs.Read($block, 0, 4096)) -gt 0) {
    if ($n -ne 4096) { $mismatch = "第 $k 块长度不足（读到 ${n} 字节）——疑似扩容盘"; break }
    $exp = [BitConverter]::ToUInt32($block, 0)
    if ($exp -ne [uint32]$k) { $mismatch = "第 $k 块序号不符（期望 $k，读到 $exp）——疑似扩容盘"; break }
    $md5r.TransformBlock($block, 0, 4096, $null, 0) | Out-Null
    $k++
  }
  $fs.Close()
  $sw.Stop()
  $readMBs = [Math]::Round(($k * 4096) / 1MB / $sw.Elapsed.TotalSeconds, 1)
  Write-Output "读回完成: $([Math]::Round($sw.Elapsed.TotalSeconds,1))s（${readMBs} MB/s）"

  $md5w.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
  $md5r.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
  $hashW = [BitConverter]::ToString($md5w.Hash)
  $hashR = [BitConverter]::ToString($md5r.Hash)
  $hashOk = $hashW -eq $hashR

  Write-Output "校验块数: $k / $blockCount"
  Write-Output "MD5 一致: $hashOk"
  if ($mismatch) { Write-Output "块校验: $mismatch" }

  if ($hashOk -and $k -eq $blockCount -and -not $mismatch) {
    Write-Output "结论: 未发现扩容迹象（写入与读回完全一致）。"
  } elseif ($k -eq $blockCount -and $hashOk -and $mismatch) {
    Write-Output "结论: 疑似扩容盘！$mismatch"
  } else {
    Write-Output "结论: 疑似扩容盘！写入 $blockCount 块仅读回 $k 块且校验不一致。"
  }
} catch {
  Write-Output "检测失败: $($_.Exception.Message)"
} finally {
  if (Test-Path $testFile) { Remove-Item $testFile -Force -ErrorAction SilentlyContinue }
  Write-Output "（测试文件已删除）"
}
exit 0
