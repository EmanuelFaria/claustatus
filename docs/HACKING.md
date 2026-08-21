# Hacking Guide

Things you'd want to know before modifying the code.

## statusline.sh

### BASE_OVERHEAD

```bash
BASE_OVERHEAD=30500
```

Claude Code's API reports raw token counts for your messages and responses, but the
actual context window usage includes invisible overhead: the system prompt, CLAUDE.md
files, tool definitions, hook outputs, etc. This ~30,500 token constant is added to the
raw API count to get the "true" context usage matching what Claude Code's own UI shows.

If your CTX% looks off relative to what Claude Code reports, this is the value to adjust.
It was empirically tuned by comparing the statusline's calculated percentage against
Claude Code's `used_percentage` field across multiple sessions.

### Why Unit Separator instead of Tab for field splitting

```bash
IFS=$'\x1f' read -r MODEL CC_VERSION ... <<< "$(jq '... | join("\u001f")')"
```

Bash's `read` with `IFS=$'\t'` treats tab as whitespace — consecutive tabs collapse to
one delimiter. When `workspace.project_dir` is empty (common), the `\t\t` collapses and
shifts all subsequent fields by one. This lands the session UUID in `SES_DURATION_MS`
and crashes arithmetic. ASCII Unit Separator (0x1F) is non-whitespace so it preserves
empty fields correctly.

### Why the custom `json_val` / `json_num` functions

```bash
json_val() { local k="\"$1\""; local s="${2#*$k:}"; s="${s#*\"}"; echo "${s%%\"*}"; }
json_num() { local k="\"$1\""; local s="${2#*$k:}"; echo "${s%%[!0-9]*}"; }
```

Route files (`.guidance_route.json`, etc.) are read on every statusline render. Using
`jq` for each read adds ~15ms per file × 4 files = ~60ms extra per render — blowing past
the 50ms target. These bash string-manipulation functions parse the simple route JSON in
~0ms using only built-in operations.

Note: `json_num` uses `[!0-9]*` not `[,}]*` — the brace `}` inside `[,}]` is
interpreted as closing the `${...}` parameter expansion, not as part of the character
class. This was a bug that caused garbled output.

### Color strategy: 16-color for most rows, 8-bit for route rows

The statusline runs inside Claude Code's TUI (terminal UI). During testing, 8-bit 256-color
codes (`\033[48;5;Nm`) caused truncation artifacts on some model configurations and
Claude Code versions. Basic 16-color codes (`\033[4Xm`) are universally compatible.

**Exception:** The Activity row uses 8-bit colors because it runs after the TUI has
already rendered the status area, and the richer palette is visually useful there.
The route rows (GUIDE/SKILL/INTENT/LEARN) also use 8-bit because they appear late in
the output where TUI compatibility is less critical.

If you're adding new rows, start with 16-color and only switch to 8-bit if you
have a specific reason.

### Why no `set -e` or `set -o pipefail`

Non-zero exit codes cause Claude Code to **hide the statusline globally across all open
sessions** — not just the session that errored. This is a Claude Code behavior, not
something we can control. During model switches (`/model`), Claude Code sends a different
JSON structure that causes jq or arithmetic to fail transiently. Without error flags,
these failures produce wrong values for one render and then self-correct. With error flags,
they silently kill the statusline for everyone.

### The Activity row 8-bit colors

The Activity row reads from `~/.claude/temp/.current_activity.json` written by Claude
Code's hooks. Because it uses 8-bit for state-specific colors (orange for running tool,
blue for processing, yellow for waiting), it doesn't follow the 16-color-everywhere rule.
If you're adding an activity state, match the existing 8-bit pattern.

### How the NAME row is populated

The NAME row shows the session's custom title, set via `/rename` in Claude Code. The
`/rename` command writes a `{"type":"custom-title","customTitle":"..."}` entry to the
session's `.jsonl` transcript file. The statusline reads this by scanning the transcript
for the last `custom-title` entry.

This result is cached in `/tmp/statusline-sessname-{SESSION_ID}` to avoid re-scanning
the transcript on every render.

### PRECOMPACT alert system

Per-session flag files drive the precompact alerts (global fallback only when SESSION_ID is empty):

| File | Created by | Meaning |
|------|-----------|---------|
| `.precompact_running_{SID}` | Watcher daemon / PreCompact hook start | Extraction in progress — suppress PRECOMPACT NOW |
| `.precompact_ready_{SID}` | Watcher daemon / PreCompact hook end | Output ready — show PASTE PRECOMPACT NOW |
| `.precompact_needed_{SID}` | statusline.sh (≤40K tokens remaining) | Sentinel for PostToolUse AI injection |
| `.precompact_extracted_{SID}` | Watcher daemon / PreCompact hook | Hysteresis — prevents re-trigger until >40K tokens |
| `.precompact_alerted_{SID}` | statusline.sh (≤30K tokens remaining) | One-shot sound/fireworks guard |

