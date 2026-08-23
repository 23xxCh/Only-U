# Only-U agent-junk migrate: junction relocation wizard for one knowledge entry.
# robocopy /E /COPY:DAT -> SHA256 verify sampled files -> mklink /J -> verify link readable
# -> only then remove the original directory. Default is preview-only.
param(
    [Parameter(Mandatory = $true)][string]$TargetId,
    [Parameter(Mandatory = $true)][string]$DestRoot,
    [switch]$Execute
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

function Get-DirStats([string]$path) {
    $total = [long]0
    $count = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $path -Force))
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
    return @{ Bytes = $total; Count = $count }
}

# SHA256 全量哈希（.NET 直算，不依赖 Get-FileHash；失败返回 $null，调用方按 fail-closed 处理）
function Get-FileSha256([string]$path) {
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($path)
        try { $bytes = $sha.ComputeHash($stream) } finally { $stream.Dispose(); $sha.Dispose() }
        return ([BitConverter]::ToString($bytes)).Replace('-', '')
    } catch { return $null }
}

$knowledgePath = Join-Path $PSScriptRoot '..\knowledge\agent-footprints.json'
$knowledge = Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8 | ConvertFrom-Json
$entry = $knowledge | Where-Object { $_.id -eq $TargetId }
if (-not $entry) {
    Write-Output ("source not found: unknown targetId '{0}'" -f $TargetId)
    exit 1
}
if ($entry.action -ne 'migrate') {
    Write-Output ("refused: entry '{0}' advises action '{1}', not migrate. notes: {2}" -f $entry.id, $entry.action, $entry.notes)
    exit 1
}

# 候选源目录：非通配、存在、且是容器；取最大的一个作为迁移对象
$candidates = @()
foreach ($rawPath in $entry.paths) {
    $expanded = Expand-EnvPath $rawPath
    if ($expanded.Contains('*')) { continue }
    if (Test-Path -LiteralPath $expanded -PathType Container) {
        $candidates += $expanded
    }
}
if ($candidates.Count -eq 0) {
    Write-Output ("source not found: no existing directory for '{0}' ({1})" -f $entry.id, $entry.name)
    exit 1
}

$source = $null
$sourceBytes = [long]0
foreach ($c in $candidates) {
    $stats = Get-DirStats $c
    if ($stats.Bytes -ge $sourceBytes) {
        $sourceBytes = $stats.Bytes
        $source = $c
        $script:sourceFileCount = $stats.Count
    }
}
$fileCount = $script:sourceFileCount

$sourceItem = Get-Item -LiteralPath $source -Force
if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    Write-Output ("refused: '{0}' is already a junction/reparse point (migrated?)" -f $source)
    exit 1
}

$destRootFull = [System.IO.Path]::GetFullPath($DestRoot)
$dest = Join-Path $destRootFull (Split-Path -Leaf $source)

$sourceDrive = ($source -replace '^([A-Za-z]:).*$', '$1')
$destDrive = ($destRootFull -replace '^([A-Za-z]:).*$', '$1')

Write-Output '=== Only-U agent-junk migrate ==='
Write-Output ("entry: {0} ({1}) tier={2}" -f $entry.id, $entry.name, $entry.tier)
Write-Output ("source: {0}" -f $source)
Write-Output ("dest: {0}" -f $dest)
Write-Output ("size: {0} ({1} files)" -f (Format-Bytes $sourceBytes), $fileCount)
Write-Output 'plan: robocopy /E /COPY:DAT -> SHA256 verify up to 3 files -> mklink /J -> verify link readable -> remove original'

$refusals = @()
if ($sourceDrive -ieq $destDrive) {
    $refusals += ('dest is on the same drive as source ({0}) - no space gain' -f $sourceDrive)
}
if (Test-Path -LiteralPath $dest) {
    $refusals += ('dest already exists: {0} (refusing to merge/overwrite)' -f $dest)
}
try {
    $destDriveFree = (Get-PSDrive -Name $destDrive.Substring(0, 1) -ErrorAction Stop).Free
    if ($sourceBytes -gt 0 -and $destDriveFree -lt ($sourceBytes * 1.05)) {
        $refusals += ('dest drive free space {0} < required ~{1}' -f (Format-Bytes $destDriveFree), (Format-Bytes ([long]($sourceBytes * 1.05))))
    }
} catch { }

if (-not $Execute) {
    Write-Output 'mode: PREVIEW (nothing copied, nothing linked, nothing deleted)'
    foreach ($r in $refusals) { Write-Output ("warning: {0}" -f $r) }
    exit 0
}

if ($refusals.Count -gt 0) {
    Write-Output 'refused:'
    foreach ($r in $refusals) { Write-Output ("  {0}" -f $r) }
    exit 1
}

