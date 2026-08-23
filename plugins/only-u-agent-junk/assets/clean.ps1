# Only-U agent-junk clean: green-tier only (caches/logs/updater leftovers).
# Default is preview-only; -Execute performs real deletion.
# Red-tier paths (sessions/history/auth/config/...) are NEVER enumerated here
# and additionally rejected by a hardcoded keyword blacklist.
param(
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

function Convert-ToLong([object]$value) {
    if ($null -eq $value) { return [long]0 }
    return [long]$value
}

function Expand-EnvPath([string]$p) {
    $r = $p
    if ($env:USERPROFILE) { $r = $r.Replace('%USERPROFILE%', $env:USERPROFILE) }
    if ($env:LOCALAPPDATA) { $r = $r.Replace('%LOCALAPPDATA%', $env:LOCALAPPDATA) }
    if ($env:APPDATA) { $r = $r.Replace('%APPDATA%', $env:APPDATA) }
    if ($env:TEMP) { $r = $r.Replace('%TEMP%', $env:TEMP) }
    return $r
}

# ── 红档黑名单（双保险第一层：知识库 tier=green 才进枚举；第二层：路径含任一关键词即拒绝）──
$redKeywords = @(
    'sessions', 'session_index', 'history', 'auth', 'credentials', 'config',
    'settings', 'secrets', 'conversations', 'memory', 'projects',
    'state.vscdb', 'globalstorage', 'workspacestorage', 'modulardata',
    'cascade', 'tasks', 'soul.md', 'identity.md', 'user.md', 'bootstrap.md',
    'brain', 'threads', 'transcripts', 'file-history', 'resume'
)

function Test-RedPath([string]$path) {
    foreach ($kw in $redKeywords) {
        if ($path -like "*$kw*") { return $kw }
    }
    return $null
}

# ── 绿档枚举（与 knowledge/agent-footprints.json 的 tier=green 条目一一对应）──
# kind: dir = 清空目录内容（保留目录本身）；file = 删单个文件；pattern = 父目录下通配删除
$greenTargets = @(
    # OpenAI Codex
    @{ label = 'codex-tmp'; path = '%USERPROFILE%\.codex\.tmp'; kind = 'dir' },
    @{ label = 'codex-tmp2'; path = '%USERPROFILE%\.codex\tmp'; kind = 'dir' },
    @{ label = 'codex-plugins-cache'; path = '%USERPROFILE%\.codex\plugins'; kind = 'dir' },
    @{ label = 'codex-sandbox-bin'; path = '%USERPROFILE%\.codex\.sandbox-bin'; kind = 'dir' },
    @{ label = 'codex-cache'; path = '%USERPROFILE%\.codex\cache'; kind = 'dir' },
    @{ label = 'codex-generated-images'; path = '%USERPROFILE%\.codex\generated_images'; kind = 'dir' },
    @{ label = 'codex-attachments'; path = '%USERPROFILE%\.codex\attachments'; kind = 'dir' },
    @{ label = 'codex-log-dir'; path = '%USERPROFILE%\.codex\log'; kind = 'dir' },
    @{ label = 'codex-sandbox-logs'; path = '%USERPROFILE%\.codex\sandbox*.log'; kind = 'pattern' },
    @{ label = 'codex-logs-sqlite'; path = '%USERPROFILE%\.codex\logs_2.sqlite*'; kind = 'pattern' },
    @{ label = 'codex-runtime-install-tmp'; path = '%USERPROFILE%\.cache\codex-runtimes\codex-runtime-install-*'; kind = 'dir' },
    # Claude Code
    @{ label = 'claude-tmp'; path = '%USERPROFILE%\.claude\tmp'; kind = 'dir' },
    @{ label = 'claude-debug'; path = '%USERPROFILE%\.claude\debug'; kind = 'dir' },
    @{ label = 'claude-telemetry'; path = '%USERPROFILE%\.claude\telemetry'; kind = 'dir' },
    @{ label = 'claude-backups'; path = '%USERPROFILE%\.claude\backups'; kind = 'dir' },
    @{ label = 'claude-shell-snapshots'; path = '%USERPROFILE%\.claude\shell-snapshots'; kind = 'dir' },
    @{ label = 'claude-paste-cache'; path = '%USERPROFILE%\.claude\paste-cache'; kind = 'dir' },
    # npm / claude-cli
    @{ label = 'npm-cache'; path = '%LOCALAPPDATA%\npm-cache'; kind = 'dir' },
    @{ label = 'claude-cli-nodejs'; path = '%LOCALAPPDATA%\claude-cli-nodejs'; kind = 'dir' },
    # 腾讯 WorkBuddy
    @{ label = 'workbuddy-updater'; path = '%LOCALAPPDATA%\@genieworkbuddy-desktop-updater'; kind = 'dir' },
    @{ label = 'workbuddy-temp-update'; path = '%TEMP%\workbuddy-update-x64'; kind = 'dir' },
    @{ label = 'workbuddy-logs'; path = '%USERPROFILE%\.workbuddy\logs'; kind = 'dir' },
    @{ label = 'workbuddy-traces'; path = '%USERPROFILE%\.workbuddy\traces'; kind = 'dir' },
    @{ label = 'workbuddy-client-logs'; path = '%LOCALAPPDATA%\WorkBuddy'; kind = 'dir' },
    @{ label = 'workbuddy-plugins-cache'; path = '%USERPROFILE%\.workbuddy\plugins\cache'; kind = 'dir' },
    @{ label = 'workbuddy-connectors-market'; path = '%USERPROFILE%\.workbuddy\connectors-marketplace'; kind = 'dir' },
    # 腾讯 CodeBuddy CLI
    @{ label = 'codebuddy-logs'; path = '%USERPROFILE%\.codebuddy\logs'; kind = 'dir' },
    @{ label = 'codebuddy-traces'; path = '%USERPROFILE%\.codebuddy\traces'; kind = 'dir' },
    # Google Antigravity
    @{ label = 'antigravity-updater'; path = '%LOCALAPPDATA%\antigravity-updater'; kind = 'dir' },
    @{ label = 'antigravity-cache'; path = '%APPDATA%\Antigravity\Cache'; kind = 'dir' },
    @{ label = 'antigravity-code-cache'; path = '%APPDATA%\Antigravity\Code Cache'; kind = 'dir' },
    @{ label = 'antigravity-gpu-cache'; path = '%APPDATA%\Antigravity\GPUCache'; kind = 'dir' },
    @{ label = 'antigravity-dawn-graphite'; path = '%APPDATA%\Antigravity\DawnGraphiteCache'; kind = 'dir' },
    @{ label = 'antigravity-dawn-webgpu'; path = '%APPDATA%\Antigravity\DawnWebGPUCache'; kind = 'dir' },
    @{ label = 'antigravity-logs'; path = '%APPDATA%\Antigravity\logs'; kind = 'dir' },
    @{ label = 'antigravity-dictionaries'; path = '%APPDATA%\Antigravity\Dictionaries'; kind = 'dir' },
    @{ label = 'antigravity-crashpad'; path = '%APPDATA%\Antigravity\Crashpad'; kind = 'dir' },
    @{ label = 'antigravity-crashes'; path = '%USERPROFILE%\.gemini\antigravity\crashes'; kind = 'dir' },
    @{ label = 'antigravity-backup'; path = '%USERPROFILE%\.gemini\antigravity-backup'; kind = 'dir' },
    @{ label = 'antigravity-ide-crashes'; path = '%USERPROFILE%\.gemini\antigravity-ide\crashes'; kind = 'dir' },
    # Cursor
    @{ label = 'cursor-cache'; path = '%APPDATA%\Cursor\Cache'; kind = 'dir' },
    @{ label = 'cursor-code-cache'; path = '%APPDATA%\Cursor\Code Cache'; kind = 'dir' },
    @{ label = 'cursor-cached-data'; path = '%APPDATA%\Cursor\CachedData'; kind = 'dir' },
    @{ label = 'cursor-cached-vsixs'; path = '%APPDATA%\Cursor\CachedExtensionVSIXs'; kind = 'dir' },
    @{ label = 'cursor-cached-profiles'; path = '%APPDATA%\Cursor\CachedProfilesData'; kind = 'dir' },
    @{ label = 'cursor-gpu-cache'; path = '%APPDATA%\Cursor\GPUCache'; kind = 'dir' },
    @{ label = 'cursor-crashpad'; path = '%APPDATA%\Cursor\Crashpad'; kind = 'dir' },
    @{ label = 'cursor-logs'; path = '%APPDATA%\Cursor\logs'; kind = 'dir' },
    @{ label = 'cursor-backups'; path = '%APPDATA%\Cursor\Backups'; kind = 'dir' },
    @{ label = 'cursor-blob-storage'; path = '%APPDATA%\Cursor\blob_storage'; kind = 'dir' },
    @{ label = 'cursor-dictionaries'; path = '%APPDATA%\Cursor\Dictionaries'; kind = 'dir' },
    @{ label = 'cursor-local-cache'; path = '%LOCALAPPDATA%\Cursor'; kind = 'dir' },
    # Windsurf
    @{ label = 'windsurf-cache'; path = '%APPDATA%\Windsurf\Cache'; kind = 'dir' },
    @{ label = 'windsurf-code-cache'; path = '%APPDATA%\Windsurf\Code Cache'; kind = 'dir' },
    @{ label = 'windsurf-cached-data'; path = '%APPDATA%\Windsurf\CachedData'; kind = 'dir' },
    @{ label = 'windsurf-cached-vsixs'; path = '%APPDATA%\Windsurf\CachedExtensionVSIXs'; kind = 'dir' },
    @{ label = 'windsurf-gpu-cache'; path = '%APPDATA%\Windsurf\GPUCache'; kind = 'dir' },
    @{ label = 'windsurf-logs'; path = '%APPDATA%\Windsurf\logs'; kind = 'dir' },
    # Trae
    @{ label = 'trae-logs'; path = '%APPDATA%\Trae\logs'; kind = 'dir' },
    @{ label = 'trae-cn-logs'; path = '%APPDATA%\Trae CN\logs'; kind = 'dir' },
    @{ label = 'trae-model-cache'; path = '%APPDATA%\Trae\Cache\ModelCache'; kind = 'dir' },
    @{ label = 'trae-cn-model-cache'; path = '%APPDATA%\Trae CN\Cache\ModelCache'; kind = 'dir' },
    # 豆包
    @{ label = 'doubao-cache'; path = '%LOCALAPPDATA%\Doubao\User Data\Cache'; kind = 'dir' },
    @{ label = 'doubao-code-cache'; path = '%LOCALAPPDATA%\Doubao\User Data\Code Cache'; kind = 'dir' },
    @{ label = 'doubao-gpu-cache'; path = '%LOCALAPPDATA%\Doubao\User Data\GPUCache'; kind = 'dir' },
    # 通义灵码
    @{ label = 'lingma-cache'; path = '%USERPROFILE%\.lingma\cache'; kind = 'dir' },
    @{ label = 'lingma-logs'; path = '%USERPROFILE%\.lingma\logs'; kind = 'dir' },
    @{ label = 'lingma-tmp'; path = '%USERPROFILE%\.lingma\tmp'; kind = 'dir' },
    @{ label = 'lingma-telemetry'; path = '%LOCALAPPDATA%\.lingma'; kind = 'dir' },
    # Aider / OpenCode / Amp / Warp / VS Code / ComfyUI
    @{ label = 'aider-cache'; path = '%USERPROFILE%\.aider.cache'; kind = 'dir' },
    @{ label = 'opencode-log'; path = '%USERPROFILE%\.local\share\opencode\log'; kind = 'dir' },
    @{ label = 'amp-cache'; path = '%USERPROFILE%\.cache\amp'; kind = 'dir' },
    @{ label = 'warp-logs'; path = '%LOCALAPPDATA%\warp\Warp\data\logs'; kind = 'dir' },
    @{ label = 'warp-cache'; path = '%LOCALAPPDATA%\warp\Warp\data\cache'; kind = 'dir' },
    @{ label = 'vscode-cache'; path = '%APPDATA%\Code\Cache'; kind = 'dir' },
    @{ label = 'vscode-code-cache'; path = '%APPDATA%\Code\Code Cache'; kind = 'dir' },
    @{ label = 'vscode-cached-data'; path = '%APPDATA%\Code\CachedData'; kind = 'dir' },
    @{ label = 'vscode-cached-vsixs'; path = '%APPDATA%\Code\CachedExtensionVSIXs'; kind = 'dir' },
    @{ label = 'vscode-gpu-cache'; path = '%APPDATA%\Code\GPUCache'; kind = 'dir' },
    @{ label = 'vscode-logs'; path = '%APPDATA%\Code\logs'; kind = 'dir' },
    @{ label = 'vscode-crashpad'; path = '%APPDATA%\Code\Crashpad'; kind = 'dir' },
    @{ label = 'vscode-dictionaries'; path = '%APPDATA%\Code\Dictionaries'; kind = 'dir' },
    @{ label = 'comfyui-updater'; path = '%LOCALAPPDATA%\@comfyorgcomfyui-electron-updater'; kind = 'dir' }
)

function Get-DirFiles([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 })
}

