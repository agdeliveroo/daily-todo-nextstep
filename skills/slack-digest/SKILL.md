---
name: slack-digest
description: >
  Daily Slack activity digest. Scans the last 3 days of private channels, 1:1 DMs, group DMs,
  plus any public channel where the user is @-mentioned. Posts "Key discussions" as a DM to
  the user, and maintains TWO persistent canvases ("Owed by Me" + "Owed to Me") with
  checkable action items. Checked items disappear from the next run. Items marked done via
  ✅/done/shipped reactions on the source Slack message are also excluded. Use when the user
  asks to "run the digest", "send me the slack digest", "what happened on slack", or when
  invoked by the scheduled routine.
user_invocable: true
---

# Slack Daily Digest

Run end-to-end without prompting the user. Tool calls must be parallelized at every step that allows it.

## Identity

- User email: `anup.gaurav@deliveroo.com`
- All Slack MCP tools are prefixed `mcp__slack__`.
- State file: `~/.claude/skills/slack-digest/state.json` — stores `owed_by_me_canvas_id` and `owed_to_me_canvas_id` across runs.

## Pipeline

### 1. Resolve user ID

Call `mcp__slack__slack_search_users` with query = `anup.gaurav@deliveroo.com`. Take the first match's user ID. Call this `USER_ID` (format `U...`).

### 2. Compute date window

- `end` = today (ISO, e.g., `2026-05-15`)
- `start` = today − 3 days (e.g., `2026-05-12`)

### 3. Gather raw activity — run all three in parallel

Use `mcp__slack__slack_search_public_and_private` with these queries simultaneously:

- Q1: `from:me after:<start>` — every message you sent
- Q2: `<@USER_ID> after:<start>` — every @-mention of you (catches public channels too)
- Q3: `to:me after:<start>` — DMs sent to you (catches unreplied)

For each result, capture: `channel_id`, `channel_name`, `channel_type` (im / mpim / private_channel / public_channel), `ts`, `thread_ts` (if any), `user`, `text`, and `permalink`.

If `permalink` is not present in the search result, construct it:
- Base message: `https://doordash.enterprise.slack.com/archives/<channel_id>/p<ts_no_dot>` where `ts_no_dot` is the ts with the `.` removed (e.g., `1234567890.123456` → `1234567890123456`).
- Thread reply: append `?thread_ts=<thread_ts>&cid=<channel_id>` so the link opens the thread context.

### 4. Bucket and filter

Keep messages from these buckets:
- `im` (1:1 DM) — always keep
- `mpim` (group DM) — always keep
- `private_channel` — always keep
- `public_channel` — keep ONLY if from Q2 (you were tagged)

Discard everything else.

### 5. Rank and cap

Group messages by `channel_id`. Count messages per channel. Take the top 30 channels by count. Discard the rest.

### 6. Fetch context — parallel batches of 10

For each of the top 30 channels:
- If there's a `thread_ts`, call `mcp__slack__slack_read_thread` for the most active thread in that channel.
- Otherwise call `mcp__slack__slack_read_channel` for the last ~50 messages, filtered to `ts >= start`.

Run reads in parallel batches of 10 to avoid rate limits.

### 7. Detect completed action items (reaction-based)

Identify candidate action-item messages (commitment language: "I'll", "I will", "let me", "on it", "got it", "will send", "will check", "by EOD", etc.). For each candidate, call `mcp__slack__slack_get_reactions` in parallel. If reactions include any of `white_check_mark`, `heavy_check_mark`, `done`, `shipped`, `tada`, `ok_hand` → exclude as completed.

### 8. Synthesize three lists

#### List A — Key discussions

- One bullet per significant thread/topic.
- Format: `• *#channel-name* — <one-line topic summary>`
- Skip: FYI broadcasts, bot posts, single-emoji replies, link drops with no discussion.
- Aim for 5–12 bullets total. If more than 12, keep the most substantive.

#### List B — Today's "Owed by Me" candidates

- One item per outstanding commitment YOU made.
- For each item, record `source_permalink` = the permalink of the Slack message where you committed.
- Format: `<action> — for @person — in #channel — [↗](<source_permalink>)`
- Excluded: anything with a completion reaction (step 7).

#### List C — Today's "Owed to Me" candidates

- One item per outstanding commitment from someone else.
- For each item, record `source_permalink` = the permalink of the Slack message where they committed (or the message asking them).
- Format: `<action> — by @person — in #channel — [↗](<source_permalink>)`
- Excluded: anything with a completion reaction.

### 9. Read state file

Read `~/.claude/skills/slack-digest/state.json`. Schema:

