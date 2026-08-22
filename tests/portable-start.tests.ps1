#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$StartCmd = Join-Path $RepoRoot 'portable\start.cmd'
$RootWrapper = Join-Path $RepoRoot 'Start-Agent.cmd'
$EnvExample = Join-Path $RepoRoot 'portable\.env.example'
$GitIgnore = Join-Path $RepoRoot '.gitignore'
$Gbk = [System.Text.Encoding]::GetEncoding(936)

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if (-not $Expected.Equals($Actual)) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function It {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS: $Name" -ForegroundColor Green
    }
    catch {
        $script:Failed++
        Write-Host "FAIL: $Name" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    }
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

public static class StubNode
{
    public static int Main(string[] args)
    {
        string output = Environment.GetEnvironmentVariable("ONLY_U_TEST_STUB_OUTPUT");
        if (string.IsNullOrEmpty(output)) { return 0; }

        var sb = new StringBuilder();
        sb.AppendLine("ARGS=" + string.Join("|", args));
        sb.AppendLine("DSH_HOME=" + Environment.GetEnvironmentVariable("DSH_HOME"));
        sb.AppendLine("DEEPSEEK_API_KEY=" + Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY"));
        sb.AppendLine("PATH=" + Environment.GetEnvironmentVariable("PATH"));
        File.WriteAllText(output, sb.ToString(), new UTF8Encoding(false));
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
}

It 'portable start command launches dsh-tui without pnpm or headless' {
    $text = Read-Text $StartCmd $Gbk
    Assert-True ($text.Contains('--profile dsh-tui')) 'portable\start.cmd does not launch the dsh-tui profile.'
    Assert-True ($text -notmatch '(?i)pnpm') 'portable\start.cmd still references pnpm.'
    Assert-True ($text -notmatch '(?i)headless') 'portable\start.cmd still references the headless profile.'
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("only-u-portable-start-tests-" + [guid]::NewGuid().ToString('N'))
try {
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
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($script:Failed -gt 0) {
    Write-Host ''
    Write-Host "Portable start tests: $($script:Passed) passed, $($script:Failed) failed." -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "Portable start tests: $($script:Passed) passed, 0 failed." -ForegroundColor Green
exit 0