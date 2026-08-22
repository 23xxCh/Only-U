$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$diagnoseScript = Join-Path $repoRoot 'portable\diagnose.ps1'
$skillFile = Join-Path $repoRoot '.dsh\skills\only-u-ops\SKILL.md'
$windowsPowerShell = (Get-Command powershell -ErrorAction Stop).Source

function Get-Utf8Text {
    param([byte[]]$Bytes)
    return [System.Text.Encoding]::UTF8.GetString($Bytes)
}

$scanMarker = Get-Utf8Text (0xE6,0xAD,0xA3,0xE5,0x9C,0xA8,0xE6,0x89,0xAB,0xE6,0x8F,0x8F)
$skippedMarker = Get-Utf8Text (0xE8,0xB7,0xB3,0xE8,0xBF,0x87,0xEF,0xBC,0x9A,0xE5,0xA4,0xAA,0xE5,0xA4,0xA7,0xE6,0x88,0x96,0xE8,0xB6,0x85,0xE6,0x97,0xB6)
$criticalEventsMarker = Get-Utf8Text (0xE5,0x85,0xB3,0xE9,0x94,0xAE,0xE4,0xBA,0x8B,0xE4,0xBB,0xB6)
$startupFallbackMarker = Get-Utf8Text (0xE6,0x97,0xA0,0xE6,0xB3,0x95,0xE8,0xAF,0xBB,0xE5,0x8F,0x96,0xE5,0x90,0xAF,0xE5,0x8A,0xA8,0xE9,0xA1,0xB9,0xE6,0x95,0xB0,0xE9,0x87,0x8F)
$sessionStartMarker = Get-Utf8Text (0xE4,0xBC,0x9A,0xE8,0xAF,0x9D,0xE4,0xB8,0x80,0xE5,0xBC,0x80,0xE5,0xA7,0x8B)
$confirmationMarker = Get-Utf8Text (0xE7,0xA1,0xAE,0xE8,0xAE,0xA4)
$executionMarker = Get-Utf8Text (0xE6,0x89,0xA7,0xE8,0xA1,0x8C)

function Invoke-DiagnoseOutput {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $windowsPowerShell
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $diagnoseScript + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        Output = $outputTask.Result
        Error = $errorTask.Result
        ExitCode = $process.ExitCode
    }
}

Describe 'Only-U offline diagnose' {
    It 'caps a large TEMP scan and explains that it was skipped' {
        $largeTemp = Join-Path $TestDrive 'large-temp'
        New-Item -ItemType Directory -Path $largeTemp | Out-Null
        1..20001 | ForEach-Object {
            [System.IO.File]::WriteAllText((Join-Path $largeTemp ("file-{0}.tmp" -f $_)), 'x')
        }

        $previousTemp = $env:TEMP
        $previousTmp = $env:TMP
        $previousLocalAppData = $env:LOCALAPPDATA
        $previousWinDir = $env:WINDIR
        try {
            $env:TEMP = $largeTemp
            $env:TMP = $largeTemp
            $env:LOCALAPPDATA = $TestDrive
            $env:WINDIR = $TestDrive

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-DiagnoseOutput
            $result.ExitCode | Should Be 0
            $output = $result.Output + $result.Error
            $stopwatch.Stop()

            $output | Should BeLike '*reclaim candidates*'
            $output | Should BeLike "*$scanMarker*"
            $output | Should BeLike "*$skippedMarker*"
            $output | Should BeLike '*20000*'
            $stopwatch.Elapsed.TotalSeconds | Should BeLessThan 60
        } finally {
            $env:TEMP = $previousTemp
            $env:TMP = $previousTmp
            $env:LOCALAPPDATA = $previousLocalAppData
            $env:WINDIR = $previousWinDir
        }
    }

    It 'reports memory process, startup, and PnP driver clues without changing the machine' {
        $result = Invoke-DiagnoseOutput
        $result.ExitCode | Should Be 0
        $output = $result.Output + $result.Error

        $output | Should BeLike '*top memory processes*'
        (($output -like '*startup entries*') -or ($output -like "*$startupFallbackMarker*")) | Should Be $true
        $output | Should BeLike '*PnP devices with driver issue*'
    }

    It 'reports committed-memory, critical-event, and SMART sections on a normal machine' {
        $result = Invoke-DiagnoseOutput
        $result.ExitCode | Should Be 0
        $output = $result.Output + $result.Error

        $output | Should BeLike '*Committed Bytes In Use*'
        $output | Should BeLike "*$criticalEventsMarker*"
        $output | Should BeLike '*SMART*'
    }

    It 'does not report generic network or hypervisor events as storage faults' {
        $result = Invoke-DiagnoseOutput
        $result.ExitCode | Should Be 0
        $output = $result.Output + $result.Error

        $output | Should Not BeLike '*Miniport NIC*'
        $output | Should Not BeLike '*Hypervisor initialized I/O remapping*'
    }

    It 'keeps raw threshold values, ranks processes by commit, and bounds event details' {
        $source = Get-Content -Raw -LiteralPath $diagnoseScript

        $source | Should BeLike '*FreePctRaw*'
        $source | Should BeLike '*CommittedPercentRaw*'
        $source | Should BeLike '*Sort-Object -Property PagedMemorySize64*'
        $source | Should BeLike '*Select-Object -First 20*'
    }

    It 'uses cancellable scans, skips reparse points, and reports only real PnP error codes' {
        $source = Get-Content -Raw -LiteralPath $diagnoseScript

        $source | Should BeLike '*Start-Job*'
        $source | Should BeLike '*ReparsePoint*'
        $source | Should BeLike '*ConfigManagerErrorCode*'
    }

    It 'instructs a TUI 运维会话 to show diagnosis and clean preview before confirmation' {
        $skill = [System.IO.File]::ReadAllText($skillFile, [System.Text.Encoding]::UTF8)

        $skill.IndexOf($sessionStartMarker) | Should BeGreaterThan -1
        $skill.IndexOf('portable/diagnose.cmd') | Should BeGreaterThan $skill.IndexOf($sessionStartMarker)
        $skill.IndexOf('portable/clean.cmd') | Should BeGreaterThan $skill.IndexOf('portable/diagnose.cmd')
        $skill.IndexOf($confirmationMarker) | Should BeGreaterThan $skill.IndexOf('portable/clean.cmd')
        $skill.IndexOf($executionMarker) | Should BeGreaterThan $skill.IndexOf($confirmationMarker)
        $skill.IndexOf('-Execute') | Should BeGreaterThan $skill.IndexOf($executionMarker)
    }
}
