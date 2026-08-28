# Only-U offline diagnose. No LLM. Read-only.
param(
    [switch]$NoRun
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$diagnosisBudgetSeconds = 50
$diagnosisStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Get-DiagnosisRemainingTimeout([int]$RequestedTimeoutSeconds) {
    if ($RequestedTimeoutSeconds -le 0) { return 0 }
    $remainingSeconds = $diagnosisBudgetSeconds - $diagnosisStopwatch.Elapsed.TotalSeconds
    if ($remainingSeconds -lt 1) { return 0 }
    return [int][math]::Min($RequestedTimeoutSeconds, [math]::Floor($remainingSeconds))
}

function Invoke-BoundedRead {
    param(
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 4
    )

    $job = $null
    try {
        $effectiveTimeout = Get-DiagnosisRemainingTimeout -RequestedTimeoutSeconds $TimeoutSeconds
        if ($effectiveTimeout -le 0) { return [pscustomobject]@{ Status = 'TimedOut'; Value = $null } }
        $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
        $effectiveTimeout = Get-DiagnosisRemainingTimeout -RequestedTimeoutSeconds $TimeoutSeconds
        if ($effectiveTimeout -le 0 -or $null -eq (Wait-Job -Job $job -Timeout $effectiveTimeout)) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Status = 'TimedOut'; Value = $null }
        }
        return [pscustomobject]@{ Status = 'Complete'; Value = @(Receive-Job -Job $job -ErrorAction Stop) }
    } catch {
        return [pscustomobject]@{ Status = 'Unreadable'; Value = $null }
    } finally {
        if ($job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
}

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
        45 { return [pscustomobject]@{ Translation = '设备已拔除'; Suggestion = '重新连接设备后再检查状态'; Bucket = 'other' } }
        48 { return [pscustomobject]@{ Translation = '被策略阻止'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
        52 { return [pscustomobject]@{ Translation = '驱动未签名'; Suggestion = '去厂商官网或 Windows Update 可选更新找驱动'; Bucket = 'missing-driver' } }
        default { return [pscustomobject]@{ Translation = '未知状态'; Suggestion = '在设备管理器中查看设备状态'; Bucket = 'other' } }
    }
}

function Format-PnpDeviceLine($Device, $Detail) {
    $name = if ($Device.Name) { $Device.Name } else { '未知设备' }
    $class = if ($Device.PNPClass) { $Device.PNPClass } else { '未知类' }
    return ('{0} [{1}] 错误码{2}（{3}）→ 建议：{4}' -f $name, $class, $Device.ConfigManagerErrorCode, $Detail.Translation, $Detail.Suggestion)
}

function Get-HardwareIdSummary([string[]]$HardwareIds) {
    if ($null -eq $HardwareIds -or $HardwareIds.Count -eq 0 -or [string]::IsNullOrWhiteSpace($HardwareIds[0])) { return $null }
    $match = [regex]::Match($HardwareIds[0], '(?i)(VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|VID_[0-9A-F]{4}&PID_[0-9A-F]{4})')
    if ($match.Success) { return $match.Groups[1].Value.ToUpperInvariant() }
    return $null
}

function Get-PnpHardwareIdSummary {
    param(
        $Device,
        [scriptblock]$PropertyReader,
        [int]$TimeoutSeconds = 2
    )

    if ([string]::IsNullOrWhiteSpace($Device.PNPDeviceID)) { return $null }
    try {
        if ($PropertyReader) {
            $property = & $PropertyReader $Device.PNPDeviceID
        } else {
            $read = Invoke-BoundedRead -TimeoutSeconds $TimeoutSeconds -ArgumentList @($Device.PNPDeviceID) -ScriptBlock {
                param($instanceId)
                Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
            }
            if ($read.Status -ne 'Complete') { return $null }
            $property = @($read.Value)[0]
        }
        return Get-HardwareIdSummary -HardwareIds @($property.Data)
    } catch {
        return $null
    }
}

function Get-PnpFindingLine {
    param(
        $Finding,
        [scriptblock]$HardwareIdReader,
        [int]$HardwareIdTimeoutSeconds = 2
    )

    $line = Format-PnpDeviceLine -Device $Finding.Device -Detail $Finding.Detail
    if ($Finding.Detail.Bucket -eq 'missing-driver') {
        $hardwareId = Get-PnpHardwareIdSummary -Device $Finding.Device -PropertyReader $HardwareIdReader -TimeoutSeconds $HardwareIdTimeoutSeconds
        if ($hardwareId) { $line += ('  硬件ID={0}' -f $hardwareId) }
    }
    return $line
}

function Get-PnpBucketDisplay {
    param(
        [object[]]$Findings,
        [string]$BucketName
    )

    $matches = @($Findings | Where-Object { $_.Detail.Bucket -eq $BucketName })
    return [pscustomobject]@{ Count = $matches.Count; Entries = @($matches | Select-Object -First 5) }
}

function Get-PrinterDetectedErrorText($DetectedErrorState) {
    switch ([int]$DetectedErrorState) {
        8 { return '卡纸' }
        9 { return '脱机' }
        { $_ -in 2, 4 } { return '无纸' }
        { $_ -in 3, 5 } { return '缺粉' }
        default { return $null }
    }
}

function Test-PrinterOfflineStatus($PrinterStatus) {
    $statusText = [string]$PrinterStatus
    return ($statusText -match '(?i)offline' -or $statusText -eq '7')
}

function Get-PrinterPortHint([string]$PortName, $PrinterStatus) {
    $isOffline = Test-PrinterOfflineStatus -PrinterStatus $PrinterStatus
    if ([string]::IsNullOrWhiteSpace($PortName)) { return [pscustomobject]@{ Kind = 'unknown'; Action = 'inspect'; Text = '端口信息不可读，需结合连接状态判断。' } }
    if ($PortName -match '(?i)^WSD') {
        $text = if ($isOffline) { 'WSD 打印机脱机：网络或 WSD 协议连接可能有问题。' } else { 'WSD 端口请结合网络和 WSD 协议状态检查。' }
        return [pscustomobject]@{ Kind = 'connection'; Action = 'network-wsd'; Text = $text }
    }
    if ($PortName -match '(?i)(TCP|IP_)') { return [pscustomobject]@{ Kind = 'connection'; Action = 'ping'; Text = 'TCP/IP 端口可用 ping 验证连通性。' } }
    if ($PortName -match '(?i)^USB') { return [pscustomobject]@{ Kind = 'pnp'; Action = 'inspect-pnp'; Text = 'USB 端口请检查即插即用设备状态。' } }
    return [pscustomobject]@{ Kind = 'unknown'; Action = 'inspect'; Text = ('端口 {0}，需结合连接状态判断。' -f $PortName) }
}

function Get-PrinterConclusion {
    param($Printer, [string]$SpoolerStatus, [string]$DetectedError)

    if ($SpoolerStatus -eq 'Stopped') {
        return [pscustomobject]@{ Kind = 'service'; Text = '结论：打印服务未运行（软件问题，不是缺少驱动）。' }
    }
    $portHint = Get-PrinterPortHint -PortName $Printer.PortName -PrinterStatus $Printer.PrinterStatus
    if ($portHint.Kind -eq 'connection' -and (Test-PrinterOfflineStatus -PrinterStatus $Printer.PrinterStatus)) {
        return [pscustomobject]@{ Kind = 'connection'; Text = '结论：打印机脱机，属于网络/WSD 或连接证据，不是驱动证据。' }
    }
    if ($DetectedError) {
        return [pscustomobject]@{ Kind = 'consumable'; Text = ('结论：{0} 属于设备/耗材证据，不是驱动证据；请同时检查连接。' -f $DetectedError) }
    }
    if (-not [string]::IsNullOrWhiteSpace($Printer.DriverName)) {
        return [pscustomobject]@{ Kind = 'driver'; Text = '结论：驱动已装（仅凭驱动名，仍需结合连接状态确认）。' }
    }
    return [pscustomobject]@{ Kind = 'unknown'; Text = '结论：未见驱动名，需结合即插即用设备状态确认驱动情况。' }
}

function Format-Bytes([long]$n) {
    if ($n -lt 0) { return 'n/a' }
    if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N0} B' -f $n)
}

