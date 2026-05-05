# Launcher for this agent. Rename "reviewer" to whatever you named the dir.
& "$env:USERPROFILE\.relay-team\start-agent.ps1" -AgentName "reviewer"
exit $LASTEXITCODE
