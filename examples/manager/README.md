# Example: manager agent

The triage layer. Watches your inbox (Outlook), GitHub notifications, and any other event sources you wire up. For each event, decides: actionable / FYI / noise; which product/repo it concerns; whether to dispatch.

When work needs doing, it creates a GitHub issue in the right repo, assigned to your account. The coder agent for that repo (filtering on `assignee:@me`) picks it up automatically. The manager doesn't write code; it just routes.

## What you fill in

In `CLAUDE.md`:

| Placeholder | What to replace with |
|---|---|
| `[AGENT_NAME]` | What you named this dir (e.g. `my-manager`) |
| `[YOUR_NAME]` | Your real name |
| `[YOUR_GH_USERNAME]` | Your GitHub login |
| `[YOUR_EMAIL]` | Your work email (for the outlook plugin to know who's "you") |
| `[ORG]` | Your GitHub org (e.g. `acme-corp`) |
| `[PRODUCT_REPO_1]`, `[PRODUCT_REPO_2]` | The product repos this manager dispatches to |
| `[CENTRAL_REPO]` | (Optional) A shared central tracker like a customer-support or bug-tracking repo |
| `[LABEL_VOCAB]` | The label set the coder agents expect (e.g. `ai:queued`, `ai:triage`, `ai:needs-info`) |

In `config.json`: pick which plugins you want enabled. The example enables `outlook`, `inbox`, and `github` (notifications + watchers). Drop the ones you don't need.

## Outlook plugin (optional)

If you want the manager to read your email, you need an Outlook MCP server installed and runnable. The example config points at one — replace the path with where you installed yours, or remove the outlook section to skip email.

If your `outlook_autostart` is `true` in `~/.relay-team/config.json`, `relay-team install` will create a startup shortcut so Outlook minimises to tray on logon. Useful since the outlook plugin needs Outlook running.

## Plugins you need to copy in

```powershell
Copy-Item -Recurse <relay_source>\plugins\inbox    <relay_root>\my-manager\plugins\
Copy-Item -Recurse <relay_source>\plugins\github   <relay_root>\my-manager\plugins\
Copy-Item -Recurse <relay_source>\plugins\outlook  <relay_root>\my-manager\plugins\  # only if using outlook
```

## What the manager outputs

The manager maintains `state/status.md` — a live "what's on your plate" view. You can `relay-team status-tail my-manager` to watch it update in real time. Useful as a single-screen dashboard while you work on something else.

It can also draft emails (never sends — drafts only) when something needs your eyes.
