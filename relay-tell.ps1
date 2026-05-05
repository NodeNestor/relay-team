#requires -Version 5.1
# Send a message to one of your relay agents via its inbox plugin.
#
# Discovers the agent dir from ~/.relay-team/config.json (relay_root),
# appends one JSON line to <agent>/state/inbox.jsonl. The inbox plugin
# polls that file every 2s and emits each new line as an event.
#
# This is a file-based mechanism -- no HTTP, no daemon. Works whether
# the agent is between turns or actively processing.
#
# Usage:
#   .\relay-tell.ps1 my-coder "stop and rebase"
#   relay-tell my-coder "what are you working on?"   (after install-cli.ps1)

param(
    [Parameter(Mandatory=$true, Position=0)][string]$Agent,
    [Parameter(Mandatory=$true, Position=1, ValueFromRemainingArguments=$true)][string[]]$MessageWords
)

$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $env:USERPROFILE ".relay-team\config.json"
if (-not (Test-Path $ConfigPath)) {
    Write-Host "No config at $ConfigPath -- run install.ps1 first." -ForegroundColor Red
    exit 1
}
try {
    $cfg = Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
} catch {
    Write-Host "Could not parse $ConfigPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $cfg.relay_root)) {
    Write-Host "relay_root does not exist: $($cfg.relay_root)" -ForegroundColor Red
    exit 1
}

# Resolve agent (substring tolerated)
$agents = @()
Get-ChildItem $cfg.relay_root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if (Test-Path (Join-Path $_.FullName "start.ps1")) { $agents += $_.Name }
}
$resolved = if ($Agent -in $agents) { $Agent } else {
    $agents | Where-Object { $_ -like "*$Agent*" } | Select-Object -First 1
}
if (-not $resolved) {
    Write-Host "Unknown agent: $Agent" -ForegroundColor Red
    Write-Host "Discovered: $($agents -join ', ')" -ForegroundColor Gray
    exit 2
}

$Message = ($MessageWords -join " ")
$inboxFile = Join-Path (Join-Path $cfg.relay_root $resolved) "state\inbox.jsonl"
$inboxDir  = Split-Path $inboxFile

if (-not (Test-Path $inboxDir)) {
    Write-Host "State dir missing: $inboxDir" -ForegroundColor Red
    Write-Host "Has the agent ever run? Try 'relay-team start $resolved'." -ForegroundColor Gray
    exit 1
}

$payload = [ordered]@{
    body     = $Message
    source   = "user"
    metadata = @{
        sent_at  = (Get-Date -Format "o")
        from     = $env:USERNAME
        hostname = $env:COMPUTERNAME
    }
} | ConvertTo-Json -Depth 5 -Compress

try {
    Add-Content -Path $inboxFile -Value $payload -Encoding utf8 -ErrorAction Stop
    Write-Host "Sent to $resolved." -ForegroundColor Green
    Write-Host "  -> $inboxFile" -ForegroundColor DarkGray
} catch {
    Write-Host "Could not write to $inboxFile" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    exit 1
}