```json
{
  "owed_by_me_canvas_id": "F0..." | null,
  "owed_to_me_canvas_id": "F0..." | null,
  "self_dm_channel_id": "D..." | null
}
```

If the file doesn't exist, treat all fields as `null`.

### 10. Resolve self-DM channel ID

If `state.self_dm_channel_id` is null: send a placeholder message via `mcp__slack__slack_send_message` to `USER_ID` (Slack auto-resolves to self-DM); capture the returned channel ID; save to state. Otherwise use cached value.

### 11. Canvas reconciliation — run both canvases in parallel

For each of the two canvases (`owed_by_me` and `owed_to_me`):

#### 11a. Ensure canvas exists

If the state's canvas ID is null OR `mcp__slack__slack_read_canvas` returns not-found:
- Call `mcp__slack__slack_create_canvas` with:
  - `channel_id` = `self_dm_channel_id`
  - `title` = `"Action Items — Owed by Me"` or `"Action Items — Owed to Me"`
  - Initial content (markdown):
    ```
    # Action Items — Owed by Me

    _Updated by /slack-digest. Check items off here to remove them from future digests._

    ```
- Save the returned canvas ID to state.

#### 11b. Read current canvas

Call `mcp__slack__slack_read_canvas` with the canvas ID. Parse markdown to extract checkbox lines:
- `- [x] <text>` → checked (done, exclude)
- `- [ ] <text>` → unchecked (carry forward)

Keep only the unchecked items.

#### 11c. Dedup new candidates against carry-overs

For each new candidate from List B (or List C):
- Normalize text (lowercase, strip channel/person tags, strip `[↗](url)` link markdown, take first ~6 distinctive words of the action verb + object).
- If a carry-over has a normalized form that overlaps ≥ 70% with the new candidate, skip the new candidate (the carry-over already tracks this item; preserve its existing permalink).
- Otherwise, add the new candidate (with its permalink) to the merged list.

The merged list = `unchecked_carry_overs + deduped_new_items`. Cap at 30 items per canvas.

When reading carry-overs back from the canvas in step 11b, preserve the `[↗](url)` link suffix verbatim so it survives across runs. Lines in the canvas have the shape `- [ ] <action> — for @person — in #channel — [↗](https://...slack.com/...)`.

#### 11d. Render new canvas content

Markdown body:

```
# Action Items — Owed by Me

_Updated: 2026-05-15 13:25 IST. Check items below to remove from future digests. Click ↗ to jump to the Slack thread._

- [ ] <action 1> — for @person — in #channel — [↗](<permalink>)
- [ ] <action 2> — for @person — in #channel — [↗](<permalink>)
...

---
_Carry-overs from prior days appear above new items; once checked, they vanish on next run._
```

If an item somehow lacks a permalink (e.g., couldn't resolve the source message), omit the `— [↗](...)` suffix rather than emitting a broken link.

#### 11e. Update canvas

Call `mcp__slack__slack_update_canvas` with the new markdown body.

### 12. Format the DM digest (discussions only)

Use Slack mrkdwn:

```
:bell: *Daily Digest* — <start_date> → <end_date>

*Key discussions*
• [bullets, or `_(none)_` if empty]

*Action items*
• <N> open in Owed by Me — <canvas_link>
• <K> open in Owed to Me — <canvas_link>

_Scanned <N> channels, <M> messages over 3 days. Check items off in the canvases to remove them tomorrow._
```

Canvas links: construct as `https://deliveroo.slack.com/docs/<TEAM_ID>/<CANVAS_ID>` or use the URL returned by `slack_create_canvas`/`slack_read_canvas`.

### 13. Send the DM

Call `mcp__slack__slack_send_message` with `channel = self_dm_channel_id`, `text =` formatted digest.

### 14. Persist state

Write `state.json` with updated canvas IDs and self-DM channel ID.

### 15. Print confirmation

Output a one-line summary: `Sent digest: <N> discussions, <M> open owed-by-me (incl. <K> new), <P> open owed-to-me (incl. <Q> new).`

## Rules

- NEVER skip step 7 (reaction check) — completed items must be filtered out.
- Action item bullets MUST be one line each.
- Owner names use `@displayname` format (look up via `slack_read_user_profile` if needed — batch in parallel).
- Carry-overs are the source of truth: never re-add an unchecked carry-over as a "new" item.
- If a checked item appears in today's Slack data as still-active, ignore it (the user marked it done — trust the user).
- If the Slack MCP returns auth error at any step, halt and output: `Slack auth failed. Run /mcp and re-authenticate the slack server.`
- When invoked manually (not via schedule), also print the full digest to the terminal so the user can see it without opening Slack.

## State

Stateful via `~/.claude/skills/slack-digest/state.json`. Create if missing. Update at end of each run.
