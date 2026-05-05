# Example agents

Three reference agents you can copy into your `relay_root` and adapt. Together they form a closed loop: external event → manager triages → coder fulfils → reviewer ships. Each one is a standalone agent, but the value compounds when you run all three.

## The three roles

```
              external world
        (email, GitHub mentions,
         customer reports, etc.)
                  │
                  ▼
            ┌──────────┐
            │ manager  │   triages, dispatches
            └─────┬────┘
                  │ (creates GitHub issue)
                  ▼
            ┌──────────┐
            │  coder   │   branches, codes, tests, opens PR
            └─────┬────┘
                  │ (opens PR)
                  ▼
            ┌──────────┐
            │ reviewer │   reviews, merges, optionally releases
            └──────────┘
```

Communication between agents happens **through GitHub itself** — issue comments, labels, PR comments. No shared memory, no RPC. The issue tracker is the message bus.

## Pattern walkthrough

1. **You receive a customer email.** The `manager` agent's outlook plugin sees it, classifies it (which product? severity? actionable?), and creates a GitHub issue in the right repo, assigned to your account.
2. **The issue is now assigned to you.** The `coder` agent's GitHub watcher fires (filtered to `assignee:@me`), reads the issue, branches off your default branch, codes the change, runs tests, opens a PR.
3. **The PR exists.** The `reviewer` agent's GitHub watcher fires (filtered to AI-authored PRs by branch prefix + commit trailer). It reads the diff, decides:
   - **Approve and merge** → squash-merge, optionally tag a release
   - **Request changes** → comment on the PR; the coder's PR-comments watcher sees it and pushes a fix
   - **Hand off to human** → label `ai:needs-human` and stop
4. **Loop closes.** Either the change is shipped, or it's clearly flagged for human attention. You see status via `relay-team status` and per-agent `state/status.md`.

## Using an example

Each example dir contains:

```
example/
├── README.md            # what this agent does, what to fill in
├── CLAUDE.md            # the agent's system prompt -- has [PLACEHOLDERS]
├── config.json          # runner config -- has [PLACEHOLDERS]
├── start.ps1            # one-line launcher
└── agent.json           # task name + startup delay
```

To use one:

```powershell
# 1. Copy into your relay_root.
Copy-Item -Recurse examples\coder $env:USERPROFILE\relay-agents\my-coder

# 2. Fill in placeholders in CLAUDE.md and config.json.
notepad $env:USERPROFILE\relay-agents\my-coder\CLAUDE.md
notepad $env:USERPROFILE\relay-agents\my-coder\config.json

# 3. Copy the plugins you enabled in config.json from your relay source.
#    (relay loads plugins from <agent>/plugins/, not from the central
#    relay/plugins/ dir.)
Copy-Item -Recurse <relay_source>\plugins\github   $env:USERPROFILE\relay-agents\my-coder\plugins\
Copy-Item -Recurse <relay_source>\plugins\inbox    $env:USERPROFILE\relay-agents\my-coder\plugins\

# 4. Pick a unique mcp_port in config.json (each agent needs its own).
#    The examples use 9301 / 9302 / 9303 -- collision-safe if you run
#    all three; pick higher numbers if you add more.

# 5. Register and start.
relay-team install
relay-team start my-coder
```

## Picking what to use first

If you're new to running agents, **start with `coder/` alone** — it's the most concrete and the easiest to verify (you assign it an issue, it opens a PR). Add `reviewer/` second once you have a steady stream of AI PRs and want them auto-merged. Add `manager/` last — it's the most opinionated and works best when there are downstream coder agents to dispatch to.

You don't have to use all three. A reviewer-only setup is fine. So is a manager-only setup that just triages your inbox into issues for human attention. The pattern composes.