function Get-PatternFiles([string]$expandedPath) {
    $parent = Split-Path -Parent $expandedPath
    $leaf = Split-Path -Leaf $expandedPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $parent -Filter $leaf -File -Force -ErrorAction SilentlyContinue)
}

function Remove-EmptyChildDirectories([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return 0 }
    $directories = @(
        Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
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
        } catch { }
    }
    return $removed
}

$logDirectory = Join-Path $PSScriptRoot 'logs'
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logPath = Join-Path $logDirectory ("agent-junk-clean-{0}.log" -f $timestamp)
$logLines = New-Object System.Collections.Generic.List[string]
function Add-Log([string]$line) { $script:logLines.Add($line) }

Write-Output '=== Only-U agent-junk clean ==='
if ($Execute) {
    Write-Output 'mode: EXECUTE (green-tier only: caches / logs / traces / updater leftovers)'
} else {
    Write-Output 'mode: PREVIEW (no files deleted). Confirm then run with -Execute'
}
Add-Log ('=== agent-junk clean {0} mode={1} ===' -f (Get-Date).ToString('s'), $(if ($Execute) { 'EXECUTE' } else { 'PREVIEW' }))

$totalPreview = [long]0
$totalActual = [long]0
$totalRemoved = 0
$totalSkipped = 0
$blockedRed = @()

