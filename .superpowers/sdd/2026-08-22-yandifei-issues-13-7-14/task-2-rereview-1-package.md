# Re-review package — Task 2, fix round 1

Open findings to assess:
1. Enforce an approximately 60-second bounded/cancellable deadline for newly added printer/PnP work.
2. Prioritize WSD offline as connection evidence over a generic driver-installed conclusion.
3. Add deterministic controlled coverage for PnP buckets/HardwareID and printer branches.

```diff
9e0f299 fix(diagnose): bound device evidence reads
 portable/diagnose.ps1             | 181 +++++++++++++++++++++++++++++---------
 portable/tests/diagnose.Tests.ps1 | 102 +++++++++++++++++++++
 2 files changed, 239 insertions(+), 44 deletions(-)
diff --git a/portable/diagnose.ps1 b/portable/diagnose.ps1
index a8568c5..798a45a 100644
--- a/portable/diagnose.ps1
+++ b/portable/diagnose.ps1
@@ -1,18 +1,40 @@
 ﻿# Only-U offline diagnose. No LLM. Read-only.
 param(
     [switch]$NoRun
 )
 
 $ErrorActionPreference = 'Continue'
 [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
 
+function Invoke-BoundedRead {
+    param(
+        [scriptblock]$ScriptBlock,
+        [object[]]$ArgumentList = @(),
+        [int]$TimeoutSeconds = 4
+    )
+
+    $job = $null
+    try {
+        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
+        if ($null -eq (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
+            Stop-Job -Job $job -ErrorAction SilentlyContinue
+            return [pscustomobject]@{ Status = 'TimedOut'; Value = $null }
+        }
+        return [pscustomobject]@{ Status = 'Complete'; Value = @(Receive-Job -Job $job -ErrorAction Stop) }
+    } catch {
+        return [pscustomobject]@{ Status = 'Unreadable'; Value = $null }
+    } finally {
+        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
+    }
+}
+
 function Get-PnpErrorDetail([int]$Code) {
     switch ($Code) {
         1  { return [pscustomobject]@{ Translation = '未配置'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
         10 { return [pscustomobject]@{ Translation = '无法启动'; Suggestion = '重新插拔设备、换接口，必要时送修'; Bucket = 'suspected-hardware' } }
         22 { return [pscustomobject]@{ Translation = '已被禁用'; Suggestion = '在设备管理器中启用该设备'; Bucket = 'disabled' } }
         28 { return [pscustomobject]@{ Translation = '驱动未安装'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
         29 { return [pscustomobject]@{ Translation = '电源不足被禁用'; Suggestion = '在设备管理器中启用该设备'; Bucket = 'disabled' } }
         37 { return [pscustomobject]@{ Translation = '驱动加载失败'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
         39 { return [pscustomobject]@{ Translation = '驱动加载失败'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
         43 { return [pscustomobject]@{ Translation = '设备自报故障'; Suggestion = '重新插拔设备、换接口，必要时送修'; Bucket = 'suspected-hardware' } }
@@ -29,46 +51,114 @@ function Format-PnpDeviceLine($Device, $Detail) {
     return ('{0} [{1}] 错误码{2}（{3}）→ 建议：{4}' -f $name, $class, $Device.ConfigManagerErrorCode, $Detail.Translation, $Detail.Suggestion)
 }
 
 function Get-HardwareIdSummary([string[]]$HardwareIds) {
     if ($null -eq $HardwareIds -or $HardwareIds.Count -eq 0 -or [string]::IsNullOrWhiteSpace($HardwareIds[0])) { return $null }
     $match = [regex]::Match($HardwareIds[0], '(?i)(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|VID_[0-9A-F]{4}&PID_[0-9A-F]{4})')
     if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
     return $null
 }
 
-function Get-PnpHardwareIdSummary($Device) {
+function Get-PnpHardwareIdSummary {
+    param(
+        $Device,
+        [scriptblock]$PropertyReader,
+        [int]$TimeoutSeconds = 2
+    )
+
     if ([string]::IsNullOrWhiteSpace($Device.PNPDeviceID)) { return $null }
     try {
-        $property = Get-PnpDeviceProperty -InstanceId $Device.PNPDeviceID -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
+        if ($PropertyReader) {
+            $property = & $PropertyReader $Device.PNPDeviceID
+        } else {
+            $read = Invoke-BoundedRead -TimeoutSeconds $TimeoutSeconds -ArgumentList @($Device.PNPDeviceID) -ScriptBlock {
+                param($instanceId)
+                Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
+            }
+            if ($read.Status -ne 'Complete') { return $null }
+            $property = @($read.Value)[0]
+        }
         return Get-HardwareIdSummary -HardwareIds @($property.Data)
     } catch {
         return $null
     }
 }
 
+function Get-PnpFindingLine {
+    param(
+        $Finding,
+        [scriptblock]$HardwareIdReader,
+        [int]$HardwareIdTimeoutSeconds = 2
+    )
+
+    $line = Format-PnpDeviceLine -Device $Finding.Device -Detail $Finding.Detail
+    if ($Finding.Detail.Bucket -eq 'missing-driver') {
+        $hardwareId = Get-PnpHardwareIdSummary -Device $Finding.Device -PropertyReader $HardwareIdReader -TimeoutSeconds $HardwareIdTimeoutSeconds
+        if ($hardwareId) { $line += ('  硬件ID={0}' -f $hardwareId) }
+    }
+    return $line
+}
+
+function Get-PnpBucketDisplay {
+    param(
+        [object[]]$Findings,
+        [string]$BucketName
+    )
+
+    $matches = @($Findings | Where-Object { $_.Detail.Bucket -eq $BucketName })
+    return [pscustomobject]@{ Count = $matches.Count; Entries = @($matches | Select-Object -First 5) }
+}
+
 function Get-PrinterDetectedErrorText($DetectedErrorState) {
     switch ([int]$DetectedErrorState) {
         8 { return '卡纸' }
         9 { return '脱机' }
         { $_ -in 2, 4 } { return '无纸' }
         { $_ -in 3, 5 } { return '缺粉' }
         default { return $null }
     }
 }
 
-function Get-PrinterPortHint([string]$PortName) {
-    if ([string]::IsNullOrWhiteSpace($PortName)) { return '端口信息不可读，需结合连接状态判断。' }
-    if ($PortName -match '(?i)^WSD') { return 'WSD 端口脱机时，网络或 WSD 协议可能有问题。' }
-    if ($PortName -match '(?i)(TCP|IP_)') { return 'TCP/IP 端口可用 ping 验证连通性。' }
-    if ($PortName -match '(?i)^USB') { return 'USB 端口请检查即插即用设备状态。' }
-    return ('端口 {0}，需结合连接状态判断。' -f $PortName)
+function Test-PrinterOfflineStatus($PrinterStatus) {
+    $statusText = [string]$PrinterStatus
+    return ($statusText -match '(?i)offline' -or $statusText -eq '7')
+}
+
+function Get-PrinterPortHint([string]$PortName, $PrinterStatus) {
+    $isOffline = Test-PrinterOfflineStatus -PrinterStatus $PrinterStatus
+    if ([string]::IsNullOrWhiteSpace($PortName)) { return [pscustomobject]@{ Kind = 'unknown'; Action = 'inspect'; Text = '端口信息不可读，需结合连接状态判断。' } }
+    if ($PortName -match '(?i)^WSD') {
+        $text = if ($isOffline) { 'WSD 打印机脱机：网络或 WSD 协议连接可能有问题。' } else { 'WSD 端口请结合网络和 WSD 协议状态检查。' }
+        return [pscustomobject]@{ Kind = 'connection'; Action = 'network-wsd'; Text = $text }
+    }
+    if ($PortName -match '(?i)(TCP|IP_)') { return [pscustomobject]@{ Kind = 'connection'; Action = 'ping'; Text = 'TCP/IP 端口可用 ping 验证连通性。' } }
+    if ($PortName -match '(?i)^USB') { return [pscustomobject]@{ Kind = 'pnp'; Action = 'inspect-pnp'; Text = 'USB 端口请检查即插即用设备状态。' } }
+    return [pscustomobject]@{ Kind = 'unknown'; Action = 'inspect'; Text = ('端口 {0}，需结合连接状态判断。' -f $PortName) }
+}
+
+function Get-PrinterConclusion {
+    param($Printer, [string]$SpoolerStatus, [string]$DetectedError)
+
+    if ($SpoolerStatus -eq 'Stopped') {
+        return [pscustomobject]@{ Kind = 'service'; Text = '结论：打印服务未运行（软件问题，不是缺少驱动）。' }
+    }
+    $portHint = Get-PrinterPortHint -PortName $Printer.PortName -PrinterStatus $Printer.PrinterStatus
+    if ($portHint.Kind -eq 'connection' -and (Test-PrinterOfflineStatus -PrinterStatus $Printer.PrinterStatus)) {
+        return [pscustomobject]@{ Kind = 'connection'; Text = '结论：打印机脱机，属于网络/WSD 或连接证据，不是驱动证据。' }
+    }
+    if ($DetectedError) {
+        return [pscustomobject]@{ Kind = 'consumable'; Text = ('结论：{0} 属于设备/耗材证据，不是驱动证据；请同时检查连接。' -f $DetectedError) }
+    }
+    if (-not [string]::IsNullOrWhiteSpace($Printer.DriverName)) {
+        return [pscustomobject]@{ Kind = 'driver'; Text = '结论：驱动已装（仅凭驱动名，仍需结合连接状态确认）。' }
+    }
+    return [pscustomobject]@{ Kind = 'unknown'; Text = '结论：未见驱动名，需结合即插即用设备状态确认驱动情况。' }
 }
 
 function Format-Bytes([long]$n) {
     if ($n -lt 0) { return 'n/a' }
     if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
     if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
     return ('{0:N0} B' -f $n)
 }
 
 $maxScanFiles = 20000
@@ -319,93 +409,96 @@ if (-not $criticalEventsReadable) {
         Write-Output ("[{0}] Event {1}  {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm'), $_.Id, $msg)
     }
     if ($criticalEvents.Count -gt $eventsToDisplay.Count) {
         Write-Output ("仅显示最新 {0} 条；共命中 {1} 条关键事件。" -f $eventsToDisplay.Count, $criticalEvents.Count)
     }
 }
 
 Write-Output ''
 Write-Output '--- printers ---'
 $spooler = $null
-try {
-    $spooler = Get-Service -Name Spooler -ErrorAction Stop
-    if ($spooler.Status -eq 'Stopped') {
-        Write-Output '打印服务 Spooler: Stopped（打印服务未运行：这是软件问题，不是缺少驱动）'
+$spoolerRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
+    Get-Service -Name Spooler -ErrorAction Stop
+}
+if ($spoolerRead.Status -eq 'Complete') {
+    $spooler = @($spoolerRead.Value)[0]
+    if ($spooler) {
+        if ($spooler.Status -eq 'Stopped') {
+            Write-Output '打印服务 Spooler: Stopped（打印服务未运行：这是软件问题，不是缺少驱动）'
+        } else {
+            Write-Output ('打印服务 Spooler: {0}' -f $spooler.Status)
+        }
     } else {
-        Write-Output ('打印服务 Spooler: {0}' -f $spooler.Status)
+        Write-Output '无法读取打印服务 Spooler 状态'
     }
-} catch {
+} else {
     Write-Output '无法读取打印服务 Spooler 状态'
 }
 
 $printerStates = @()
-try {
-    $printerStates = @(Get-CimInstance Win32_Printer -ErrorAction Stop)
-} catch {
-    $printerStates = @()
+$printerStatesRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
+    Get-CimInstance Win32_Printer -ErrorAction Stop
 }
-try {
-    $printers = @(Get-Printer -ErrorAction Stop)
+if ($printerStatesRead.Status -eq 'Complete') { $printerStates = @($printerStatesRead.Value) }
+
+$printersRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
+    Get-Printer -ErrorAction Stop
+}
+if ($printersRead.Status -eq 'Complete') {
+    $printers = @($printersRead.Value)
     if ($printers.Count -eq 0) { Write-Output '未发现打印机' }
     $printers | ForEach-Object {
         $printer = $_
         Write-Output ("{0}  status={1}  driver={2}" -f $printer.Name, $printer.PrinterStatus, $printer.DriverName)
 
         $printerState = @($printerStates | Where-Object { $_.Name -eq $printer.Name } | Select-Object -First 1)[0]
         $detectedError = if ($printerState) { Get-PrinterDetectedErrorText -DetectedErrorState $printerState.DetectedErrorState } else { $null }
         if ($detectedError) {
             Write-Output ('  检测到 {0}：这是设备/耗材证据，不是驱动证据。' -f $detectedError)
         }
-        Write-Output ('  {0}' -f (Get-PrinterPortHint -PortName $printer.PortName))
-        if ($spooler -and $spooler.Status -eq 'Stopped') {
-            Write-Output '  结论：打印服务未运行（软件问题，不是缺少驱动）。'
-        } elseif ($detectedError) {
-            Write-Output ('  结论：{0} 属于设备/耗材证据，不是驱动证据；请同时检查连接。' -f $detectedError)
-        } elseif (-not [string]::IsNullOrWhiteSpace($printer.DriverName)) {
-            Write-Output '  结论：驱动已装（仅凭驱动名，仍需结合连接状态确认）。'
-        } else {
-            Write-Output '  结论：未见驱动名，需结合即插即用设备状态确认驱动情况。'
-        }
+        $portHint = Get-PrinterPortHint -PortName $printer.PortName -PrinterStatus $printer.PrinterStatus
+        $conclusion = Get-PrinterConclusion -Printer $printer -SpoolerStatus $(if ($spooler) { $spooler.Status } else { '' }) -DetectedError $detectedError
+        Write-Output ('  {0}' -f $portHint.Text)
+        Write-Output ('  {0}' -f $conclusion.Text)
     }
-} catch {
+} else {
     Write-Output '无法读取打印机'
 }
 
 Write-Output ''
 Write-Output '--- PnP devices with driver issue (capped buckets) ---'
-try {
-    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
-        Where-Object { $_.ConfigManagerErrorCode -ne 0 })
+$pnpRead = Invoke-BoundedRead -TimeoutSeconds 6 -ScriptBlock {
+    Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
+        Where-Object { $_.ConfigManagerErrorCode -ne 0 }
+}
+if ($pnpRead.Status -eq 'Complete') {
+    $devices = @($pnpRead.Value)
     if ($devices.Count -eq 0) { Write-Output '未发现驱动状态异常的即插即用设备' }
     $deviceFindings = @($devices | ForEach-Object {
         [pscustomobject]@{ Device = $_; Detail = Get-PnpErrorDetail -Code $_.ConfigManagerErrorCode }
     })
     $bucketNames = @(
         [pscustomobject]@{ Name = 'missing-driver'; Label = '缺少/加载失败/策略阻止的驱动状态' },
         [pscustomobject]@{ Name = 'suspected-hardware'; Label = '疑似硬件状态' },
         [pscustomobject]@{ Name = 'disabled'; Label = '已禁用状态' },
         [pscustomobject]@{ Name = 'other'; Label = '其他已识别或未知状态' }
     )
     foreach ($bucket in $bucketNames) {
-        $bucketFindings = @($deviceFindings | Where-Object { $_.Detail.Bucket -eq $bucket.Name })
-        if ($bucketFindings.Count -eq 0) { continue }
-        Write-Output ('{0}（{1} 项，最多显示 5 项）' -f $bucket.Label, $bucketFindings.Count)
-        $bucketFindings | Select-Object -First 5 | ForEach-Object {
-            $line = Format-PnpDeviceLine -Device $_.Device -Detail $_.Detail
-            if ($bucket.Name -eq 'missing-driver') {
-                $hardwareId = Get-PnpHardwareIdSummary -Device $_.Device
-                if ($hardwareId) { $line += ('  硬件ID={0}' -f $hardwareId) }
-            }
+        $bucketDisplay = Get-PnpBucketDisplay -Findings $deviceFindings -BucketName $bucket.Name
+        if ($bucketDisplay.Count -eq 0) { continue }
+        Write-Output ('{0}（{1} 项，最多显示 5 项）' -f $bucket.Label, $bucketDisplay.Count)
+        $bucketDisplay.Entries | ForEach-Object {
+            $line = Get-PnpFindingLine -Finding $_ -HardwareIdTimeoutSeconds 2
             Write-Output ('  {0}' -f $line)
         }
     }
-} catch {
+} else {
     Write-Output '无法读取即插即用设备状态'
 }
 
 Write-Output ''
 Write-Output '--- SMART ---'
 if (-not $smartReadable -or $smartFacts.Count -eq 0) {
     Write-Output 'SMART 不可读（跳过）'
 } else {
     $smartFacts | ForEach-Object {
         $errors = if ($null -eq $_.ReadErrorsUncorrected) { 'n/a' } else { $_.ReadErrorsUncorrected }
diff --git a/portable/tests/diagnose.Tests.ps1 b/portable/tests/diagnose.Tests.ps1
index 0144d9e..b4a2d0f 100644
--- a/portable/tests/diagnose.Tests.ps1
+++ b/portable/tests/diagnose.Tests.ps1
@@ -22,20 +22,24 @@ $pnpDriverMissing = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0
 $pnpPowerDisabled = Get-Utf8Text (0xE7,0x94,0xB5,0xE6,0xBA,0x90,0xE4,0xB8,0x8D,0xE8,0xB6,0xB3,0xE8,0xA2,0xAB,0xE7,0xA6,0x81,0xE7,0x94,0xA8)
 $pnpDriverLoadFailed = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE5,0x8A,0xA0,0xE8,0xBD,0xBD,0xE5,0xA4,0xB1,0xE8,0xB4,0xA5)
 $pnpDeviceFault = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE8,0x87,0xAA,0xE6,0x8A,0xA5,0xE6,0x95,0x85,0xE9,0x9A,0x9C)
 $pnpRemoved = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE5,0xB7,0xB2,0xE6,0x8B,0x94,0xE9,0x99,0xA4)
 $pnpPolicyBlocked = Get-Utf8Text (0xE8,0xA2,0xAB,0xE7,0xAD,0x96,0xE7,0x95,0xA5,0xE9,0x98,0xBB,0xE6,0xAD,0xA2)
 $pnpUnsigned = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0xE7,0xAD,0xBE,0xE5,0x90,0x8D)
 $driverSuggestion = (Get-Utf8Text (0xE5,0x8E,0xBB,0xE5,0x8E,0x82,0xE5,0x95,0x86,0xE5,0xAE,0x98,0xE7,0xBD,0x91,0xE6,0x88,0x96)) + ' Windows Update ' + (Get-Utf8Text (0xE5,0x8F,0xAF,0xE9,0x80,0x89,0xE6,0x9B,0xB4,0xE6,0x96,0xB0,0xE6,0x89,0xBE,0xE9,0xA9,0xB1,0xE5,0x8A,0xA8))
 $sampleDeviceName = Get-Utf8Text (0xE7,0xA4,0xBA,0xE4,0xBE,0x8B,0xE7,0xBD,0x91,0xE5,0x8D,0xA1)
 $errorCodeMarker = Get-Utf8Text (0xE9,0x94,0x99,0xE8,0xAF,0xAF,0xE7,0xA0,0x81)
 $suggestionMarker = Get-Utf8Text (0xE5,0xBB,0xBA,0xE8,0xAE,0xAE,0xEF,0xBC,0x9A)
+$printerJam = Get-Utf8Text (0xE5,0x8D,0xA1,0xE7,0xBA,0xB8)
+$printerOffline = Get-Utf8Text (0xE8,0x84,0xB1,0xE6,0x9C,0xBA)
+$printerNoPaper = Get-Utf8Text (0xE6,0x97,0xA0,0xE7,0xBA,0xB8)
+$printerNoToner = Get-Utf8Text (0xE7,0xBC,0xBA,0xE7,0xB2,0x89)
 
 function Invoke-DiagnoseOutput {
     $startInfo = New-Object System.Diagnostics.ProcessStartInfo
     $startInfo.FileName = $windowsPowerShell
     $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $diagnoseScript + '"'
     $startInfo.UseShellExecute = $false
     $startInfo.RedirectStandardOutput = $true
     $startInfo.RedirectStandardError = $true
     $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
     $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
@@ -89,20 +93,118 @@ Describe 'Only-U offline diagnose' {
     }
 
     It 'reduces readable hardware IDs to a safe vendor and device summary' {
         . $diagnoseScript -NoRun
 
         (Get-HardwareIdSummary -HardwareIds @('PCI\VEN_10EC&DEV_8168&SUBSYS_01234567')) | Should Be 'VEN_10EC&DEV_8168'
         (Get-HardwareIdSummary -HardwareIds @('USB\VID_046D&PID_C534&REV_2900')) | Should Be 'VID_046D&PID_C534'
         (Get-HardwareIdSummary -HardwareIds @('ROOT\UNKNOWN')) | Should Be $null
     }
 
+    It 'forces a timed-out diagnostic read to complete within its deadline' {
+        . $diagnoseScript -NoRun
+
+        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
+        $read = Invoke-BoundedRead -TimeoutSeconds 1 -ScriptBlock { Start-Sleep -Seconds 4; 'late result' }
+        $stopwatch.Stop()
+
+        $read.Status | Should Be 'TimedOut'
+        $read.Value | Should Be $null
+        $stopwatch.Elapsed.TotalSeconds | Should BeLessThan 3
+    }
+
+    It 'counts PnP bucket findings while displaying at most five' {
+        . $diagnoseScript -NoRun
+
+        $detail = Get-PnpErrorDetail -Code 28
+        $findings = @(1..6 | ForEach-Object {
+            [pscustomobject]@{
+                Device = [pscustomobject]@{ Name = "device-$_"; PNPClass = 'Net'; ConfigManagerErrorCode = 28; PNPDeviceID = "PCI\\$_" }
+                Detail = $detail
+            }
+        })
+        $bucket = Get-PnpBucketDisplay -Findings $findings -BucketName 'missing-driver'
+
+        $bucket.Count | Should Be 6
+        $bucket.Entries.Count | Should Be 5
+    }
+
+    It 'uses distinct hardware and disabled remediation suggestions' {
+        . $diagnoseScript -NoRun
+
+        $hardware = Get-PnpErrorDetail -Code 10
+        $disabled = Get-PnpErrorDetail -Code 22
+
+        $hardware.Bucket | Should Be 'suspected-hardware'
+        $disabled.Bucket | Should Be 'disabled'
+        $hardware.Suggestion | Should Not Be $disabled.Suggestion
+    }
+
+    It 'uses only the first hardware ID and only for missing-driver findings' {
+        . $diagnoseScript -NoRun
+
+        (Get-HardwareIdSummary -HardwareIds @('PCI\VEN_10EC&DEV_8168&SUBSYS_FIRST', 'USB\VID_046D&PID_C534')) | Should Be 'VEN_10EC&DEV_8168'
+        $reader = {
+            param($instanceId)
+            if ($instanceId -ne 'PCI\MISSING') { throw 'unexpected hardware-ID instance' }
+            return [pscustomobject]@{ Data = @('PCI\VEN_10EC&DEV_8168&SUBSYS_FIRST', 'USB\VID_046D&PID_C534') }
+        }
+        $missingFinding = [pscustomobject]@{
+            Device = [pscustomobject]@{ Name = 'missing'; PNPClass = 'Net'; ConfigManagerErrorCode = 28; PNPDeviceID = 'PCI\MISSING' }
+            Detail = Get-PnpErrorDetail -Code 28
+        }
+        $disabledFinding = [pscustomobject]@{
+            Device = [pscustomobject]@{ Name = 'disabled'; PNPClass = 'Net'; ConfigManagerErrorCode = 22; PNPDeviceID = 'PCI\DISABLED' }
+            Detail = Get-PnpErrorDetail -Code 22
+        }
+
+        (Get-PnpFindingLine -Finding $missingFinding -HardwareIdReader $reader) | Should BeLike '*VEN_10EC&DEV_8168*'
+        Get-PnpFindingLine -Finding $disabledFinding -HardwareIdReader { throw 'disabled finding must not read hardware IDs' } | Out-Null
+    }
+
+    It 'skips unreadable hardware ID properties without failing the PnP finding' {
+        . $diagnoseScript -NoRun
+
+        $device = [pscustomobject]@{ PNPDeviceID = 'PCI\UNREADABLE' }
+        $calls = New-Object System.Collections.ArrayList
+        $unreadableReader = {
+            param($instanceId)
+            [void]$calls.Add($instanceId)
+            throw 'unreadable'
+        }
+
+        (Get-PnpHardwareIdSummary -Device $device -PropertyReader $unreadableReader) | Should Be $null
+        $calls.Count | Should Be 1
+        $calls[0] | Should Be 'PCI\UNREADABLE'
+    }
+
+    It 'classifies spooler, printer errors, ports, and conclusions from controlled facts' {
+        . $diagnoseScript -NoRun
+
+        (Get-PrinterDetectedErrorText -DetectedErrorState 8) | Should Be $printerJam
+        (Get-PrinterDetectedErrorText -DetectedErrorState 9) | Should Be $printerOffline
+        (Get-PrinterDetectedErrorText -DetectedErrorState 2) | Should Be $printerNoPaper
+        (Get-PrinterDetectedErrorText -DetectedErrorState 5) | Should Be $printerNoToner
+
+        $wsdOffline = Get-PrinterPortHint -PortName 'WSD-123' -PrinterStatus 'Offline'
+        $wsdOffline.Kind | Should Be 'connection'
+        $wsdOffline.Action | Should Be 'network-wsd'
+        (Get-PrinterPortHint -PortName 'IP_192.0.2.1' -PrinterStatus 'Normal').Action | Should Be 'ping'
+        (Get-PrinterPortHint -PortName 'USB001' -PrinterStatus 'Normal').Action | Should Be 'inspect-pnp'
+
+        $offlinePrinter = [pscustomobject]@{ PortName = 'WSD-123'; PrinterStatus = 'Offline'; DriverName = 'installed driver' }
+        (Get-PrinterConclusion -Printer $offlinePrinter -SpoolerStatus 'Running' -DetectedError $null).Kind | Should Be 'connection'
+        (Get-PrinterConclusion -Printer $offlinePrinter -SpoolerStatus 'Stopped' -DetectedError $null).Kind | Should Be 'service'
+        $serializedOfflinePrinter = [pscustomobject]@{ PortName = 'WSD-123'; PrinterStatus = 7; DriverName = 'installed driver' }
+        (Get-PrinterConclusion -Printer $serializedOfflinePrinter -SpoolerStatus 'Running' -DetectedError $null).Kind | Should Be 'connection'
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

