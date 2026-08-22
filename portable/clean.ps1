# Only-U clean with delete-protection. Default is preview-only.
param(
    [switch]$Execute
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Format-Bytes([long]$n) {
    if ($n -ge 1GB) { return ('{0:N1} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N0} B' -f $n)
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

$allowList = @(
    $env:TEMP,
    $env:TMP,
    "$env:LOCALAPPDATA\Temp",
    "$env:WINDIR\Temp"
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

Write-Output '=== Only-U clean ==='
if ($Execute) {
    Write-Output 'mode: EXECUTE (allow-listed temp dirs only)'
} else {
    Write-Output 'mode: PREVIEW (no files deleted). Confirm then run with -Execute'
}
Write-Output ''

$totalPreview = [long]0
$blocked = @()

foreach ($dir in $allowList) {
    if (Test-Protected $dir) {
        $blocked += $dir
        Write-Output ("blocked (delete-protection): {0}" -f $dir)
        continue
    }
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-Output ("missing: {0}" -f $dir)
        continue
    }

    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File -ErrorAction SilentlyContinue)
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    $totalPreview += [long]$bytes
    Write-Output ("{0}" -f $dir)
    Write-Output ("  files {0}, about {1}" -f $files.Count, (Format-Bytes $bytes))

    if ($Execute) {
        $removed = 0
        foreach ($f in $files) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $removed++
            } catch {
            }
        }
        Write-Output ("  removed {0} (skipped locked files)" -f $removed)
    }
}

Write-Output ''
Write-Output ("preview total about {0} (temp allow-list only; user docs skipped)" -f (Format-Bytes $totalPreview))
if ($blocked.Count -gt 0) {
    Write-Output 'blocked by delete-protection:'
    $blocked | ForEach-Object { Write-Output ("  {0}" -f $_) }
}

if (-not $Execute) {
    Write-Output ''
    Write-Output 'To delete: portable\clean.cmd -Execute'
    Write-Output 'Never cleans Desktop / Documents / Downloads / Pictures.'
}