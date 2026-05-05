# Launcher for this agent. After you copy this dir into your relay_root,
# rename "coder" below to whatever you named the dir (or run via the
# relay-team CLI which figures it out from the path).
& "$env:USERPROFILE\.relay-team\start-agent.ps1" -AgentName "coder"
exit $LASTEXITCODE
