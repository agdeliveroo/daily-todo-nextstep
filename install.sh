#!/usr/bin/env bash
set -euo pipefail

# install.sh — install the slack-digest skill and its launchd job onto this Mac.
# Idempotent. Re-running upgrades in place.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills/slack-digest/SKILL.md"
SKILL_DST_DIR="$HOME/.claude/skills/slack-digest"
SKILL_DST="$SKILL_DST_DIR/SKILL.md"
PLIST_SRC="$REPO_DIR/launchd/com.USER.slack-digest.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.$USER.slack-digest.plist"
LOG_DIR="$HOME/.claude/logs"

if [[ ! -f "$SKILL_SRC" ]]; then
    echo "error: $SKILL_SRC not found"
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "error: 'claude' binary not in PATH. Install Claude Code CLI first: https://claude.ai/code"
    exit 1
fi

CLAUDE_BIN="$(command -v claude)"
echo "Using claude binary: $CLAUDE_BIN"

# 1. Install the skill.
mkdir -p "$SKILL_DST_DIR"
cp "$SKILL_SRC" "$SKILL_DST"
echo "Installed skill → $SKILL_DST"

# 2. Render the plist (substitute USER, claude binary path).
mkdir -p "$(dirname "$PLIST_DST")" "$LOG_DIR"
sed \
    -e "s|/Users/USER/.local/bin/claude|$CLAUDE_BIN|g" \
    -e "s|USER|$USER|g" \
    "$PLIST_SRC" > "$PLIST_DST"
echo "Installed plist → $PLIST_DST"

# 3. Validate the plist.
plutil -lint "$PLIST_DST"

# 4. Load (or reload) the launchd job.
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load -w "$PLIST_DST"
echo "Loaded launchd job: com.$USER.slack-digest"

cat <<EOF

Install complete. Next:
  - Test now:   launchctl start com.$USER.slack-digest
  - Watch log:  tail -f $LOG_DIR/slack-digest.out.log
  - Authenticate the Slack MCP server inside Claude Code:
      /mcp  →  pick slack  →  re-auth with scopes:
        search:read, chat:write, canvases:read, canvases:write, users:read.email

Scheduled fire times: Mon–Fri 08:03 local. Edit $PLIST_DST to change.
EOF
