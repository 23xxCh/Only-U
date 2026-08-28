#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
Describe 'portable start command' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $StartCmd = Join-Path $RepoRoot 'portable\start.cmd'
        $RootWrapper = Join-Path $RepoRoot 'Start-Agent.cmd'
        $EnvExample = Join-Path $RepoRoot 'portable\.env.example'
        $GitIgnore = Join-Path $RepoRoot '.gitignore'
        $Gbk = [System.Text.Encoding]::GetEncoding(936)

        function Assert-True {
            param([bool]$Condition, [string]$Message)
            if (-not $Condition) { throw $Message }
        }

        function Assert-Equal {
            param([object]$Expected, [object]$Actual, [string]$Message)
            if (-not $Expected.Equals($Actual)) { throw "$Message Expected '$Expected', got '$Actual'." }
        }

        function Read-Text {
            param([string]$Path, [System.Text.Encoding]$Encoding)
            [System.IO.File]::ReadAllText($Path, $Encoding)
        }

        function Test-NoBom {
            param([string]$Path)
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        }

        function New-StubNode {
            param([string]$OutputPath)

            $source = @"
using System;
using System.IO;
using System.Text;
using System.Threading;

public static class StubNode
{
    public static int Main(string[] args)
    {
        if (string.Equals(Path.GetFileName(Environment.GetCommandLineArgs()[0]), "powershell.exe", StringComparison.OrdinalIgnoreCase))
        {
            return 7;
        }

        string output = Environment.GetEnvironmentVariable("ONLY_U_TEST_STUB_OUTPUT");
        if (!string.IsNullOrEmpty(output))
        {
            var sb = new StringBuilder();
            sb.AppendLine("ARGS=" + string.Join("|", args));
            sb.AppendLine("DSH_HOME=" + Environment.GetEnvironmentVariable("DSH_HOME"));
            sb.AppendLine("DSH_AGENTS_HOME=" + Environment.GetEnvironmentVariable("DSH_AGENTS_HOME"));
            sb.AppendLine("DEEPSEEK_API_KEY=" + Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY"));
            sb.AppendLine("PATH=" + Environment.GetEnvironmentVariable("PATH"));
            File.WriteAllText(output, sb.ToString(), new UTF8Encoding(false));
        }

        foreach (string arg in args)
        {
            const string readyPrefix = "--only-u-test-ready=";
            if (arg.StartsWith(readyPrefix)) { File.WriteAllText(arg.Substring(readyPrefix.Length), string.Empty); }
        }
        while (Array.IndexOf(args, "--only-u-test-wait") >= 0) { Thread.Sleep(25); }
        return 0;
    }
}
"@

            $frameworkCandidates = @(
                (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319'),
                (Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319')
            )
            $csc = $null
            foreach ($candidate in $frameworkCandidates) {
                $possible = Join-Path $candidate 'csc.exe'
                if (Test-Path -LiteralPath $possible -PathType Leaf) {
                    $csc = $possible
                    break
                }
            }
            if ($null -eq $csc) {
                throw 'Could not locate the .NET Framework C# compiler.'
            }

            $sourcePath = Join-Path (Split-Path -Parent $OutputPath) 'StubNode.cs'
            [System.IO.File]::WriteAllText($sourcePath, $source, [System.Text.Encoding]::UTF8)
            & $csc /nologo /target:exe "/out:$OutputPath" $sourcePath
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to compile the stub Node executable. csc exited with $LASTEXITCODE."
            }
            Remove-Item -LiteralPath $sourcePath -Force
        }

        function ConvertTo-QuotedProcessArgument {
            param([string]$Argument)
            '"' + $Argument.Replace('"', '\"') + '"'
        }

        function Invoke-Capture {
            param([string]$Command, [string]$OutputPath, [switch]$SendNewline)
            if ($SendNewline) {
                $line = "echo. | `"$Command`" > `"$OutputPath`" 2>&1"
            } else {
                $line = "`"$Command`" > `"$OutputPath`" 2>&1"
            }
            cmd /d /c "$line"
            $LASTEXITCODE
        }

        function Invoke-CaptureWithInput {
            param([string]$Command, [string]$OutputPath, [string]$InputLine)
            $line = "echo $InputLine| `"$Command`" > `"$OutputPath`" 2>&1"
            cmd /d /c "$line"
            $LASTEXITCODE
        }
    }

    It 'portable start command exists' {
        Assert-True (Test-Path -LiteralPath $StartCmd -PathType Leaf) 'portable\start.cmd is missing.'
    }

    It 'root wrapper exists' {
        Assert-True (Test-Path -LiteralPath $RootWrapper -PathType Leaf) 'Start-Agent.cmd is missing.'
    }

    It 'portable start command has no UTF-8 BOM' {
        Assert-True (Test-NoBom $StartCmd) 'portable\start.cmd starts with an UTF-8 BOM.'
    }

    It 'root wrapper has no UTF-8 BOM' {
        Assert-True (Test-NoBom $RootWrapper) 'Start-Agent.cmd starts with an UTF-8 BOM.'
    }

    It 'portable start command uses only launcher-relative paths' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text -notmatch '(?i)[FED]:\\') 'portable\start.cmd contains a fixed drive letter.'
        Assert-True ($text.Contains('%~dp0')) 'portable\start.cmd does not use %~dp0.'
    }

    It 'portable start command prepares the baked runtime' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text.Contains('runtime\node\node.exe')) 'portable\start.cmd does not use the baked Node executable.'
        Assert-True ($text.Contains('runtime\dsh\lib\bin.js')) 'portable\start.cmd does not use the baked dsh CLI.'
        Assert-True ($text.Contains('runtime\dsh\profiles\dsh-tui\package.json')) 'portable\start.cmd does not check the dsh-tui profile.'
        Assert-True ($text.Contains('set "PATH=%PORTABLE_DIR%runtime\node;%PATH%"')) 'portable\start.cmd does not prepend the baked Node directory to PATH.'
        Assert-True ($text.Contains('set "DSH_HOME=%PORTABLE_DIR%runtime\dsh"')) 'portable\start.cmd does not set DSH_HOME to the baked dsh directory.'
        Assert-True ($text.Contains('set "DSH_AGENTS_HOME=%PORTABLE_DIR%.agents-home"')) 'portable\start.cmd does not isolate DSH_AGENTS_HOME onto the USB pack.'
        Assert-True ($text -notmatch '(?i)set\s+"USERPROFILE=') 'portable\start.cmd must not redirect USERPROFILE.'
        Assert-True ($text -notmatch '(?i)set\s+"HOME=') 'portable\start.cmd must not redirect HOME.'
        Assert-True ($text.Contains('set "DSH_TUI_NO_UPDATE=1"')) 'portable\start.cmd does not set DSH_TUI_NO_UPDATE=1.'
        Assert-True ($text.Contains('theme copy failed')) 'portable\start.cmd does not echo a visible theme-copy failure.'
        Assert-True ($text.Contains('lib\types\components\LogoV2.js')) 'portable\start.cmd does not compare cache vs USB LogoV2.js.'
    }

    It 'portable start command prompts for an empty Key and points offline users to diagnose.cmd' {
        $text = Read-Text $StartCmd $Gbk
        $keyIndex = $text.IndexOf('set "DEEPSEEK_API_KEY="')
        $promptIndex = $text.IndexOf('set /p DEEPSEEK_API_KEY=')
        $writeIndex = $text.IndexOf('>"%ENV_FILE%" echo DEEPSEEK_API_KEY=%DEEPSEEK_API_KEY%')
        Assert-True ($keyIndex -ge 0) 'portable\start.cmd is missing the Key load.'
        Assert-True ($promptIndex -gt $keyIndex) 'portable\start.cmd must prompt for an empty Key after loading .env.'
        Assert-True ($writeIndex -gt $promptIndex) 'portable\start.cmd must persist a pasted Key to .env.'
        Assert-True ($text.Contains('diagnose.cmd')) 'portable\start.cmd does not point offline users to diagnose.cmd.'
    }

    It 'portable start command launches dsh-tui without pnpm or headless' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text.Contains('--profile dsh-tui')) 'portable\start.cmd does not launch the dsh-tui profile.'
        Assert-True ($text -notmatch '(?i)pnpm') 'portable\start.cmd still references pnpm.'
        Assert-True ($text -notmatch '(?i)headless') 'portable\start.cmd still references the headless profile.'
    }

    It 'portable start command skips ping, CIM, robocopy, and tasklist on this click' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text -notmatch '(?i)\bping\b') 'portable\start.cmd must not ping on the hot path.'
        Assert-True ($text -notmatch '(?i)Get-CimInstance') 'portable\start.cmd must not query CIM on the hot path.'
        Assert-True ($text -notmatch '(?i)Win32_Process') 'portable\start.cmd must not inspect process command lines on the hot path.'
        Assert-True ($text -notmatch '(?i)robocopy "') 'portable\start.cmd must not robocopy on this click.'
        Assert-True ($text -notmatch '(?i)tasklist') 'portable\start.cmd must not use tasklist.'
        Assert-True ($text.Contains('Never robocopy on this click')) 'portable\start.cmd does not document the no-robocopy hot path.'
    }

    It 'portable start command does not use PID-file duplicate tracking' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text -notmatch '(?i)(pidfile|\.pid|ONLY_U_[A-Z_]*PID)') 'portable\start.cmd must not use PID-file duplicate tracking.'
    }

    It 'portable start command handles DeepSeek Key safely' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text.Contains('DEEPSEEK_API_KEY')) 'portable\start.cmd does not handle DEEPSEEK_API_KEY.'
        Assert-True ($text -notmatch 'echo\s+%DEEPSEEK_API_KEY%') 'portable\start.cmd prints the API Key.'
        Assert-True ($text -notmatch '(?i)Authorization') 'portable\start.cmd prints an Authorization header.'
    }

    It 'root wrapper calls the portable start command' {
        $text = Read-Text $RootWrapper $Gbk
        Assert-True ($text.Contains('%~dp0portable\start.cmd')) 'Start-Agent.cmd does not call portable\start.cmd.'
    }

    It 'gitignore protects launcher secrets and runtime' {
        $text = Read-Text $GitIgnore ([System.Text.Encoding]::UTF8)
        foreach ($entry in @('portable/.env', 'portable/runtime/', 'portable/.dsh-home/')) {
            Assert-True ($text.Contains($entry)) ".gitignore is missing $entry."
        }
    }

    It 'environment example contains the expected templates' {
        $text = Read-Text $EnvExample ([System.Text.Encoding]::UTF8)
        Assert-True ($text.Contains('DEEPSEEK_API_KEY=')) '.env.example is missing DEEPSEEK_API_KEY=.'
        Assert-True ($text.Contains('DEEPSEEK_BASE_URL=')) '.env.example is missing DEEPSEEK_BASE_URL=.'
        Assert-True ($text -notmatch 'sk-[A-Za-z0-9]') '.env.example appears to contain a real API Key.'
    }

    Context 'baked runtime launch' {
        BeforeAll {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("only-u portable start tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            $portableDir = Join-Path $tempRoot 'portable'
            New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
            Copy-Item -LiteralPath $StartCmd -Destination (Join-Path $portableDir 'start.cmd')
            Copy-Item -LiteralPath $RootWrapper -Destination (Join-Path $tempRoot 'Start-Agent.cmd')

            $runtimeNodeDir = Join-Path $portableDir 'runtime\node'
            $runtimeDshDir = Join-Path $portableDir 'runtime\dsh'
            $runtimeBinDir = Join-Path $runtimeDshDir 'lib'
            $runtimeProfileDir = Join-Path $runtimeDshDir 'profiles\dsh-tui'
            $nodeExe = Join-Path $runtimeNodeDir 'node.exe'
            $binJs = Join-Path $runtimeBinDir 'bin.js'
            $profileJson = Join-Path $runtimeProfileDir 'package.json'
            $envFile = Join-Path $portableDir '.env'
            $stubOutput = Join-Path $tempRoot 'stub-output.txt'
        }

        It 'fails fast when the baked Node executable is missing' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            $outputFile = Join-Path $tempRoot 'missing-node-output.txt'
            $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            Assert-Equal 1 $exitCode 'Missing node.exe should exit with code 1.'
            Assert-True ($output.Contains('diagnose.cmd')) 'Missing node.exe message should point to diagnose.cmd.'
        }

        It 'fails fast when the baked dsh CLI is missing' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeBinDir -Force | Out-Null
            New-StubNode $nodeExe
            $outputFile = Join-Path $tempRoot 'missing-cli-output.txt'
            $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            Assert-Equal 1 $exitCode 'Missing lib\bin.js should exit with code 1.'
            Assert-True ($output.Contains('diagnose.cmd')) 'Missing lib\bin.js message should point to diagnose.cmd.'
        }

        It 'fails fast when the dsh-tui profile is missing' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeBinDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeProfileDir -Force | Out-Null
            if (Test-Path -LiteralPath $nodeExe) { Remove-Item -LiteralPath $nodeExe -Force }
            New-StubNode $nodeExe
            Set-Content -LiteralPath $binJs -Value '' -Encoding ASCII
            $outputFile = Join-Path $tempRoot 'missing-profile-output.txt'
            $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            Assert-Equal 1 $exitCode 'Missing dsh-tui profile should exit with code 1.'
            Assert-True ($output.Contains('diagnose.cmd')) 'Missing dsh-tui profile message should point to diagnose.cmd.'
        }

        It 'starts the baked dsh-tui runtime when a Key exists' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeBinDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeProfileDir -Force | Out-Null
            if (Test-Path -LiteralPath $nodeExe) { Remove-Item -LiteralPath $nodeExe -Force }
            New-StubNode $nodeExe
            Set-Content -LiteralPath $binJs -Value '' -Encoding ASCII
            Set-Content -LiteralPath $profileJson -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath $envFile -Value "DEEPSEEK_API_KEY=sk-test-key-for-unit-test`r`nDEEPSEEK_BASE_URL=https://example.invalid`r`n" -Encoding ASCII

            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:ONLY_U_TEST_STUB_OUTPUT = $stubOutput
            try {
                $outputFile = Join-Path $tempRoot 'existing-key-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
            }
            finally {
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
            }

            Assert-Equal 0 $exitCode 'Existing Key should start dsh-tui successfully.'
            Assert-True (Test-Path -LiteralPath $stubOutput -PathType Leaf) 'The stub Node executable was not invoked.'

            $stubText = [System.IO.File]::ReadAllText($stubOutput, [System.Text.Encoding]::UTF8)
            $expectedArgs = "$binJs|--profile|dsh-tui"
            Assert-True ($stubText.Contains("ARGS=$expectedArgs")) 'The launcher did not pass the expected arguments to the baked CLI.'
            Assert-True ($stubText.Contains("DSH_HOME=$runtimeDshDir")) 'The launcher did not set DSH_HOME to the baked dsh directory.'
            $expectedAgentsHome = Join-Path $portableDir '.agents-home'
            Assert-True ($stubText.Contains("DSH_AGENTS_HOME=$expectedAgentsHome")) 'The launcher did not isolate DSH_AGENTS_HOME onto the USB pack.'
            Assert-True ($stubText.Contains('DEEPSEEK_API_KEY=sk-test-key-for-unit-test')) 'The launcher did not pass DEEPSEEK_API_KEY from .env.'
            $pathLine = ($stubText -split "`r?`n") | Where-Object { $_ -like 'PATH=*' } | Select-Object -First 1
            Assert-True ($pathLine.StartsWith("PATH=$runtimeNodeDir;")) 'The launcher did not prepend the baked Node directory to PATH.'
        }

        It 'root wrapper starts the portable launcher' {
            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:ONLY_U_TEST_STUB_OUTPUT = $stubOutput
            try {
                $outputFile = Join-Path $tempRoot 'wrapper-output.txt'
                $exitCode = Invoke-Capture (Join-Path $tempRoot 'Start-Agent.cmd') $outputFile
            }
            finally {
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
            }

            Assert-Equal 0 $exitCode 'Start-Agent.cmd should forward success from portable\start.cmd.'
            Assert-True (Test-Path -LiteralPath $stubOutput -PathType Leaf) 'Start-Agent.cmd did not invoke portable\start.cmd.'
        }

        It 'exits when Key is empty after the prompt' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeBinDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeProfileDir -Force | Out-Null
            if (-not (Test-Path -LiteralPath $nodeExe)) { New-StubNode $nodeExe }
            Set-Content -LiteralPath $binJs -Value '' -Encoding ASCII
            Set-Content -LiteralPath $profileJson -Value '{}' -Encoding ASCII
            if (Test-Path -LiteralPath $envFile) { Remove-Item -LiteralPath $envFile -Force }
            $oldKey = $env:DEEPSEEK_API_KEY
            Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
            $outputFile = Join-Path $tempRoot 'empty-key-output.txt'
            try {
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
            }
            finally {
                if ($null -eq $oldKey) { Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue } else { $env:DEEPSEEK_API_KEY = $oldKey }
            }
            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            Assert-Equal 1 $exitCode 'An empty Key should exit with code 1.'
            Assert-True ($output.Contains('diagnose.cmd')) 'An empty Key should point to diagnose.cmd.'
            Assert-True (-not (Test-Path -LiteralPath $envFile)) 'An empty Key must not write .env.'
        }

        It 'writes a pasted Key to .env and starts the TUI' {
            New-Item -ItemType Directory -Path $runtimeNodeDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeBinDir -Force | Out-Null
            New-Item -ItemType Directory -Path $runtimeProfileDir -Force | Out-Null
            if (-not (Test-Path -LiteralPath $nodeExe)) { New-StubNode $nodeExe }
            Set-Content -LiteralPath $binJs -Value '' -Encoding ASCII
            Set-Content -LiteralPath $profileJson -Value '{}' -Encoding ASCII
            if (Test-Path -LiteralPath $envFile) { Remove-Item -LiteralPath $envFile -Force }
            if (Test-Path -LiteralPath $stubOutput) { Remove-Item -LiteralPath $stubOutput -Force }
            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:ONLY_U_TEST_STUB_OUTPUT = $stubOutput
            try {
                $outputFile = Join-Path $tempRoot 'pasted-key-output.txt'
                $exitCode = Invoke-CaptureWithInput (Join-Path $portableDir 'start.cmd') $outputFile 'sk-pasted-key-for-unit-test'
            }
            finally {
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
            }

            Assert-Equal 0 $exitCode 'A pasted Key should start dsh-tui successfully.'
            Assert-True (Test-Path -LiteralPath $envFile -PathType Leaf) 'A pasted Key should create portable\.env.'
            $saved = [System.IO.File]::ReadAllText($envFile)
            Assert-True ($saved.Contains('DEEPSEEK_API_KEY=sk-pasted-key-for-unit-test')) 'portable\.env did not store the pasted Key.'
            Assert-True ($saved.Contains('DEEPSEEK_BASE_URL=https://api.deepseek.com')) 'portable\.env did not store the default base URL.'
            Assert-True (Test-Path -LiteralPath $stubOutput -PathType Leaf) 'A pasted Key should still invoke the baked Node executable.'
            $stubText = [System.IO.File]::ReadAllText($stubOutput, [System.Text.Encoding]::UTF8)
            Assert-True ($stubText.Contains('DEEPSEEK_API_KEY=sk-pasted-key-for-unit-test')) 'The launcher did not pass the pasted Key to the process environment.'
        }

        AfterAll {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    Context 'theme copy and staged boot' {
        BeforeAll {
            $stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("only-u-stage-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        }

        AfterAll {
            if (Test-Path -LiteralPath $stageRoot) {
                Remove-Item -LiteralPath $stageRoot -Recurse -Force
            }
        }

        It 'echoes a theme copy failure and still starts the TUI' {
            $pack = Join-Path $stageRoot 'theme-fail'
            $portableDir = Join-Path $pack 'portable'
            $runtimeNodeDir = Join-Path $portableDir 'runtime\node'
            $runtimeBinDir = Join-Path $portableDir 'runtime\dsh\lib'
            $runtimeProfileDir = Join-Path $portableDir 'runtime\dsh\profiles\dsh-tui'
            $themeDir = Join-Path $portableDir 'themes'
            $fakeUser = Join-Path $pack 'fake-user'
            New-Item -ItemType Directory -Path $runtimeNodeDir, $runtimeBinDir, $runtimeProfileDir, $themeDir, (Join-Path $fakeUser '.dsh-tui') -Force | Out-Null
            Copy-Item -LiteralPath $StartCmd -Destination (Join-Path $portableDir 'start.cmd')
            New-StubNode (Join-Path $runtimeNodeDir 'node.exe')
            Set-Content -LiteralPath (Join-Path $runtimeBinDir 'bin.js') -Value '' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeProfileDir 'package.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $themeDir 'only-u.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $themeDir 'only-u-dark.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $portableDir '.env') -Value "DEEPSEEK_API_KEY=sk-test-key-for-unit-test`r`n" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $fakeUser '.dsh-tui\themes') -Value 'not-a-directory' -Encoding ASCII

            $oldUser = $env:USERPROFILE
            $env:USERPROFILE = $fakeUser
            try {
                $outputFile = Join-Path $pack 'theme-fail-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
                $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            }
            finally {
                $env:USERPROFILE = $oldUser
            }

            Assert-Equal 0 $exitCode 'Theme copy failure must still start the TUI.'
            Assert-True ($output.Contains('theme copy failed')) 'Theme copy failure must be visible.'
        }

        It 'uses USB runtime this click when cache LogoV2.js differs, without robocopy' {
            $pack = Join-Path $stageRoot 'logo-mismatch'
            $portableDir = Join-Path $pack 'portable'
            $runtimeNodeDir = Join-Path $portableDir 'runtime\node'
            $runtimeDshDir = Join-Path $portableDir 'runtime\dsh'
            $runtimeBinDir = Join-Path $runtimeDshDir 'lib'
            $runtimeProfileDir = Join-Path $runtimeDshDir 'profiles\dsh-tui'
            $usbTuiRoot = Join-Path $runtimeProfileDir 'node_modules\@deepseek-harness-tui\dsh-tui'
            $usbTui = Join-Path $usbTuiRoot 'lib\types\components'
            $stubOutput = Join-Path $pack 'stub-output.txt'
            New-Item -ItemType Directory -Path $runtimeNodeDir, $runtimeBinDir, $usbTui -Force | Out-Null
            Copy-Item -LiteralPath $StartCmd -Destination (Join-Path $portableDir 'start.cmd')
            New-StubNode (Join-Path $runtimeNodeDir 'node.exe')
            Set-Content -LiteralPath (Join-Path $runtimeBinDir 'bin.js') -Value '' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeProfileDir 'package.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $usbTuiRoot 'package.json') -Value '{"version":"0.8.8"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $usbTui 'LogoV2.js') -Value "renderBigText('ONLY-U-USB')" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeDshDir 'BAKE-ID') -Value 'bake-test-1' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $portableDir '.env') -Value "DEEPSEEK_API_KEY=sk-test-key-for-unit-test`r`n" -Encoding ASCII

            $localApp = Join-Path $pack 'localapp'
            $cacheRoot = Join-Path $localApp 'Only-U\cache'
            $cacheTuiRoot = Join-Path $cacheRoot 'dsh\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui'
            $cacheTui = Join-Path $cacheTuiRoot 'lib\types\components'
            New-Item -ItemType Directory -Path (Join-Path $cacheRoot 'node'), (Join-Path $cacheRoot 'dsh\lib'), (Join-Path $cacheRoot 'dsh\profiles\dsh-tui'), $cacheTui -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $runtimeNodeDir 'node.exe') -Destination (Join-Path $cacheRoot 'node\node.exe')
            Set-Content -LiteralPath (Join-Path $cacheRoot 'dsh\lib\bin.js') -Value '' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheRoot 'dsh\profiles\dsh-tui\package.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheTuiRoot 'package.json') -Value '{"version":"0.8.8"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheTui 'LogoV2.js') -Value "renderBigText('ONLY-U-STALE')" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheRoot 'BAKE-ID') -Value 'bake-test-1' -Encoding ASCII

            $oldLocal = $env:LOCALAPPDATA
            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:LOCALAPPDATA = $localApp
            $env:ONLY_U_TEST_STUB_OUTPUT = $stubOutput
            try {
                $outputFile = Join-Path $pack 'mismatch-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
            }
            finally {
                $env:LOCALAPPDATA = $oldLocal
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
            }

            Assert-Equal 0 $exitCode 'LogoV2 mismatch should still start from USB this click.'
            $stale = [System.IO.File]::ReadAllText((Join-Path $cacheTui 'LogoV2.js'))
            Assert-True ($stale.Contains('ONLY-U-STALE')) 'Cache LogoV2.js must be left unchanged; no robocopy this click.'
            $stubText = [System.IO.File]::ReadAllText($stubOutput, [System.Text.Encoding]::UTF8)
            $usbBin = Join-Path $runtimeBinDir 'bin.js'
            Assert-True ($stubText.Contains("ARGS=$usbBin|--profile|dsh-tui")) 'LogoV2 mismatch must launch USB bin.js, not the stale cache.'
        }

        It 'uses the local cache node when BAKE-ID and LogoV2.js already match' {
            $pack = Join-Path $stageRoot 'cache-hit'
            $portableDir = Join-Path $pack 'portable'
            $runtimeNodeDir = Join-Path $portableDir 'runtime\node'
            $runtimeDshDir = Join-Path $portableDir 'runtime\dsh'
            $runtimeBinDir = Join-Path $runtimeDshDir 'lib'
            $runtimeProfileDir = Join-Path $runtimeDshDir 'profiles\dsh-tui'
            $usbTuiRoot = Join-Path $runtimeProfileDir 'node_modules\@deepseek-harness-tui\dsh-tui'
            $usbTui = Join-Path $usbTuiRoot 'lib\types\components'
            $stubOutput = Join-Path $pack 'stub-output.txt'
            New-Item -ItemType Directory -Path $runtimeNodeDir, $runtimeBinDir, $usbTui -Force | Out-Null
            Copy-Item -LiteralPath $StartCmd -Destination (Join-Path $portableDir 'start.cmd')
            New-StubNode (Join-Path $runtimeNodeDir 'node.exe')
            Set-Content -LiteralPath (Join-Path $runtimeBinDir 'bin.js') -Value '' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeProfileDir 'package.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $usbTuiRoot 'package.json') -Value '{"version":"0.8.8"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $usbTui 'LogoV2.js') -Value "renderBigText('ONLY-U-USB')" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $runtimeDshDir 'BAKE-ID') -Value 'bake-test-1' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $portableDir '.env') -Value "DEEPSEEK_API_KEY=sk-test-key-for-unit-test`r`n" -Encoding ASCII

            $localApp = Join-Path $pack 'localapp'
            $cacheRoot = Join-Path $localApp 'Only-U\cache'
            $cacheTuiRoot = Join-Path $cacheRoot 'dsh\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui'
            $cacheTui = Join-Path $cacheTuiRoot 'lib\types\components'
            $cacheBin = Join-Path $cacheRoot 'dsh\lib\bin.js'
            New-Item -ItemType Directory -Path (Join-Path $cacheRoot 'node'), (Join-Path $cacheRoot 'dsh\lib'), (Join-Path $cacheRoot 'dsh\profiles\dsh-tui'), $cacheTui -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $runtimeNodeDir 'node.exe') -Destination (Join-Path $cacheRoot 'node\node.exe')
            Set-Content -LiteralPath $cacheBin -Value '' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheRoot 'dsh\profiles\dsh-tui\package.json') -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheTuiRoot 'package.json') -Value '{"version":"0.8.8"}' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheTui 'LogoV2.js') -Value "renderBigText('ONLY-U-USB')" -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $cacheRoot 'BAKE-ID') -Value 'bake-test-1' -Encoding ASCII

            $oldLocal = $env:LOCALAPPDATA
            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:LOCALAPPDATA = $localApp
            $env:ONLY_U_TEST_STUB_OUTPUT = $stubOutput
            try {
                $outputFile = Join-Path $pack 'cache-hit-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
            }
            finally {
                $env:LOCALAPPDATA = $oldLocal
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
            }

            Assert-Equal 0 $exitCode 'Matching cache should start dsh-tui.'
            $stubText = [System.IO.File]::ReadAllText($stubOutput, [System.Text.Encoding]::UTF8)
            Assert-True ($stubText.Contains("ARGS=$cacheBin|--profile|dsh-tui")) 'Matching BAKE-ID and LogoV2.js must launch the cached bin.js.'
        }
    }
}
