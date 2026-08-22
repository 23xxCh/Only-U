# Bake a host-independent Only-U USB pack.
# Run on a dev machine that already has: pnpm, built dsh/, profile dsh-tui.
# Usage: powershell -File scripts\bake-usb.ps1 -Dest F:\Only-U
param(
  [Parameter(Mandatory = $false)]
  [string]$Dest = 'F:\Only-U'
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Dsh = Join-Path $Repo 'dsh'
$Staging = Join-Path $env:TEMP 'only-u-dsh-deploy'
$GitBin = 'C:\Program Files\Git\bin'
if (Test-Path $GitBin) { $env:Path = "$GitBin;$env:Path" }

function Assert-Path($path, $hint) {
  if (-not (Test-Path -LiteralPath $path)) { throw $hint }
}

Assert-Path (Join-Path $Dsh 'package.json') '找不到 dsh\。在仓库根运行。'
Assert-Path (Join-Path $Dsh 'apps\cli\lib\bin.js') 'dsh 还没 build。先 cd dsh && pnpm run build。'
Assert-Path $Dest "目标不存在: $Dest"
$nodeSrc = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodeSrc) { throw '开发机 PATH 上没有 node.exe' }

Write-Host "== 1. pnpm deploy 扁平 CLI -> $Staging"
if (Test-Path $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging -Force | Out-Null
Push-Location $Dsh
try {
  & pnpm --filter @deepseek-ai/dsh deploy --legacy --prod --config.node-linker=hoisted --config.auto-install-peers=false --config.link-workspace-packages=true $Staging
  if ($LASTEXITCODE -ne 0) { throw "pnpm deploy failed: $LASTEXITCODE" }
} finally { Pop-Location }

$destScope = Join-Path $Staging 'node_modules\@deepseek-ai'
New-Item -ItemType Directory -Path $destScope -Force | Out-Null
Get-ChildItem (Join-Path $Dsh 'vendor') -Directory | ForEach-Object {
  $pkgFile = Join-Path $_.FullName 'package.json'
  if (-not (Test-Path $pkgFile)) { return }
  $name = (Get-Content $pkgFile -Raw | ConvertFrom-Json).name
  if ($name -notlike '@deepseek-ai/*') { return }
  $leaf = $name.Substring('@deepseek-ai/'.Length)
  $out = Join-Path $destScope $leaf
  if (Test-Path $out) { return }
  Write-Host "   vendor $name"
  cmd /c "robocopy `"$($_.FullName)`" `"$out`" /E /COPY:DAT /NFL /NDL /NP /XD node_modules" | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy vendor $name failed: $LASTEXITCODE" }
}

# pnpm deploy omits workspace packages that are only reached via nested links
# (dsh-timeout, dsh-scope, ...). Copy every built @deepseek-ai package.
foreach ($rootName in @('packages', 'vendor', 'apps', 'native')) {
  $root = Join-Path $Dsh $rootName
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem $root -Recurse -Filter package.json -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
    ForEach-Object {
      $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
      if ($json.name -notlike '@deepseek-ai/*') { return }
      $leaf = $json.name.Substring('@deepseek-ai/'.Length)
      $out = Join-Path $destScope $leaf
      if ((Test-Path (Join-Path $out 'package.json')) -and (Test-Path (Join-Path $out 'lib'))) { return }
      Write-Host "   workspace $($json.name)"
      New-Item -ItemType Directory -Path $out -Force | Out-Null
      cmd /c "robocopy `"$(Split-Path $_.FullName)`" `"$out`" /E /COPY:DAT /NFL /NDL /NP /XD node_modules tests" | Out-Null
      if ($LASTEXITCODE -ge 8) { throw "robocopy workspace $($json.name) failed: $LASTEXITCODE" }
    }
}

