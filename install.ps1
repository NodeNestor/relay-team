#requires -Version 5.1
<#
.SYNOPSIS
    relay-team install wizard. Writes ~/.relay-team/config.json.

.DESCRIPTION
    Interactive setup. Asks for the three mandatory paths (relay_root,
    venv_python, relay_source), validates them, writes the config file.
    Idempotent -- re-running shows current values as defaults.
#>

$ErrorActionPreference = "Stop"

$ConfigDir  = Join-Path $env:USERPROFILE ".relay-team"
$ConfigPath = Join-Path $ConfigDir "config.json"

# Load existing config so re-runs show current values as defaults.
$existing = $null
if (Test-Path $ConfigPath) {
    try { $existing = Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json } catch {}
}

function Prompt-Path {
    param([string]$Label, [string]$Default, [switch]$MustExist, [string]$ExistHint = "")
    while ($true) {
        $defStr = if ($Default) { " [$Default]" } else { "" }
        $val = Read-Host "$Label$defStr"
        if (-not $val) { $val = $Default }
        if (-not $val) {
            Write-Host "  required, please enter a path." -ForegroundColor Yellow
            continue
        }
        $val = [System.Environment]::ExpandEnvironmentVariables($val)
        if ($MustExist -and -not (Test-Path $val)) {
            Write-Host "  path does not exist: $val" -ForegroundColor Yellow
            if ($ExistHint) { Write-Host "  $ExistHint" -ForegroundColor DarkGray }
            $accept = Read-Host "  use it anyway? [y/N]"
            if ($accept -notmatch '^(y|yes)$') { continue }
        }
        return $val
    }
}

function Prompt-YesNo {
    param([string]$Label, [bool]$Default = $false)
    $defStr = if ($Default) { "Y/n" } else { "y/N" }
    $val = Read-Host "$Label [$defStr]"
    if (-not $val) { return $Default }
    return ($val -match '^(y|yes)$')
}

Write-Host "" -ForegroundColor Cyan
Write-Host "relay-team install" -ForegroundColor Cyan
Write-Host "-------------------" -ForegroundColor Cyan
Write-Host "This writes $ConfigPath. Re-run any time to change paths."
Write-Host ""

# 1. relay_root -- where agent dirs will live.
$defaultRoot = if ($existing -and $existing.relay_root) { $existing.relay_root } else { Join-Path $env:USERPROFILE "relay-agents" }
$relayRoot = Prompt-Path -Label "Where should agent directories live? (relay_root)" -Default $defaultRoot

# 2. venv_python -- Python interpreter for the runner.
$defaultPython = if ($existing -and $existing.venv_python) { $existing.venv_python } else { "" }
$venvPython = Prompt-Path -Label "Path to the Python 3.12 interpreter for the runner (venv_python)" -Default $defaultPython -MustExist -ExistHint "create with: python -m venv path\\to\\relay-venv"

# 3. relay_source -- where the relay repo is cloned.
$defaultSource = if ($existing -and $existing.relay_source) { $existing.relay_source } else { "" }
$relaySource = Prompt-Path -Label "Path to your local clone of NodeNestor/relay (relay_source)" -Default $defaultSource -MustExist -ExistHint "clone with: git clone https://github.com/NodeNestor/relay.git"

# Sanity check the relay clone has the runner.
$runnerEntry = Join-Path $relaySource "runner\__main__.py"
if (-not (Test-Path $runnerEntry)) {
    Write-Host ""
    Write-Host "  WARNING: $runnerEntry not found." -ForegroundColor Yellow
    Write-Host "  Is $relaySource really a clone of NodeNestor/relay?" -ForegroundColor DarkGray
    if (-not (Prompt-YesNo "  use it anyway?" $false)) {
        Write-Host "Aborted." -ForegroundColor Red
        exit 1
    }
}

# 4. Optional knobs.
$defaultPrefix = if ($existing -and $existing.task_name_prefix) { $existing.task_name_prefix } else { "RelayTeam-" }
$prefixIn = Read-Host "Task Scheduler name prefix [$defaultPrefix]"
$prefix = if ($prefixIn) { $prefixIn } else { $defaultPrefix }

$defaultOutlook = if ($existing -and $null -ne $existing.outlook_autostart) { [bool]$existing.outlook_autostart } else { $false }
$outlook = Prompt-YesNo -Label "Add Outlook autostart shortcut on install? (only useful if any agent uses the outlook plugin)" -Default $defaultOutlook

# 5. Make relay_root if it doesn't exist.
if (-not (Test-Path $relayRoot)) {
    if (Prompt-YesNo -Label "Create $relayRoot now?" -Default $true) {
        New-Item -ItemType Directory -Path $relayRoot -Force | Out-Null
        Write-Host "  created $relayRoot" -ForegroundColor Green
    }
}

# 6. Write config.
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Copy shared/start-agent.ps1 into the config dir so agents don't depend on
# this repo's checkout location.
$sharedSource = Join-Path $PSScriptRoot "shared\start-agent.ps1"
$sharedDest   = Join-Path $ConfigDir "start-agent.ps1"
if (Test-Path $sharedSource) {
    Copy-Item -Path $sharedSource -Destination $sharedDest -Force
    Write-Host "  copied start-agent.ps1 -> $sharedDest" -ForegroundColor DarkGray
} else {
    Write-Host "  WARNING: shared/start-agent.ps1 not found in this repo." -ForegroundColor Yellow
}
$config = [ordered]@{
    relay_root         = $relayRoot
    venv_python        = $venvPython
    relay_source       = $relaySource
    task_name_prefix   = $prefix
    outlook_autostart  = $outlook
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($ConfigPath, $config, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Wrote $ConfigPath" -ForegroundColor Green
Write-Host ""
Get-Content $ConfigPath -Encoding utf8

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. .\install-cli.ps1                 (adds relay-team / relay-tell to your PowerShell profile)"
Write-Host "  2. Copy an example into your relay_root, e.g.:"
Write-Host "       Copy-Item -Recurse examples\coder $relayRoot\my-coder"
Write-Host "  3. Edit my-coder\CLAUDE.md and config.json to fit your repo / username."
Write-Host "  4. Copy plugins from $relaySource\plugins\ into my-coder\plugins\ for the ones you enabled."
Write-Host "  5. relay-team install                 (registers Task Scheduler entries)"
Write-Host "  6. relay-team start my-coder          (foreground first run)"
