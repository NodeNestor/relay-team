#requires -Version 5.1
<#
.SYNOPSIS
    relay-team -- multi-agent orchestration CLI for relay (https://github.com/NodeNestor/relay).

.DESCRIPTION
    Manages a team of always-on Claude Code agents under one root directory.
    Discovers agents from <relay_root>/<agent>/start.ps1, registers Task
    Scheduler entries, starts/stops/restarts them, tails their logs, sends
    messages to their inbox.

.EXAMPLE
    relay-team status
    Shows every agent's run state and last activity.

.EXAMPLE
    relay-team install
    Registers Task Scheduler entries for all discovered agents.

.EXAMPLE
    relay-team tell my-coder "what are you working on?"
    Sends a user message to my-coder via the inbox plugin.
#>

param(
    [Parameter(Mandatory=$false, Position=0)][string]$Command,
    [Parameter(Mandatory=$false, Position=1, ValueFromRemainingArguments=$true)][string[]]$Args
)

$ErrorActionPreference = "Stop"

# ----- Config loading -----

$ConfigPath = Join-Path $env:USERPROFILE ".relay-team\config.json"

function Get-RelayTeamConfig {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "No config found at $ConfigPath" -ForegroundColor Red
        Write-Host "Run install.ps1 from the relay-team repo to create one." -ForegroundColor Gray
        exit 1
    }
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        Write-Host "Could not parse $ConfigPath -- $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    foreach ($required in @("relay_root", "venv_python", "relay_source")) {
        if (-not $cfg.$required) {
            Write-Host "Config missing required field: $required" -ForegroundColor Red
            exit 1
        }
    }
    if (-not $cfg.task_name_prefix) {
        Add-Member -InputObject $cfg -NotePropertyName task_name_prefix -NotePropertyValue "RelayTeam-" -Force
    }
    if ($null -eq $cfg.outlook_autostart) {
        Add-Member -InputObject $cfg -NotePropertyName outlook_autostart -NotePropertyValue $false -Force
    }
    return $cfg
}

# ----- Agent discovery -----

function Get-AgentDirName {
    param($AgentPath)
    return (Split-Path -Leaf $AgentPath)
}

function Discover-Agents {
    param($RelayRoot)
    if (-not (Test-Path $RelayRoot)) {
        Write-Host "relay_root does not exist: $RelayRoot" -ForegroundColor Red
        exit 1
    }
    $found = @()
    Get-ChildItem $RelayRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-Path (Join-Path $_.FullName "start.ps1")) {
            $found += $_.Name
        }
    }
    return $found
}

function Get-AgentMeta {
    param($Cfg, $Agent)
    $agentDir = Join-Path $Cfg.relay_root $Agent
    $metaPath = Join-Path $agentDir "agent.json"
    $defaultSuffix = ($Agent -replace '[^a-zA-Z0-9]', '')  # strip non-alnum, e.g. "my-coder" -> "mycoder"
    # Title-case version is nicer; do a simple split on '-' and capitalize.
    $defaultSuffix = ($Agent -split '[-_]' | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { '' }
    }) -join ''

    $meta = @{
        task_name_suffix = $defaultSuffix
        startup_delay_sec = 60
        description = ""
    }
    if (Test-Path $metaPath) {
        try {
            $loaded = Get-Content $metaPath -Raw -Encoding utf8 | ConvertFrom-Json
            if ($loaded.task_name_suffix)  { $meta.task_name_suffix  = $loaded.task_name_suffix }
            if ($loaded.startup_delay_sec) { $meta.startup_delay_sec = [int]$loaded.startup_delay_sec }
            if ($loaded.description)        { $meta.description        = $loaded.description }
        } catch {
            Write-Host "  ! Could not parse $metaPath -- using defaults" -ForegroundColor Yellow
        }
    }
    $meta.task_name = "$($Cfg.task_name_prefix)$($meta.task_name_suffix)"
    $meta.agent_dir = $agentDir
    return $meta
}

function Get-AllAgentMeta {
    param($Cfg)
    $agents = Discover-Agents $Cfg.relay_root
    $out = @{}
    foreach ($agent in $agents) {
        $out[$agent] = Get-AgentMeta -Cfg $Cfg -Agent $agent
    }
    return $out
}

function Resolve-Agent {
    param($Cfg, $Name)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    $agents = Discover-Agents $Cfg.relay_root
    if ($Name -in $agents) { return $Name }
    # Substring match for convenience
    $match = $agents | Where-Object { $_ -like "*$Name*" } | Select-Object -First 1
    if (-not $match) {
        throw "Unknown agent '$Name'. Discovered: $($agents -join ', ')"
    }
    return $match
}

