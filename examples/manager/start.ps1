# Launcher for this agent. Rename "manager" to whatever you named the dir.
& "$env:USERPROFILE\.relay-team\start-agent.ps1" -AgentName "manager"
exit $LASTEXITCODE