if (-not (Test-Path -LiteralPath $destRootFull)) {
    New-Item -ItemType Directory -Path $destRootFull -Force | Out-Null
}

# ── 1. robocopy 复制（/COPY:DAT 数据+属性+时间戳；退出码 >=8 为失败）──
Write-Output 'step 1: robocopy copy...'
$null = robocopy $source $dest /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NP
$rc = $LASTEXITCODE
if ($rc -ge 8) {
    Write-Output ("ABORTED: robocopy failed (exit {0}); source untouched" -f $rc)
    exit 1
}
Write-Output ("  robocopy exit {0} (0-7 = ok)" -f $rc)

# ── 2. 逐字节抽验（取最大 3 个文件做 SHA256 全量比对；哈希留待步骤 5 验链接用）──
Write-Output 'step 2: verify sampled files (SHA256, full content)...'
$samples = @(Get-ChildItem -LiteralPath $source -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 } |
    Sort-Object Length -Descending | Select-Object -First 3)
if ($samples.Count -eq 0) {
    Write-Output 'ABORTED: no files found in source to verify'
    exit 1
}
$sampleHashes = @{}
foreach ($s in $samples) {
    $rel = $s.FullName.Substring($source.Length).TrimStart('\')
    $destFile = Join-Path $dest $rel
    if (-not (Test-Path -LiteralPath $destFile)) {
        Write-Output ("ABORTED: sample missing at dest: {0}; source untouched" -f $rel)
        exit 1
    }
    $h1 = Get-FileSha256 $s.FullName
    $h2 = Get-FileSha256 $destFile
    if (-not $h1 -or -not $h2 -or ($h1 -ne $h2)) {
        Write-Output ("ABORTED: hash mismatch or hash failure for {0}; source untouched" -f $rel)
        exit 1
    }
    $sampleHashes[$rel] = $h1
    Write-Output ("  verified: {0} ({1})" -f $rel, (Format-Bytes $s.Length))
}

# ── 3. 改名原目录（比直接删安全：链接失败可原样改回）──
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$backup = "{0}.migrating-{1}" -f $source, $timestamp
Write-Output 'step 3: rename original aside...'
try {
    Rename-Item -LiteralPath $source -NewName (Split-Path -Leaf $backup) -ErrorAction Stop
} catch {
    Write-Output ("ABORTED: cannot rename source ({0}); nothing changed" -f $_.Exception.Message)
    exit 1
}

# ── 4. 建联接（cmd /c mklink /J，无需管理员）──
Write-Output 'step 4: create junction...'
$mkOutput = cmd /c mklink /J "$source" "$dest" 2>&1
$mkRc = $LASTEXITCODE
if ($mkRc -ne 0 -or -not (Test-Path -LiteralPath $source)) {
    Write-Output ("  mklink failed (exit {0}): {1}" -f $mkRc, $mkOutput)
    Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $source)
    Write-Output 'ABORTED: junction creation failed; original restored, nothing lost'
    exit 1
}
Write-Output ("  junction: {0} -> {1}" -f $source, $dest)

# ── 5. 验证链接可读（通过链接路径读回抽验文件，比对步骤 2 存下的原始哈希）──
Write-Output 'step 5: verify link readable...'
$linkOk = $true
$linkCheck = $null
foreach ($rel in $sampleHashes.Keys) {
    $viaLink = Join-Path $source $rel
    if (-not (Test-Path -LiteralPath $viaLink)) { $linkOk = $false; $linkCheck = $rel; break }
    $h = Get-FileSha256 $viaLink
    if (-not $h -or ($h -ne $sampleHashes[$rel])) { $linkOk = $false; $linkCheck = $rel; break }
}
if (-not $linkOk) {
    Write-Output ("  link verification failed at: {0}" -f $linkCheck)
    [System.IO.Directory]::Delete($source, $false)
    Rename-Item -LiteralPath $backup -NewName (Split-Path -Leaf $source)
    Write-Output 'ABORTED: link not readable; junction removed, original restored, nothing lost'
    exit 1
}
Write-Output '  link verified: sampled files readable through junction'

# ── 6. 删除原实体目录（链接已验证工作后才执行）──
Write-Output 'step 6: remove original directory (link verified working)...'
try {
    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
} catch {
    Write-Output ("  WARNING: original backup dir could not be fully removed: {0} ({1})" -f $backup, $_.Exception.Message)
    Write-Output '  (junction works; clean the leftover manually if needed)'
}

Write-Output 'MIGRATED.'
Write-Output ("result: {0} -> junction -> {1} ({2}, {3} files)" -f $source, $dest, (Format-Bytes $sourceBytes), $fileCount)
exit 0
