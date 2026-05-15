# daily-todo-nextstep

Daily Slack activity digest that posts to your own Slackbot DM, with two persistent
canvases for "Owed by Me" / "Owed to Me" action items that you can check off in Slack
to remove from future digests.

Built as a Claude Code skill + macOS launchd job. Runs locally on your Mac without
needing Claude Code to be open.

## What it does

Every weekday at 08:03 (your local time), the job:

1. Scans the last 3 days of your Slack activity — private channels, 1:1 DMs, group DMs,
   plus public channels where you were @-mentioned.
2. DMs you a "Key discussions" summary in your Slackbot self-DM.
3. Maintains two persistent Slack canvases in that same DM:
   - **Action Items — Owed by Me**
   - **Action Items — Owed to Me**
4. Each canvas bullet links back to the source Slack thread (`↗`).
5. Check items off in the canvas → they vanish from tomorrow's digest.

## Prerequisites

- macOS (uses launchd)
- [Claude Code CLI](https://claude.ai/code) installed (`claude` binary in `$PATH`)
- Slack MCP server authenticated in your local Claude Code config (`/mcp` inside Claude
  Code, authenticate the Slack server with `search:read`, `chat:write`, `canvases:read`,
  `canvases:write`, `users:read.email` scopes — the auth flow handles this)

## Install

```bash
git clone https://github.com/agdeliveroo/daily-todo-nextstep ~/daily-todo-nextstep
cd ~/daily-todo-nextstep
./install.sh
```

`install.sh` will:
1. Copy `skills/slack-digest/SKILL.md` to `~/.claude/skills/slack-digest/SKILL.md`.
2. Render `launchd/com.USER.slack-digest.plist` with your actual username and copy it
   to `~/Library/LaunchAgents/`.
3. Prompt you for your email and Slack workspace subdomain to substitute into the skill.
4. Load the launchd job (`launchctl load -w`).

## Manual setup (if you'd rather see what's happening)

### 1. Place the skill

```bash
mkdir -p ~/.claude/skills/slack-digest
cp skills/slack-digest/SKILL.md ~/.claude/skills/slack-digest/SKILL.md
```

Then open the file and replace the two placeholders near the top:
- `<YOUR_EMAIL>` → your work email
- `<YOUR_WORKSPACE>` → your Slack workspace subdomain (e.g., `acme` if your Slack is
  `acme.slack.com`)

### 2. Place the launchd plist

```bash
sed "s/USER/$USER/g" launchd/com.USER.slack-digest.plist > \
  ~/Library/LaunchAgents/com.$USER.slack-digest.plist
launchctl load -w ~/Library/LaunchAgents/com.$USER.slack-digest.plist
```

### 3. Test it now

```bash
launchctl start com.$USER.slack-digest
tail -f ~/.claude/logs/slack-digest.out.log
```

On first run it creates the two canvases in your Slackbot self-DM and posts the digest.
Subsequent runs reuse the same canvases (IDs cached in `~/.claude/skills/slack-digest/state.json`).

## Configuration

| Knob | Where | Default |
|---|---|---|
| Time of day | `StartCalendarInterval` in the plist | 08:03 local time, Mon-Fri |
| Lookback window | Step 2 of the skill | 3 days |
| Channel cap | Step 5 of the skill | top 30 by message count |
| Completion-reaction emoji | Step 7 of the skill | ✅, 👍, 🎉, etc. |

## Corporate networks (Netskope, Zscaler)

If your machine is behind a corporate MITM proxy, Node.js needs the proxy CA bundle:

```xml
<!-- in the plist, inside <EnvironmentVariables>: -->
<key>NODE_EXTRA_CA_CERTS</key>
<string>/Users/USER/.netskope-ca.pem</string>
```

Without this, MCP HTTPS calls fail silently in launchd.

## Files

- `skills/slack-digest/SKILL.md` — the runbook Claude follows each morning
- `launchd/com.USER.slack-digest.plist` — macOS scheduler config (template)
- `docs/plan.md` — original design notes
- `install.sh` — installer (does the path substitutions)

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No DM arrives, `err.log` empty | Laptop was asleep at fire time | launchd queues missed runs; check the log when the Mac wakes |
| `command not found: claude` in `err.log` | `PATH` env var not set in the plist | Edit the plist's `<EnvironmentVariables>` to include where `claude` lives |
| TLS errors on MCP HTTPS calls | Corporate MITM proxy | Set `NODE_EXTRA_CA_CERTS` (see above) |
| Canvases not updating | State file pointing at deleted canvases | Delete `~/.claude/skills/slack-digest/state.json` and re-run; canvases will be re-created |
| Same items appearing again after checking | Wording drifted between runs | Manually edit one canvas to merge; future runs will dedup correctly |

## Why this exists

I wanted a daily summary of my Slack activity with explicit next-steps tracking, but
nothing off-the-shelf could ingest from multiple private channels + DMs while letting
me check items off in Slack itself. This skill + a launchd job covers that in ~200
lines of Markdown configuration.
