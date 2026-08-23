#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Describe 'Only-U save-report history and two-tier wipe' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $saveScript = Join-Path $repoRoot 'portable\save-report.ps1'
        $wipeScript = Join-Path $repoRoot 'portable\wipe-records.ps1'
    }

    It 'save-report writes report and appends history section #1' {
        $root = Join-Path $TestDrive 'save-one'
        New-Item -ItemType Directory -Path $root | Out-Null
        & $saveScript -PortableDir $root -SkipDiagnose | Out-Null
        $reports = @(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -Filter 'report-*.txt' -File)
        $history = @(Get-ChildItem -LiteralPath $root -Filter 'history-*.md' -File)
        $reports.Count | Should -Be 1
        $history.Count | Should -Be 1
        $h = Get-Content -LiteralPath $history[0].FullName -Raw -Encoding UTF8
        $h | Should -BeLike '*维修履历*'
        $h | Should -BeLike '*每次维修追加一节，勿手改*'
        $h | Should -BeLike '*维修 #1*'
        $h | Should -BeLike ('*{0}*' -f $reports[0].Name)
    }

    It 'save-report second run appends section #2 without overwriting' {
        $root = Join-Path $TestDrive 'save-two'
        New-Item -ItemType Directory -Path $root | Out-Null
        & $saveScript -PortableDir $root -SkipDiagnose | Out-Null
        & $saveScript -PortableDir $root -SkipDiagnose | Out-Null
        $reports = @(Get-ChildItem -LiteralPath (Join-Path $root 'reports') -Filter 'report-*.txt' -File)
        $history = @(Get-ChildItem -LiteralPath $root -Filter 'history-*.md' -File)
        $reports.Count | Should -Be 2
        $history.Count | Should -Be 1
        $h = Get-Content -LiteralPath $history[0].FullName -Raw -Encoding UTF8
        $matches = [regex]::Matches($h, '(?m)^## .+ 维修 #(\d+)')
        $matches.Count | Should -Be 2
        $matches[0].Groups[1].Value | Should -Be '1'
        $matches[1].Groups[1].Value | Should -Be '2'
    }

    It 'wipe Mode N deletes nothing' {
        $root = Join-Path $TestDrive 'wipe-n'
        $sessionDir = Join-Path $root 'runtime\dsh\sessions'
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sessionDir 'keep.txt') -Value 'x' -Encoding ASCII
        & $wipeScript -PortableDir $root -Mode N | Out-Null
        Test-Path -LiteralPath (Join-Path $sessionDir 'keep.txt') | Should -Be $true
    }

    It 'wipe Mode Y clears sessions but keeps reports and history' {
        $root = Join-Path $TestDrive 'wipe-y'
        $sessionDir = Join-Path $root 'runtime\dsh\sessions'
        $reportDir = Join-Path $root 'reports'
        $logDir = Join-Path $root 'logs'
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sessionDir 'chat.json') -Value '{}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $reportDir 'report-PC-1.txt') -Value 'r' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $logDir 'clean-1.log') -Value 'l' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $root 'history-PC.md') -Value '# PC' -Encoding UTF8
        $out = & $wipeScript -PortableDir $root -Mode Y | Out-String
        (Get-ChildItem -LiteralPath $sessionDir -Force).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $reportDir 'report-PC-1.txt') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $root 'history-PC.md') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $logDir 'clean-1.log') | Should -Be $true
        $out | Should -BeLike '*维修履历（reports + history）已保留*'
    }

    It 'wipe Mode A clears reports history logs and sessions; keeps dirs and .env' {
        $root = Join-Path $TestDrive 'wipe-a'
        $sessionDir = Join-Path $root 'runtime\dsh\sessions'
        $reportDir = Join-Path $root 'reports'
        $logDir = Join-Path $root 'logs'
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sessionDir 'chat.json') -Value '{}' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $reportDir 'report-PC-1.txt') -Value 'r' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $logDir 'clean-1.log') -Value 'l' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $root 'history-PC.md') -Value '# PC' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root '.env') -Value 'DEEPSEEK_API_KEY=keep' -Encoding ASCII
        & $wipeScript -PortableDir $root -Mode A | Out-Null
        (Get-ChildItem -LiteralPath $sessionDir -Force).Count | Should -Be 0
        (Get-ChildItem -LiteralPath $reportDir -Force).Count | Should -Be 0
        (Get-ChildItem -LiteralPath $logDir -Force).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $root 'history-PC.md') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $root '.env') | Should -Be $true
        Test-Path -LiteralPath $reportDir | Should -Be $true
        Test-Path -LiteralPath $logDir | Should -Be $true
        Test-Path -LiteralPath $sessionDir | Should -Be $true
    }
}
