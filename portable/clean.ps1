# Only-U clean with delete-protection. Default is preview-only.
param(
    [switch]$Execute,
    [switch]$Interactive
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$cutoff = (Get-Date).AddDays(-7)

function Format-Bytes([long]$n) {
    if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    if ($n -ge 1KB) { return ('{0:N1} KB' -f ($n / 1KB)) }
    return ('{0:N0} B' -f $n)
}

function Convert-ToLong([object]$value) {
    if ($null -eq $value) { return [long]0 }
    return [long]$value
}

$protectedRoots = @(
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('MyPictures'),
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents",
    "$env:SystemDrive\Users\Public\Documents"
) | Where-Object { $_ } | Select-Object -Unique

function Test-Protected([string]$path) {
    $full = [System.IO.Path]::GetFullPath($path)
    foreach ($root in $protectedRoots) {
        if (-not $root) { continue }
        $r = [System.IO.Path]::GetFullPath($root)
        if ($full.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-ChildFiles {
    param(
        [string]$Path,
        [string]$Pattern = '*'
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $Pattern })
}

function Select-ByAge {
    param([object[]]$Files)
    $oldFiles = @($Files | Where-Object { $_.LastWriteTime -lt $cutoff })
    $newFiles = @($Files | Where-Object { $_.LastWriteTime -ge $cutoff })
    return @{
        OldFiles = $oldFiles
        NewFiles = $newFiles
    }
}

function Get-PlanSummary {
    param([object]$Files)
    $items = @($Files | Where-Object { $null -ne $_ })
    $bytes = Convert-ToLong (($items | Measure-Object Length -Sum).Sum)
    $count = @($items).Count
    return @{
        Count = $count
        Bytes = $bytes
    }
}

function Remove-Files {
    param([object[]]$Files)
    $result = @{
        Removed = 0
        Bytes = [long]0
        Skipped = 0
    }
    foreach ($file in $Files) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $result.Removed++
            $result.Bytes += [long]$file.Length
        } catch {
            $result.Skipped++
        }
    }
    return $result
}

function Remove-EmptyChildDirectories {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return 0 }
    $directories = @(
        Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 } |
        Sort-Object -Property FullName -Descending
    )
    $removed = 0
    foreach ($directory in $directories) {
        try {
            if (-not (Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
                $removed++
            }
        } catch {
        }
    }
    return $removed
}

$tempAllowList = @(
    $env:TEMP,
    $env:TMP,
    "$env:LOCALAPPDATA\Temp",
    "$env:WINDIR\Temp"
) | Where-Object { $_ } | Select-Object -Unique

$thumbnailDirectories = @(
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
) | Where-Object { $_ } | Select-Object -Unique

$werDirectories = @(
    "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
    "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
) | Where-Object { $_ } | Select-Object -Unique

$updateDirectories = @(
    "$env:WINDIR\SoftwareDistribution\Download"
) | Where-Object { $_ } | Select-Object -Unique

$recycleBinDirectory = "$env:SystemDrive\`$Recycle.Bin"
$logDirectory = Join-Path $PSScriptRoot 'logs'
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logPath = Join-Path $logDirectory ("clean-{0}.log" -f $timestamp)
$logLines = New-Object System.Collections.Generic.List[string]

function Add-Log {
    param([string]$Line)
    $script:logLines.Add($Line)
}

Add-Log ('=== Only-U clean {0} ===' -f (Get-Date).ToString('s'))
Add-Log ('mode: {0}' -f ($(if ($Execute) { 'EXECUTE' } else { 'PREVIEW' })))

Write-Output '=== Only-U clean ==='
if ($Execute) {
    Write-Output 'mode: EXECUTE (allow-listed cleanup categories only)'
} else {
    Write-Output 'mode: PREVIEW (no files deleted). Confirm then run with -Execute'
    Write-Output '执行后日志将写入 portable\logs\'
}
Write-Output ''

$spaceBefore = $null
if ($Execute) {
    try {
        $spaceBefore = [long](Get-PSDrive -Name C -ErrorAction Stop).Free
    } catch {
        $spaceBefore = $null
    }
}

$totalPreview = [long]0
$totalPlanned = [long]0
$totalActual = [long]0
$totalRemoved = 0
$totalSkipped = 0
$blocked = @()
$categoryResults = @()