$maxScanFiles = 20000
$scanTimeoutSeconds = 8

function Get-DirSize([string]$path) {
    if ($path -match '^[\\]{2}') {
        return [pscustomobject]@{ Status = 'Unc'; Bytes = 0; Files = 0 }
    }
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ Status = 'Missing'; Bytes = 0; Files = 0 }
    }

    $effectiveTimeout = Get-DiagnosisRemainingTimeout -RequestedTimeoutSeconds $scanTimeoutSeconds
    if ($effectiveTimeout -le 0) {
        return [pscustomobject]@{ Status = 'Skipped'; Bytes = 0; Files = 0 }
    }
    $job = Start-Job -ArgumentList $path, $maxScanFiles -ScriptBlock {
        param([string]$rootPath, [int]$fileLimit)
        [long]$bytes = 0
        [int]$files = 0
        $directories = New-Object 'System.Collections.Stack'
        $directories.Push([System.IO.DirectoryInfo]$rootPath)

        while ($directories.Count -gt 0) {
            $directory = [System.IO.DirectoryInfo]$directories.Pop()
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            try {
                foreach ($file in $directory.GetFiles()) {
                    if ($files -ge $fileLimit) {
                        return [pscustomobject]@{ Status = 'Skipped'; Bytes = $bytes; Files = $files }
                    }
                    $bytes += $file.Length
                    $files++
                }
                foreach ($child in $directory.GetDirectories()) {
                    if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $directories.Push($child)
                    }
                }
            } catch [System.UnauthorizedAccessException] {
                continue
            } catch [System.IO.IOException] {
                continue
            }
        }
        return [pscustomobject]@{ Status = 'Complete'; Bytes = $bytes; Files = $files }
    }
    try {
        $effectiveTimeout = Get-DiagnosisRemainingTimeout -RequestedTimeoutSeconds $scanTimeoutSeconds
        if ($effectiveTimeout -le 0 -or $null -eq (Wait-Job -Job $job -Timeout $effectiveTimeout)) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Status = 'Skipped'; Bytes = 0; Files = 0 }
        }
        $result = @(Receive-Job -Job $job -ErrorAction Stop | Select-Object -First 1)[0]
        if ($null -eq $result) { return [pscustomobject]@{ Status = 'Unreadable'; Bytes = 0; Files = 0 } }
        return $result
    } catch {
        return [pscustomobject]@{ Status = 'Unreadable'; Bytes = 0; Files = 0 }
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

if ($NoRun) { return }

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

$memoryFacts = $null
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $memoryFacts = [pscustomobject]@{
        Used = [long](($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB)
        Total = [long]($os.TotalVisibleMemorySize * 1KB)
        Commit = [long](($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB)
        CommitLimit = [long]($os.TotalVirtualMemorySize * 1KB)
    }
} catch {
    $memoryFacts = $null
}

$committedPercentRaw = $null
$committedPercent = $null
try {
    $sample = Get-Counter '\Memory\% Committed Bytes In Use' -ErrorAction Stop
    $committedPercentRaw = $sample.CounterSamples[0].CookedValue
    $committedPercent = [math]::Round($committedPercentRaw, 1)
} catch {
    $committedPercentRaw = $null
    $committedPercent = $null
}

$pageFiles = @()
try {
    $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
} catch {
    $pageFiles = @()
}

$criticalEvents = @()
$criticalEventsReadable = $true
try {
    $criticalEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = @(2004, 7, 129, 153, 157); StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    $criticalEvents = @($criticalEvents | Where-Object {
        ($_.Id -eq 2004 -and $_.ProviderName -eq 'Microsoft-Windows-Resource-Exhaustion-Detector') -or
        ($_.Id -in 7, 153, 157 -and $_.ProviderName -eq 'Disk') -or
        ($_.Id -eq 129 -and $_.ProviderName -match '^(storahci|stornvme|iaStor.*|Disk)$')
    })
} catch {
    $criticalEventsReadable = $false
}

$smartFacts = @()
$smartReadable = $true
try {
    $physicalDisks = @(Get-PhysicalDisk -ErrorAction Stop)
    foreach ($physicalDisk in $physicalDisks) {
        $reliability = $null
        try { $reliability = Get-StorageReliabilityCounter -PhysicalDisk $physicalDisk -ErrorAction Stop } catch { }
        $smartFacts += [pscustomobject]@{
            Name = $physicalDisk.FriendlyName
            HealthStatus = [string]$physicalDisk.HealthStatus
            ReadErrorsUncorrected = if ($reliability) { [long]$reliability.ReadErrorsUncorrected } else { $null }
            Temperature = if ($reliability) { $reliability.Temperature } else { $null }
        }
    }
} catch {
    $smartReadable = $false
}

$redFlags = @()
$systemDisk = @($diskFacts | Where-Object { $_.DeviceId -eq 'C:' } | Select-Object -First 1)[0]
if ($systemDisk -and ($systemDisk.FreePctRaw -lt 5 -or $systemDisk.FreeSpace -lt 1GB)) {
    $redFlags += 'C 盘空间严重不足（剩余低于 5% 或 1 GB）'
}
if ($null -ne $committedPercentRaw -and $committedPercentRaw -gt 90) {
    $redFlags += ('提交内存高压（{0}%）' -f $committedPercent)
}
if (@($criticalEvents | Where-Object { $_.Id -eq 2004 }).Count -gt 0) {
    $redFlags += '检测到事件 2004（低虚拟内存）'
}
if (@($criticalEvents | Where-Object { $_.Id -in 129, 153 }).Count -ge 3) {
    $redFlags += '检测到 7 天内 3 次以上存储超时/重置事件'
}
if (@($smartFacts | Where-Object { $_.HealthStatus -ne 'Healthy' -or ($null -ne $_.ReadErrorsUncorrected -and $_.ReadErrorsUncorrected -ne 0) }).Count -gt 0) {
    $redFlags += '硬盘健康异常'
}

Write-Output '=== Only-U diagnose (offline, read-only) ==='
Write-Output ("time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Output ("computer: {0}" -f $env:COMPUTERNAME)
Write-Output ("user: {0}" -f $env:USERNAME)
if ($redFlags.Count -gt 0) {
    Write-Output ''
    Write-Output '=== 报告红灯区 ==='
    $redFlags | ForEach-Object { Write-Output ("! {0}" -f $_) }
    Write-Output '红灯项需要优先处理，详见对应小节。'
}

Write-Output ''
Write-Output '--- disk ---'
if ($diskFacts.Count -eq 0) { Write-Output '无法读取磁盘信息' }
$diskFacts | ForEach-Object {
    Write-Output ("{0}  total {1}  free {2} ({3}%)" -f $_.DeviceId, (Format-Bytes $_.Size), (Format-Bytes $_.FreeSpace), $_.FreePct)
    if ($_.DeviceId -eq 'C:' -and $_.FreePctRaw -lt 15) {
        Write-Output '  ! C: free < 15%. Preview clean with portable\clean.cmd'
    }
}

Write-Output ''
Write-Output '--- memory ---'
if ($memoryFacts) {
    Write-Output ("RAM used {0} / {1}" -f (Format-Bytes $memoryFacts.Used), (Format-Bytes $memoryFacts.Total))
    Write-Output ("Commit {0} / Commit Limit {1}" -f (Format-Bytes $memoryFacts.Commit), (Format-Bytes $memoryFacts.CommitLimit))
} else {
    Write-Output '无法读取内存信息'
}
if ($null -ne $committedPercent) {
    $commitLabel = if ($committedPercentRaw -gt 85) { '高压' } elseif ($committedPercentRaw -gt 75) { '预警' } else { '正常' }
    Write-Output ("% Committed Bytes In Use: {0}%（{1}）" -f $committedPercent, $commitLabel)
} else {
    Write-Output '无法读取 % Committed Bytes In Use'
}
if ($pageFiles.Count -eq 0) {
    Write-Output '无法读取 pagefile 使用情况'
} else {
    $pageFiles | ForEach-Object {
        Write-Output ("pagefile {0}  used {1} MB / allocated {2} MB" -f $_.Name, $_.CurrentUsage, $_.AllocatedBaseSize)
    }
}

try {
    Write-Output 'top memory processes (read-only):'
    Get-Process -ErrorAction Stop |
        Sort-Object -Property PagedMemorySize64 -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            Write-Output ("  {0}  working set {1}  commit {2}" -f $_.ProcessName, (Format-Bytes $_.WorkingSet64), (Format-Bytes $_.PagedMemorySize64))
        }
} catch {
    Write-Output '无法读取占内存进程'
}

try {
    $startupCount = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop).Count
    Write-Output ("startup entries: {0} (read-only clue)" -f $startupCount)
} catch {
    Write-Output '无法读取启动项数量'
}

Write-Output ''
Write-Output '--- reclaim candidates (not deleted) ---'
$candidates = @(
    $env:TEMP,
    $env:TMP,
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\Temp",
    "$env:WINDIR\SoftwareDistribution\Download"
) | Where-Object { $_ } | Select-Object -Unique

foreach ($dir in $candidates) {
    Write-Output ("正在扫描 {0}" -f $dir)
    $scan = Get-DirSize $dir
    switch ($scan.Status) {
        'Complete' { Write-Output ("  {0}  files={1}" -f (Format-Bytes $scan.Bytes), $scan.Files) }
        'Skipped' { Write-Output ("  跳过：太大或超时（已统计 {0} 个文件，约 {1}）" -f $scan.Files, (Format-Bytes $scan.Bytes)) }
        'Missing' { Write-Output '  无法读取（路径不存在）' }
        'Unc' { Write-Output '  跳过：UNC 路径' }
        default { Write-Output '  无法读取' }
    }
}

Write-Output ''
Write-Output '--- 关键事件（近 7 天，仅命中项） ---'
if (-not $criticalEventsReadable) {
    Write-Output '无法读取关键事件（可能需要管理员权限）'
} elseif ($criticalEvents.Count -eq 0) {
    Write-Output '未发现低虚拟内存或存储异常关键事件'
} else {
    $eventsToDisplay = @($criticalEvents | Sort-Object -Property TimeCreated -Descending | Select-Object -First 20)
    $eventsToDisplay | ForEach-Object {
        $msg = if ($_.Message) { ($_.Message -replace '\s+', ' ') } else { '' }
        if ($msg.Length -gt 280) { $msg = $msg.Substring(0, 280) }
        Write-Output ("[{0}] Event {1}  {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm'), $_.Id, $msg)
    }
    if ($criticalEvents.Count -gt $eventsToDisplay.Count) {
        Write-Output ("仅显示最新 {0} 条；共命中 {1} 条关键事件。" -f $eventsToDisplay.Count, $criticalEvents.Count)
    }
}

Write-Output ''
Write-Output '--- printers ---'
$spooler = $null
$spoolerRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
    Get-Service -Name Spooler -ErrorAction Stop
}
if ($spoolerRead.Status -eq 'Complete') {
    $spooler = @($spoolerRead.Value)[0]
    if ($spooler) {
        if ($spooler.Status -eq 'Stopped') {
            Write-Output '打印服务 Spooler: Stopped（打印服务未运行：这是软件问题，不是缺少驱动）'
        } else {
            Write-Output ('打印服务 Spooler: {0}' -f $spooler.Status)
        }
    } else {
        Write-Output '无法读取打印服务 Spooler 状态'
    }
} else {
    Write-Output '无法读取打印服务 Spooler 状态'
}

$printerStates = @()
$printerStatesRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
    Get-CimInstance Win32_Printer -ErrorAction Stop
}
if ($printerStatesRead.Status -eq 'Complete') { $printerStates = @($printerStatesRead.Value) }

