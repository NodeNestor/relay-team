#requires -Version 5.1
# One-shot installer that adds the `relay-team` and `relay-tell` commands
# to your PowerShell profile so you can call them from any directory.
#
# Idempotent -- running twice does nothing the second time.
#
# Usage:
#   .\install-cli.ps1

$ErrorActionPreference = "Stop"

$relayTeamScript = Join-Path $PSScriptRoot "relay-team.ps1"
$relayTellScript = Join-Path $PSScriptRoot "relay-tell.ps1"

if (-not (Test-Path $relayTeamScript)) {
    Write-Host "ERROR: $relayTeamScript not found." -ForegroundColor Red
    Write-Host "Run this from inside the relay-team repo." -ForegroundColor Gray
    exit 1
}

if (-not (Test-Path $PROFILE)) {
    Write-Host "Creating $PROFILE..." -ForegroundColor Cyan
    New-Item -Path $PROFILE -ItemType File -Force | Out-Null
}

$marker = "# ===== relay-team CLI ====="
$current = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($current -and $current.Contains($marker)) {
    Write-Host "relay-team already in your PowerShell profile -- nothing to do." -ForegroundColor Gray
    Write-Host "  marker found in $PROFILE" -ForegroundColor DarkGray
} else {
    $block = @"

$marker
function relay-team { & "$relayTeamScript" @args }
function relay-tell { & "$relayTellScript" @args }
# ===== /relay-team CLI =====
"@
    Add-Content -Path $PROFILE -Value $block -Encoding utf8
    Write-Host "Added 'relay-team' and 'relay-tell' to $PROFILE" -ForegroundColor Green
}

# Re-source so the current session has them too.
. $PROFILE

Write-Host ""
Write-Host "Try it:" -ForegroundColor Cyan
Write-Host "  relay-team help"
Write-Host "  relay-team status"
Write-Host ""
Write-Host "Open a new PowerShell window and the commands will be available there too." -ForegroundColor Gray