function Show-Category {
    param(
        [string]$Kind,
        [string]$Path,
        [string]$Note,
        [object]$Plan,
        [int]$NewCount = 0,
        [bool]$AgeFilter = $false
    )

    $script:totalPreview += [long]$Plan.Bytes
    $bytesText = Format-Bytes $Plan.Bytes
    Write-Output ("[{0}] {1}" -f $Kind, $Path)
    if ($AgeFilter) {
        Write-Output ("  按 7 天门限过滤后：{0} 文件 / {1}（另有 {2} 个新文件跳过）" -f $Plan.Count, $bytesText, $NewCount)
    } else {
        Write-Output ("  files {0}, about {1}" -f $Plan.Count, $bytesText)
    }
    if ($Note) { Write-Output ("  note: {0}" -f $Note) }

    Add-Log ('[{0}] {1}' -f $Kind, $Path)
    Add-Log ('  planned files: {0}' -f $Plan.Count)
    Add-Log ('  planned bytes: {0}' -f $Plan.Bytes)
    if ($AgeFilter) {
        Add-Log ('  skipped by 7-day age gate: {0}' -f $NewCount)
    }
    if ($Note) { Add-Log ('  note: {0}' -f $Note) }
}

foreach ($dir in $tempAllowList) {
    if (Test-Protected $dir) {
        $blocked += $dir
        Write-Output ("blocked (delete-protection): {0}" -f $dir)
        Add-Log ('blocked (delete-protection): {0}' -f $dir)
        continue
    }

    $selection = Select-ByAge (Get-ChildFiles $dir)
    $summary = Get-PlanSummary $selection.OldFiles
    Show-Category 'TEMP' $dir '' $summary $selection.NewFiles.Count $true
    $totalPlanned += $summary.Bytes

    if ($Execute) {
        $result = Remove-Files $selection.OldFiles
        $removedDirectories = Remove-EmptyChildDirectories $dir
        $totalActual += $result.Bytes
        $totalRemoved += $result.Removed
        $totalSkipped += $result.Skipped
        $script:categoryResults += [pscustomobject]@{
            Kind = 'TEMP'; Path = $dir; PlannedCount = $summary.Count; PlannedBytes = $summary.Bytes
            RemovedCount = $result.Removed; ActualBytes = $result.Bytes; Skipped = $result.Skipped
        }
        Write-Output ("  removed {0}, skipped {1}" -f $result.Removed, $result.Skipped)
        Add-Log ('  removed: {0}' -f $result.Removed)
        Add-Log ('  skipped locked: {0}' -f $result.Skipped)
        Add-Log ('  removed empty directories: {0}' -f $removedDirectories)
        Add-Log ('  actual bytes: {0}' -f $result.Bytes)
    }
}

foreach ($dir in $thumbnailDirectories) {
    if (Test-Protected $dir) { $blocked += $dir; continue }
    $files = Get-ChildFiles $dir 'thumbcache_*.db'
    $summary = Get-PlanSummary $files
    Show-Category 'THUMBNAIL CACHE' $dir 'thumbcache_*.db; Windows will rebuild it' $summary
    $totalPlanned += $summary.Bytes
    if ($Execute) {
        $result = Remove-Files $files
        $removedDirectories = Remove-EmptyChildDirectories $dir
        $totalActual += $result.Bytes; $totalRemoved += $result.Removed; $totalSkipped += $result.Skipped
        $script:categoryResults += [pscustomobject]@{
            Kind = 'THUMBNAIL CACHE'; Path = $dir; PlannedCount = $summary.Count; PlannedBytes = $summary.Bytes
            RemovedCount = $result.Removed; ActualBytes = $result.Bytes; Skipped = $result.Skipped
        }
        Write-Output ("  removed {0}, skipped {1}" -f $result.Removed, $result.Skipped)
        Add-Log ('  removed: {0}' -f $result.Removed)
        Add-Log ('  skipped locked: {0}' -f $result.Skipped)
        Add-Log ('  removed empty directories: {0}' -f $removedDirectories)
        Add-Log ('  actual bytes: {0}' -f $result.Bytes)
    }
}

