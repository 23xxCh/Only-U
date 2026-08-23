# Re-review package — Task 3, fix round 1

Open findings to assess:
1. Only a positive exact DSH command-line match blocks; all query/tool failures fail open.
2. Fake-node process arguments are reliable in paths with spaces.
3. Tests cover full recovery guidance and unrelated node nonblocking.

```diff
57e9bfc fix: fail open when TUI guard query fails
 portable/start.cmd             |  5 ++-
 tests/portable-start.tests.ps1 | 86 ++++++++++++++++++++++++++++++++++++++++--
 2 files changed, 85 insertions(+), 6 deletions(-)
diff --git a/portable/start.cmd b/portable/start.cmd
index 7306ea2..5019282 100644
--- a/portable/start.cmd
+++ b/portable/start.cmd
@@ -72,22 +72,23 @@ powershell -NoProfile -ExecutionPolicy Bypass -Command "$path = $env:ONLY_U_ENV_
 if errorlevel 1 (
   echo д�� portable\.env ʧ�ܣ��޷����� Only-U��
   echo �������� portable\diagnose.cmd ��� U �̰���
   echo.
   pause
   exit /b 1
 )
 
 :start
 set "ONLY_U_DSH_BIN=%DSH_BIN%"
-powershell -NoProfile -ExecutionPolicy Bypass -Command "$target = $env:ONLY_U_DSH_BIN; try { $existing = Get-CimInstance -ClassName Win32_Process -Filter 'Name = ''node.exe''' -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1; if ($null -ne $existing) { exit 1 } } catch { exit 0 }"
-if errorlevel 1 (
+powershell -NoProfile -ExecutionPolicy Bypass -Command "$target = $env:ONLY_U_DSH_BIN; try { $existing = Get-CimInstance -ClassName Win32_Process -Filter 'Name = ''node.exe''' -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1; if ($null -ne $existing) { exit 42 } } catch { exit 0 }"
+set "DSH_GUARD_EXIT=%ERRORLEVEL%"
+if "%DSH_GUARD_EXIT%"=="42" (
   echo DSH TUI �������С���ر����д��ڣ���������������н��������� node.exe �����ԡ�
   echo.
   pause
   exit /b 1
 )
 echo �������� Only-U ��ά�Ự...
 "%NODE_EXE%" "%DSH_BIN%" --profile dsh-tui
 set "START_EXIT=%ERRORLEVEL%"
 if not "%START_EXIT%"=="0" (
   echo TUI ����ʧ�ܣ��˳��� %START_EXIT%����
diff --git a/tests/portable-start.tests.ps1 b/tests/portable-start.tests.ps1
index a1dd7dc..d44eb53 100644
--- a/tests/portable-start.tests.ps1
+++ b/tests/portable-start.tests.ps1
@@ -53,20 +53,25 @@ function New-StubNode {
     $source = @"
 using System;
 using System.IO;
 using System.Text;
 using System.Threading;
 
 public static class StubNode
 {
     public static int Main(string[] args)
     {
+        if (string.Equals(Path.GetFileName(Environment.GetCommandLineArgs()[0]), "powershell.exe", StringComparison.OrdinalIgnoreCase))
+        {
+            return 7;
+        }
+
         string output = Environment.GetEnvironmentVariable("ONLY_U_TEST_STUB_OUTPUT");
         if (!string.IsNullOrEmpty(output))
         {
             var sb = new StringBuilder();
             sb.AppendLine("ARGS=" + string.Join("|", args));
             sb.AppendLine("DSH_HOME=" + Environment.GetEnvironmentVariable("DSH_HOME"));
             sb.AppendLine("DEEPSEEK_API_KEY=" + Environment.GetEnvironmentVariable("DEEPSEEK_API_KEY"));
             sb.AppendLine("PATH=" + Environment.GetEnvironmentVariable("PATH"));
             File.WriteAllText(output, sb.ToString(), new UTF8Encoding(false));
         }
@@ -100,20 +105,25 @@ public static class StubNode
 
     $sourcePath = Join-Path (Split-Path -Parent $OutputPath) 'StubNode.cs'
     [System.IO.File]::WriteAllText($sourcePath, $source, [System.Text.Encoding]::UTF8)
     & $csc /nologo /target:exe "/out:$OutputPath" $sourcePath
     if ($LASTEXITCODE -ne 0) {
         throw "Failed to compile the stub Node executable. csc exited with $LASTEXITCODE."
     }
     Remove-Item -LiteralPath $sourcePath -Force
 }
 
+function ConvertTo-QuotedProcessArgument {
+    param([string]$Argument)
+    '"' + $Argument.Replace('"', '\"') + '"'
+}
+
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
@@ -165,22 +175,27 @@ It 'portable start command launches dsh-tui without pnpm or headless' {
     Assert-True ($text -notmatch '(?i)headless') 'portable\start.cmd still references the headless profile.'
 }
 
 It 'portable start command inspects node command lines for an exact DSH launcher match' {
     $text = Read-Text $StartCmd $Gbk
     Assert-True ($text.Contains('Get-CimInstance -ClassName Win32_Process')) 'portable\start.cmd does not query Windows process command lines through CIM.'
     Assert-True ($text.Contains('CommandLine')) 'portable\start.cmd does not inspect process command lines.'
     Assert-True ($text.Contains('set "ONLY_U_DSH_BIN=%DSH_BIN%"')) 'portable\start.cmd does not compare process command lines with the launcher exact DSH path.'
     Assert-True ($text.Contains("-Filter 'Name = ''node.exe'''")) 'portable\start.cmd does not limit duplicate inspection to node.exe processes.'
     Assert-True ($text -notmatch '(?i)tasklist') 'portable\start.cmd must not use tasklist for command-line duplicate detection.'
-    $closeExistingWindow = -join [char[]]@(0x8BF7, 0x5173, 0x95ED, 0x73B0, 0x6709, 0x7A97, 0x53E3)
-    Assert-True ($text.Contains($closeExistingWindow)) 'portable\start.cmd does not tell the user how to close the existing TUI.'
+    Assert-True ($text.Contains('exit 42')) 'portable\start.cmd does not use a dedicated duplicate-match exit code.'
+    Assert-True ($text.Contains('set "DSH_GUARD_EXIT=%ERRORLEVEL%"')) 'portable\start.cmd does not capture the duplicate-query exit code immediately.'
+    Assert-True ($text.Contains('if "%DSH_GUARD_EXIT%"=="42"')) 'portable\start.cmd does not block only the dedicated duplicate-match exit code.'
+    $alreadyRunning = 'DSH TUI ' + (-join [char[]]@(0x5DF2, 0x5728, 0x8FD0, 0x884C))
+    $recoveryGuidance = -join [char[]]@(0x8BF7, 0x5173, 0x95ED, 0x73B0, 0x6709, 0x7A97, 0x53E3, 0xFF0C, 0x6216, 0x5728, 0x4EFB, 0x52A1, 0x7BA1, 0x7406, 0x5668, 0x4E2D, 0x7ED3, 0x675F, 0x6B8B, 0x7559, 0x7684, 0x20, 0x6E, 0x6F, 0x64, 0x65, 0x2E, 0x65, 0x78, 0x65, 0x20, 0x540E, 0x91CD, 0x8BD5, 0x3002)
+    Assert-True ($text.Contains($alreadyRunning)) 'portable\start.cmd does not say that DSH TUI is already running.'
+    Assert-True ($text.Contains($recoveryGuidance)) 'portable\start.cmd does not give the full Task Manager recovery guidance.'
 }
 
 It 'portable start command does not use PID-file duplicate tracking' {
     $text = Read-Text $StartCmd $Gbk
     Assert-True ($text -notmatch '(?i)(pidfile|\.pid|ONLY_U_[A-Z_]*PID)') 'portable\start.cmd must not use PID-file duplicate tracking.'
 }
 
 It 'portable start command handles DeepSeek Key safely' {
     $text = Read-Text $StartCmd $Gbk
     Assert-True ($text.Contains('DEEPSEEK_API_KEY')) 'portable\start.cmd does not handle DEEPSEEK_API_KEY.'
@@ -200,21 +215,21 @@ It 'gitignore protects launcher secrets and runtime' {
     }
 }
 
 It 'environment example contains the expected templates' {
     $text = Read-Text $EnvExample ([System.Text.Encoding]::UTF8)
     Assert-True ($text.Contains('DEEPSEEK_API_KEY=')) '.env.example is missing DEEPSEEK_API_KEY=.'
     Assert-True ($text.Contains('DEEPSEEK_BASE_URL=')) '.env.example is missing DEEPSEEK_BASE_URL=.'
     Assert-True ($text -notmatch 'sk-[A-Za-z0-9]') '.env.example appears to contain a real API Key.'
 }
 
-$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("only-u-portable-start-tests-" + [guid]::NewGuid().ToString('N'))
+$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("only-u portable start tests-" + [guid]::NewGuid().ToString('N'))
 try {
     New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
     $portableDir = Join-Path $tempRoot 'portable'
     New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
     Copy-Item -LiteralPath $StartCmd -Destination (Join-Path $portableDir 'start.cmd')
     Copy-Item -LiteralPath $RootWrapper -Destination (Join-Path $tempRoot 'Start-Agent.cmd')
 
     $runtimeNodeDir = Join-Path $portableDir 'runtime\node'
     $runtimeDshDir = Join-Path $portableDir 'runtime\dsh'
     $runtimeBinDir = Join-Path $runtimeDshDir 'lib'
@@ -299,26 +314,89 @@ try {
             $exitCode = Invoke-Capture (Join-Path $tempRoot 'Start-Agent.cmd') $outputFile
         }
         finally {
             $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
         }
 
         Assert-Equal 0 $exitCode 'Start-Agent.cmd should forward success from portable\start.cmd.'
         Assert-True (Test-Path -LiteralPath $stubOutput -PathType Leaf) 'Start-Agent.cmd did not invoke portable\start.cmd.'
     }
 
+    It 'continues normal launch when the duplicate-process query fails' {
+        $fakePowerShell = Join-Path $runtimeNodeDir 'powershell.exe'
+        $queryFailureOutput = Join-Path $tempRoot 'query-failure-output.txt'
+        New-StubNode $fakePowerShell
+
+        $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
+        $env:ONLY_U_TEST_STUB_OUTPUT = $queryFailureOutput
+        try {
+            $outputFile = Join-Path $tempRoot 'query-failure-launcher-output.txt'
+            $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
+            $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
+        }
+        finally {
+            $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
+            if (Test-Path -LiteralPath $fakePowerShell) { Remove-Item -LiteralPath $fakePowerShell -Force }
+        }
+
+        Assert-Equal 0 $exitCode 'A failed duplicate-process query should fail open and launch dsh-tui.'
+        Assert-True (Test-Path -LiteralPath $queryFailureOutput -PathType Leaf) 'A failed duplicate-process query should still invoke the baked Node executable.'
+        Assert-True ($output -notmatch 'DSH TUI') 'A failed duplicate-process query must not show the duplicate-TUI block.'
+    }
+
+    It 'does not block an unrelated node command line' {
+        $unrelatedScript = Join-Path $runtimeBinDir 'unrelated.js'
+        $fakeReadyFile = Join-Path $tempRoot 'unrelated-node-ready.txt'
+        $unrelatedOutput = Join-Path $tempRoot 'unrelated-node-launch-output.txt'
+        $unrelatedNode = $null
+        Set-Content -LiteralPath $unrelatedScript -Value '' -Encoding ASCII
+
+        try {
+            $fakeArguments = @($unrelatedScript, "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }
+            $unrelatedNode = Start-Process -FilePath $nodeExe -ArgumentList $fakeArguments -PassThru
+            $deadline = [DateTime]::UtcNow.AddSeconds(5)
+            while (-not (Test-Path -LiteralPath $fakeReadyFile) -and [DateTime]::UtcNow -lt $deadline) {
+                Start-Sleep -Milliseconds 25
+            }
+            Assert-True (Test-Path -LiteralPath $fakeReadyFile -PathType Leaf) 'The unrelated fake node.exe did not start.'
+
+            $oldOutput = $env:ONLY_U_TEST_STUB_OUTPUT
+            $env:ONLY_U_TEST_STUB_OUTPUT = $unrelatedOutput
+            try {
+                $outputFile = Join-Path $tempRoot 'unrelated-node-launcher-output.txt'
+                $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile
+            }
+            finally {
+                $env:ONLY_U_TEST_STUB_OUTPUT = $oldOutput
+            }
+        }
+        finally {
+            if ($null -ne $unrelatedNode) {
+                $unrelatedNode.Refresh()
+                if (-not $unrelatedNode.HasExited) {
+                    Stop-Process -Id $unrelatedNode.Id -Force
+                    $unrelatedNode.WaitForExit()
+                }
+            }
+        }
+
+        Assert-Equal 0 $exitCode 'An unrelated node.exe command line should not block dsh-tui.'
+        Assert-True (Test-Path -LiteralPath $unrelatedOutput -PathType Leaf) 'An unrelated node.exe command line should still launch the baked Node executable.'
+    }
+
     It 'blocks a second launcher when its DSH TUI command line is already running' {
         $fakeReadyFile = Join-Path $tempRoot 'duplicate-node-ready.txt'
         $fakeNode = $null
 
         try {
-            $fakeNode = Start-Process -FilePath $nodeExe -ArgumentList @($binJs, '--profile', 'dsh-tui', "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') -PassThru
+            $fakeArguments = @($binJs, '--profile', 'dsh-tui', "--only-u-test-ready=$fakeReadyFile", '--only-u-test-wait') | ForEach-Object { ConvertTo-QuotedProcessArgument $_ }
+            $fakeNode = Start-Process -FilePath $nodeExe -ArgumentList $fakeArguments -PassThru
             $deadline = [DateTime]::UtcNow.AddSeconds(5)
             while (-not (Test-Path -LiteralPath $fakeReadyFile) -and [DateTime]::UtcNow -lt $deadline) {
                 Start-Sleep -Milliseconds 25
             }
             Assert-True (Test-Path -LiteralPath $fakeReadyFile -PathType Leaf) 'The duplicate-test fake node.exe did not start.'
 
             $outputFile = Join-Path $tempRoot 'duplicate-tui-output.txt'
             $exitCode = Invoke-Capture (Join-Path $portableDir 'start.cmd') $outputFile -SendNewline
             $output = [System.IO.File]::ReadAllText($outputFile, $Gbk)
             Assert-True ($exitCode -ne 0) 'A duplicate DSH TUI launcher should exit with a nonzero code.'
```

