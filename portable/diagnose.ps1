# Only-U offline diagnose. No LLM. Read-only.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Format-Bytes([long]$n) {
    if ($n -lt 0) { return 'n/a' }
    if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N0} B' -f $n)
}

function Get-DirSize([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $sum = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $sum) { $sum = 0 }
        return [long]$sum
    } catch {
        return $null
    }
}

Write-Output '=== Only-U diagnose (offline, read-only) ==='
Write-Output ("time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Output ("computer: {0}" -f $env:COMPUTERNAME)
Write-Output ("user: {0}" -f $env:USERNAME)
Write-Output ''

Write-Output '--- disk ---'
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $freePct = if ($_.Size -gt 0) { [math]::Round(100 * $_.FreeSpace / $_.Size, 1) } else { 0 }
        Write-Output ("{0}  total {1}  free {2} ({3}%)" -f $_.DeviceID, (Format-Bytes $_.Size), (Format-Bytes $_.FreeSpace), $freePct)
        if ($_.DeviceID -eq 'C:' -and $freePct -lt 15) {
            Write-Output '  ! C: free < 15%. Preview clean with portable\clean.cmd'
        }
    }

Write-Output ''
Write-Output '--- memory ---'
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) {
    $used = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB
    $total = $os.TotalVisibleMemorySize * 1KB
    Write-Output ("RAM used {0} / {1}" -f (Format-Bytes $used), (Format-Bytes $total))
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
    $size = Get-DirSize $dir
    $label = if ($null -eq $size) { 'unreadable' } else { Format-Bytes $size }
    $exists = Test-Path -LiteralPath $dir
    Write-Output ("{0}" -f $dir)
    Write-Output ("  {0}  exists={1}" -f $label, $exists)
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
    Write-Output '(cannot read System log; may need elevation)'
}

Write-Output ''
Write-Output '--- printers ---'
try {
    Get-Printer -ErrorAction Stop | ForEach-Object {
        Write-Output ("{0}  status={1}  driver={2}" -f $_.Name, $_.PrinterStatus, $_.DriverName)
    }
} catch {
    Write-Output '(Get-Printer unavailable)'
}

Write-Output ''
Write-Output 'Next: if online, give this report to the agent. Clean preview: portable\clean.cmd'
Write-Output 'USB Wi-Fi path: not in this hackathon.'