**Two-tier alert system** (uses overhead-aware `effective_remaining_tokens` and the actual model window):
- **≤40K tokens:** Amber banner ("CONTEXT LOW — WRAP UP"), sentinel written for PostToolUse AI injection
- **≤30K tokens:** Red flashing banner ("PRECOMPACT NOW!"), one-shot Sosumi sound + iTerm2 fireworks

**PRECOMPACT NOW** is suppressed while `.precompact_running_{SID}` exists and is <2 minutes old. The flag auto-expires so a crashed script can't suppress the alert forever.

**PASTE PRECOMPACT NOW** reads `.precompact_ready_{SID}`. It disappears automatically after **5 minutes** (`READY_AGE -lt 300`). When it expires, the file is deleted.

**Two-row alternating display:** Both alerts render as two rows that swap positions on alternating seconds (`$(date +%S) % 2`). This creates a visible flash without relying on ANSI blink, which Claude Code's TUI strips.

**Hysteresis:** After compact/auto-compact, stale statusline data may still show ≤30K tokens. The `.precompact_extracted_{SID}` marker prevents the watcher from re-triggering extraction. It clears above 40K; a healthy render also removes an obsolete sentinel after a model/window change.

To dismiss early:
```bash
rm ~/.claude/temp/.precompact_ready_${SESSION_ID}
rm ~/.claude/temp/.precompact_running_${SESSION_ID}
```

### precompact_alert_watcher.py

`~/.claude/scripts/precompact_alert_watcher.py` is a background daemon (LaunchAgent: `com.personalos.precompact-alert-watcher`) that watches the same flag files and fires system-level alerts.

**What it does on trigger:**

1. **macOS notification** — `osascript` banner. Title is "PRECOMPACT NOW" or "PASTE PRECOMPACT NOW". Body includes the window number, e.g. "window 19 — RANDOM REQUESTS".
2. **iTerm2 tab flash** — writes ANSI red background + reset to the TTY path recorded in `.iterm_sync_{SID}.json`. Red for 2 seconds, then reset.
3. **Dock bounce** — bounces the iTerm2 dock icon via `osascript`.

**TTY flash mechanism:** `statusline.sh` writes `"tty":"/dev/ttysNNN"` into each `.iterm_sync_{SID}.json`. The watcher reads all sync files, finds any with an active alert, and writes escape codes directly to the stored TTY path. This bypasses the iTerm2 Python API and works even when `statusline_title_sync.py` is not running.

**Window number extraction:** The watcher parses the `iterm_session_id` field in `.iterm_sync_{SID}.json`. Format is `w{N}t{M}p{L}:{UUID}` — the window number in the notification is `N+1` (1-based display).

**Polling:** Every 5 seconds. 2-minute cooldown per alert type between repeat notifications to avoid notification storms during a long low-context session.

## statusline_title_sync.py

### Session matching strategy

The script tries three methods to match an iTerm2 session to a Claude session, in
priority order:

1. **Direct match** — `iterm_session_id` in the sync file matches iTerm2's `session.session_id` (1:1, most reliable)
2. **Cached mapping** — previous successful match saved in `_applied` dict, valid only if sync file < 30 min old
3. **User variable** — `user.sessionId` we previously set (survives profile changes), same 30-min recency check

Tab title fallback was removed — matching by repo directory name caused wrong badges to bleed across windows when multiple sessions shared the same repo.

### Why the sync script sets tab title via Python API instead of escape codes

`\033]1;title\007` sets the "session name" internally in iTerm2, but whether it
*displays* depends on the profile's Title Components setting. The Python API's
`tab.async_set_title()` bypasses this and sets the title directly. The script also
handles profile change events — re-applying titles when you switch profiles, which
would otherwise clear user-set titles.

## USAGE / API$ Cost Delta-Accumulation

The statusline renders many times per session. `SES_COST` is a **cumulative session total** — if you just add it to a monthly file on every render, you triple-count it. The USAGE and API$ rows use a delta pattern instead:

```
delta = SES_COST - last_seen_cost_for_this_session
monthly_total += delta
last_seen_cost_for_this_session = SES_COST
```

Files:
- `~/.claude/temp/.ses_last_{SESSION_ID}` — per-session "last seen" cost (float, 4dp)
- `~/.claude/temp/.monthly_cost_YYYY-MM` — monthly accumulator; new file = new month = auto-reset

