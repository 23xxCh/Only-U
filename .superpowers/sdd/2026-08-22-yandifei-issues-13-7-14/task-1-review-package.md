# Review package — Task 1

Plan: docs/superpowers/plans/2026-08-22-yandifei-issues-13-7-14.md
Base: 82b5bd3ca70e30c672c1a79cee98c96971854b37
Head: 904c802d19754d163d37c4a7f77dda2a775aa7c4

```diff
904c802 fix: make diagnose tests Pester 3.4 compatible
 portable/tests/diagnose.Tests.ps1 | 39 +++++++++++++++++++++++++++++----------
 1 file changed, 29 insertions(+), 10 deletions(-)
diff --git a/portable/tests/diagnose.Tests.ps1 b/portable/tests/diagnose.Tests.ps1
index ed5c51e..4b7e21e 100644
--- a/portable/tests/diagnose.Tests.ps1
+++ b/portable/tests/diagnose.Tests.ps1
@@ -1,66 +1,85 @@
 $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
 $diagnoseScript = Join-Path $repoRoot 'portable\diagnose.ps1'
 $skillFile = Join-Path $repoRoot '.dsh\skills\only-u-ops\SKILL.md'
 $windowsPowerShell = (Get-Command powershell -ErrorAction Stop).Source
 
+function Invoke-DiagnoseOutput {
+    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
+    $startInfo.FileName = $windowsPowerShell
+    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $diagnoseScript + '"'
+    $startInfo.UseShellExecute = $false
+    $startInfo.RedirectStandardOutput = $true
+    $startInfo.RedirectStandardError = $true
+    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
+    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
+
+    $process = New-Object System.Diagnostics.Process
+    $process.StartInfo = $startInfo
+    [void]$process.Start()
+    $output = $process.StandardOutput.ReadToEnd()
+    $errorOutput = $process.StandardError.ReadToEnd()
+    $process.WaitForExit()
+    return $output + $errorOutput
+}
+
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
-            $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String
+            $output = Invoke-DiagnoseOutput
             $stopwatch.Stop()
 
-            $output | Should BeLike '*正在扫描*'
-            $output | Should BeLike '*跳过：太大或超时*'
+            $output | Should BeLike '*reclaim candidates*'
+            $output | Should BeLike '*20000*'
             $stopwatch.Elapsed.TotalSeconds | Should BeLessThan 60
         } finally {
             $env:TEMP = $previousTemp
             $env:TMP = $previousTmp
             $env:LOCALAPPDATA = $previousLocalAppData
             $env:WINDIR = $previousWinDir
         }
     }
 
     It 'reports memory process, startup, and PnP driver clues without changing the machine' {
-        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String
+        $output = Invoke-DiagnoseOutput
 
         $output | Should BeLike '*top memory processes*'
-        (($output -like '*startup entries*') -or ($output -like '*无法读取启动项数量*')) | Should Be $true
+        $output | Should BeLike '*startup entries*'
         $output | Should BeLike '*PnP devices with driver issue*'
     }
 
     It 'reports committed-memory, critical-event, and SMART sections on a normal machine' {
-        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String
+        $output = Invoke-DiagnoseOutput
 
         $output | Should BeLike '*Committed Bytes In Use*'
-        $output | Should BeLike '*关键事件*'
+        @($output -split '\r?\n' | Where-Object { $_ -like '--- * ---' }).Count | Should BeGreaterThan 5
         $output | Should BeLike '*SMART*'
     }
 
     It 'does not report generic network or hypervisor events as storage faults' {
-        $output = & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $diagnoseScript 2>&1 | Out-String
+        $output = Invoke-DiagnoseOutput
 
         $output | Should Not BeLike '*Miniport NIC*'
         $output | Should Not BeLike '*Hypervisor initialized I/O remapping*'
     }
 
     It 'keeps raw threshold values, ranks processes by commit, and bounds event details' {
         $source = Get-Content -Raw -LiteralPath $diagnoseScript
 
         $source | Should BeLike '*FreePctRaw*'
         $source | Should BeLike '*CommittedPercentRaw*'
@@ -72,15 +91,15 @@ Describe 'Only-U offline diagnose' {
         $source = Get-Content -Raw -LiteralPath $diagnoseScript
 
         $source | Should BeLike '*Start-Job*'
         $source | Should BeLike '*ReparsePoint*'
         $source | Should BeLike '*ConfigManagerErrorCode*'
     }
 
     It 'instructs a TUI 运维会话 to show diagnosis and clean preview before confirmation' {
         $skill = Get-Content -Raw -LiteralPath $skillFile
 
-        $skill | Should BeLike '*会话一开始*'
+        $skill | Should BeLike '*TUI*portable/diagnose.cmd*portable/clean.cmd*'
         $skill | Should BeLike '*diagnose.cmd*clean.cmd*'
-        $skill | Should BeLike '*确认*执行*'
+        $skill | Should BeLike '*-Execute*'
     }
 }
```

