# Review package — Task 2

Plan: docs/superpowers/plans/2026-08-22-yandifei-issues-13-7-14.md
Base: 3e16c628de10440785986802d6b29deb7bd3aa9c
Head: 82d9f5a3fd34f80ef6c6610691e473ebc335bf9f

```diff
82d9f5a feat(diagnose): translate driver and printer faults
 portable/diagnose.ps1             | 129 ++++++++++++++++++++++++++++++++++++--
 portable/tests/diagnose.Tests.ps1 |  56 +++++++++++++++++
 2 files changed, 179 insertions(+), 6 deletions(-)
diff --git a/portable/diagnose.ps1 b/portable/diagnose.ps1
index 5d969e7..a8568c5 100644
--- a/portable/diagnose.ps1
+++ b/portable/diagnose.ps1
@@ -1,14 +1,76 @@
 ﻿# Only-U offline diagnose. No LLM. Read-only.
+param(
+    [switch]$NoRun
+)
+
 $ErrorActionPreference = 'Continue'
 [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
 
+function Get-PnpErrorDetail([int]$Code) {
+    switch ($Code) {
+        1  { return [pscustomobject]@{ Translation = '未配置'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        10 { return [pscustomobject]@{ Translation = '无法启动'; Suggestion = '重新插拔设备、换接口，必要时送修'; Bucket = 'suspected-hardware' } }
+        22 { return [pscustomobject]@{ Translation = '已被禁用'; Suggestion = '在设备管理器中启用该设备'; Bucket = 'disabled' } }
+        28 { return [pscustomobject]@{ Translation = '驱动未安装'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        29 { return [pscustomobject]@{ Translation = '电源不足被禁用'; Suggestion = '在设备管理器中启用该设备'; Bucket = 'disabled' } }
+        37 { return [pscustomobject]@{ Translation = '驱动加载失败'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        39 { return [pscustomobject]@{ Translation = '驱动加载失败'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        43 { return [pscustomobject]@{ Translation = '设备自报故障'; Suggestion = '重新插拔设备、换接口，必要时送修'; Bucket = 'suspected-hardware' } }
+        45 { return [pscustomobject]@{ Translation = '设备已拔除'; Suggestion = '重新连接设备后再检查状态'; Bucket = 'other' } }
+        48 { return [pscustomobject]@{ Translation = '被策略阻止'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        52 { return [pscustomobject]@{ Translation = '驱动未签名'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
+        default { return [pscustomobject]@{ Translation = '未知状态'; Suggestion = '在设备管理器中查看设备状态'; Bucket = 'other' } }
+    }
+}
+
+function Format-PnpDeviceLine($Device, $Detail) {
+    $name = if ($Device.Name) { $Device.Name } else { '未知设备' }
+    $class = if ($Device.PNPClass) { $Device.PNPClass } else { '未知类' }
+    return ('{0} [{1}] 错误码{2}（{3}）→ 建议：{4}' -f $name, $class, $Device.ConfigManagerErrorCode, $Detail.Translation, $Detail.Suggestion)
+}
+
+function Get-HardwareIdSummary([string[]]$HardwareIds) {
+    if ($null -eq $HardwareIds -or $HardwareIds.Count -eq 0 -or [string]::IsNullOrWhiteSpace($HardwareIds[0])) { return $null }
+    $match = [regex]::Match($HardwareIds[0], '(?i)(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|VID_[0-9A-F]{4}&PID_[0-9A-F]{4})')
+    if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
+    return $null
+}
+
+function Get-PnpHardwareIdSummary($Device) {
+    if ([string]::IsNullOrWhiteSpace($Device.PNPDeviceID)) { return $null }
+    try {
+        $property = Get-PnpDeviceProperty -InstanceId $Device.PNPDeviceID -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
+        return Get-HardwareIdSummary -HardwareIds @($property.Data)
+    } catch {
+        return $null
+    }
+}
+
+function Get-PrinterDetectedErrorText($DetectedErrorState) {
+    switch ([int]$DetectedErrorState) {
+        8 { return '卡纸' }
+        9 { return '脱机' }
+        { $_ -in 2, 4 } { return '无纸' }
+        { $_ -in 3, 5 } { return '缺粉' }
+        default { return $null }
+    }
+}
+
+function Get-PrinterPortHint([string]$PortName) {
+    if ([string]::IsNullOrWhiteSpace($PortName)) { return '端口信息不可读，需结合连接状态判断。' }
+    if ($PortName -match '(?i)^WSD') { return 'WSD 端口脱机时，网络或 WSD 协议可能有问题。' }
+    if ($PortName -match '(?i)(TCP|IP_)') { return 'TCP/IP 端口可用 ping 验证连通性。' }
+    if ($PortName -match '(?i)^USB') { return 'USB 端口请检查即插即用设备状态。' }
+    return ('端口 {0}，需结合连接状态判断。' -f $PortName)
+}
+
 function Format-Bytes([long]$n) {
     if ($n -lt 0) { return 'n/a' }
     if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
     if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
     return ('{0:N0} B' -f $n)
 }
 
 $maxScanFiles = 20000
 $scanTimeoutSeconds = 8
 
@@ -59,20 +121,22 @@ function Get-DirSize([string]$path) {
         $result = @(Receive-Job -Job $job -ErrorAction Stop | Select-Object -First 1)[0]
         if ($null -eq $result) { return [pscustomobject]@{ Status = 'Unreadable'; Bytes = 0; Files = 0 } }
         return $result
     } catch {
         return [pscustomobject]@{ Status = 'Unreadable'; Bytes = 0; Files = 0 }
     } finally {
         Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
     }
 }
 
+if ($NoRun) { return }
+
 $diskFacts = @()
 try {
     $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
     $disks | ForEach-Object {
         $freePctRaw = if ($_.Size -gt 0) { 100 * $_.FreeSpace / $_.Size } else { 0 }
         $diskFacts += [pscustomobject]@{ DeviceId = $_.DeviceID; Size = [long]$_.Size; FreeSpace = [long]$_.FreeSpace; FreePctRaw = $freePctRaw; FreePct = [math]::Round($freePctRaw, 1) }
     }
 } catch {
     $diskFacts = @()
 }
@@ -254,39 +318,92 @@ if (-not $criticalEventsReadable) {
         if ($msg.Length -gt 280) { $msg = $msg.Substring(0, 280) }
         Write-Output ("[{0}] Event {1}  {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm'), $_.Id, $msg)
     }
     if ($criticalEvents.Count -gt $eventsToDisplay.Count) {
         Write-Output ("仅显示最新 {0} 条；共命中 {1} 条关键事件。" -f $eventsToDisplay.Count, $criticalEvents.Count)
     }
 }
 
 Write-Output ''
 Write-Output '--- printers ---'
+$spooler = $null
+try {
+    $spooler = Get-Service -Name Spooler -ErrorAction Stop
+    if ($spooler.Status -eq 'Stopped') {
+        Write-Output '打印服务 Spooler: Stopped（打印服务未运行：这是软件问题，不是缺少驱动）'
+    } else {
+        Write-Output ('打印服务 Spooler: {0}' -f $spooler.Status)
+    }
+} catch {
+    Write-Output '无法读取打印服务 Spooler 状态'
+}
+
+$printerStates = @()
+try {
+    $printerStates = @(Get-CimInstance Win32_Printer -ErrorAction Stop)
+} catch {
+    $printerStates = @()
+}
 try {
     $printers = @(Get-Printer -ErrorAction Stop)
     if ($printers.Count -eq 0) { Write-Output '未发现打印机' }
     $printers | ForEach-Object {
-        Write-Output ("{0}  status={1}  driver={2}" -f $_.Name, $_.PrinterStatus, $_.DriverName)
+        $printer = $_
+        Write-Output ("{0}  status={1}  driver={2}" -f $printer.Name, $printer.PrinterStatus, $printer.DriverName)
+
+        $printerState = @($printerStates | Where-Object { $_.Name -eq $printer.Name } | Select-Object -First 1)[0]
+        $detectedError = if ($printerState) { Get-PrinterDetectedErrorText -DetectedErrorState $printerState.DetectedErrorState } else { $null }
+        if ($detectedError) {
+            Write-Output ('  检测到 {0}：这是设备/耗材证据，不是驱动证据。' -f $detectedError)
+        }
+        Write-Output ('  {0}' -f (Get-PrinterPortHint -PortName $printer.PortName))
+        if ($spooler -and $spooler.Status -eq 'Stopped') {
+            Write-Output '  结论：打印服务未运行（软件问题，不是缺少驱动）。'
+        } elseif ($detectedError) {
+            Write-Output ('  结论：{0} 属于设备/耗材证据，不是驱动证据；请同时检查连接。' -f $detectedError)
+        } elseif (-not [string]::IsNullOrWhiteSpace($printer.DriverName)) {
+            Write-Output '  结论：驱动已装（仅凭驱动名，仍需结合连接状态确认）。'
+        } else {
+            Write-Output '  结论：未见驱动名，需结合即插即用设备状态确认驱动情况。'
+        }
     }
 } catch {
     Write-Output '无法读取打印机'
 }
 
 Write-Output ''
-Write-Output '--- PnP devices with driver issue (max 8) ---'
+Write-Output '--- PnP devices with driver issue (capped buckets) ---'
 try {
     $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
-        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
-        Select-Object -First 8)
+        Where-Object { $_.ConfigManagerErrorCode -ne 0 })
     if ($devices.Count -eq 0) { Write-Output '未发现驱动状态异常的即插即用设备' }
-    $devices | ForEach-Object {
-        Write-Output ("{0}  class={1}  error-code={2}" -f $_.Name, $_.PNPClass, $_.ConfigManagerErrorCode)
+    $deviceFindings = @($devices | ForEach-Object {
+        [pscustomobject]@{ Device = $_; Detail = Get-PnpErrorDetail -Code $_.ConfigManagerErrorCode }
+    })
+    $bucketNames = @(
+        [pscustomobject]@{ Name = 'missing-driver'; Label = '缺少/加载失败/策略阻止的驱动状态' },
+        [pscustomobject]@{ Name = 'suspected-hardware'; Label = '疑似硬件状态' },
+        [pscustomobject]@{ Name = 'disabled'; Label = '已禁用状态' },
+        [pscustomobject]@{ Name = 'other'; Label = '其他已识别或未知状态' }
+    )
+    foreach ($bucket in $bucketNames) {
+        $bucketFindings = @($deviceFindings | Where-Object { $_.Detail.Bucket -eq $bucket.Name })
+        if ($bucketFindings.Count -eq 0) { continue }
+        Write-Output ('{0}（{1} 项，最多显示 5 项）' -f $bucket.Label, $bucketFindings.Count)
+        $bucketFindings | Select-Object -First 5 | ForEach-Object {
+            $line = Format-PnpDeviceLine -Device $_.Device -Detail $_.Detail
+            if ($bucket.Name -eq 'missing-driver') {
+                $hardwareId = Get-PnpHardwareIdSummary -Device $_.Device
+                if ($hardwareId) { $line += ('  硬件ID={0}' -f $hardwareId) }
+            }
+            Write-Output ('  {0}' -f $line)
+        }
     }
 } catch {
     Write-Output '无法读取即插即用设备状态'
 }
 
 Write-Output ''
 Write-Output '--- SMART ---'
 if (-not $smartReadable -or $smartFacts.Count -eq 0) {
     Write-Output 'SMART 不可读（跳过）'
 } else {
diff --git a/portable/tests/diagnose.Tests.ps1 b/portable/tests/diagnose.Tests.ps1
index 782dcad..0144d9e 100644
--- a/portable/tests/diagnose.Tests.ps1
+++ b/portable/tests/diagnose.Tests.ps1
@@ -8,20 +8,34 @@ function Get-Utf8Text {
     return [System.Text.Encoding]::UTF8.GetString($Bytes)
 }
 
 $scanMarker = Get-Utf8Text (0xE6,0xAD,0xA3,0xE5,0x9C,0xA8,0xE6,0x89,0xAB,0xE6,0x8F,0x8F)
 $skippedMarker = Get-Utf8Text (0xE8,0xB7,0xB3,0xE8,0xBF,0x87,0xEF,0xBC,0x9A,0xE5,0xA4,0xAA,0xE5,0xA4,0xA7,0xE6,0x88,0x96,0xE8,0xB6,0x85,0xE6,0x97,0xB6)
 $criticalEventsMarker = Get-Utf8Text (0xE5,0x85,0xB3,0xE9,0x94,0xAE,0xE4,0xBA,0x8B,0xE4,0xBB,0xB6)
 $startupFallbackMarker = Get-Utf8Text (0xE6,0x97,0xA0,0xE6,0xB3,0x95,0xE8,0xAF,0xBB,0xE5,0x8F,0x96,0xE5,0x90,0xAF,0xE5,0x8A,0xA8,0xE9,0xA1,0xB9,0xE6,0x95,0xB0,0xE9,0x87,0x8F)
 $sessionStartMarker = Get-Utf8Text (0xE4,0xBC,0x9A,0xE8,0xAF,0x9D,0xE4,0xB8,0x80,0xE5,0xBC,0x80,0xE5,0xA7,0x8B)
 $confirmationMarker = Get-Utf8Text (0xE7,0xA1,0xAE,0xE8,0xAE,0xA4)
 $executionMarker = Get-Utf8Text (0xE6,0x89,0xA7,0xE8,0xA1,0x8C)
+$pnpUnconfigured = Get-Utf8Text (0xE6,0x9C,0xAA,0xE9,0x85,0x8D,0xE7,0xBD,0xAE)
+$pnpCannotStart = Get-Utf8Text (0xE6,0x97,0xA0,0xE6,0xB3,0x95,0xE5,0x90,0xAF,0xE5,0x8A,0xA8)
+$pnpDisabled = Get-Utf8Text (0xE5,0xB7,0xB2,0xE8,0xA2,0xAB,0xE7,0xA6,0x81,0xE7,0x94,0xA8)
+$pnpDriverMissing = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0xE5,0xAE,0x89,0xE8,0xA3,0x85)
+$pnpPowerDisabled = Get-Utf8Text (0xE7,0x94,0xB5,0xE6,0xBA,0x90,0xE4,0xB8,0x8D,0xE8,0xB6,0xB3,0xE8,0xA2,0xAB,0xE7,0xA6,0x81,0xE7,0x94,0xA8)
+$pnpDriverLoadFailed = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE5,0x8A,0xA0,0xE8,0xBD,0xBD,0xE5,0xA4,0xB1,0xE8,0xB4,0xA5)
+$pnpDeviceFault = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE8,0x87,0xAA,0xE6,0x8A,0xA5,0xE6,0x95,0x85,0xE9,0x9A,0x9C)
+$pnpRemoved = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE5,0xB7,0xB2,0xE6,0x8B,0x94,0xE9,0x99,0xA4)
+$pnpPolicyBlocked = Get-Utf8Text (0xE8,0xA2,0xAB,0xE7,0xAD,0x96,0xE7,0x95,0xA5,0xE9,0x98,0xBB,0xE6,0xAD,0xA2)
+$pnpUnsigned = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0xE7,0xAD,0xBE,0xE5,0x90,0x8D)
+$driverSuggestion = (Get-Utf8Text (0xE5,0x8E,0xBB,0xE5,0x8E,0x82,0xE5,0x95,0x86,0xE5,0xAE,0x98,0xE7,0xBD,0x91,0xE6,0x88,0x96)) + ' Windows Update ' + (Get-Utf8Text (0xE5,0x8F,0xAF,0xE9,0x80,0x89,0xE6,0x9B,0xB4,0xE6,0x96,0xB0,0xE6,0x89,0xBE,0xE9,0xA9,0xB1,0xE5,0x8A,0xA8))
+$sampleDeviceName = Get-Utf8Text (0xE7,0xA4,0xBA,0xE4,0xBE,0x8B,0xE7,0xBD,0x91,0xE5,0x8D,0xA1)
+$errorCodeMarker = Get-Utf8Text (0xE9,0x94,0x99,0xE8,0xAF,0xAF,0xE7,0xA0,0x81)
+$suggestionMarker = Get-Utf8Text (0xE5,0xBB,0xBA,0xE8,0xAE,0xAE,0xEF,0xBC,0x9A)
 
 function Invoke-DiagnoseOutput {
     $startInfo = New-Object System.Diagnostics.ProcessStartInfo
     $startInfo.FileName = $windowsPowerShell
     $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $diagnoseScript + '"'
     $startInfo.UseShellExecute = $false
     $startInfo.RedirectStandardOutput = $true
     $startInfo.RedirectStandardError = $true
     $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
     $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
@@ -33,20 +47,62 @@ function Invoke-DiagnoseOutput {
     $errorTask = $process.StandardError.ReadToEndAsync()
     $process.WaitForExit()
     return [pscustomobject]@{
         Output = $outputTask.Result
         Error = $errorTask.Result
         ExitCode = $process.ExitCode
     }
 }
 
 Describe 'Only-U offline diagnose' {
+    It 'translates recognized PnP driver and device states into actionable buckets' {
+        . $diagnoseScript -NoRun
+
+        $expected = @(
+            [pscustomobject]@{ Code = 1; Translation = $pnpUnconfigured; Bucket = 'missing-driver' },
+            [pscustomobject]@{ Code = 10; Translation = $pnpCannotStart; Bucket = 'suspected-hardware' },
+            [pscustomobject]@{ Code = 22; Translation = $pnpDisabled; Bucket = 'disabled' },
+            [pscustomobject]@{ Code = 28; Translation = $pnpDriverMissing; Bucket = 'missing-driver' },
+            [pscustomobject]@{ Code = 29; Translation = $pnpPowerDisabled; Bucket = 'disabled' },
+            [pscustomobject]@{ Code = 37; Translation = $pnpDriverLoadFailed; Bucket = 'missing-driver' },
+            [pscustomobject]@{ Code = 39; Translation = $pnpDriverLoadFailed; Bucket = 'missing-driver' },
+            [pscustomobject]@{ Code = 43; Translation = $pnpDeviceFault; Bucket = 'suspected-hardware' },
+            [pscustomobject]@{ Code = 45; Translation = $pnpRemoved; Bucket = 'other' },
+            [pscustomobject]@{ Code = 48; Translation = $pnpPolicyBlocked; Bucket = 'missing-driver' },
+            [pscustomobject]@{ Code = 52; Translation = $pnpUnsigned; Bucket = 'missing-driver' }
+        )
+        foreach ($item in $expected) {
+            $detail = Get-PnpErrorDetail -Code $item.Code
+            $detail.Translation | Should Be $item.Translation
+            $detail.Bucket | Should Be $item.Bucket
+        }
+
+        (Get-PnpErrorDetail -Code 28).Suggestion | Should Be $driverSuggestion
+    }
+
+    It 'formats a translated PnP finding with the device class code and practical suggestion' {
+        . $diagnoseScript -NoRun
+
+        $device = [pscustomobject]@{ Name = $sampleDeviceName; PNPClass = 'Net'; ConfigManagerErrorCode = 28 }
+        $line = Format-PnpDeviceLine -Device $device -Detail (Get-PnpErrorDetail -Code 28)
+
+        $line | Should Be ($sampleDeviceName + ' [Net] ' + $errorCodeMarker + '28' + (Get-Utf8Text (0xEF,0xBC,0x88)) + $pnpDriverMissing + (Get-Utf8Text (0xEF,0xBC,0x89,0xE2,0x86,0x92,0x20)) + $suggestionMarker + $driverSuggestion)
+    }
+
+    It 'reduces readable hardware IDs to a safe vendor and device summary' {
+        . $diagnoseScript -NoRun
+
+        (Get-HardwareIdSummary -HardwareIds @('PCI\VEN_10EC&DEV_8168&SUBSYS_01234567')) | Should Be 'VEN_10EC&DEV_8168'
+        (Get-HardwareIdSummary -HardwareIds @('USB\VID_046D&PID_C534&REV_2900')) | Should Be 'VID_046D&PID_C534'
+        (Get-HardwareIdSummary -HardwareIds @('ROOT\UNKNOWN')) | Should Be $null
+    }
+
     It 'caps a large TEMP scan and explains that it was skipped' {
         $largeTemp = Join-Path $TestDrive 'large-temp'
         New-Item -ItemType Directory -Path $largeTemp | Out-Null
         1..20001 | ForEach-Object {
             [System.IO.File]::WriteAllText((Join-Path $largeTemp ("file-{0}.tmp" -f $_)), 'x')
         }
 
         $previousTemp = $env:TEMP
         $previousTmp = $env:TMP
         $previousLocalAppData = $env:LOCALAPPDATA
```