All file I/O is in a single `awk BEGIN` block to avoid spawning multiple subprocesses. The block reads both files, computes the delta, updates both files, and prints the new total — all atomically within awk.

Edge cases handled:
- Session cost decreases (model switch resets session): delta clamped to 0
- File doesn't exist yet: defaults to 0
- `SESSION_ID` empty: entire block is skipped (statusline running in test mode)

## LIMITS Background Refresh

`~/.claude/temp/.api_limits.json` is written by a background subshell at the bottom of `statusline.sh`. The subshell:

1. Checks a lock file (`~/.claude/temp/.api_limits_refresh.lock`) — exits if <30s old
2. Checks the cache file — exits if <10 min old
3. Resolves `ANTHROPIC_API_KEY` from environment, then `security find-generic-password`
4. Issues `curl -I` HEAD request (no body, minimal cost)
5. Parses `anthropic-ratelimit-*` headers and writes JSON

The key is resolved inside the background subshell — the main render path never blocks on Keychain access.

## CAP Row — Rolling Usage Caps

The CAP row shows Anthropic's actual 5-hour and 7-day rolling usage cap percentages — the numbers that determine when a Max subscriber gets throttled.

**Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
**Auth:** Same `ANTHROPIC_API_KEY` as the LIMITS row (env → Keychain)
**Headers:** `x-api-key`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`
**Response:** `{"five_hour": 63, "seven_day": 41}` (percentages, or null)

**Cache:** `~/.claude/temp/.usage_caps.json` — refreshed every 60 minutes by a background subshell. The endpoint returns `retry-after: ~3500s` (~58 min), so polling faster would just get 429'd.

**Display freshness:** Cache shown if < 2 hours old (gives buffer for transient refresh failures).

**Color thresholds** (based on `max(five_hour, seven_day)`):
- Green: ≤ 50%
- Amber: ≤ 75%
- Red: > 75%

**Parsing:** Uses `python3 -c` in the background subshell to extract JSON fields (the response is a proper JSON object, not simple enough for `json_num` bash parsing which expects flat key-value). This is acceptable because it runs in background — doesn't block rendering.

**Difference from USAGE row:** USAGE tracks dollar spend vs a self-imposed weekly budget. CAP tracks actual Anthropic rolling limits. Max subscribers care about CAP; API-key-only users care about USAGE.

## Adding a New Row

1. Decide on a route file name: `~/.claude/temp/.myrow_route_{SID}.json`
2. Define your JSON schema (see `hooks/route_file_format.md` for patterns)
3. In `statusline.sh`, add:
   - Default variables near line 232: `MYROW_TEXT="none"`, `BG_MYROW_R="\033[48;5;240m"`, etc.
   - File read block after the existing route reads (following GUIDE/SKILL/INTENT/LEARN pattern)
   - Printf row in the output section
4. Write a hook that creates the route file
5. Update `hooks/route_file_format.md` with the new schema

## Content Wrapping (print_row)

Long content is wrapped automatically at 34 characters (matching the CLONE row width):

```bash
print_row "$BG_COLOR" "$FG_COLOR" "LABEL" "$content"
```

- Content ≤ 34 chars: single line
- Content > 34 chars: wraps at last word boundary before 34, continuation on second line

GUIDE, SKILL, INTENT, LEARN, AGENT, NAME, REPO, MTHS, and LIMITS all use `print_row`. The MODEL and CTX rows do not — they have fixed-width multi-segment designs.

To change the wrap width, update `MAX_ROW_CONTENT` near the top of `statusline.sh`.

## AGENT Row

The AGENT row appears between MODEL and CTX only when a background agent/subagent is active:

```
AGENT  Read codebase for architecture...  2m 14s
```

**Data source:** `~/.claude/temp/.agent_activity_{SID}.json`

**Populated by:** `agent_activity_tracker.sh` (PreToolUse hook, matcher: `tools:Agent,Task`)

**Cleared by:** same hook on PostToolUse

**JSON format:**
```json
{"status":"running","description":"task description","started":1234567890,"tool":"Agent"}
```

Elapsed time is calculated fresh on each render — the incrementing timer signals Claude isn't frozen during long agent calls.

## Conditional Rows

These rows only appear when active (hidden entirely when inactive):

| Row | Shows when |
|-----|-----------|
| AGENT | Agent/Task tool is running |
| CAP | `~/.claude/temp/.usage_caps.json` exists and is <2h old |
| SKILL | Skill loaded, offered, or declined |
| INTENT | Capability routing matched |
| NAME | Session has been renamed via `/rename` |
| LIMITS | `~/.claude/temp/.api_limits.json` exists and is <20 min old |

Always-on rows: Activity, MODEL, CTX, USAGE, API$, REPO, CLONE, ID, GUIDE, LEARN.