$printersRead = Invoke-BoundedRead -TimeoutSeconds 4 -ScriptBlock {
    Get-Printer -ErrorAction Stop
}
if ($printersRead.Status -eq 'Complete') {
    $printers = @($printersRead.Value)
    if ($printers.Count -eq 0) { Write-Output '未发现打印机' }
    $printers | ForEach-Object {
        $printer = $_
        Write-Output ("{0}  status={1}  driver={2}" -f $printer.Name, $printer.PrinterStatus, $printer.DriverName)

        $printerState = @($printerStates | Where-Object { $_.Name -eq $printer.Name } | Select-Object -First 1)[0]
        $detectedError = if ($printerState) { Get-PrinterDetectedErrorText -DetectedErrorState $printerState.DetectedErrorState } else { $null }
        if ($detectedError) {
            Write-Output ('  检测到 {0}：这是设备/耗材证据，不是驱动证据。' -f $detectedError)
        }
        $portHint = Get-PrinterPortHint -PortName $printer.PortName -PrinterStatus $printer.PrinterStatus
        $conclusion = Get-PrinterConclusion -Printer $printer -SpoolerStatus $(if ($spooler) { $spooler.Status } else { '' }) -DetectedError $detectedError
        Write-Output ('  {0}' -f $portHint.Text)
        Write-Output ('  {0}' -f $conclusion.Text)
    }
} else {
    Write-Output '无法读取打印机'
}