foreach ($dir in $werDirectories) {
    if (Test-Protected $dir) { $blocked += $dir; continue }
    $files = Get-ChildFiles $dir
    $summary = Get-PlanSummary $files
    Show-Category 'WER REPORTS' $dir 'contents only; report directory itself is preserved' $summary
    $totalPlanned += $summary.Bytes
    if ($Execute) {
        $result = Remove-Files $files
        $removedDirectories = Remove-EmptyChildDirectories $dir
        $totalActual += $result.Bytes; $totalRemoved += $result.Removed; $totalSkipped += $result.Skipped
        $script:categoryResults += [pscustomobject]@{
            Kind = 'WER REPORTS'; Path = $dir; PlannedCount = $summary.Count; PlannedBytes = $summary.Bytes
            RemovedCount = $result.Removed; ActualBytes = $result.Bytes; Skipped = $result.Skipped
        }
        Write-Output ("  removed {0}, skipped {1}" -f $result.Removed, $result.Skipped)
        Add-Log ('  removed: {0}' -f $result.Removed)
        Add-Log ('  skipped locked: {0}' -f $result.Skipped)
        Add-Log ('  removed empty directories: {0}' -f $removedDirectories)
        Add-Log ('  actual bytes: {0}' -f $result.Bytes)
    }
}

foreach ($dir in $updateDirectories) {
    if (Test-Protected $dir) { $blocked += $dir; continue }
    $files = Get-ChildFiles $dir
    $summary = Get-PlanSummary $files
    Show-Category 'WINDOWS UPDATE CACHE' $dir '清空后已下载更新需重下' $summary
    $totalPlanned += $summary.Bytes
    if ($Execute) {
        $result = Remove-Files $files
        $removedDirectories = Remove-EmptyChildDirectories $dir
        $totalActual += $result.Bytes; $totalRemoved += $result.Removed; $totalSkipped += $result.Skipped
        $script:categoryResults += [pscustomobject]@{
            Kind = 'WINDOWS UPDATE CACHE'; Path = $dir; PlannedCount = $summary.Count; PlannedBytes = $summary.Bytes
            RemovedCount = $result.Removed; ActualBytes = $result.Bytes; Skipped = $result.Skipped
        }
        Write-Output ("  removed {0}, skipped {1}" -f $result.Removed, $result.Skipped)
        Add-Log ('  removed: {0}' -f $result.Removed)
        Add-Log ('  skipped locked: {0}' -f $result.Skipped)
        Add-Log ('  removed empty directories: {0}' -f $removedDirectories)
        Add-Log ('  actual bytes: {0}' -f $result.Bytes)
    }
}

if (Test-Protected $recycleBinDirectory) {
    $blocked += $recycleBinDirectory
} else {
    $files = Get-ChildFiles $recycleBinDirectory
    $summary = Get-PlanSummary $files
    Show-Category 'RECYCLE BIN' "$env:SystemDrive Recycle Bin" 'emptied only with -Execute' $summary
    $totalPlanned += $summary.Bytes
    if ($Execute) {
        $beforeBytes = $summary.Bytes
        $skipped = 0
        try {
            Clear-RecycleBin -DriveLetter $env:SystemDrive -Force -ErrorAction Stop
        } catch {
            $skipped = 1
        }
        $afterFiles = Get-ChildFiles $recycleBinDirectory
        $afterSummary = Get-PlanSummary $afterFiles
        $actualBytes = [long]$beforeBytes - [long]$afterSummary.Bytes
        if ($actualBytes -lt 0) { $actualBytes = [long]0 }
        if ($afterSummary.Count -gt 0) { $skipped = $afterSummary.Count }
        $actualRemoved = $summary.Count - $afterSummary.Count
        if ($actualRemoved -lt 0) { $actualRemoved = 0 }
        $totalActual += $actualBytes
        $totalRemoved += $actualRemoved
        $totalSkipped += $skipped
        $script:categoryResults += [pscustomobject]@{
            Kind = 'RECYCLE BIN'; Path = "$env:SystemDrive Recycle Bin"; PlannedCount = $summary.Count; PlannedBytes = $summary.Bytes
            RemovedCount = $actualRemoved; ActualBytes = $actualBytes; Skipped = $skipped
        }
        Write-Output ("  removed {0} files, skipped {1}" -f $actualRemoved, $skipped)
        Add-Log ('  removed: {0}' -f $actualRemoved)
        Add-Log ('  skipped locked: {0}' -f $skipped)
        Add-Log ('  actual bytes: {0}' -f $actualBytes)
    }
}

