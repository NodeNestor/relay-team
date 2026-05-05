# Example: coder agent

A single-repo coder. Watches one GitHub repo for issues assigned to you, branches off your default branch, makes the change, runs tests locally, opens a PR. Never merges its own PRs (that's the reviewer's job, or yours).

## What you fill in

In `CLAUDE.md`:

| Placeholder | What to replace with |
|---|---|
| `[AGENT_NAME]` | Whatever you named this agent dir (e.g. `my-coder`) |
| `[YOUR_GH_USERNAME]` | Your GitHub login (the one your `gh` CLI is authenticated as) |
| `[YOUR_ORG]/[YOUR_REPO]` | The repo this agent owns (e.g. `acme-corp/widget-app`) |
| `[/PATH/TO/LOCAL/CLONE]` | Absolute path to your local clone of the repo |
| `[DEFAULT_BRANCH]` | Usually `main` or `master` |
| `[BRANCH_PREFIX]` | Convention for agent branches, e.g. `agent/issue-` |
| `[BUILD_COMMAND]` | `npm run build`, `dotnet build`, `cargo build`, etc. |
| `[TEST_COMMAND]` | `npm test`, `pytest`, `go test ./...`, etc. |
| `[STACK_DESCRIPTION]` | One sentence: language + framework + test runner |

In `config.json`:

| Field | What to set |
|---|---|
| `claude.model` | `opus` for best code quality, `sonnet` for cheaper |
| `claude.additional_args[1]` | Local clone path — `--add-dir` exposes it to the model |
| `runner.mcp_port` | A unique port (9301 in this example; pick something else if it collides) |
| `plugins.github.watchers[0].repo` | `[YOUR_ORG]/[YOUR_REPO]` |
| `plugins.github.watchers[1].repo` | Same |

## Plugins you need to copy in

After `Copy-Item`-ing this dir into your `relay_root`, also copy:

```powershell
Copy-Item -Recurse <relay_source>\plugins\inbox    <relay_root>\my-coder\plugins\
Copy-Item -Recurse <relay_source>\plugins\github   <relay_root>\my-coder\plugins\
```

## Optional: pair with a reviewer

If you also run the reviewer example, the reviewer will pick up this coder's PRs (it filters by branch prefix `agent/issue-*` and the commit trailer `Autonomously-by:`), review them, and squash-merge the good ones. Make sure the `BRANCH_PREFIX` and the commit trailer in your CLAUDE.md match what the reviewer expects.