Write-Output ''
Write-Output '--- PnP devices with driver issue (capped buckets) ---'
$pnpRead = Invoke-BoundedRead -TimeoutSeconds 6 -ScriptBlock {
    Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 }
}
if ($pnpRead.Status -eq 'Complete') {
    $devices = @($pnpRead.Value)
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
        $bucketDisplay = Get-PnpBucketDisplay -Findings $deviceFindings -BucketName $bucket.Name
        if ($bucketDisplay.Count -eq 0) { continue }
        Write-Output ('{0}（{1} 项，最多显示 5 项）' -f $bucket.Label, $bucketDisplay.Count)
        $bucketDisplay.Entries | ForEach-Object {
            $line = Get-PnpFindingLine -Finding $_ -HardwareIdTimeoutSeconds 2
            Write-Output ('  {0}' -f $line)
        }
    }
} else {
    Write-Output '无法读取即插即用设备状态'
}

Write-Output ''
Write-Output '--- SMART ---'
if (-not $smartReadable -or $smartFacts.Count -eq 0) {
    Write-Output 'SMART 不可读（跳过）'
} else {
    $smartFacts | ForEach-Object {
        $errors = if ($null -eq $_.ReadErrorsUncorrected) { 'n/a' } else { $_.ReadErrorsUncorrected }
        $temperature = if ($null -eq $_.Temperature) { 'n/a' } else { ("{0} C" -f $_.Temperature) }
        Write-Output ("{0}  health={1}  read-errors-uncorrected={2}  temperature={3}" -f $_.Name, $_.HealthStatus, $errors, $temperature)
    }
}

