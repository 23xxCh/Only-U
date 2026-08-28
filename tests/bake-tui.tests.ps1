#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'baked TUI profile asserts' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $RepoRoot 'scripts\bake-tui.ps1')
        $BakeUsb = Join-Path $RepoRoot 'scripts\bake-usb.ps1'
        $BakeUsbText = [IO.File]::ReadAllText($BakeUsb)
        $BakeTuiText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'scripts\bake-tui.ps1'))

        function Assert-True {
            param([bool]$Condition, [string]$Message)
            if (-not $Condition) { throw $Message }
        }

        function New-FakeDest {
            param([string]$Root, [string]$Version = '0.8.8', [hashtable]$Files)
            if ($null -eq $Files) { $Files = @{} }
            $tui = Join-Path $Root 'portable\runtime\dsh\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui'
            $bundle = Join-Path $Root 'portable\runtime\dsh\profiles\dsh-tui\node_modules\only-u-bundle'
            New-Item -ItemType Directory -Path (Join-Path $tui 'lib\types\components\sessions') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tui 'lib\types\dsh-adapter\sessions') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $tui 'lib\types\sessions') -Force | Out-Null
            New-Item -ItemType Directory -Path $bundle -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $tui 'package.json'), "{`"name`":`"@deepseek-harness-tui/dsh-tui`",`"version`":`"$Version`"}")
            [IO.File]::WriteAllText((Join-Path $Root 'portable\runtime\dsh\profiles\dsh-tui\package.json'), '{"name":"dsh-profile-dsh-tui","dsh":{"profile":{"bundles":["@deepseek-ai/dsh-base","@deepseek-harness-tui/dsh-tui","only-u-bundle"]}}}')
            $logo = if ($Files.ContainsKey('logo')) { $Files.logo } else { "renderBigText('ONLY-U')" }
            $font = if ($Files.ContainsKey('font')) { $Files.font } else { "O: ['x']`nL: ['x']`nY: ['x']`nU: ['x']`n'-': ['x']" }
            $plugin = if ($Files.ContainsKey('plugin')) { $Files.plugin } else { "if (process.env.DSH_TUI_NO_UPDATE === '1') { return }" }
            $patch = if ($Files.ContainsKey('patch')) { $Files.patch } else { "- insert:`n    - id: only-u-bundle`n      name: 'only-u-bundle'" }
            [IO.File]::WriteAllText((Join-Path $tui 'lib\types\components\LogoV2.js'), $logo)
            [IO.File]::WriteAllText((Join-Path $tui 'lib\types\components\bigfont.js'), $font)
            [IO.File]::WriteAllText((Join-Path $tui 'lib\types\dsh-adapter\plugin.js'), $plugin)
            if (-not $Files.ContainsKey('omitSessions')) {
                [IO.File]::WriteAllText((Join-Path $tui 'lib\types\dsh-adapter\sessions\index.js'), 'export {}')
            }
            if (-not $Files.ContainsKey('omitFormat')) {
                [IO.File]::WriteAllText((Join-Path $tui 'lib\types\sessions\format.js'), 'export {}')
            }
            if (-not $Files.ContainsKey('omitComponentSessions')) {
                [IO.File]::WriteAllText((Join-Path $tui 'lib\types\components\sessions\SessionListRow.js'), 'export {}')
            }
            [IO.File]::WriteAllText((Join-Path $bundle 'cordis.patch.yml'), $patch)
            return $Root
        }
    }

    It 'bake-usb compiles repo TUI and does not clone the live host profile' {
        Assert-True ($BakeUsbText.Contains('Invoke-DshTuiCompile')) 'bake-usb.ps1 does not compile dsh-tui.'
        Assert-True ($BakeUsbText.Contains('Install-DestTuiProfile')) 'bake-usb.ps1 does not install the Dest TUI profile.'
        Assert-True ($BakeUsbText.Contains('plugin --profile dsh-tui add') -or $BakeUsbText.Contains('Install-DestTuiProfile')) 'bake-usb.ps1 does not install plugins onto Dest.'
        Assert-True ($BakeUsbText -notmatch "USERPROFILE.*\.dsh\\profiles\\dsh-tui") 'bake-usb.ps1 still clones the live host profile.'
    }

    It 'Install-DestTuiProfile packs only-u-bundle as a tarball' {
        Assert-True ($BakeTuiText.Contains('npm pack')) 'bake-tui.ps1 does not npm pack only-u-bundle.'
        Assert-True ($BakeTuiText.Contains('.tgz')) 'bake-tui.ps1 does not install a tarball.'
        Assert-True ($BakeTuiText.Contains('/XJ')) 'bake-tui.ps1 does not exclude junctions on FAT32 copy.'
        Assert-True ($BakeTuiText.Contains("Join-Path `$profSrc 'sessions'")) 'robocopy must exclude only the profile sessions dir.'
        Assert-True ($BakeTuiText.Contains('lib\types\sessions')) 'bake-tui.ps1 does not restore types/sessions after robocopy.'
        Assert-True ($BakeTuiText.Contains('lib\types\components\sessions')) 'bake-tui.ps1 does not restore components/sessions after robocopy.'
        $robo = ($BakeTuiText -split "`n" | Where-Object { $_ -match 'robocopy \$profSrc' } | Select-Object -First 1)
        Assert-True (($null -ne $robo) -and ($robo.Trim().Length -gt 0)) 'missing robocopy of baked profile'
        Assert-True ($robo -notmatch '/XD sessions(\s|$)') 'bare /XD sessions would drop dsh-adapter/sessions.'
    }

    It 'bake-usb writes BAKE-ID only after Assert-BakedTui' {
        $assertAt = $BakeUsbText.IndexOf('Assert-BakedTui')
        $bakeIdAt = $BakeUsbText.LastIndexOf('Write-BakeId')
        Assert-True ($assertAt -ge 0) 'bake-usb.ps1 does not call Assert-BakedTui.'
        Assert-True ($bakeIdAt -gt $assertAt) 'BAKE-ID is written before asserts.'
        Assert-True ($BakeUsbText.Contains('Write-BakeId -Repo $Repo -RuntimeDsh $runtimeDsh')) 'bake-usb.ps1 does not write BAKE-ID via Write-BakeId.'
    }

    It 'Assert-BakedTui accepts Dest files Node actually loads' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-ok-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root | Out-Null
            Assert-BakedTui -Dest $root
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects the wrong TUI version' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-ver-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Version '0.9.0' | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'wrong version must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects LogoV2.js without ONLY-U' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-logo-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Files @{ logo = 'renderBigText("DEEPSEEK")' } | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'whale splash LogoV2.js must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects plugin.js without DSH_TUI_NO_UPDATE' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-upd-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Files @{ plugin = 'void checkForTuiUpdate()' } | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'plugin.js without DSH_TUI_NO_UPDATE must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects a profile without the bundle patch' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-patch-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Files @{ patch = '[]' } | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'missing only-u-bundle patch must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects Dest missing dsh-adapter/sessions' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-sess-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Files @{ omitSessions = $true } | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'missing dsh-adapter/sessions/index.js must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'Assert-BakedTui rejects Dest missing types/sessions/format.js' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('only-u-bake-tui-fmt-' + [guid]::NewGuid().ToString('N'))
        try {
            New-FakeDest $root -Files @{ omitFormat = $true } | Out-Null
            $threw = $false
            try { Assert-BakedTui -Dest $root } catch { $threw = $true }
            Assert-True $threw 'missing types/sessions/format.js must throw'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
