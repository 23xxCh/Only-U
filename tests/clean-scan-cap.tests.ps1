#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'clean.ps1 scan cap' {
    BeforeAll {
        $Clean = Join-Path (Split-Path -Parent $PSScriptRoot) 'portable\clean.ps1'
        $Source = [System.IO.File]::ReadAllText($Clean)
    }

    It 'caps each directory scan and skips reparse points' {
        $Source | Should -BeLike '*$scanFileLimit = 20000*'
        $Source | Should -BeLike '*$scanTimeoutSeconds = 8*'
        $Source | Should -BeLike '*ReparsePoint*'
        $Source | Should -BeLike '*跳过：太大或超时*'
        $Source | Should -BeLike '*正在扫描*'
        $Source | Should -Not -BeLike '*Get-ChildItem -LiteralPath $Path -Recurse -Force -File*'
    }

    It 'skips a directory after the file limit without hanging' {
        $root = Join-Path $TestDrive 'cap'
        $portable = Join-Path $root 'portable'
        New-Item -ItemType Directory -Path $portable -Force | Out-Null
        $script = Join-Path $portable 'clean.ps1'
        $patched = $Source.Replace('$scanFileLimit = 20000', '$scanFileLimit = 20')
        [System.IO.File]::WriteAllText($script, $patched)

        $temp = Join-Path $root 'Temp'
        New-Item -ItemType Directory -Path $temp, (Join-Path $root 'Local\Temp'), (Join-Path $root 'Win\Temp'), (Join-Path $root 'Local\Microsoft\Windows\Explorer'), (Join-Path $root 'ProgramData\Microsoft\Windows\WER\ReportQueue'), (Join-Path $root 'ProgramData\Microsoft\Windows\WER\ReportArchive'), (Join-Path $root 'Local\Microsoft\Windows\WER\ReportQueue'), (Join-Path $root 'Local\Microsoft\Windows\WER\ReportArchive'), (Join-Path $root 'Win\SoftwareDistribution\Download'), (Join-Path $root '$Recycle.Bin') -Force | Out-Null
        1..40 | ForEach-Object {
            [System.IO.File]::WriteAllText((Join-Path $temp ("old-{0}.tmp" -f $_)), 'x')
            (Get-Item -LiteralPath (Join-Path $temp ("old-{0}.tmp" -f $_))).LastWriteTime = (Get-Date).AddDays(-8)
        }

        $previous = @{
            TEMP = $env:TEMP
            TMP = $env:TMP
            LOCALAPPDATA = $env:LOCALAPPDATA
            WINDIR = $env:WINDIR
            ProgramData = $env:ProgramData
            SystemDrive = $env:SystemDrive
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $env:TEMP = $temp
            $env:TMP = $temp
            $env:LOCALAPPDATA = Join-Path $root 'Local'
            $env:WINDIR = Join-Path $root 'Win'
            $env:ProgramData = Join-Path $root 'ProgramData'
            $env:SystemDrive = $root
            $out = & $script | Out-String
        }
        finally {
            $env:TEMP = $previous.TEMP
            $env:TMP = $previous.TMP
            $env:LOCALAPPDATA = $previous.LOCALAPPDATA
            $env:WINDIR = $previous.WINDIR
            $env:ProgramData = $previous.ProgramData
            $env:SystemDrive = $previous.SystemDrive
        }
        $sw.Stop()

        $out | Should -BeLike '*正在扫描*'
        $out | Should -BeLike '*跳过：太大或超时*'
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 20
    }
}