$bootJs = Join-Path $Staging 'node_modules\@deepseek-ai\dsh-app-boot\lib\index.js'
if (Test-Path $bootJs) {
  $js = [IO.File]::ReadAllText($bootJs)
  $old = @'
	if (stat !== void 0) {
		if (!stat.isSymbolicLink()) throw new Error(`dsh: ${link} exists and is not a symlink; remove it so dsh can manage the installation fallback`);
		if (readlinkSync(link) === target) return;
		unlinkSync(link);
	}
	try {
		symlinkSync(target, link, "junction");
	} catch (error) {
		/* v8 ignore next 4 */
		if (error.code !== "EEXIST" || !lstatSync(link).isSymbolicLink() || readlinkSync(link) !== target) throw error;
	}
'@
  $new = @'
	if (stat !== void 0) {
		if (stat.isSymbolicLink()) {
			if (readlinkSync(link) === target) return;
			unlinkSync(link);
		} else {
			return;
		}
	}
	try {
		symlinkSync(target, link, "junction");
	} catch (error) {
		if (error.code === "EEXIST" || error.code === "EPERM" || error.code === "EISDIR" || error.code === "ENOTSUP" || error.code === "EINVAL" || error.code === "EACCES") return;
		throw error;
	}
'@
  if ($js.Contains($old)) {
    [IO.File]::WriteAllText($bootJs, $js.Replace($old, $new))
    Write-Host '   patched dsh-app-boot ensureSymlink for FAT32'
  } else {
    Write-Host '   warn: ensureSymlink patch target not found (upstream may have changed)'
  }
}

Write-Host "== 2. 拷仓库骨架（不含 dsh/node_modules）"
$xd = [System.Collections.Generic.List[string]]::new()
$xd.Add((Join-Path $Repo '.git'))
$xd.Add((Join-Path $Repo 'wxcontext'))
$xd.Add('node_modules')
Get-ChildItem -LiteralPath $Repo -Directory | Where-Object { $_.Name -like 'token*' } | ForEach-Object { [void]$xd.Add($_.FullName) }
$roboArgs = @($Repo, $Dest, '/E', '/COPY:DAT', '/R:1', '/W:1', '/NFL', '/NDL', '/NP')
foreach ($d in $xd) { $roboArgs += '/XD'; $roboArgs += $d }
& robocopy @roboArgs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy repo failed: $LASTEXITCODE" }

Write-Host "== 3. 便携 Node + 扁平 CLI"
$runtimeNode = Join-Path $Dest 'portable\runtime\node'
$runtimeDsh = Join-Path $Dest 'portable\runtime\dsh'
New-Item -ItemType Directory -Path $runtimeNode -Force | Out-Null
Copy-Item -LiteralPath $nodeSrc -Destination (Join-Path $runtimeNode 'node.exe') -Force
New-Item -ItemType Directory -Path $runtimeDsh -Force | Out-Null
cmd /c "robocopy `"$Staging`" `"$runtimeDsh`" /E /COPY:DAT /MT:4 /R:1 /W:1 /NFL /NDL /NP"
if ($LASTEXITCODE -ge 8) { throw "robocopy runtime dsh failed: $LASTEXITCODE" }

Write-Host "== 4. TUI profile + skill"
$profSrc = Join-Path $env:USERPROFILE '.dsh\profiles\dsh-tui'
Assert-Path (Join-Path $profSrc 'package.json') '本机没有 profile dsh-tui。先: cd dsh && pnpm dsh plugin --profile dsh-tui add @deepseek-harness-tui/dsh-tui'
$profDst = Join-Path $runtimeDsh 'profiles\dsh-tui'
New-Item -ItemType Directory -Path $profDst -Force | Out-Null
cmd /c "robocopy `"$profSrc`" `"$profDst`" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP"
if ($LASTEXITCODE -ge 8) { throw "robocopy profile failed: $LASTEXITCODE" }
$skillSrc = Join-Path $Repo '.dsh\skills\only-u-ops\SKILL.md'
$skillDst = Join-Path $runtimeDsh 'skills\only-u-ops'
New-Item -ItemType Directory -Path $skillDst -Force | Out-Null
Copy-Item -LiteralPath $skillSrc -Destination (Join-Path $skillDst 'SKILL.md') -Force

