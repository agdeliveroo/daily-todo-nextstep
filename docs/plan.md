# Design notes

## Why two canvases, not one

A single "Action Items" canvas mixes things you owe out with things you're waiting on,
which makes triage harder. Separating "Owed by Me" (your work) from "Owed to Me"
(nags for others) lets the digest answer two distinct questions:
"what do I need to ship today?" and "who am I unblocked by?".

## Why the canvas is the source of truth, not the SKILL state file

Carry-overs come from parsing the previous canvas markdown back into bullets. That means
the user can check items off in Slack and they vanish from the next run — no separate
"done" list to maintain. The state file holds only canvas IDs and the self-DM channel ID;
it deliberately does not cache the content of action items.

## Why scan for completion reactions in step 7

Sometimes people don't reply to a thread to confirm — they emoji-react with ✅, 🎉, 👍, etc.
We treat those reactions as "this commitment is done" so the canvas stays clean even when
the conversation didn't get a textual closeout.

## Why top-30 channel cap

Empirically, hot weeks produce 50–80 active channels but the long tail is mostly
broadcast/FYI. Capping at 30 keeps the synthesis step fast (≤30 read_channel calls) and
the digest readable. Raise the cap if you find substantive discussions getting cut.

## Why a dedup pass against carry-overs

Without it, every run re-adds yesterday's "Owed by Me" items as today's "Owed by Me" items,
just with a fresh permalink. The 70% normalized-text overlap threshold catches the same
commitment phrased slightly differently across runs (e.g., "send the deck" vs "send deck
to Alice"). Sub-70% means the work materially changed and should be treated as new.

## Open improvements

- Substitute `<YOUR_EMAIL>` / `<YOUR_WORKSPACE>` placeholders into the skill at install
  time (README claims this; current `install.sh` does not — it copies verbatim, so other
  users would need to hand-edit `SKILL.md` after install).
- Cache `slack_read_user_profile` results across runs to cut display-name lookups.
- Add a weekly mode (Mon morning, 7-day window) alongside the daily.