function Get-AgentProcess {
    param($Cfg, $Agent)
    $agentDir = Join-Path $Cfg.relay_root $Agent
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($agentDir) }
}

# ----- Commands -----

function Cmd-Install {
    $cfg = Get-RelayTeamConfig
    Write-Host "Installing relay-team..." -ForegroundColor Cyan

    # 1. Optional Outlook autostart shortcut.
    if ($cfg.outlook_autostart) {
        $outlookCandidates = @(
            "C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "C:\Program Files (x86)\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "C:\Program Files\Microsoft Office\Office16\OUTLOOK.EXE",
            "C:\Program Files (x86)\Microsoft Office\Office16\OUTLOOK.EXE"
        )
        $running = Get-Process OUTLOOK -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($running) { $outlookCandidates = @($running.Path) + $outlookCandidates }
        $outlookExe = $outlookCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        $startupDir = [Environment]::GetFolderPath("Startup")
        $linkPath = Join-Path $startupDir "Outlook (relay-team minimised).lnk"
        if ($outlookExe) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($linkPath)
            $shortcut.TargetPath = $outlookExe
            $shortcut.Arguments = "/minimized"
            $shortcut.WindowStyle = 7
            $shortcut.Save()
            Write-Host "  [ok] Outlook autostart shortcut: $linkPath" -ForegroundColor Green
        } else {
            Write-Host "  ! OUTLOOK.EXE not found -- skipped autostart" -ForegroundColor Yellow
        }
    }

    # 2. Per-agent Task Scheduler entries.
    $allMeta = Get-AllAgentMeta -Cfg $cfg
    if ($allMeta.Count -eq 0) {
        Write-Host "  ! No agents discovered under $($cfg.relay_root)" -ForegroundColor Yellow
        Write-Host "    Drop an agent dir there (e.g. copy from examples/) and re-run install." -ForegroundColor Gray
        return
    }
    foreach ($agent in $allMeta.Keys) {
        $meta = $allMeta[$agent]
        $startScript = Join-Path $meta.agent_dir "start.ps1"
        if (-not (Test-Path $startScript)) {
            Write-Host "  ! $agent : start.ps1 missing -- skipped" -ForegroundColor Yellow
            continue
        }

        $action = New-ScheduledTaskAction `
            -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startScript`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $trigger.Delay = "PT$($meta.startup_delay_sec)S"

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable:$false `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 5) `
            -ExecutionTimeLimit (New-TimeSpan -Days 7)

        $principal = New-ScheduledTaskPrincipal `
            -UserId $env:USERNAME `
            -LogonType Interactive `
            -RunLevel Limited

        Unregister-ScheduledTask -TaskName $meta.task_name -Confirm:$false -ErrorAction SilentlyContinue

        Register-ScheduledTask `
            -TaskName $meta.task_name `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "relay-team agent: $agent" | Out-Null

        Write-Host "  [ok] $agent -> task '$($meta.task_name)' (delay $($meta.startup_delay_sec)s)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Done. Agents will start at next logon." -ForegroundColor Green
    Write-Host "Or run 'relay-team start' to launch one foreground now."
}

function Cmd-Uninstall {
    $cfg = Get-RelayTeamConfig
    Write-Host "Uninstalling relay-team Task Scheduler entries..." -ForegroundColor Cyan
    $allMeta = Get-AllAgentMeta -Cfg $cfg
    foreach ($agent in $allMeta.Keys) {
        $taskName = $allMeta[$agent].task_name
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "  [ok] removed $taskName" -ForegroundColor Green
        } catch {
            Write-Host "  - $taskName not registered (already removed?)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "Note: agent files and state under $($cfg.relay_root) left in place." -ForegroundColor Gray
}

function Cmd-Start {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    if (-not $AgentName) {
        $agents = Discover-Agents $cfg.relay_root
        Write-Host "Starting $($agents.Count) discovered agents in separate windows (skipping any already running)..." -ForegroundColor Cyan
        foreach ($agent in $agents) {
            $existing = @(Get-AgentProcess -Cfg $cfg -Agent $agent)
            if ($existing.Count -gt 0) {
                Write-Host "  - $agent already running (pid $($existing[0].ProcessId)) -- skipped" -ForegroundColor Gray
                continue
            }
            $startScript = Join-Path (Join-Path $cfg.relay_root $agent) "start.ps1"
            Start-Process powershell.exe -ArgumentList @("-NoProfile", "-File", $startScript) -WindowStyle Normal
            Write-Host "  [ok] spawned $agent" -ForegroundColor Green
        }
        return
    }
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    $existing = @(Get-AgentProcess -Cfg $cfg -Agent $agent)
    if ($existing.Count -gt 0) {
        Write-Host "$agent is already running (pid $($existing[0].ProcessId)). Use 'relay-team restart $agent' to relaunch." -ForegroundColor Yellow
        return
    }
    $startScript = Join-Path (Join-Path $cfg.relay_root $agent) "start.ps1"
    Write-Host "Starting $agent (foreground)..." -ForegroundColor Cyan
    & $startScript
}

function Cmd-Stop {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $targets = if ($AgentName) { @(Resolve-Agent -Cfg $cfg -Name $AgentName) } else { Discover-Agents $cfg.relay_root }
    foreach ($agent in $targets) {
        $procs = @(Get-AgentProcess -Cfg $cfg -Agent $agent)
        if ($procs.Count -eq 0) {
            Write-Host "  - $agent : not running" -ForegroundColor Gray
            continue
        }
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                Write-Host "  [ok] killed $agent (pid $($p.ProcessId))" -ForegroundColor Green
            } catch {
                Write-Host "  ! failed to stop pid $($p.ProcessId): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

function Cmd-Restart {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $targets = if ($AgentName) { @(Resolve-Agent -Cfg $cfg -Name $AgentName) } else { Discover-Agents $cfg.relay_root }
    foreach ($agent in $targets) {
        Cmd-Stop $agent
        Start-Sleep -Seconds 2
        $taskName = (Get-AgentMeta -Cfg $cfg -Agent $agent).task_name
        try {
            Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
            Write-Host "  [ok] restarted $agent via Task Scheduler" -ForegroundColor Green
        } catch {
            Write-Host "  ! could not start scheduled task '$taskName' -- start manually with 'relay-team start $agent'" -ForegroundColor Yellow
        }
    }
}

function Cmd-Status {
    $cfg = Get-RelayTeamConfig
    $allMeta = Get-AllAgentMeta -Cfg $cfg
    if ($allMeta.Count -eq 0) {
        Write-Host "No agents discovered under $($cfg.relay_root)" -ForegroundColor Yellow
        return
    }
    foreach ($agent in $allMeta.Keys | Sort-Object) {
        $meta = $allMeta[$agent]
        $procs = @(Get-AgentProcess -Cfg $cfg -Agent $agent)
        $running = $procs.Count -gt 0
        $color = if ($running) { "Green" } else { "DarkGray" }
        $state = if ($running) { "RUNNING (pid $($procs[0].ProcessId))" } else { "stopped" }

        Write-Host ""
        Write-Host "[$agent] $state" -ForegroundColor $color

        $statusMd = Join-Path $meta.agent_dir "state\status.md"
        if (Test-Path $statusMd) {
            $age = (Get-Date) - (Get-Item $statusMd).LastWriteTime
            $ageStr = if ($age.TotalMinutes -lt 60) {
                "{0:N0}m ago" -f $age.TotalMinutes
            } else {
                "{0:N1}h ago" -f $age.TotalHours
            }
            Write-Host "  status.md updated: $ageStr" -ForegroundColor DarkGray
        }

        $log = Join-Path $meta.agent_dir "state\start.log"
        if (Test-Path $log) {
            $lastLine = Get-Content $log -Tail 1 -ErrorAction SilentlyContinue
            if ($lastLine) {
                Write-Host "  last log:   $lastLine" -ForegroundColor DarkGray
            }
        }

        try {
            $task = Get-ScheduledTask -TaskName $meta.task_name -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -TaskName $meta.task_name
            Write-Host "  task:       $($task.State) (last result: $($info.LastTaskResult))" -ForegroundColor DarkGray
        } catch {
            Write-Host "  task:       not registered (run 'relay-team install')" -ForegroundColor DarkYellow
        }
    }
    Write-Host ""
}

function Cmd-Tell {
    param($AgentName, [string[]]$MessageWords)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    if (-not $MessageWords -or $MessageWords.Count -eq 0) {
        Write-Host "Usage: relay-team tell <agent> <message...>" -ForegroundColor Yellow
        return
    }
    $tellScript = Join-Path $PSScriptRoot "relay-tell.ps1"
    & $tellScript $agent @MessageWords
}

function Cmd-Logs {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    $log = Join-Path (Join-Path $cfg.relay_root $agent) "state\logs\claude_stream.jsonl"
    if (-not (Test-Path $log)) {
        Write-Host "No log yet at $log. Has the agent run?" -ForegroundColor Yellow
        return
    }
    Write-Host "Tailing $log (Ctrl-C to stop)..." -ForegroundColor Cyan
    Get-Content $log -Wait -Tail 20
}

function Cmd-StatusTail {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    $statusMd = Join-Path (Join-Path $cfg.relay_root $agent) "state\status.md"
    if (-not (Test-Path $statusMd)) {
        Write-Host "No status.md yet at $statusMd." -ForegroundColor Yellow
        return
    }
    Write-Host "Tailing $statusMd (Ctrl-C to stop)..." -ForegroundColor Cyan
    Get-Content $statusMd -Wait
}

function Cmd-Config {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    Start-Process (Join-Path (Join-Path $cfg.relay_root $agent) "config.json")
}

function Cmd-ClaudeMd {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    Start-Process (Join-Path (Join-Path $cfg.relay_root $agent) "CLAUDE.md")
}

function Cmd-EnableRemote {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    $cfgPath = Join-Path (Join-Path $cfg.relay_root $agent) "config.json"
    $obj = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
    if (-not $obj.runner) {
        Add-Member -InputObject $obj -NotePropertyName runner -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $name = "relay-$agent"
    Add-Member -InputObject $obj.runner -NotePropertyName remote_control_name -NotePropertyValue $name -Force
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($cfgPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [ok] remote control ENABLED for $agent (name '$name')" -ForegroundColor Green
    Write-Host "    Restart the agent (relay-team restart $agent) for it to take effect." -ForegroundColor Gray
}

function Cmd-DisableRemote {
    param($AgentName)
    $cfg = Get-RelayTeamConfig
    $agent = Resolve-Agent -Cfg $cfg -Name $AgentName
    $cfgPath = Join-Path (Join-Path $cfg.relay_root $agent) "config.json"
    $obj = Get-Content $cfgPath -Raw -Encoding utf8 | ConvertFrom-Json
    if (-not $obj.runner) {
        Write-Host "remote control already disabled for $agent." -ForegroundColor Gray
        return
    }
    Add-Member -InputObject $obj.runner -NotePropertyName remote_control_name -NotePropertyValue "" -Force
    $json = $obj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($cfgPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [ok] remote control DISABLED for $agent" -ForegroundColor Green
}

function Cmd-Init {
    param($AgentName)
    if (-not $AgentName) {
        Write-Host "Usage: relay-team init <agent-name>" -ForegroundColor Yellow
        return
    }
    if ($AgentName -notmatch '^[a-z][a-z0-9_-]*$') {
        Write-Host "Agent name must be lowercase alnum + dash/underscore (regex: ^[a-z][a-z0-9_-]*$)" -ForegroundColor Red
        return
    }
    $cfg = Get-RelayTeamConfig
    $dest = Join-Path $cfg.relay_root $AgentName
    if (Test-Path $dest) {
        Write-Host "Path exists: $dest" -ForegroundColor Red
        return
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dest "plugins") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dest "state") -Force | Out-Null

    # start.ps1 -- references the launcher in the user's config dir, so
    # this agent works regardless of where relay-team is checked out.
    $startContent = "# Launcher for the $AgentName agent.`n& `"`$env:USERPROFILE\.relay-team\start-agent.ps1`" -AgentName `"$AgentName`"`nexit `$LASTEXITCODE`n"
    [System.IO.File]::WriteAllText((Join-Path $dest "start.ps1"), $startContent, [System.Text.UTF8Encoding]::new($false))

    # agent.json
    $titleSuffix = ($AgentName -split '[-_]' | ForEach-Object {
        if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { '' }
    }) -join ''
    $agentMeta = @{
        task_name_suffix = $titleSuffix
        startup_delay_sec = 60
        description = "TODO: describe what this agent does"
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $dest "agent.json"), $agentMeta, [System.Text.UTF8Encoding]::new($false))

    # config.json — minimal
    $cfgContent = @"
{
  "claude": {
    "model": "sonnet",
    "additional_args": []
  },
  "runner": {
    "mcp_port": 9300,
    "log_level": "INFO"
  },
  "plugins": {
    "inbox": {
      "enabled": true,
      "path": "state/inbox.jsonl",
      "poll_sec": 2,
      "default_source": "user"
    }
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $dest "config.json"), $cfgContent, [System.Text.UTF8Encoding]::new($false))

    # CLAUDE.md — minimal placeholder
    $claudeContent = @"
# You are the $AgentName Agent

[REPLACE THIS WITH YOUR AGENT'S MISSION]

External events arrive serialised into this conversation as user
messages with prefix:

- ``[FROM user | via=inbox]`` -- direct message via ``relay-team tell``

## Mission

[Describe what this agent does, what it watches, what it acts on.]

## Hard rules

- [List rules the agent must never violate.]

## Tools

- ``gh`` CLI (if needed)
- ``git`` (if needed)
- Bash + PowerShell

## On startup

[How should the agent behave on first boot? Wait passively? Snapshot
state? Send a hello?]
"@
    [System.IO.File]::WriteAllText((Join-Path $dest "CLAUDE.md"), $claudeContent, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Created agent skeleton: $dest" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Edit $dest\CLAUDE.md to define the agent's mission."
    Write-Host "  2. Edit $dest\config.json to set the right MCP port and add plugins (e.g. github)."
    Write-Host "  3. If you add the github plugin, copy plugins/github/ from your relay source into $dest\plugins\."
    Write-Host "  4. Run 'relay-team install' to register it with Task Scheduler."
    Write-Host "  5. Run 'relay-team start $AgentName' for a foreground first run."
}

function Show-Help {
    Write-Host "relay-team -- multi-agent orchestration CLI for relay" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:  relay-team <command> [args]"
    Write-Host ""
    Write-Host "Setup:"
    Write-Host "  install                        Register Task Scheduler entries for all discovered agents"
    Write-Host "  uninstall                      Remove all Task Scheduler entries this tool created"
    Write-Host "  init <name>                    Scaffold a new empty agent under your relay_root"
    Write-Host ""
    Write-Host "Lifecycle:"
    Write-Host "  start [agent]                  Foreground launch (or all if no agent given)"
    Write-Host "  stop [agent]                   Kill the running runner process(es)"
    Write-Host "  restart [agent]                Stop then start (uses Task Scheduler)"
    Write-Host "  status                         Show all agents' run state, last log, status.md age"
    Write-Host ""
    Write-Host "Comms:"
    Write-Host "  tell <agent> <message...>      Inject a user message via inbox.jsonl"
    Write-Host "  logs <agent>                   Tail the agent's claude_stream.jsonl"
    Write-Host "  status-tail <agent>            Tail the agent's state/status.md"
    Write-Host ""
    Write-Host "Per-agent edits:"
    Write-Host "  config <agent>                 Open the agent's config.json in default editor"
    Write-Host "  claude-md <agent>              Open the agent's CLAUDE.md in default editor"
    Write-Host "  enable-remote <agent>          Add /remote-control bootstrap so it shows on claude.ai/code"
    Write-Host "  disable-remote <agent>         Remove it"
    Write-Host ""
    try {
        $cfg = Get-RelayTeamConfig
        $agents = Discover-Agents $cfg.relay_root
        if ($agents.Count -gt 0) {
            Write-Host "Discovered agents under $($cfg.relay_root):"
            foreach ($a in $agents) { Write-Host "  - $a" }
        } else {
            Write-Host "No agents discovered yet under $($cfg.relay_root). Use 'relay-team init <name>' or copy from examples/."
        }
    } catch {
        Write-Host "(config not loaded yet -- run install.ps1 from the relay-team repo first)" -ForegroundColor Gray
    }
}

# ----- Dispatch -----

$ArgList = if ($Args) { @($Args) } else { @() }
$Arg0    = if ($ArgList.Count -gt 0) { $ArgList[0] } else { $null }
$ArgRest = if ($ArgList.Count -gt 1) { $ArgList[1..($ArgList.Count - 1)] } else { @() }

switch ($Command) {
    "install"          { Cmd-Install }
    "uninstall"        { Cmd-Uninstall }
    "init"             { Cmd-Init $Arg0 }
    "start"            { Cmd-Start $Arg0 }
    "stop"             { Cmd-Stop $Arg0 }
    "restart"          { Cmd-Restart $Arg0 }
    "status"           { Cmd-Status }
    "tell"             { Cmd-Tell $Arg0 $ArgRest }
    "logs"             { Cmd-Logs $Arg0 }
    "status-tail"      { Cmd-StatusTail $Arg0 }
    "config"           { Cmd-Config $Arg0 }
    "claude-md"        { Cmd-ClaudeMd $Arg0 }
    "enable-remote"    { Cmd-EnableRemote $Arg0 }
    "disable-remote"   { Cmd-DisableRemote $Arg0 }
    "help"             { Show-Help }
    "-h"               { Show-Help }
    "--help"           { Show-Help }
    ""                 { Show-Help }
    $null              { Show-Help }
    default {
        Write-Host "Unknown command: '$Command'" -ForegroundColor Red
        Write-Host ""
        Show-Help
        exit 1
    }
}