if ($Execute) {
    $deviation = [double]0
    if ($totalPlanned -gt 0) { $deviation = [Math]::Abs($totalPlanned - $totalActual) / [double]$totalPlanned }
    Add-Log ('total planned bytes: {0}' -f $totalPlanned)
    Add-Log ('total actual bytes: {0}' -f $totalActual)
    Add-Log ('total removed files: {0}' -f $totalRemoved)
    Add-Log ('total skipped files: {0}' -f $totalSkipped)
    Add-Log ('plan/actual deviation: {0:P1}' -f $deviation)
    if ($deviation -gt 0.10) {
        Add-Log ('WARNING: actual freed bytes differ from plan by more than 10%')
    }
}

Write-Output ''
Write-Output ("preview total about {0} (allow-listed categories; user docs skipped)" -f (Format-Bytes $totalPreview))
if ($Execute) {
    Write-Output ("planned {0}; actually freed about {1}; removed {2}; skipped {3}" -f (Format-Bytes $totalPlanned), (Format-Bytes $totalActual), $totalRemoved, $totalSkipped)
    Write-Output ("log: {0}" -f $logPath)
}
if ($blocked.Count -gt 0) {
    Write-Output 'blocked by delete-protection:'
    $blocked | ForEach-Object { Write-Output ("  {0}" -f $_) }
    $blocked | ForEach-Object { Add-Log ('blocked by delete-protection: {0}' -f $_) }
}

if ($Execute -and $null -ne $spaceBefore) {
    try {
        $driveC = Get-PSDrive -Name C -ErrorAction Stop
        $spaceAfter = [long]$driveC.Free
    } catch {
        $spaceAfter = $null
    }
    if ($null -ne $spaceAfter) {
        $totalCapacity = [double]($driveC.Free + $driveC.Used)
        $percentBefore = 0
        if ($totalCapacity -gt 0) { $percentBefore = [int][Math]::Round(100.0 * $spaceBefore / $totalCapacity) }
        $percentAfter = 0
        if ($totalCapacity -gt 0) { $percentAfter = [int][Math]::Round(100.0 * $spaceAfter / $totalCapacity) }
        $deltaBytes = $spaceAfter - $spaceBefore
        $deltaSign = if ($deltaBytes -ge 0) { '+' } else { '-' }
        Write-Output ''
        Write-Output '== 空间回收 =='
        Write-Output ('执行前：C: 剩余 {0} ({1}%)' -f (Format-Bytes $spaceBefore), $percentBefore)
        Write-Output ('执行后：C: 剩余 {0} ({1}%)' -f (Format-Bytes $spaceAfter), $percentAfter)
        Write-Output ('本次释放：约 {0}{1}' -f $deltaSign, (Format-Bytes ([Math]::Abs($deltaBytes))))
        Add-Log '== 空间回收 =='
        Add-Log ('执行前：C: 剩余 {0} ({1}%)' -f (Format-Bytes $spaceBefore), $percentBefore)
        Add-Log ('执行后：C: 剩余 {0} ({1}%)' -f (Format-Bytes $spaceAfter), $percentAfter)
        Add-Log ('本次释放：约 {0}{1}' -f $deltaSign, (Format-Bytes ([Math]::Abs($deltaBytes))))
    }
}

if ($Execute) {
    if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($logPath, $logLines, $utf8NoBom)
}

if (-not $Execute -and -not $Interactive) {
    Write-Output ''
    Write-Output 'To delete: portable\clean.cmd -Execute'
    Write-Output 'Never cleans Desktop / Documents / Downloads / Pictures.'
}

if ($Interactive -and -not $Execute) {
    Write-Output ''
    Write-Output ("将清理约 {0}（白名单类别；用户文档已跳过）" -f (Format-Bytes $totalPreview))
    while ($true) {
        Write-Output '按 Y 立即执行 / N 取消 / R 重看清单'
        $answer = Read-Host '> '
        if ($null -eq $answer) {
            Write-Output '输入已结束，按取消处理。'
            break
        }
        if ($answer -match '^[Yy]$') {
            & $PSCommandPath -Execute
            break
        }
        if ($answer -match '^[Nn]$') {
            Write-Output '已取消，未删除任何文件。'
            break
        }
        if ($answer -match '^[Rr]$') {
            & $PSCommandPath -Interactive
            break
        }
        Write-Output '无效输入，请输入 Y / N / R。'
    }
}
