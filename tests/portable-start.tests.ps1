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
            cmd /d /c $line
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
    }

    It 'portable start command performs an offline preflight before the Key check' {
        $text = Read-Text $StartCmd $Gbk
        $networkIndex = $text.IndexOf('ping -n 1 -w 2000 223.5.5.5')
        $keyIndex = $text.IndexOf('set "DEEPSEEK_API_KEY="')
        Assert-True ($networkIndex -ge 0) 'portable\start.cmd is missing the ping offline preflight.'
        Assert-True ($keyIndex -gt $networkIndex) 'portable\start.cmd must run the offline preflight before the Key check.'
        Assert-True ($text.Contains('diagnose.cmd')) 'portable\start.cmd does not point offline users to diagnose.cmd.'
    }

    It 'portable start command launches dsh-tui without pnpm or headless' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text.Contains('--profile dsh-tui')) 'portable\start.cmd does not launch the dsh-tui profile.'
        Assert-True ($text -notmatch '(?i)pnpm') 'portable\start.cmd still references pnpm.'
        Assert-True ($text -notmatch '(?i)headless') 'portable\start.cmd still references the headless profile.'
    }

    It 'portable start command inspects node command lines for an exact DSH launcher match' {
        $text = Read-Text $StartCmd $Gbk
        Assert-True ($text.Contains('Get-CimInstance -ClassName Win32_Process')) 'portable\start.cmd does not query Windows process command lines through CIM.'
        Assert-True ($text.Contains('CommandLine')) 'portable\start.cmd does not inspect process command lines.'
        Assert-True ($text.Contains('set "ONLY_U_DSH_BIN=%RUN_BIN%"')) 'portable\start.cmd does not compare process command lines with the launcher exact DSH path.'
        Assert-True ($text.Contains("-Filter 'Name = ''node.exe'''")) 'portable\start.cmd does not limit duplicate inspection to node.exe processes.'
        Assert-True ($text -notmatch '(?i)tasklist') 'portable\start.cmd must not use tasklist for command-line duplicate detection.'
        Assert-True ($text.Contains('exit 42')) 'portable\start.cmd does not use a dedicated duplicate-match exit code.'
        Assert-True ($text.Contains('set "DSH_GUARD_EXIT=%ERRORLEVEL%"')) 'portable\start.cmd does not capture the duplicate-query exit code immediately.'
        Assert-True ($text.Contains('if "%DSH_GUARD_EXIT%"=="42"')) 'portable\start.cmd does not block only the dedicated duplicate-match exit code.'
        $alreadyRunning = 'DSH TUI ' + (-join [char[]]@(0x5DF2, 0x5728, 0x8FD0, 0x884C))
        $recoveryGuidance = -join [char[]]@(0x8BF7, 0x5173, 0x95ED, 0x90A3, 0x4E2A, 0x7A97, 0x53E3, 0xFF08, 0x6216, 0x7ED3, 0x675F, 0x5176, 0x4E2D, 0x7684, 0x20, 0x6E, 0x6F, 0x64, 0x65, 0x2E, 0x65, 0x78, 0x65, 0xFF09, 0x518D, 0x8BD5, 0x3002)
        Assert-True ($text.Contains($alreadyRunning)) 'portable\start.cmd does not say that DSH TUI is already running.'
        Assert-True ($text.Contains($recoveryGuidance)) 'portable\start.cmd does not give the full Task Manager recovery guidance.'
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

        It 'continues normal launch when the duplicate-process query fails' {
            $fakePowerShell = Join-Path $runtimeNodeDir 'powershell.exe'
            $queryFailureOutput = Join-Path $tempRoot 'query-failure-output.txt'
            New-StubNode $fakePowerShell

            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
            $env:ONLY_U_TEST_STUB_OUTPUT = $queryFailureOutput
            try {
                $outputFile = Join-Path $tempRoot 'query-failure-launcher-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
                $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
            }
            finally {
                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
                if (Test-Path -LiteralPath $fakePowerShell) { Remove-Item -LiteralPath $fakePowerShell -Force }
            }

            Assert-Equal 0 $exitCode 'A failed duplicate-process query should fail open and launch dsh-tui.'
            Assert-True (Test-Path -LiteralPath $queryFailureOutput -PathType Leaf) 'A failed duplicate-process query should still invoke the baked Node executable.'
            Assert-True ($output -notmatch 'DSH TUI') 'A failed duplicate-process query must not show the duplicate-TUI block.'
        }

        It 'does not block an unrelated node command line' {
            $unrelatedScript = Join-Path $runtimeBinDir 'unrelated.js'
            $fakeReadyFile = Join-Path $tempRoot 'unrelated-node-ready.txt'
            $unrelatedOutput = Join-Path $tempRoot 'unrelated-node-launch-output.txt'
            $unrelatedNode = $null
            Set-Content -LiteralPath $unrelatedScript -Value '' -Encoding ASCII

            try {
                $fakeArguments = @($unrelatedScript, "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }
                $unrelatedNode = Start-Process -FilePath $nodeExe -ArgumentList $fakeArguments -PassThru
                $deadline = [DateTime]::UtcNow.AddSeconds(5)
                while (-not (Test-Path -LiteralPath $fakeReadyFile) -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 25
                }
                Assert-True (Test-Path -LiteralPath $fakeReadyFile -PathType Leaf) 'The unrelated fake node.exe did not start.'

                $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
                $env:ONLY_U_TEST_STUB_OUTPUT = $unrelatedOutput
                try {
                    $outputFile = Join-Path $tempRoot 'unrelated-node-launcher-output.txt'
                    $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
                }
                finally {
                    $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
                }
            }
            finally {
                if ($null -ne $unrelatedNode) {
                    $unrelatedNode.Refresh()
                    if (-not $unrelatedNode.HasExited) {
                        Stop-Process -Id $unrelatedNode.Id -Force
                        $unrelatedNode.WaitForExit()
                    }
                }
            }

            Assert-Equal 0 $exitCode 'An unrelated node.exe command line should not block dsh-tui.'
            Assert-True (Test-Path -LiteralPath $unrelatedOutput -PathType Leaf) 'An unrelated node.exe command line should still launch the baked Node executable.'
        }

        It 'blocks a second launcher when its DSH TUI command line is already running' {
            $fakeReadyFile = Join-Path $tempRoot 'duplicate-node-ready.txt'
            $fakeNode = $null

            try {
                $fakeArguments = @($binJs, '--profile', 'dsh-tui', "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }
                $fakeNode = Start-Process -FilePath $nodeExe -ArgumentList $fakeArguments -PassThru
                $deadline = [DateTime]::UtcNow.AddSeconds(5)
                while (-not (Test-Path -LiteralPath $fakeReadyFile) -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 25
                }
                Assert-True (Test-Path -LiteralPath $fakeReadyFile -PathType Leaf) 'The duplicate-test fake node.exe did not start.'

                $outputFile = Join-Path $tempRoot 'duplicate-tui-output.txt'
                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
                $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
                Assert-True ($exitCode -ne 0) 'A duplicate DSH TUI launcher should exit with a nonzero code.'
                Assert-True ($output.Contains('DSH TUI')) 'Duplicate DSH TUI launcher should explain that DSH TUI is already running.'
            }
            finally {
                if ($null -ne $fakeNode) {
                    $fakeNode.Refresh()
                    if (-not $fakeNode.HasExited) {
                        Stop-Process -Id $fakeNode.Id -Force
                        $fakeNode.WaitForExit()
                    }
                }
            }
        }

        AfterAll {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
