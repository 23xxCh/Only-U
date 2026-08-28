# Bake helpers for the USB TUI profile.
# Dot-source from bake-usb.ps1 and from tests. Does not run on load.
# Dest = USB pack root (e.g. F:\Only-U).
# Encoding: ASCII-only strings so Windows PowerShell 5.1 can parse without a BOM.

Set-StrictMode -Version Latest

function Get-BakedTuiRoot {
  param([Parameter(Mandatory = $true)][string]$Dest)
  Join-Path $Dest 'portable\runtime\dsh\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui'
}

function Get-BakedProfileDir {
  param([Parameter(Mandatory = $true)][string]$Dest)
  Join-Path $Dest 'portable\runtime\dsh\profiles\dsh-tui'
}

function Get-BakedBundleRoot {
  param([Parameter(Mandatory = $true)][string]$Dest)
  Join-Path $Dest 'portable\runtime\dsh\profiles\dsh-tui\node_modules\only-u-bundle'
}

function Write-BakeId {
  param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$RuntimeDsh
  )
  $bakeSha = git -C $Repo rev-parse --short HEAD 2>$null
  if (-not $bakeSha) { $bakeSha = 'nogit' }
  [IO.File]::WriteAllText((Join-Path $RuntimeDsh 'BAKE-ID'), "$bakeSha-$(Get-Date -Format 'yyyyMMdd-HHmmss')")
}

function Assert-BakedTui {
  param([Parameter(Mandatory = $true)][string]$Dest)

  $tui = Get-BakedTuiRoot -Dest $Dest
  $pkgPath = Join-Path $tui 'package.json'
  if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) {
    throw "baked TUI package.json missing: $pkgPath"
  }
  $pkg = [IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
  if ($pkg.version -ne '0.8.8') {
    throw "Dest dsh-tui version is $($pkg.version), must be 0.8.8"
  }

  $logoPath = Join-Path $tui 'lib\types\components\LogoV2.js'
  if (-not (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
    throw "baked LogoV2.js missing: $logoPath"
  }
  $logo = [IO.File]::ReadAllText($logoPath)
  if ($logo -notmatch 'ONLY-U') {
    throw 'LogoV2.js does not contain ONLY-U (this is the file Node loads)'
  }

  $fontPath = Join-Path $tui 'lib\types\components\bigfont.js'
  if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
    throw "baked bigfont.js missing: $fontPath"
  }
  $font = [IO.File]::ReadAllText($fontPath)
  foreach ($glyph in @('O:', 'L:', 'Y:', 'U:', "'-':")) {
    if ($font.IndexOf($glyph) -lt 0) {
      throw "bigfont.js missing glyph $glyph"
    }
  }

  $pluginPath = Join-Path $tui 'lib\types\dsh-adapter\plugin.js'
  if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "baked plugin.js missing: $pluginPath"
  }
  $plugin = [IO.File]::ReadAllText($pluginPath)
  if ($plugin.IndexOf('DSH_TUI_NO_UPDATE') -lt 0) {
    throw 'plugin.js does not contain DSH_TUI_NO_UPDATE'
  }

  $sessionMod = Join-Path $tui 'lib\types\dsh-adapter\sessions\index.js'
  if (-not (Test-Path -LiteralPath $sessionMod -PathType Leaf)) {
    throw "baked dsh-adapter/sessions/index.js missing: $sessionMod"
  }

  $formatMod = Join-Path $tui 'lib\types\sessions\format.js'
  if (-not (Test-Path -LiteralPath $formatMod -PathType Leaf)) {
    throw "baked types/sessions/format.js missing: $formatMod"
  }

  $rowMod = Join-Path $tui 'lib\types\components\sessions\SessionListRow.js'
  if (-not (Test-Path -LiteralPath $rowMod -PathType Leaf)) {
    throw "baked components/sessions/SessionListRow.js missing: $rowMod"
  }

  $profilePath = Join-Path (Get-BakedProfileDir -Dest $Dest) 'package.json'
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "baked profile package.json missing: $profilePath"
  }
  $manifest = [IO.File]::ReadAllText($profilePath) | ConvertFrom-Json
  $bundles = @($manifest.dsh.profile.bundles)
  if ($bundles -notcontains 'only-u-bundle') {
    throw 'profile dsh.profile.bundles is missing only-u-bundle'
  }

  $patchPath = Join-Path (Get-BakedBundleRoot -Dest $Dest) 'cordis.patch.yml'
  if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
    throw "baked only-u-bundle cordis.patch.yml missing: $patchPath"
  }
  $patch = [IO.File]::ReadAllText($patchPath)
  if ($patch -notmatch 'id:\s*only-u-bundle') {
    throw 'only-u-bundle cordis.patch.yml was not injected'
  }
}

function Invoke-DshTuiCompile {
  param([Parameter(Mandatory = $true)][string]$Repo)

  $dshTui = Join-Path $Repo 'dsh-tui'
  if (-not (Test-Path -LiteralPath (Join-Path $dshTui 'package.json') -PathType Leaf)) {
    throw 'dsh-tui package.json not found; run from the repo root.'
  }

  Push-Location $dshTui
  try {
    if (-not (Test-Path -LiteralPath (Join-Path $dshTui 'node_modules'))) {
      Write-Host '   pnpm install dsh-tui'
      & pnpm install --frozen-lockfile
      if ($LASTEXITCODE -ne 0) { throw "dsh-tui pnpm install failed: $LASTEXITCODE" }
    }
    Write-Host '   npm run compile'
    & npm run compile
    if ($LASTEXITCODE -ne 0) { throw "dsh-tui compile failed: $LASTEXITCODE" }
  }
  finally {
    Pop-Location
  }

  $logo = Join-Path $dshTui 'lib\types\components\LogoV2.js'
  if (-not (Test-Path -LiteralPath $logo -PathType Leaf)) {
    throw "compile did not write $logo"
  }
}

