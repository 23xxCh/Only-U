# Only-U offline diagnose. No LLM. Read-only.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

$diskFacts = @()
try {
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
    $disks | ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } else { 0 }
        $diskFacts += [pscustomobject]@{ DeviceId = $_.DeviceID; Size = [long]$_.Size; FreeSpace = [long]$_.FreeSpace; FreePct = $freePct }
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

$committedPercent = $null
try {
    $sample = Get-Counter '\Memory\% Committed Bytes In Use' -ErrorAction Stop
    $committedPercent = [math]::Round($sample.CounterSamples[0].CookedValue, 1)
} catch {
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
if ($systemDisk -and ($systemDisk.FreePct -lt 5 -or $systemDisk.FreeSpace -lt 1GB)) {
    $redFlags += 'C 盘空间严重不足（剩余低于 5% 或 1 GB）'
}
if ($null -ne $committedPercent -and $committedPercent -gt 90) {
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
    if ($_.DeviceId -eq 'C:' -and $_.FreePct -lt 15) {
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
    $commitLabel = if ($committedPercent -gt 85) { '高压' } elseif ($committedPercent -gt 75) { '预警' } else { '正常' }
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
        Sort-Object -Property WorkingSet64 -Descending |
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
    $criticalEvents | Sort-Object -Property TimeCreated -Descending | ForEach-Object {
        $msg = if ($_.Message) { ($_.Message -replace '\s+', ' ') } else { '' }
        if ($msg.Length -gt 280) { $msg = $msg.Substring(0, 280) }
        Write-Output ("[{0}] Event {1}  {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm'), $_.Id, $msg)
    }
}

Write-Output ''
Write-Output '--- printers ---'
try {
    $printers = @(Get-Printer -ErrorAction Stop)
    if ($printers.Count -eq 0) { Write-Output '未发现打印机' }
    $printers | ForEach-Object {
        Write-Output ("{0}  status={1}  driver={2}" -f $_.Name, $_.PrinterStatus, $_.DriverName)
    }
} catch {
    Write-Output '无法读取打印机'
}

Write-Output ''
Write-Output '--- PnP devices with driver issue (max 8) ---'
try {
    $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object -First 8)
    if ($devices.Count -eq 0) { Write-Output '未发现驱动状态异常的即插即用设备' }
    $devices | ForEach-Object {
        Write-Output ("{0}  class={1}  error-code={2}" -f $_.Name, $_.PNPClass, $_.ConfigManagerErrorCode)
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
