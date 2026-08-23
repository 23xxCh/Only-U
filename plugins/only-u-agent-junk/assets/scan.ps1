# Only-U agent-junk scan: read-only footprint report from knowledge JSON.
param()

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$knowledgePath = Join-Path $PSScriptRoot '..\knowledge\agent-footprints.json'
$knowledge = Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8 | ConvertFrom-Json

function Format-Bytes([long]$n) {
    if ($n -ge 1GB) { return ('{0:N2} GB' -f ($n / 1GB)) }
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    if ($n -ge 1KB) { return ('{0:N1} KB' -f ($n / 1KB)) }
    return ('{0:N0} B' -f $n)
}

function Expand-EnvPath([string]$p) {
    $r = $p
    if ($env:USERPROFILE) { $r = $r.Replace('%USERPROFILE%', $env:USERPROFILE) }
    if ($env:LOCALAPPDATA) { $r = $r.Replace('%LOCALAPPDATA%', $env:LOCALAPPDATA) }
    if ($env:APPDATA) { $r = $r.Replace('%APPDATA%', $env:APPDATA) }
    if ($env:TEMP) { $r = $r.Replace('%TEMP%', $env:TEMP) }
    return $r
}

# 目录大小：手压栈遍历，跳过 ReparsePoint（防止跟随 junction 造成循环/重复计数）
function Get-PathSize([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    } catch {
        return @{ Bytes = [long]0; Count = 0; Type = 'missing' }
    }
    if (-not ($item.PSIsContainer)) {
        return @{ Bytes = [long]$item.Length; Count = 1; Type = 'file' }
    }
    $total = [long]0
    $count = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push($item)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { $children = $dir.EnumerateFileSystemInfos() } catch { continue }
        foreach ($child in $children) {
            try {
                if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if (($child.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $stack.Push($child)
                } else {
                    $total += [long]$child.Length
                    $count++
                }
            } catch { }
        }
    }
    return @{ Bytes = $total; Count = $count; Type = 'dir' }
}

$reportEntries = @()
$greenBytes = [long]0
$yellowBytes = [long]0
$redBytes = [long]0
$foundCount = 0
$missingCount = 0

foreach ($entry in $knowledge) {
    $pathRows = @()
    $entryBytes = [long]0
    $entryFound = $false

    foreach ($rawPath in $entry.paths) {
        $expanded = Expand-EnvPath $rawPath
        $targets = @()
        if ($expanded.Contains('*')) {
            # 通配路径（如 codex-runtime-install-*）：展开为逐个实例
            try { $targets = @(Get-Item -Path $expanded -Force -ErrorAction SilentlyContinue) } catch { $targets = @() }
        } else {
            $targets = @(,$expanded)
        }
        foreach ($t in $targets) {
            if ($null -eq $t) { continue }
            $tPath = if ($t -is [string]) { $t } else { $t.FullName }
            if ([string]::IsNullOrEmpty($tPath)) { continue }
            $size = Get-PathSize $tPath
            $exists = ($size.Type -ne 'missing')
            if ($exists) { $entryFound = $true }
            $entryBytes += $size.Bytes
            $pathRows += [pscustomobject]@{
                path = $tPath
                exists = $exists
                type = $size.Type
                sizeBytes = $size.Bytes
                sizeText = Format-Bytes $size.Bytes
            }
        }
    }

    if ($entryFound) { $foundCount++ } else { $missingCount++ }
    switch ($entry.tier) {
        'green' { $greenBytes += $entryBytes }
        'yellow' { $yellowBytes += $entryBytes }
        'red' { $redBytes += $entryBytes }
    }

    $reportEntries += [pscustomobject]@{
        id = $entry.id
        name = $entry.name
        tier = $entry.tier
        action = $entry.action
        bloatSource = $entry.bloatSource
        found = $entryFound
        totalBytes = $entryBytes
        totalText = Format-Bytes $entryBytes
        paths = $pathRows
        notes = $entry.notes
    }
}

$report = [pscustomobject]@{
    scannedAt = (Get-Date).ToString('s')
    mode = 'read-only-scan'
    summary = [pscustomobject]@{
        footprintsTotal = @($knowledge).Count
        found = $foundCount
        notFound = $missingCount
        greenBytes = $greenBytes
        greenText = Format-Bytes $greenBytes
        yellowBytes = $yellowBytes
        yellowText = Format-Bytes $yellowBytes
        redBytes = $redBytes
        redText = Format-Bytes $redBytes
        hint = 'green=可安全清理（ops_agent_junk_clean）；yellow=可重建索引/过期缓存（逐类确认）；red=会话/配置/登录态（只可 ops_agent_migrate 迁移，永不清理）'
    }
    entries = $reportEntries
}

Write-Output ($report | ConvertTo-Json -Depth 6 -Compress)