$envSrc = Join-Path $Repo 'portable\.env'
$envDst = Join-Path $Dest 'portable\.env'
if ((Test-Path $envSrc) -and -not (Test-Path $envDst)) {
  Copy-Item -LiteralPath $envSrc -Destination $envDst
}

Write-Host "== 5. start.cmd + 盘根入口"
# cmd.exe on Chinese Windows reads .cmd as GBK, not UTF-8. UTF-8 BOM splits parentheses.
$gbk = [Text.Encoding]::GetEncoding(936)
$start = @'
@echo off
setlocal EnableExtensions
set "PORTABLE=%~dp0"
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
pushd "%ROOT%"

if exist "%PORTABLE%.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%PORTABLE%.env") do (
    if not "%%A"=="" set "%%A=%%B"
  )
)

set "NODE=%PORTABLE%runtime\node\node.exe"
set "BIN=%PORTABLE%runtime\dsh\lib\bin.js"
set "DSH_HOME=%PORTABLE%runtime\dsh"

echo Only-U USB pack
echo   diagnose: diagnose.cmd
echo   clean preview: clean.cmd
echo.

if not exist "%NODE%" (
  echo Missing Node: portable\runtime\node\node.exe
  echo Run diagnose.cmd instead.
  goto :fail
)
if not exist "%BIN%" (
  echo Missing CLI: portable\runtime\dsh\lib\bin.js
  echo Run diagnose.cmd instead.
  goto :fail
)
if not exist "%DSH_HOME%\profiles\dsh-tui\package.json" (
  echo Missing TUI profile: portable\runtime\dsh\profiles\dsh-tui
  echo Run diagnose.cmd instead.
  goto :fail
)
if "%DEEPSEEK_API_KEY%"=="" (
  echo Missing DEEPSEEK_API_KEY in portable\.env
  echo Run diagnose.cmd if offline.
  goto :fail
)

set "PATH=%PORTABLE%runtime\node;%PATH%"
"%NODE%" "%BIN%" --profile dsh-tui %*
set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" goto :fail
popd
exit /b 0

:fail
echo.
echo Agent failed to start. Press any key.
pause >nul
popd
exit /b 1
'@
[IO.File]::WriteAllText((Join-Path $Dest 'portable\start.cmd'), $start, $gbk)

function Write-Launcher($name, $body) {
  [IO.File]::WriteAllText((Join-Path $Dest $name), $body, $gbk)
}
$wrap = "@echo off`r`ncd /d `"%~dp0`"`r`ncall `"%~dp0portable\start.cmd`" %*`r`nif errorlevel 1 pause`r`nexit /b %ERRORLEVEL%`r`n"
$wrapDiag = "@echo off`r`ncd /d `"%~dp0`"`r`ncall `"%~dp0portable\diagnose.cmd`" %*`r`nif errorlevel 1 pause`r`nexit /b %ERRORLEVEL%`r`n"
$wrapClean = "@echo off`r`ncd /d `"%~dp0`"`r`ncall `"%~dp0portable\clean.cmd`" -Interactive %*`r`nif errorlevel 1 pause`r`nexit /b %ERRORLEVEL%`r`n"
Write-Launcher '诊断.cmd' $wrapDiag
Write-Launcher '清理预览.cmd' $wrapClean
Write-Launcher '启动Agent.cmd' $wrap
Write-Launcher 'Start-Agent.cmd' $wrap

$nodeOut = Join-Path $runtimeNode 'node.exe'
$binOut = Join-Path $runtimeDsh 'lib\bin.js'
Write-Host '== 校验 CLI --help'
& $nodeOut $binOut --help | Select-Object -First 8
if ($LASTEXITCODE -ne 0) { throw 'baked CLI --help failed' }

Write-Host ''
Write-Host "烤盘完成: $Dest"
Write-Host '客户机: 双击 Start-Agent.cmd 或 启动Agent.cmd（有网）；诊断.cmd（无网）'
Write-Host '不要在 TUI 里 /update。新插件在开发机 plugin add 后再跑本脚本。'
