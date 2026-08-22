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
  $name = ([IO.File]::ReadAllText($pkgFile) | ConvertFrom-Json).name
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
      $json = [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json
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
  $js = [IO.File]::ReadAllText($bootJs).Replace("`r`n", "`n")
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
  $old = $old.Replace("`r`n", "`n")
  $new = $new.Replace("`r`n", "`n")
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

Write-Host "== 5. agent-presets 实体拷贝（FAT32 无 junction，修 U 盘 agent 零工具 P0）"
$presetSrc = Join-Path $runtimeDsh 'config\agent-presets'
Assert-Path (Join-Path $presetSrc 'standard\agent.cordis.yml') 'dsh 构建产物缺少 config\agent-presets\standard（dsh 版本变化？先核对）'
$presetDst = Join-Path $runtimeDsh 'profiles\node_modules\@deepseek-ai\dsh\config\agent-presets'
New-Item -ItemType Directory -Path $presetDst -Force | Out-Null
cmd /c "robocopy `"$presetSrc`" `"$presetDst`" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP"
if ($LASTEXITCODE -ge 8) { throw "robocopy agent-presets failed: $LASTEXITCODE" }
# 仓库自有 preset（如 only-u-repair）同步进两个 preset 根
$repoPresets = Join-Path $Repo 'presets'
if (Test-Path $repoPresets) {
  Get-ChildItem $repoPresets -Directory | ForEach-Object {
    foreach ($root in @($presetSrc, $presetDst)) {
      cmd /c "robocopy `"$($_.FullName)`" `"$(Join-Path $root $_.Name)`" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP"
      if ($LASTEXITCODE -ge 8) { throw "robocopy preset $($_.Name) failed: $LASTEXITCODE" }
    }
  }
}

Write-Host "== 6. start.cmd + 盘根入口"
# start.cmd 唯一源 = 仓库 portable\start.cmd（GBK 无 BOM、含 #27 单实例锁），不再维护内联副本
$gbk = [Text.Encoding]::GetEncoding(936)
Copy-Item -LiteralPath (Join-Path $Repo 'portable\start.cmd') -Destination (Join-Path $Dest 'portable\start.cmd') -Force

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
$helpOut = & $nodeOut $binOut --help 2>&1
$helpExit = $LASTEXITCODE
$helpOut | Select-Object -First 8
if ($helpExit -ne 0) { throw "baked CLI --help failed: $helpExit" }

Write-Host ''
Write-Host "烤盘完成: $Dest"
Write-Host '客户机: 双击 Start-Agent.cmd 或 启动Agent.cmd（有网）；诊断.cmd（无网）'
Write-Host '不要在 TUI 里 /update。新插件在开发机 plugin add 后再跑本脚本。'
