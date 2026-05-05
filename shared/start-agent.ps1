# Generic launcher for one relay agent.
#
# Called from each agent's start.ps1 with -AgentName <name>. Reads the
# global config (~/.relay-team/config.json) for the venv + relay source
# paths, then launches `python -m runner --agent-dir <agent-dir>`.
#
# Failure modes:
# - config missing                       -> exit 1
# - relay_root or agent dir missing      -> wait up to 5 min (encrypted
#                                            drives may unlock late after
#                                            logon), then exit 1
# - venv or relay source missing         -> exit 1
# - Runner crashes                       -> surface its exit code so Task
#                                            Scheduler can restart it

param(
    [Parameter(Mandatory=$true)][string]$AgentName
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

$AgentDir   = Join-Path $cfg.relay_root $AgentName
$VenvPython = $cfg.venv_python
$RelayRoot  = $cfg.relay_source
$LogFile    = Join-Path $AgentDir "state\start.log"

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$stamp] $Message"
    Write-Host $line
    if (Test-Path (Join-Path $AgentDir "state")) {
        Add-Content -Path $LogFile -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
    }
}

# 1. Wait for the agent dir (handles late mounts of encrypted drives).
$deadline = (Get-Date).AddMinutes(5)
Write-Log "Waiting for $AgentDir to be available..."
while (-not (Test-Path $AgentDir)) {
    if ((Get-Date) -gt $deadline) {
        Write-Log "$AgentDir never appeared within 5 min. Exiting."
        exit 1
    }
    Start-Sleep -Seconds 10
}
Write-Log "$AgentDir is available."

# Make sure state dir exists for our own logging.
$stateDir = Join-Path $AgentDir "state"
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

# 2. Sanity-check the venv interpreter.
if (-not (Test-Path $VenvPython)) {
    Write-Log "venv python missing at $VenvPython. Update ~/.relay-team/config.json or create the venv: python -m venv ..."
    exit 1
}

# 3. Sanity-check the relay runner.
if (-not (Test-Path (Join-Path $RelayRoot "runner\__main__.py"))) {
    Write-Log "relay runner missing at $RelayRoot. Clone https://github.com/NodeNestor/relay there, or fix relay_source in config."
    exit 1
}

# 4. Sanity-check the agent has the bare-minimum files.
foreach ($required in @("CLAUDE.md", "config.json")) {
    if (-not (Test-Path (Join-Path $AgentDir $required))) {
        Write-Log "missing $required in $AgentDir -- aborting."
        exit 1
    }
}

# 5. Launch.
Write-Log "Launching relay runner for agent '$AgentName'..."
Set-Location $RelayRoot
& $VenvPython -m runner --agent-dir $AgentDir
$rc = $LASTEXITCODE
Write-Log "Runner exited with code $rc"
exit $rc