Write-Output ''
Write-Output 'Next: if online, give this report to the agent. Clean preview: portable\clean.cmd'
Write-Output 'USB Wi-Fi path: not in this hackathon.'

# --- 接下来怎么办（白话建议，纯规则映射，离线） ---
function Get-NextSteps {
    $steps = @()
    $systemDisk = @($diskFacts | Where-Object { $_.DeviceId -eq 'C:' } | Select-Object -First 1)[0]
    if ($systemDisk -and ($systemDisk.FreePctRaw -lt 5 -or $systemDisk.FreeSpace -lt 1GB)) {
        $steps += ('C 盘只剩 {0}%，亮红灯 → 双击 U 盘里的「清理预览.cmd」，先看清单再按 Y 回收空间' -f $systemDisk.FreePct)
    }
    if ($null -ne $committedPercentRaw -and $committedPercentRaw -gt 90) {
        $steps += ('内存不足（提交内存已用 {0}%）→ 关掉不用的程序；经常发生建议加内存条' -f $committedPercent)
    }
    if (@($criticalEvents | Where-Object { $_.Id -eq 2004 }).Count -gt 0) {
        $steps += '系统近期内存压力过高（事件 2004）→ 关掉不用的程序；经常发生建议加内存条'
    }
    $storageEvents = @($criticalEvents | Where-Object { $_.Id -in 129, 153 })
    if ($storageEvents.Count -ge 3) {
        $steps += ('硬盘最近 7 天响应慢 {0} 次 → 尽快备份重要文件，让维修师傅检查 SMART' -f $storageEvents.Count)
    }
    if (@($smartFacts | Where-Object { $_.HealthStatus -ne 'Healthy' -or ($null -ne $_.ReadErrorsUncorrected -and $_.ReadErrorsUncorrected -ne 0) }).Count -gt 0) {
        $steps += '硬盘健康告警 → 立即备份重要文件，考虑换盘'
    }
    $printerProblems = @()
    try {
        $printerProblems = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.PNPClass -eq 'Printer' -and $null -ne $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 })
    } catch {
        $printerProblems = @()
    }
    if (@($printerProblems | Where-Object { $_.ConfigManagerErrorCode -eq 28 }).Count -gt 0) {
        $steps += '打印机驱动缺失（CM_PROB 28）→ 到打印机厂商官网下载对应型号驱动，或去电脑维修店'
    }
    $otherPrinterProblems = @($printerProblems | Where-Object { $_.ConfigManagerErrorCode -ne 28 })
    if ($otherPrinterProblems.Count -gt 0) {
        $steps += ('打印机驱动异常（CM_PROB {0}）→ 先重装该设备驱动再看' -f $otherPrinterProblems[0].ConfigManagerErrorCode)
    }
    return $steps
}

Write-Output ''
Write-Output '=== 接下来怎么办 ==='
$nextSteps = @(Get-NextSteps)
if ($nextSteps.Count -eq 0) {
    Write-Output '系统体检通过，未见红灯。建议 30 天后再查一次。'
} else {
    $shownSteps = @($nextSteps | Select-Object -First 5)
    for ($i = 0; $i -lt $shownSteps.Count; $i++) {
        Write-Output ("{0}. {1}" -f ($i + 1), $shownSteps[$i])
    }
    if ($nextSteps.Count -gt 5) {
        Write-Output ("还有 {0} 条，详见上方红灯清单" -f ($nextSteps.Count - 5))
    }
    Write-Output ''
    Write-Output '处理不了？带 U 盘去维修店，给师傅看 reports\ 下的 diagnose-*.log。'
}

Write-Output ''
Write-Output '能清多少：见上方可回收空间；本次未删除任何文件。'
Write-Output '不碰什么：桌面 / 文档 / 下载 / 图片 / 聊天记录。'
Write-Output '说确认才删：只有你说「确认」或「执行」才会清理。'