function Install-DestTuiProfile {
  param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Dest,
    [Parameter(Mandatory = $true)][string]$NodeExe,
    [Parameter(Mandatory = $true)][string]$DshBin
  )

  if (-not (Test-Path -LiteralPath $NodeExe -PathType Leaf)) { throw "node.exe not found: $NodeExe" }
  if (-not (Test-Path -LiteralPath $DshBin -PathType Leaf)) { throw "dsh CLI not found: $DshBin" }

  $bundle = Join-Path $Repo 'plugins\only-u-bundle'
  if (-not (Test-Path -LiteralPath (Join-Path $bundle 'package.json') -PathType Leaf)) {
    throw "only-u-bundle not found: $bundle"
  }

  $profileHome = Join-Path $env:TEMP 'only-u-profile-bake'
  if (Test-Path -LiteralPath $profileHome) {
    Remove-Item -LiteralPath $profileHome -Recurse -Force
  }
  New-Item -ItemType Directory -Path $profileHome -Force | Out-Null

  $prevHome = $env:DSH_HOME
  $prevAgents = $env:DSH_AGENTS_HOME
  $env:DSH_HOME = $profileHome
  $env:DSH_AGENTS_HOME = Join-Path $profileHome 'agents-home'
  try {
    Write-Host '   plugin add @deepseek-harness-tui/dsh-tui@0.8.8'
    & $NodeExe $DshBin plugin --profile dsh-tui add '@deepseek-harness-tui/dsh-tui@0.8.8'
    if ($LASTEXITCODE -ne 0) { throw "plugin add dsh-tui@0.8.8 failed: $LASTEXITCODE" }

    Write-Host '   sync compiled dsh-tui into bake profile'
    & $NodeExe (Join-Path $Repo 'dsh-tui\scripts\sync-profile.mjs')
    if ($LASTEXITCODE -ne 0) { throw "sync-profile failed: $LASTEXITCODE" }

    # Pack to TEMP (no spaces). pnpm file: links become junctions; FAT32 Dest cannot hold them.
    # A repo path with a space also gets split by dsh plugin -> pnpm.
    $packDir = Join-Path $env:TEMP 'only-u-bundle-pack'
    if (Test-Path -LiteralPath $packDir) {
      Remove-Item -LiteralPath $packDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packDir -Force | Out-Null
    Write-Host '   npm pack only-u-bundle'
    Push-Location $bundle
    try {
      & npm pack --pack-destination $packDir
      if ($LASTEXITCODE -ne 0) { throw "npm pack only-u-bundle failed: $LASTEXITCODE" }
    }
    finally {
      Pop-Location
    }
    $tarball = Get-ChildItem -LiteralPath $packDir -Filter '*.tgz' -File | Select-Object -First 1
    if (-not $tarball) { throw "npm pack did not write a tgz in $packDir" }

    Write-Host '   plugin add only-u-bundle tarball'
    & $NodeExe $DshBin plugin --profile dsh-tui add $tarball.FullName
    if ($LASTEXITCODE -ne 0) { throw "plugin add only-u-bundle failed: $LASTEXITCODE" }

    $profSrc = Join-Path $profileHome 'profiles\dsh-tui'
    $profDst = Get-BakedProfileDir -Dest $Dest
    if (Test-Path -LiteralPath $profDst) {
      Remove-Item -LiteralPath $profDst -Recurse -Force
    }
    New-Item -ItemType Directory -Path $profDst -Force | Out-Null
    # Exclude only the profile transcript dir. A bare /XD sessions also drops
    # every TUI module folder named sessions (dsh-adapter, types, components).
    # /XJ: do not try to recreate NTFS junctions on FAT32.
    & robocopy $profSrc $profDst /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /XJ /XD (Join-Path $profSrc 'sessions')
    if ($LASTEXITCODE -ge 8) { throw "robocopy baked profile failed: $LASTEXITCODE" }

    # Restore TUI modules named sessions in case /XD still matches by basename.
    $tuiSessionDirs = @(
      'node_modules\@deepseek-harness-tui\dsh-tui\lib\types\sessions',
      'node_modules\@deepseek-harness-tui\dsh-tui\lib\types\dsh-adapter\sessions',
      'node_modules\@deepseek-harness-tui\dsh-tui\lib\types\components\sessions'
    )
    foreach ($rel in $tuiSessionDirs) {
      $from = Join-Path $profSrc $rel
      if (-not (Test-Path -LiteralPath $from)) { continue }
      $to = Join-Path $profDst $rel
      New-Item -ItemType Directory -Path $to -Force | Out-Null
      & robocopy $from $to /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP
      if ($LASTEXITCODE -ge 8) { throw "robocopy restore $rel failed: $LASTEXITCODE" }
    }
  }
  finally {
    if ($null -eq $prevHome -or $prevHome -eq '') {
      Remove-Item Env:\DSH_HOME -ErrorAction SilentlyContinue
    } else {
      $env:DSH_HOME = $prevHome
    }
    if ($null -eq $prevAgents -or $prevAgents -eq '') {
      Remove-Item Env:\DSH_AGENTS_HOME -ErrorAction SilentlyContinue
    } else {
      $env:DSH_AGENTS_HOME = $prevAgents
    }
  }
}
