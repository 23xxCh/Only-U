#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
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
                Set-Item -Path ('Env:\{0}\{1}' -f 'Env', $entry.Key) -Value $entry.Value
            }
        }

        return [pscustomobject]@{
            ScriptPath = $script
            Root = $Root
            Output = ($cleanOutput | Out-String)
        }
    }
}

Describe 'Only-U clean space before/after summary' {
    It 'execute prints the freed-space summary with before and after values' {
        Mock Clear-RecycleBin { }
        $root = Join-Path $TestDrive 'space-execute'
        $result = Invoke-CleanFixture $Root -Execute
        $output = $result.Output

        $output | Should -BeLike '*== 空间回收 ==*'
        $output | Should -BeLike '*执行前：C: 剩余*'
        $output | Should -BeLike '*执行后：C: 剩余*'
        $output | Should -BeLike '*本次释放：约*'
    }

    It 'execute appends the summary lines to the deletion log tail' {
        Mock Clear-RecycleBin { }
        $root = Join-Path $TestDrive 'space-log'
        $result = Invoke-CleanFixture $Root -Execute

        $logs = @(Get-ChildItem -LiteralPath (Join-Path $root 'portable\logs') -Filter 'clean-*.log')
        $logs.Count | Should -Be 1
        $logText = [System.IO.File]::ReadAllText($logs[0].FullName, [System.Text.Encoding]::UTF8)
        $logText | Should -BeLike '*== 空间回收 ==*'
        $logText | Should -BeLike '*执行前：C: 剩余*'
        $logText | Should -BeLike '*执行后：C: 剩余*'
        $logText | Should -BeLike '*本次释放：约*'
    }

    It 'preview mode does not measure or print the space summary' {
        $root = Join-Path $TestDrive 'space-preview'
        $result = Invoke-CleanFixture $Root
        $output = $result.Output

        $output | Should -Not -BeLike '*空间回收*'
        $output | Should -Not -BeLike '*执行前：C: 剩余*'
        $output | Should -Not -BeLike '*本次释放：约*'
    }
}
