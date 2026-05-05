# relay-team

A multi-agent orchestration CLI for [`relay`](https://github.com/NodeNestor/relay) — the lightweight two-way runner for Claude Code. Manage a team of always-on Claude Code agents from one command: install them, start/stop/restart, tail their logs, send them messages.

`relay` runs **one** agent. `relay-team` runs **a coordinated team of agents** that watch GitHub, email, webhooks, etc., dispatch work to each other through GitHub itself, and keep running across logons via Windows Task Scheduler.

```
PS> relay-team status

[manager]            RUNNING (pid 14340)
  status.md updated: 8m ago
  task:              Ready

[coder]              RUNNING (pid 7948)
  task:              Ready

[reviewer]           RUNNING (pid 26048)
  task:              Ready
```

## Why a team

A single Claude Code agent is good at handling its slice of the world. But real workflows are rarely one slice:

- A **manager** agent watches your inbox + GitHub mentions, triages each event, and creates tickets in the right repos.
- A **coder** agent watches its assigned tickets in one repo, branches, codes, tests, opens PRs.
- A **reviewer** agent watches PRs the coder opened, reviews them rigorously, merges the good ones, escalates the rest.

Each agent is small and focused. They communicate not over RPC or shared memory but **through GitHub itself** — issue comments, labels, PR comments. The issue tracker is the message bus. This is robust, auditable, and survives any agent dying alone.

`relay-team` is the CLI that makes this kind of multi-agent setup feel like one tool instead of N hand-rolled scripts.

## What's in the box

- **`relay-team.ps1`** — the CLI. `install`, `uninstall`, `start`, `stop`, `restart`, `status`, `tell`, `logs`, `init`, etc.
- **`relay-tell.ps1`** — focused message-sending script (also available via `relay-team tell`).
- **`install.ps1`** — interactive config wizard. Run once to set up paths.
- **`install-cli.ps1`** — adds `relay-team` and `relay-tell` to your PowerShell profile so you can run them from anywhere.
- **`shared/start-agent.ps1`** — the generic launcher each agent's `start.ps1` calls into.
- **`examples/`** — three reference agents: `coder/`, `reviewer/`, `manager/`. Copy one, fill in the placeholders, you have a working agent.

## Prerequisites

You need these installed before `relay-team` is useful:

1. **Windows + PowerShell 5.1+** (Windows 10/11 default).
2. **Python 3.12** in a venv. `relay-team` assumes one venv shared across all agents (Task Scheduler entries reference one `python.exe` path).
3. **`gh` CLI** authenticated. Each agent runs `gh` calls; the active account is what shapes their identity.
4. **Claude Code** installed and signed in (`claude` on PATH).
5. **`relay`** cloned somewhere — `relay-team` invokes `python -m runner` from that directory. See [`NodeNestor/relay`](https://github.com/NodeNestor/relay) for the runner itself.

## Install

```powershell
git clone https://github.com/NodeNestor/relay-team.git
cd relay-team
.\install.ps1            # interactive wizard, writes ~/.relay-team/config.json
.\install-cli.ps1        # adds relay-team / relay-tell to your $PROFILE
```

After that, in any new PowerShell window:

```powershell
relay-team help
```

## Quick start with an example agent

```powershell
# Pick one of the examples and copy it into your relay-root.
# Replace <relay-root> with the path you gave install.ps1
# (defaults to %USERPROFILE%\relay-agents).
Copy-Item -Recurse examples\coder <relay-root>\my-coder

# Open my-coder/CLAUDE.md and replace [PLACEHOLDERS]
# with your repo, GitHub username, working directory, etc.
notepad <relay-root>\my-coder\CLAUDE.md

# Edit my-coder/config.json — set the watcher repos and an MCP port
# that doesn't collide with another agent.
notepad <relay-root>\my-coder\config.json

# Register and start it.
relay-team install        # registers Task Scheduler entries for all agents
relay-team start my-coder # foreground for the first run, watch it boot
```

`relay-team install` re-registers Task Scheduler entries for every agent it discovers. Adding a new agent is "drop a folder under your relay-root, run `install`."

## Concepts

### Agent

A directory under your `relay_root`. Minimum contents:

```
my-agent/
├── start.ps1       # one-line wrapper that calls shared/start-agent.ps1
├── config.json     # runner config (model, MCP port, plugins)
├── CLAUDE.md       # the agent's prompt — its identity and rules
├── agent.json      # (optional) task name + startup delay metadata
├── plugins/        # plugin source dirs (copied from relay's plugins/)
│   ├── inbox/
│   └── github/
└── state/          # auto-created. logs, inbox, status, session ID
```

The agent's `CLAUDE.md` is its **system prompt** — it defines what the agent thinks it is, what it watches, what it's allowed to do. This is where the leverage is.

### Watchers and the inbox

Two ways events get into an agent's session:

- **Watchers** poll external sources (GitHub issues, PRs, runs, notifications) and emit events into the agent's conversation.
- **Inbox** is a file (`state/inbox.jsonl`) any process can append to. `relay-team tell <agent> "<message>"` is just a wrapper that appends one JSON line. The inbox plugin polls it every 2s.

Watchers are always-on; the inbox is for ad-hoc nudges from you or other tools.

### Multi-agent communication

Agents on the same machine **don't** talk to each other directly. They share state through GitHub:

- The manager creates an issue in `your-org/your-app` and assigns it to your account.
- The coder agent's watcher (filtered to `assignee:@me` on `your-org/your-app`) sees the new issue and starts work.
- The coder opens a PR. The reviewer agent's watcher (filtered to `author:@me head:agent/issue-*`) sees the PR and reviews it.
- Reviewer comments → coder's PR-comments watcher fires → coder fixes → reviewer re-reviews → eventually merges.

This pattern works across machines too: another teammate's `manager` on their PC creating issues your `coder` picks up. No shared infrastructure needed.

## CLI reference

```
relay-team install             Register Task Scheduler entries for all discovered agents
relay-team uninstall           Remove all Task Scheduler entries this tool created
relay-team start [agent]       Foreground launch (or all in separate windows if no agent)
relay-team stop [agent]        Kill the running runner process
relay-team restart [agent]     Stop, then start via Task Scheduler
relay-team status              Show every agent's run state, last log line, status.md age
relay-team tell <agent> <msg>  Inject a user message via inbox.jsonl
relay-team logs <agent>        Tail the agent's claude_stream.jsonl
relay-team status-tail <agent> Tail the agent's state/status.md
relay-team config <agent>      Open the agent's config.json in your default editor
relay-team claude-md <agent>   Open the agent's CLAUDE.md in your default editor
relay-team enable-remote <a>   Add /remote-control to bootstrap so it shows on claude.ai/code
relay-team disable-remote <a>  Remove it
relay-team init <name>         Scaffold a new empty agent dir from the bare-minimum template
relay-team help
```

## Configuration

`relay-team` reads its global config from `~/.relay-team/config.json`:

```json
{
  "relay_root": "C:\\Users\\you\\relay-agents",
  "venv_python": "C:\\Users\\you\\relay-venv\\Scripts\\python.exe",
  "relay_source": "C:\\Users\\you\\relay",
  "task_name_prefix": "RelayTeam-",
  "outlook_autostart": false
}
```

| Field | Meaning |
|---|---|
| `relay_root` | Directory containing agent subdirectories. Each subdir with a `start.ps1` is treated as one agent. |
| `venv_python` | Absolute path to the Python interpreter that `python -m runner` will use. |
| `relay_source` | Path to your local clone of `NodeNestor/relay`. The launcher runs `python -m runner` from here. |
| `task_name_prefix` | Prefix for Windows Task Scheduler entries. Default `RelayTeam-`. |
| `outlook_autostart` | If `true`, `install` adds an Outlook minimised-to-tray autostart shortcut (useful if any agent uses the outlook plugin). Default `false`. |

Per-agent overrides live in `<agent>/agent.json`:

```json
{
  "task_name_suffix": "MyCoder",
  "startup_delay_sec": 90,
  "description": "Coder agent for your-org/your-app"
}
```

Both fields are optional. If `task_name_suffix` is absent, it's derived from the directory name (e.g., `my-coder` → `MyCoder`). If `startup_delay_sec` is absent, defaults to 60s.

## Example agents

`examples/` ships with three reference shells modelled on a real production team. Each is fully templated with `[PLACEHOLDERS]` you fill in:

- **`coder/`** — watches assigned issues in one repo, branches off `main` per issue, codes, tests locally, opens PR. Never merges its own.
- **`reviewer/`** — watches AI-authored PRs (filtered by branch prefix and commit trailer), reviews rigorously, squash-merges when good, escalates to human otherwise. Optionally tags + cuts a release.
- **`manager/`** — watches your email + GitHub notifications across multiple repos, triages, dispatches by creating issues in the right product repo. Maintains a live `status.md` of what's on your plate.

Together they form a closed loop: external event → manager triages → coder fulfils → reviewer ships. No human in the middle for routine work.

See [`examples/README.md`](examples/README.md) for the full pattern walkthrough.

## License

MIT. See [LICENSE](LICENSE).