foreach ($target in $greenTargets) {
    $expanded = Expand-EnvPath $target.path

    # 红档黑名单：任何路径命中即拒绝该目标（双保险第二层）
    $hit = Test-RedPath $expanded
    if ($hit) {
        $blockedRed += ("{0} -> keyword '{1}'" -f $expanded, $hit)
        Add-Log ("REJECTED red-keyword: {0} ({1})" -f $expanded, $hit)
        continue
    }

    # 解析实际目标（通配 dir 展开为多个实例）
    $instances = @()
    if ($target.kind -eq 'dir' -and $expanded.Contains('*')) {
        $instances = @(Get-Item -Path $expanded -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    } elseif ($target.kind -eq 'dir') {
        if (Test-Path -LiteralPath $expanded -PathType Container) { $instances = @(,$expanded) }
    } else {
        $instances = @(,$expanded)
    }

    foreach ($instance in $instances) {
        if ([string]::IsNullOrEmpty($instance)) { continue }

        $files = @()
        if ($target.kind -eq 'dir') {
            $files = Get-DirFiles $instance
        } else {
            $files = Get-PatternFiles $instance
        }
        if ($files.Count -eq 0) { continue }

        $bytes = Convert-ToLong (($files | Measure-Object Length -Sum).Sum)
        $totalPreview += $bytes
        Write-Output ("[green] {0}: {1}" -f $target.label, $instance)
        Write-Output ("  files {0}, about {1}" -f $files.Count, (Format-Bytes $bytes))
        Add-Log ("[green] {0}: {1} files={2} bytes={3}" -f $target.label, $instance, $files.Count, $bytes)

        if ($Execute) {
            $removed = 0; $skipped = 0; $actual = [long]0
            foreach ($file in $files) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $removed++; $actual += [long]$file.Length
                } catch { $skipped++ }
            }
            if ($target.kind -eq 'dir') {
                Remove-EmptyChildDirectories $instance | Out-Null
            }
            $totalActual += $actual
            $totalRemoved += $removed
            $totalSkipped += $skipped
            Write-Output ("  removed {0}, skipped {1}" -f $removed, $skipped)
            Add-Log ("  removed={0} skipped={1} actualBytes={2}" -f $removed, $skipped, $actual)
        }
    }
}

Write-Output ''
Write-Output ("green total: {0} (safe to reclaim; yellow/red tiers not included)" -f (Format-Bytes $totalPreview))
Add-Log ('green total bytes: {0}' -f $totalPreview)
if ($Execute) {
    Write-Output ("planned {0}; actually freed {1}; removed {2}; skipped {3}" -f (Format-Bytes $totalPreview), (Format-Bytes $totalActual), $totalRemoved, $totalSkipped)
    Write-Output ("log: {0}" -f $logPath)
    Add-Log ('total actual bytes: {0}' -f $totalActual)
    Add-Log ('total removed files: {0}' -f $totalRemoved)
    Add-Log ('total skipped files: {0}' -f $totalSkipped)
}
if ($blockedRed.Count -gt 0) {
    Write-Output 'rejected by red-tier blacklist (never cleaned):'
    $blockedRed | ForEach-Object {
        Write-Output ("  {0}" -f $_)
    }
} else {
    Write-Output 'red-tier blacklist: 0 hits (no sessions/history/auth/config paths enumerated)'
}
Write-Output 'Never cleans session history / configs / credentials / chat databases.'

if ($Execute) {
    if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($logPath, $logLines, $utf8NoBom)
}
