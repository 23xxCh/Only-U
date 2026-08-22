$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$diagnoseScript = Join-Path $repoRoot 'portable\diagnose.ps1'
$skillFile = Join-Path $repoRoot '.dsh\skills\only-u-ops\SKILL.md'
$windowsPowerShell = (Get-Command powershell -ErrorAction Stop).Source

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
            $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String
            $stopwatch.Stop()

            $output | Should BeLike '*正在扫描*'
            $output | Should BeLike '*跳过：太大或超时*'
            $stopwatch.Elapsed.TotalSeconds | Should BeLessThan 60
        } finally {
            $env:TEMP = $previousTemp
            $env:TMP = $previousTmp
            $env:LOCALAPPDATA = $previousLocalAppData
            $env:WINDIR = $previousWinDir
        }
    }

    It 'reports memory process, startup, and PnP driver clues without changing the machine' {
        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String

        $output | Should BeLike '*top memory processes*'
        (($output -like '*startup entries*') -or ($output -like '*无法读取启动项数量*')) | Should Be $true
        $output | Should BeLike '*PnP devices with driver issue*'
    }

    It 'reports committed-memory, critical-event, and SMART sections on a normal machine' {
        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String

        $output | Should BeLike '*Committed Bytes In Use*'
        $output | Should BeLike '*关键事件*'
        $output | Should BeLike '*SMART*'
    }

    It 'does not report generic network or hypervisor events as storage faults' {
        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String

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
        $skill = Get-Content -Raw -LiteralPath $skillFile

        $skill | Should BeLike '*会话一开始*'
        $skill | Should BeLike '*diagnose.cmd*clean.cmd*'
        $skill | Should BeLike '*确认*执行*'
    }
}
