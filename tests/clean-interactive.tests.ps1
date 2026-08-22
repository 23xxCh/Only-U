#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $cleanSource = Join-Path $repoRoot 'portable\clean.ps1'
    $environmentNames = @('TEMP', 'TMP', 'LOCALAPPDATA', 'WINDIR', 'ProgramData', 'SystemDrive')

    function Invoke-CleanFixture {
        param(
            [string]$Root,
            [switch]$Execute,
            [switch]$Interactive
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
            $cleanOutput = if ($Execute) { & $script -Execute } elseif ($Interactive) { & $script -Interactive } else { & $script }
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
}

Describe 'Only-U clean interactive confirmation' {
    It 'shows the Y/N/R prompt after the preview list when -Interactive is passed' {
        Mock Read-Host { 'N' }
        $root = Join-Path $TestDrive 'interactive-prompt'
        $result = Invoke-CleanFixture $Root -Interactive
        $output = $result.Output

        $output | Should -BeLike '*将清理约*'
        $output | Should -BeLike '*按 Y 立即执行 / N 取消 / R 重看清单*'
        $output | Should -BeLike '*已取消，未删除任何文件。*'

        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should -Be $true
    }

    It 'N cancels and deletes nothing' {
        Mock Read-Host { 'N' }
        $root = Join-Path $TestDrive 'interactive-no'
        $result = Invoke-CleanFixture $Root -Interactive
        $output = $result.Output

        $output | Should -BeLike '*已取消，未删除任何文件。*'
        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Temp\new-temp.txt')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Local\Microsoft\Windows\Explorer\thumbcache_test.db')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $root 'portable\logs')) | Should -Be $false
    }

    It 'invalid input re-asks and does not execute' {
        $queue = [System.Collections.Generic.Queue[string]]::new()
        $queue.Enqueue('x')
        $queue.Enqueue('N')
        Mock Read-Host { $queue.Dequeue() }

        $root = Join-Path $TestDrive 'interactive-invalid'
        $result = Invoke-CleanFixture $Root -Interactive
        $output = $result.Output

        $output | Should -BeLike '*无效输入，请输入 Y / N / R。*'
        $output | Should -BeLike '*按 Y 立即执行 / N 取消 / R 重看清单*按 Y 立即执行 / N 取消 / R 重看清单*'
        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should -Be $true
    }

    It 'Y executes the cleanup only after the user confirms' {
        Mock Clear-RecycleBin { }
        Mock Read-Host { 'Y' }
        $root = Join-Path $TestDrive 'interactive-yes'
        $result = Invoke-CleanFixture $Root -Interactive
        $output = $result.Output

        $output | Should -BeLike '*planned*actually freed*removed*skipped*'
        $output | Should -BeLike '*log:*'
        (Test-Path -LiteralPath (Join-Path $root 'Temp\old-temp.txt')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $root 'Temp\new-temp.txt')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $root 'Local\Microsoft\Windows\Explorer\thumbcache_test.db')) | Should -Be $false

        $logs = @(Get-ChildItem -LiteralPath (Join-Path $root 'portable\logs') -Filter 'clean-*.log')
        $logs.Count | Should -Be 1
    }

    It 'without -Interactive the preview never blocks on input' {
        Mock Read-Host { throw 'Read-Host called unexpectedly' }
        $root = Join-Path $TestDrive 'non-interactive'
        $result = Invoke-CleanFixture $Root
        $output = $result.Output

        $output | Should -BeLike '*To delete: portable\clean.cmd -Execute*'
        $output | Should -Not -BeLike '*按 Y 立即执行 / N 取消 / R 重看清单*'
        $output | Should -Not -BeLike '*Read-Host called unexpectedly*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }
}
