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
$pnpUnconfigured = Get-Utf8Text (0xE6,0x9C,0xAA,0xE9,0x85,0x8D,0xE7,0xBD,0xAE)
$pnpCannotStart = Get-Utf8Text (0xE6,0x97,0xA0,0xE6,0xB3,0x95,0xE5,0x90,0xAF,0xE5,0x8A,0xA8)
$pnpDisabled = Get-Utf8Text (0xE5,0xB7,0xB2,0xE8,0xA2,0xAB,0xE7,0xA6,0x81,0xE7,0x94,0xA8)
$pnpDriverMissing = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0xE5,0xAE,0x89,0xE8,0xA3,0x85)
$pnpPowerDisabled = Get-Utf8Text (0xE7,0x94,0xB5,0xE6,0xBA,0x90,0xE4,0xB8,0x8D,0xE8,0xB6,0xB3,0xE8,0xA2,0xAB,0xE7,0xA6,0x81,0xE7,0x94,0xA8)
$pnpDriverLoadFailed = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE5,0x8A,0xA0,0xE8,0xBD,0xBD,0xE5,0xA4,0xB1,0xE8,0xB4,0xA5)
$pnpDeviceFault = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE8,0x87,0xAA,0xE6,0x8A,0xA5,0xE6,0x95,0x85,0xE9,0x9A,0x9C)
$pnpRemoved = Get-Utf8Text (0xE8,0xAE,0xBE,0xE5,0xA4,0x87,0xE5,0xB7,0xB2,0xE6,0x8B,0x94,0xE9,0x99,0xA4)
$pnpPolicyBlocked = Get-Utf8Text (0xE8,0xA2,0xAB,0xE7,0xAD,0x96,0xE7,0x95,0xA5,0xE9,0x98,0xBB,0xE6,0xAD,0xA2)
$pnpUnsigned = Get-Utf8Text (0xE9,0xA9,0xB1,0xE5,0x8A,0xA8,0xE6,0x9C,0xAA,0xE7,0xAD,0xBE,0xE5,0x90,0x8D)
$driverSuggestion = (Get-Utf8Text (0xE5,0x8E,0xBB,0xE5,0x8E,0x82,0xE5,0x95,0x86,0xE5,0xAE,0x98,0xE7,0xBD,0x91,0xE6,0x88,0x96)) + ' Windows Update ' + (Get-Utf8Text (0xE5,0x8F,0xAF,0xE9,0x80,0x89,0xE6,0x9B,0xB4,0xE6,0x96,0xB0,0xE6,0x89,0xBE,0xE9,0xA9,0xB1,0xE5,0x8A,0xA8))
$sampleDeviceName = Get-Utf8Text (0xE7,0xA4,0xBA,0xE4,0xBE,0x8B,0xE7,0xBD,0x91,0xE5,0x8D,0xA1)
$errorCodeMarker = Get-Utf8Text (0xE9,0x94,0x99,0xE8,0xAF,0xAF,0xE7,0xA0,0x81)
$suggestionMarker = Get-Utf8Text (0xE5,0xBB,0xBA,0xE8,0xAE,0xAE,0xEF,0xBC,0x9A)
$printerJam = Get-Utf8Text (0xE5,0x8D,0xA1,0xE7,0xBA,0xB8)
$printerOffline = Get-Utf8Text (0xE8,0x84,0xB1,0xE6,0x9C,0xBA)
$printerNoPaper = Get-Utf8Text (0xE6,0x97,0xA0,0xE7,0xBA,0xB8)
$printerNoToner = Get-Utf8Text (0xE7,0xBC,0xBA,0xE7,0xB2,0x89)

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
    It 'translates recognized PnP driver and device states into actionable buckets' {
        . $diagnoseScript -NoRun

        $expected = @(
            [pscustomobject]@{ Code = 1; Translation = $pnpUnconfigured; Bucket = 'missing-driver' },
            [pscustomobject]@{ Code = 10; Translation = $pnpCannotStart; Bucket = 'suspected-hardware' },
            [pscustomobject]@{ Code = 22; Translation = $pnpDisabled; Bucket = 'disabled' },
            [pscustomobject]@{ Code = 28; Translation = $pnpDriverMissing; Bucket = 'missing-driver' },
            [pscustomobject]@{ Code = 29; Translation = $pnpPowerDisabled; Bucket = 'disabled' },
            [pscustomobject]@{ Code = 37; Translation = $pnpDriverLoadFailed; Bucket = 'missing-driver' },
            [pscustomobject]@{ Code = 39; Translation = $pnpDriverLoadFailed; Bucket = 'missing-driver' },
            [pscustomobject]@{ Code = 43; Translation = $pnpDeviceFault; Bucket = 'suspected-hardware' },
            [pscustomobject]@{ Code = 45; Translation = $pnpRemoved; Bucket = 'other' },
            [pscustomobject]@{ Code = 48; Translation = $pnpPolicyBlocked; Bucket = 'missing-driver' },
            [pscustomobject]@{ Code = 52; Translation = $pnpUnsigned; Bucket = 'missing-driver' }
        )
        foreach ($item in $expected) {
            $detail = Get-PnpErrorDetail -Code $item.Code
            $detail.Translation | Should Be $item.Translation
            $detail.Bucket | Should Be $item.Bucket
        }

        (Get-PnpErrorDetail -Code 28).Suggestion | Should Be $driverSuggestion
    }

    It 'formats a translated PnP finding with the device class code and practical suggestion' {
        . $diagnoseScript -NoRun

        $device = [pscustomobject]@{ Name = $sampleDeviceName; PNPClass = 'Net'; ConfigManagerErrorCode = 28 }
        $line = Format-PnpDeviceLine -Device $device -Detail (Get-PnpErrorDetail -Code 28)

        $line | Should Be ($sampleDeviceName + ' [Net] ' + $errorCodeMarker + '28' + (Get-Utf8Text (0xEF,0xBC,0x88)) + $pnpDriverMissing + (Get-Utf8Text (0xEF,0xBC,0x89,0xE2,0x86,0x92,0x20)) + $suggestionMarker + $driverSuggestion)
    }

    It 'reduces readable hardware IDs to a safe vendor and device summary' {
        . $diagnoseScript -NoRun

        (Get-HardwareIdSummary -HardwareIds @('PCI\VEN_10EC&DEV_8168&SUBSYS_01234567')) | Should Be 'VEN_10EC&DEV_8168'
        (Get-HardwareIdSummary -HardwareIds @('USB\VID_046D&PID_C534&REV_2900')) | Should Be 'VID_046D&PID_C534'
        (Get-HardwareIdSummary -HardwareIds @('ROOT\UNKNOWN')) | Should Be $null
    }

    It 'forces a timed-out diagnostic read to complete within its deadline' {
        . $diagnoseScript -NoRun

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $read = Invoke-BoundedRead -TimeoutSeconds 1 -ScriptBlock { Start-Sleep -Seconds 4; 'late result' }
        $stopwatch.Stop()

        $read.Status | Should Be 'TimedOut'
        $read.Value | Should Be $null
        $stopwatch.Elapsed.TotalSeconds | Should BeLessThan 3
    }

    It 'counts PnP bucket findings while displaying at most five' {
        . $diagnoseScript -NoRun

        $detail = Get-PnpErrorDetail -Code 28
        $findings = @(1..6 | ForEach-Object {
            [pscustomobject]@{
                Device = [pscustomobject]@{ Name = "device-$_"; PNPClass = 'Net'; ConfigManagerErrorCode = 28; PNPDeviceID = "PCI\\$_" }
                Detail = $detail
            }
        })
        $bucket = Get-PnpBucketDisplay -Findings $findings -BucketName 'missing-driver'

        $bucket.Count | Should Be 6
        $bucket.Entries.Count | Should Be 5
    }

    It 'uses distinct hardware and disabled remediation suggestions' {
        . $diagnoseScript -NoRun

        $hardware = Get-PnpErrorDetail -Code 10
        $disabled = Get-PnpErrorDetail -Code 22

        $hardware.Bucket | Should Be 'suspected-hardware'
        $disabled.Bucket | Should Be 'disabled'
        $hardware.Suggestion | Should Not Be $disabled.Suggestion
    }

    It 'uses only the first hardware ID and only for missing-driver findings' {
        . $diagnoseScript -NoRun

        (Get-HardwareIdSummary -HardwareIds @('PCI\VEN_10EC&DEV_8168&SUBSYS_FIRST', 'USB\VID_046D&PID_C534')) | Should Be 'VEN_10EC&DEV_8168'
        $reader = {
            param($instanceId)
            if ($instanceId -ne 'PCI\MISSING') { throw 'unexpected hardware-ID instance' }
            return [pscustomobject]@{ Data = @('PCI\VEN_10EC&DEV_8168&SUBSYS_FIRST', 'USB\VID_046D&PID_C534') }
        }
        $missingFinding = [pscustomobject]@{
            Device = [pscustomobject]@{ Name = 'missing'; PNPClass = 'Net'; ConfigManagerErrorCode = 28; PNPDeviceID = 'PCI\MISSING' }
            Detail = Get-PnpErrorDetail -Code 28
        }
        $disabledFinding = [pscustomobject]@{
            Device = [pscustomobject]@{ Name = 'disabled'; PNPClass = 'Net'; ConfigManagerErrorCode = 22; PNPDeviceID = 'PCI\DISABLED' }
            Detail = Get-PnpErrorDetail -Code 22
        }

        (Get-PnpFindingLine -Finding $missingFinding -HardwareIdReader $reader) | Should BeLike '*VEN_10EC&DEV_8168*'
        Get-PnpFindingLine -Finding $disabledFinding -HardwareIdReader { throw 'disabled finding must not read hardware IDs' } | Out-Null
    }

    It 'skips unreadable hardware ID properties without failing the PnP finding' {
        . $diagnoseScript -NoRun

        $device = [pscustomobject]@{ PNPDeviceID = 'PCI\UNREADABLE' }
        $calls = New-Object System.Collections.ArrayList
        $unreadableReader = {
            param($instanceId)
            [void]$calls.Add($instanceId)
            throw 'unreadable'
        }

        (Get-PnpHardwareIdSummary -Device $device -PropertyReader $unreadableReader) | Should Be $null
        $calls.Count | Should Be 1
        $calls[0] | Should Be 'PCI\UNREADABLE'
    }

    It 'classifies spooler, printer errors, ports, and conclusions from controlled facts' {
        . $diagnoseScript -NoRun

        (Get-PrinterDetectedErrorText -DetectedErrorState 8) | Should Be $printerJam
        (Get-PrinterDetectedErrorText -DetectedErrorState 9) | Should Be $printerOffline
        (Get-PrinterDetectedErrorText -DetectedErrorState 2) | Should Be $printerNoPaper
        (Get-PrinterDetectedErrorText -DetectedErrorState 5) | Should Be $printerNoToner

        $wsdOffline = Get-PrinterPortHint -PortName 'WSD-123' -PrinterStatus 'Offline'
        $wsdOffline.Kind | Should Be 'connection'
        $wsdOffline.Action | Should Be 'network-wsd'
        (Get-PrinterPortHint -PortName 'IP_192.0.2.1' -PrinterStatus 'Normal').Action | Should Be 'ping'
        (Get-PrinterPortHint -PortName 'USB001' -PrinterStatus 'Normal').Action | Should Be 'inspect-pnp'

        $offlinePrinter = [pscustomobject]@{ PortName = 'WSD-123'; PrinterStatus = 'Offline'; DriverName = 'installed driver' }
        (Get-PrinterConclusion -Printer $offlinePrinter -SpoolerStatus 'Running' -DetectedError $null).Kind | Should Be 'connection'
        (Get-PrinterConclusion -Printer $offlinePrinter -SpoolerStatus 'Stopped' -DetectedError $null).Kind | Should Be 'service'
        $serializedOfflinePrinter = [pscustomobject]@{ PortName = 'WSD-123'; PrinterStatus = 7; DriverName = 'installed driver' }
        (Get-PrinterConclusion -Printer $serializedOfflinePrinter -SpoolerStatus 'Running' -DetectedError $null).Kind | Should Be 'connection'
    }

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
