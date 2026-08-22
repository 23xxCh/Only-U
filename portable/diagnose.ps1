# Only-U offline diagnose. No LLM. Read-only.
param(
    [switch]$NoRun
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

function Get-PnpHardwareIdSummary($Device) {
    if ([string]::IsNullOrWhiteSpace($Device.PNPDeviceID)) { return $null }
    try {
        $property = Get-PnpDeviceProperty -InstanceId $Device.PNPDeviceID -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop
        return Get-HardwareIdSummary -HardwareIds @($property.Data)
    } catch {
        return $null
    }
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

function Get-PrinterPortHint([string]$PortName) {
    if ([string]::IsNullOrWhiteSpace($PortName)) { return '端口信息不可读，需结合连接状态判断。' }
    if ($PortName -match '(?i)^WSD') { return 'WSD 端口脱机时，网络或 WSD 协议可能有问题。' }
    if ($PortName -match '(?i)(TCP|IP_)') { return 'TCP/IP 端口可用 ping 验证连通性。' }
    if ($PortName -match '(?i)^USB') { return 'USB 端口请检查即插即用设备状态。' }
    return ('端口 {0}，需结合连接状态判断。' -f $PortName)
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
        if ($null -eq (Wait-Job -Job $job -Timeout $scanTimeoutSeconds)) {
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
try {
    $spooler = Get-Service -Name Spooler -ErrorAction Stop
    if ($spooler.Status -eq 'Stopped') {
        Write-Output '打印服务 Spooler: Stopped（打印服务未运行：这是软件问题，不是缺少驱动）'
    } else {
        Write-Output ('打印服务 Spooler: {0}' -f $spooler.Status)
    }
} catch {
    Write-Output '无法读取打印服务 Spooler 状态'
}

$printerStates = @()
try {
    $printerStates = @(Get-CimInstance Win32_Printer -ErrorAction Stop)
} catch {
    $printerStates = @()
}
try {
    $printers = @(Get-Printer -ErrorAction Stop)
    if ($printers.Count -eq 0) { Write-Output '未发现打印机' }
    $printers | ForEach-Object {
        $printer = $_
        Write-Output ("{0}  status={1}  driver={2}" -f $printer.Name, $printer.PrinterStatus, $printer.DriverName)

        $printerState = @($printerStates | Where-Object { $_.Name -eq $printer.Name } | Select-Object -First 1)[0]
        $detectedError = if ($printerState) { Get-PrinterDetectedErrorText -DetectedErrorState $printerState.DetectedErrorState } else { $null }
        if ($detectedError) {
            Write-Output ('  检测到 {0}：这是设备/耗材证据，不是驱动证据。' -f $detectedError)
        }
        Write-Output ('  {0}' -f (Get-PrinterPortHint -PortName $printer.PortName))
        if ($spooler -and $spooler.Status -eq 'Stopped') {
            Write-Output '  结论：打印服务未运行（软件问题，不是缺少驱动）。'
        } elseif ($detectedError) {
            Write-Output ('  结论：{0} 属于设备/耗材证据，不是驱动证据；请同时检查连接。' -f $detectedError)
        } elseif (-not [string]::IsNullOrWhiteSpace($printer.DriverName)) {
            Write-Output '  结论：驱动已装（仅凭驱动名，仍需结合连接状态确认）。'
        } else {
            Write-Output '  结论：未见驱动名，需结合即插即用设备状态确认驱动情况。'
        }
    }
} catch {
    Write-Output '无法读取打印机'
}

Write-Output ''
Write-Output '--- PnP devices with driver issue (capped buckets) ---'
try {
    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 })
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
        $bucketFindings = @($deviceFindings | Where-Object { $_.Detail.Bucket -eq $bucket.Name })
        if ($bucketFindings.Count -eq 0) { continue }
        Write-Output ('{0}（{1} 项，最多显示 5 项）' -f $bucket.Label, $bucketFindings.Count)
        $bucketFindings | Select-Object -First 5 | ForEach-Object {
            $line = Format-PnpDeviceLine -Device $_.Device -Detail $_.Detail
            if ($bucket.Name -eq 'missing-driver') {
                $hardwareId = Get-PnpHardwareIdSummary -Device $_.Device
                if ($hardwareId) { $line += ('  硬件ID={0}' -f $hardwareId) }
            }
            Write-Output ('  {0}' -f $line)
        }
    }
} catch {
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
