# Review package — Task 3

Plan: docs/superpowers/plans/2026-08-22-yandifei-issues-13-7-14.md
Base: 483f47b9dda26ac4f70df0b938cab9e8fd465b4f
Head: 20abe365c1e2605e9a73cc3bcc7b922868ad51eb

```diff
20abe36 fix: guard against duplicate DSH TUI launch
 portable/start.cmd             |  8 +++++
 tests/portable-start.tests.ps1 | 72 ++++++++++++++++++++++++++++++++++++------
 2 files changed, 71 insertions(+), 9 deletions(-)
diff --git a/portable/start.cmd b/portable/start.cmd
index ae42db2..7306ea2 100644
--- a/portable/start.cmd
+++ b/portable/start.cmd
@@ -71,20 +71,28 @@ set "ONLY_U_ENV_FILE=%ENV_FILE%"
 powershell -NoProfile -ExecutionPolicy Bypass -Command "$path = $env:ONLY_U_ENV_FILE; $key = $env:DEEPSEEK_API_KEY; $lines = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllLines($path) } else { @() }; $found = $false; for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match '^[ \t]*DEEPSEEK_API_KEY[ \t]*=') { $lines[$i] = 'DEEPSEEK_API_KEY=' + $key; $found = $true } }; if (-not $found) { $lines += 'DEEPSEEK_API_KEY=' + $key }; $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllLines($path, $lines, $utf8NoBom)"
 if errorlevel 1 (
   echo д�� portable\.env ʧ�ܣ��޷����� Only-U��
   echo �������� portable\diagnose.cmd ��� U �̰���
   echo.
   pause
   exit /b 1
 )
 
 :start
+set "ONLY_U_DSH_BIN=%DSH_BIN%"
+powershell -NoProfile -ExecutionPolicy Bypass -Command "$target = $env:ONLY_U_DSH_BIN; try { $existing = Get-CimInstance -ClassName Win32_Process -Filter 'Name = ''node.exe''' -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1; if ($null -ne $existing) { exit 1 } } catch { exit 0 }"
+if errorlevel 1 (
+  echo DSH TUI �������С���ر����д��ڣ���������������н��������� node.exe �����ԡ�
+  echo.
+  pause
+  exit /b 1
+)
 echo �������� Only-U ��ά�Ự...
 "%NODE_EXE%" "%DSH_BIN%" --profile dsh-tui
 set "START_EXIT=%ERRORLEVEL%"
 if not "%START_EXIT%"=="0" (
   echo TUI ����ʧ�ܣ��˳��� %START_EXIT%����
   echo �������� portable\diagnose.cmd ��� U �̰���
   echo.
   pause
 )
 exit /b %START_EXIT%
diff --git a/tests/portable-start.tests.ps1 b/tests/portable-start.tests.ps1
index 9a23d58..a1dd7dc 100644
--- a/tests/portable-start.tests.ps1
+++ b/tests/portable-start.tests.ps1
@@ -47,34 +47,43 @@ function Test-NoBom {
     -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
 }
 
 function New-StubNode {
     param([string]$OutputPath)
 
     $source = @"
 using System;
 using System.IO;
 using System.Text;
+using System.Threading;
 
 public static class StubNode
 {
     public static int Main(string[] args)
     {
         string output = Environment.GetEnvironmentVariable("ONLY_U_TEST_STUB_OUTPUT");
-        if (string.IsNullOrEmpty(output)) { return 0; }
-
-        var sb = new StringBuilder();
-        sb.AppendLine("ARGS=" + string.Join("|", args));
-        sb.AppendLine("DSH_HOME=" + Environment.GetEnvironmentVariable("DSH_HOME"));
-        sb.AppendLine("DEEPSEEK_API_KEY=" + Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY"));
-        sb.AppendLine("PATH=" + Environment.GetEnvironmentVariable("PATH"));
-        File.WriteAllText(output, sb.ToString(), new UTF8Encoding(false));
+        if (!string.IsNullOrEmpty(output))
+        {
+            var sb = new StringBuilder();
+            sb.AppendLine("ARGS=" + string.Join("|", args));
+            sb.AppendLine("DSH_HOME=" + Environment.GetEnvironmentVariable("DSH_HOME"));
+            sb.AppendLine("DEEPSEEK_API_KEY=" + Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY"));
+            sb.AppendLine("PATH=" + Environment.GetEnvironmentVariable("PATH"));
+            File.WriteAllText(output, sb.ToString(), new UTF8Encoding(false));
+        }
+
+        foreach (string arg in args)
+        {
+            const string readyPrefix = "--only-u-test-ready=";
+            if (arg.StartsWith(readyPrefix)) { File.WriteAllText(arg.Substring(readyPrefix.Length), string.Empty); }
+        }
+        while (Array.IndexOf(args, "--only-u-test-wait") >= 0) { Thread.Sleep(25); }
         return 0;
     }
 }
 "@
 
     $frameworkCandidates = @(
         (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319'),
         (Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319')
     )
     $csc = $null
@@ -149,20 +158,36 @@ It 'portable start command performs an offline preflight before the Key check' {
     Assert-True ($text.Contains('diagnose.cmd')) 'portable\start.cmd does not point offline users to diagnose.cmd.'
 }
 
 It 'portable start command launches dsh-tui without pnpm or headless' {
     $text = Read-Text $StartCmd $Gbk
     Assert-True ($text.Contains('--profile dsh-tui')) 'portable\start.cmd does not launch the dsh-tui profile.'
     Assert-True ($text -notmatch '(?i)pnpm') 'portable\start.cmd still references pnpm.'
     Assert-True ($text -notmatch '(?i)headless') 'portable\start.cmd still references the headless profile.'
 }
 
+It 'portable start command inspects node command lines for an exact DSH launcher match' {
+    $text = Read-Text $StartCmd $Gbk
+    Assert-True ($text.Contains('Get-CimInstance -ClassName Win32_Process')) 'portable\start.cmd does not query Windows process command lines through CIM.'
+    Assert-True ($text.Contains('CommandLine')) 'portable\start.cmd does not inspect process command lines.'
+    Assert-True ($text.Contains('set "ONLY_U_DSH_BIN=%DSH_BIN%"')) 'portable\start.cmd does not compare process command lines with the launcher exact DSH path.'
+    Assert-True ($text.Contains("-Filter 'Name = ''node.exe'''")) 'portable\start.cmd does not limit duplicate inspection to node.exe processes.'
+    Assert-True ($text -notmatch '(?i)tasklist') 'portable\start.cmd must not use tasklist for command-line duplicate detection.'
+    $closeExistingWindow = -join [char[]]@(0x8BF7, 0x5173, 0x95ED, 0x73B0, 0x6709, 0x7A97, 0x53E3)
+    Assert-True ($text.Contains($closeExistingWindow)) 'portable\start.cmd does not tell the user how to close the existing TUI.'
+}
+
+It 'portable start command does not use PID-file duplicate tracking' {
+    $text = Read-Text $StartCmd $Gbk
+    Assert-True ($text -notmatch '(?i)(pidfile|\.pid|ONLY_U_[A-Z_]*PID)') 'portable\start.cmd must not use PID-file duplicate tracking.'
+}
+
 It 'portable start command handles DeepSeek Key safely' {
     $text = Read-Text $StartCmd $Gbk
     Assert-True ($text.Contains('DEEPSEEK_API_KEY')) 'portable\start.cmd does not handle DEEPSEEK_API_KEY.'
     Assert-True ($text -notmatch 'echo\s+%DEEPSEEK_API_KEY%') 'portable\start.cmd prints the API Key.'
     Assert-True ($text -notmatch '(?i)Authorization') 'portable\start.cmd prints an Authorization header.'
 }
 
 It 'root wrapper calls the portable start command' {
     $text = Read-Text $RootWrapper $Gbk
     Assert-True ($text.Contains('%~dp0portable\start.cmd')) 'Start-Agent.cmd does not call portable\start.cmd.'
@@ -273,26 +298,55 @@ try {
             $outputFile = Join-Path $tempRoot 'wrapper-output.txt'
             $exitCode = Invoke-Capture (Join-Path $tempRoot 'Start-Agent.cmd') $outputFile
         }
         finally {
             $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
         }
 
         Assert-Equal 0 $exitCode 'Start-Agent.cmd should forward success from portable\start.cmd.'
         Assert-True (Test-Path -LiteralPath $stubOutput -PathType Leaf) 'Start-Agent.cmd did not invoke portable\start.cmd.'
     }
+
+    It 'blocks a second launcher when its DSH TUI command line is already running' {
+        $fakeReadyFile = Join-Path $tempRoot 'duplicate-node-ready.txt'
+        $fakeNode = $null
+
+        try {
+            $fakeNode = Start-Process -FilePath $nodeExe -ArgumentList @($binJs, '--profile', 'dsh-tui', "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') -PassThru
+            $deadline = [DateTime]::UtcNow.AddSeconds(5)
+            while (-not (Test-Path -LiteralPath $fakeReadyFile) -and [DateTime]::UtcNow -lt $deadline) {
+                Start-Sleep -Milliseconds 25
+            }
+            Assert-True (Test-Path -LiteralPath $fakeReadyFile -PathType Leaf) 'The duplicate-test fake node.exe did not start.'
+
+            $outputFile = Join-Path $tempRoot 'duplicate-tui-output.txt'
+            $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
+            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
+            Assert-True ($exitCode -ne 0) 'A duplicate DSH TUI launcher should exit with a nonzero code.'
+            Assert-True ($output.Contains('DSH TUI')) 'Duplicate DSH TUI launcher should explain that DSH TUI is already running.'
+        }
+        finally {
+            if ($null -ne $fakeNode) {
+                $fakeNode.Refresh()
+                if (-not $fakeNode.HasExited) {
+                    Stop-Process -Id $fakeNode.Id -Force
+                    $fakeNode.WaitForExit()
+                }
+            }
+        }
+    }
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
-exit 0
\ No newline at end of file
+exit 0
```

