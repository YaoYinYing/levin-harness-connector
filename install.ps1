# Install Levin for magpie from GitHub in one command, and pin the model entry
# magpie may write. Windows.
#
# NOTE: there is no Windows build of Levin Harness yet — its install docs offer
# an Apple silicon .dmg and its Terms of Service say macOS only, other platforms
# planned. This script is written for the day that build ships; it has never run
# on Windows, and on a machine without Levin it cannot do anything useful.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Create
#   powershell -ExecutionPolicy Bypass -File install.ps1 -List
#
# One line from the web, no clone:
#
#   irm https://raw.githubusercontent.com/YaoYinYing/levin-harness-connector/main/install.ps1 | iex
#
# Why a script at all: magpie runs agent plugins in moejs, with no fs and no
# process.env, so a plugin cannot look at Levin's config to find out which entry
# to write — and magpie's JSON editor only replaces key paths that already
# exist, so a wrong or missing choice destroys the whole llmConfigs array. This
# script does the one part a plugin cannot: read the config, choose an entry,
# and pin its id into the installed copy of slot.js.
#
# Everything is idempotent: running it twice re-pins and reloads, nothing else.
[CmdletBinding()]
param(
  [switch]$Create,   # no usable entry yet: append one to Levin's config first (quit Levin)
  [switch]$List,     # only print Levin's model entries and their ids
  [switch]$Link,     # also put a `magpie` command on PATH (%LOCALAPPDATA%\Microsoft\WindowsApps)
  [string]$Magpie,   # magpie.exe or magpie-cli.exe, if not found automatically
  [string]$Spec = "github:YaoYinYing/levin-harness-connector"
)

$ErrorActionPreference = 'Stop'
$name = 'levin-harness-connector'

function Say([string]$m) { Write-Host $m }
function Die([string]$m) { Write-Error "install.ps1: $m"; exit 1 }

# magpie on Windows is magpie.exe (the app) or magpie-cli.exe (the command line,
# from the release assets). Neither is on PATH by default.
function Resolve-Magpie {
  if ($Magpie) {
    if (-not (Test-Path $Magpie)) { Die "Magpie=$Magpie does not exist" }
    return (Resolve-Path $Magpie).Path
  }
  $onPath = Get-Command magpie, magpie-cli -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($onPath) { return $onPath.Source }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\magpie\magpie.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\magpie\magpie-cli.exe'),
    (Join-Path $env:LOCALAPPDATA 'magpie\magpie.exe'),
    (Join-Path $env:ProgramFiles 'magpie\magpie.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'magpie\magpie.exe'),
    (Join-Path $env:USERPROFILE 'magpie\magpie.exe'),
    (Join-Path $env:USERPROFILE 'Downloads\magpie-windows-amd64.exe'),
    (Join-Path $env:USERPROFILE 'Downloads\magpie-cli-windows-amd64.exe')
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
  }
  return $null
}

$magpieExe = Resolve-Magpie
if (-not $magpieExe) {
  Die @"
no magpie found. Looked on PATH, then in %LOCALAPPDATA%\Programs\magpie,
%LOCALAPPDATA%\magpie, %ProgramFiles%\magpie and your Downloads.
If it lives elsewhere:
    powershell -ExecutionPolicy Bypass -File install.ps1 -Magpie "C:\path\to\magpie.exe"
"@
}
Say "-> magpie: $magpieExe"

if ($Link) {
  # A .cmd shim, so `magpie` works in a new shell. WindowsApps is already on PATH.
  $binDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
  $shim = Join-Path $binDir 'magpie.cmd'
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  # %* passes arguments through; the quotes keep a path with spaces intact
  Set-Content -Path $shim -Encoding ASCII -Value "@echo off`r`n`"$magpieExe`" %*"
  Say "-> wrote $shim"
  if (-not (($env:PATH -split ';') -contains $binDir)) {
    Say "  note: $binDir is not on PATH in this session; open a new terminal to use plain 'magpie'"
  }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Die "node is not on PATH. Install Node.js 18 or newer (https://nodejs.org) and run this again."
}

Say "-> installing $Spec"
& $magpieExe plugin add $Spec
if ($LASTEXITCODE -ne 0) { Die "magpie plugin add failed (exit $LASTEXITCODE)" }

# The installed copy, not a clone: magpie loads plugins from its own folder, so
# that is the slot.js magpie reads.
$cfgDir = if ($env:MAGPIE_CONFIG_DIR) { $env:MAGPIE_CONFIG_DIR }
elseif ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'magpie' }
else { Join-Path $env:USERPROFILE '.config\magpie' }
$pluginDir = Get-ChildItem -Path (Join-Path $cfgDir 'plugins\node_modules') -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName 'package.json') } |
  Where-Object { (Get-Content (Join-Path $_.FullName 'package.json') -Raw | ConvertFrom-Json).name -eq $name } |
  Select-Object -First 1
if (-not $pluginDir) { Die "could not find the installed $name under $cfgDir\plugins\node_modules" }
Say "-> plugin lives at $($pluginDir.FullName)"

$pinArgs = @((Join-Path $pluginDir.FullName 'tools\pin-slot.mjs'))
if ($Create) { $pinArgs += '--create' }
if ($List) { $pinArgs += '--list' }
Say "-> pinning the Levin model entry magpie may write"
& node @pinArgs
if ($LASTEXITCODE -ne 0) { Die "pinning failed (see above)" }
if ($List) { exit 0 }

# A plugin's agent module is compiled when magpie starts, so a new pin is only
# read after the plugin is loaded again.
& $magpieExe plugin off $name 2>$null | Out-Null
& $magpieExe plugin on $name 2>$null | Out-Null

Say ""
Say "Done. In magpie -> Agents -> the Levin row, pick a model."
Say "Levin reads its model when a chat starts: send the next message or open a new chat."
Say "Undo: pick Levin's previous model in that row, or `"$magpieExe`" $name default."
