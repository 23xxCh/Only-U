$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cleanSource = Join-Path $repoRoot 'portable\clean.ps1'
$environmentNames = @('TEMP', 'TMP', 'LOCALAPPDATA', 'WINDIR', 'ProgramData', 'SystemDrive')

function Invoke-CleanFixture {
    param(
        [string]$Root,
        [switch]$Execute
    )

    $portableRoot = Join-Path $Root 'portable'
    New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
    $script = Join-Path $portableRoot 'clean.ps1'
    Copy-Item -LiteralPath $cleanSource -Destination $script

    $directories = @(
        'Temp',
        'Local\Temp',
        'Win\Temp',
        'Local\Microsoft\Windows\Explorer',
        'ProgramData\Microsoft\Windows\WER\ReportQueue',
        'ProgramData\Microsoft\Windows\WER\ReportArchive',
        'Local\Microsoft\Windows\WER\ReportQueue',
        'Local\Microsoft\Windows\WER\ReportArchive',
        'Win\SoftwareDistribution\Download',
        '$Recycle.Bin'
    )
    foreach ($relative in $directories) {
        New-Item -ItemType Directory -Path (Join-Path $Root $relative) -Force | Out-Null
    }

    $oldTime = (Get-Date).AddDays(-8)
    $oldTemp = Join-Path $Root 'Temp\old-temp.txt'
    [System.IO.File]::WriteAllText($oldTemp, '12345')
    (Get-Item -LiteralPath $oldTemp).LastWriteTime = $oldTime
    [System.IO.File]::WriteAllText((Join-Path $Root 'Temp\new-temp.txt'), '123')

    [System.IO.File]::WriteAllText((Join-Path $Root 'Local\Microsoft\Windows\Explorer\thumbcache_test.db'), '123456')
    [System.IO.File]::WriteAllText((Join-Path $Root 'ProgramData\Microsoft\Windows\WER\ReportQueue\report.dmp'), '12345678')
    [System.IO.File]::WriteAllText((Join-Path $Root 'Win\SoftwareDistribution\Download\update.msu'), '1234567890')

    $previous = @{}
    foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        $env:TEMP = Join-Path $Root 'Temp'
        $env:TMP = Join-Path $Root 'Temp'
        $env:LOCALAPPDATA = Join-Path $Root 'Local'
        $env:WINDIR = Join-Path $Root 'Win'
        $env:ProgramData = Join-Path $Root 'ProgramData'
        $env:SystemDrive = $Root
        $cleanOutput = if ($Execute) { & $script -Execute } else { & $script }
    }
    finally {
        foreach ($entry in $previous.GetEnumerator()) {
            Set-Item -Path ('Env:\{0}' -f $entry.Key) -Value $entry.Value
        }
    }

    return [pscustomobject]@{
        ScriptPath = $script
        Output = ($cleanOutput | Out-String)
    }
}

Describe 'Only-U safe clean' {
    It 'keeps the required user-content roots protected' {
        $source = Get-Content -Raw -LiteralPath $cleanSource

        $source | Should BeLike '*MyDocuments*'
        $source | Should BeLike '*Desktop*'
        $source | Should BeLike '*MyPictures*'
        $source | Should BeLike '*Downloads*'
        $source | Should BeLike '*Never cleans Desktop / Documents / Downloads / Pictures.*'
    }

    It 'never expands into forbidden cleanup targets' {
        $source = Get-Content -Raw -LiteralPath $cleanSource

        $source | Should Not BeLike '*Windows.old*'
        $source | Should Not BeLike '*WinSxS*'
        $source | Should Not BeLike '*Windows\Installer*'
        $source | Should Not BeLike '*hiberfil*'
        $source | Should Not BeLike '*pagefile*'
        $source | Should Not BeLike '*Chrome*'
        $source | Should Not BeLike '*Edge*'
    }

    It 'preview shows every safe category, applies the 7-day gate, and deletes nothing' {
        $root = Join-Path $TestDrive 'preview'
        $result = Invoke-CleanFixture $Root
        $output = $result.Output

        $output | Should BeLike '*[TEMP]*'
        $output | Should BeLike '*按 7 天门限过滤后：1 文件*另有 1 个新文件跳过*'
        $output | Should BeLike '*[THUMBNAIL CACHE]*'
        $output | Should BeLike '*thumbcache_*.db*'
        $output | Should BeLike '*[WER REPORTS]*'
        $output | Should BeLike '*[WINDOWS UPDATE CACHE]*'
        $output | Should BeLike '*清空后已下载更新需重下*'
        $output | Should BeLike '*[RECYCLE BIN]*'
        $output | Should BeLike '*emptied only with -Execute*'
        $output | Should BeLike '*执行后日志将写入 portable\logs\*'

        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Temp\new-temp.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Local\Microsoft\Windows\Explorer\thumbcache_test.db')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'ProgramData\Microsoft\Windows\WER\ReportQueue\report.dmp')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Win\SoftwareDistribution\Download\update.msu')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'portable\logs')) | Should Be $false
    }

    It 'execute removes allow-listed content and writes a matching UTF-8 log' {
        Mock Clear-RecycleBin { }
        $root = Join-Path $TestDrive 'execute'
        $result = Invoke-CleanFixture $Root -Execute
        $outputText = $result.Output

        Assert-MockCalled Clear-RecycleBin 1 {
            $DriveLetter -eq $root
        }

        $outputText | Should BeLike '*planned*actually freed*removed*skipped*'
        $outputText | Should BeLike '*log:*'

        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $root 'Temp\new-temp.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Local\Microsoft\Windows\Explorer\thumbcache_test.db')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $root 'ProgramData\Microsoft\Windows\WER\ReportQueue\report.dmp')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $root 'Win\SoftwareDistribution\Download\update.msu')) | Should Be $false

        $logs = @(Get-ChildItem -LiteralPath (Join-Path $root 'portable\logs') -Filter 'clean-*.log')
        $logs.Count | Should Be 1
        $log = $logs[0]
        $log.Name | Should Match '^clean-\d{8}-\d{6}\.log$'
        $bytes = [System.IO.File]::ReadAllBytes($log.FullName)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
        $logText = [System.IO.File]::ReadAllText($log.FullName, [System.Text.Encoding]::UTF8)
        $logText | Should BeLike '*[TEMP]*'
        $logText | Should BeLike '*planned bytes:*'
        $logText | Should BeLike '*actual bytes:*'
        $logText | Should BeLike '*skipped locked: 0*'
        $logText | Should BeLike '*[THUMBNAIL CACHE]*'
        $logText | Should BeLike '*[WER REPORTS]*'
        $logText | Should BeLike '*[WINDOWS UPDATE CACHE]*'
        $logText | Should BeLike '*[RECYCLE BIN]*'
        $logText | Should BeLike '*total planned bytes:*'
        $logText | Should BeLike '*total actual bytes:*'
        $logText | Should BeLike '*plan/actual deviation: 0.0%*'
    }

    It 'keeps clean.ps1 as UTF-8 with BOM and clean.cmd as GBK without BOM' {
        $psBytes = [System.IO.File]::ReadAllBytes($cleanSource)
        ($psBytes[0] -eq 0xEF -and $psBytes[1] -eq 0xBB -and $psBytes[2] -eq 0xBF) | Should Be $true

        $cmdPath = Join-Path $repoRoot 'portable\clean.cmd'
        $cmdBytes = [System.IO.File]::ReadAllBytes($cmdPath)
        ($cmdBytes[0] -eq 0xEF -and $cmdBytes[1] -eq 0xBB -and $cmdBytes[2] -eq 0xBF) | Should Be $false
    }
}