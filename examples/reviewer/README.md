# Example: reviewer agent

Watches AI-authored PRs in one repo (filtered by branch prefix + commit trailer), reviews them rigorously, squash-merges the good ones, escalates the rest. Optionally tags + cuts a release after a successful merge.

This is the inverse of the coder: where the coder is forbidden to merge, the reviewer is the one allowed to merge — but only AI work, never human PRs.

## What you fill in

In `CLAUDE.md`:

| Placeholder | What to replace with |
|---|---|
| `[AGENT_NAME]` | Whatever you named this agent dir (e.g. `my-reviewer`) |
| `[CODER_AGENT_NAME]` | The coder it pairs with (e.g. `my-coder`) |
| `[YOUR_GH_USERNAME]` | Your GitHub login |
| `[YOUR_ORG]/[YOUR_REPO]` | The repo this reviewer watches |
| `[/PATH/TO/REVIEWER_CLONE]` | Absolute path to a **separate** local clone (don't share with the coder — they'd fight over the working tree) |
| `[BRANCH_PREFIX]` | Must match the coder's branch prefix (e.g. `agent/issue-`) |
| `[COMMIT_TRAILER]` | Must match what the coder writes (e.g. `Autonomously-by: my-coder`) |
| `[BUILD_COMMAND]` | What "build" means for your stack |
| `[TEST_COMMAND]` | What "test" means for your stack |
| `[VERSION_LOCATION]` | Where versions live: `git tags only`, `package.json`, `Cargo.toml`, `*.csproj`, etc. — informs the release flow |
| `[RELEASE_TRIGGER]` | How releases happen — push tag, GitHub release, CI workflow trigger, etc. |

In `config.json`:

| Field | What to set |
|---|---|
| `claude.model` | `opus` strongly recommended (you want it to actually catch bugs) |
| `claude.additional_args[1]` | Reviewer's local clone path |
| `runner.mcp_port` | Unique port (9302 in this example) |
| `plugins.github.watchers[0].repo` | `[YOUR_ORG]/[YOUR_REPO]` |
| `plugins.github.watchers[0].filter` | The author + branch + label filter that selects only AI PRs you want reviewed |

## Why a separate clone

The coder is constantly branching, pushing, and pulling in its working tree. If the reviewer used the same dir, `gh pr checkout` would race against the coder's `git push` and you'd get random failures. Cheap fix: clone the repo twice, into two different paths, one per agent.

## Release decisions

The example CLAUDE.md includes a release-decision section. **Skim and adjust to your stack** — release semantics vary a lot (some teams release every PR, some batch, some never auto-release). The defaults are conservative: only release on `fix:` (patch) or `feat:` (minor) PRs, never auto-major.

## Plugins you need to copy in

```powershell
Copy-Item -Recurse <relay_source>\plugins\inbox    <relay_root>\my-reviewer\plugins\
Copy-Item -Recurse <relay_source>\plugins\github   <relay_root>\my-reviewer\plugins\
```
