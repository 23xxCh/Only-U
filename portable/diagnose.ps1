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

Write-Output '=== Only-U diagnose (offline, read-only) ==='
Write-Output ("time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Output ("computer: {0}" -f $env:COMPUTERNAME)
Write-Output ("user: {0}" -f $env:USERNAME)
Write-Output ''

Write-Output '--- disk ---'
try {
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
    if ($disks.Count -eq 0) { Write-Output '无法读取磁盘信息' }
    $disks | ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } else { 0 }
        Write-Output ("{0}  total {1}  free {2} ({3}%)" -f $_.DeviceID, (Format-Bytes $_.Size), (Format-Bytes $_.FreeSpace), $freePct)
        if ($_.DeviceID -eq 'C:' -and $freePct -lt 15) {
            Write-Output '  ! C: free < 15%. Preview clean with portable\clean.cmd'
        }
    }
} catch {
    Write-Output '无法读取磁盘信息'
}

Write-Output ''
Write-Output '--- memory ---'
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) {
    $used = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB
    $total = $os.TotalVisibleMemorySize * 1KB
    Write-Output ("RAM used {0} / {1}" -f (Format-Bytes $used), (Format-Bytes $total))
} else {
    Write-Output '无法读取内存信息'
}

try {
    Write-Output 'top memory processes (read-only):'
    Get-Process -ErrorAction Stop |
        Sort-Object -Property WorkingSet64 -Descending |
        Select-Object -First 5 |
        ForEach-Object {
            Write-Output ("  {0}  {1}" -f $_.ProcessName, (Format-Bytes $_.WorkingSet64))
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
Write-Output '--- recent System errors (max 8) ---'
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2; StartTime = (Get-Date).AddDays(-3) } -MaxEvents 8 -ErrorAction Stop |
        ForEach-Object {
            $msg = if ($_.Message) { ($_.Message -replace '\s+', ' ') } else { '' }
            if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
            Write-Output ("[{0}] {1}  {2}" -f $_.TimeCreated.ToString('MM-dd HH:mm'), $_.ProviderName, $msg)
        }
} catch {
    Write-Output '无法读取 System 事件日志（可能需要管理员权限）'
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
Write-Output 'Next: if online, give this report to the agent. Clean preview: portable\clean.cmd'
Write-Output 'USB Wi-Fi path: not in this hackathon.'
