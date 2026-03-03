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

### PASTE PRECOMPACT alert expiry

The green "PASTE PRECOMPACT NOW" alert reads `~/.claude/temp/.precompact_ready`. It
disappears automatically after **5 minutes** (the `READY_AGE -lt 300` check). When it
expires, the file is deleted. This gives you time to copy and paste the precompact output
without the alert lingering forever.

To dismiss it early: `rm ~/.claude/temp/.precompact_ready`

## statusline_title_sync.py

### Session matching strategy

The script tries four methods to match an iTerm2 session to a Claude session, in
priority order:

1. **Direct match** — `iterm_session_id` in the sync file matches iTerm2's `session.session_id` (1:1, most reliable)
2. **Cached mapping** — previous successful match saved in `_applied` dict
3. **User variable** — `user.sessionId` we previously set (survives profile changes)
4. **Tab title fallback** — tab title matches `repo_name` in sync files (ambiguous, last resort)

If you have multiple Claude sessions in the same repository, method 4 can match the
wrong session. Method 1-3 are unambiguous.

### Why the sync script sets tab title via Python API instead of escape codes

`\033]1;title\007` sets the "session name" internally in iTerm2, but whether it
*displays* depends on the profile's Title Components setting. The Python API's
`tab.async_set_title()` bypasses this and sets the title directly. The script also
handles profile change events — re-applying titles when you switch profiles, which
would otherwise clear user-set titles.

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

Long content is wrapped automatically at 42 characters (matching MODEL row width):

```bash
print_row "$BG_COLOR" "$FG_COLOR" "LABEL" "$content"
```

- Content ≤ 42 chars: single line
- Content > 42 chars: wraps at last word boundary before 42, continuation on second line

GUIDE, SKILL, INTENT, LEARN, and AGENT all use `print_row`. Fixed-layout rows (MODEL, CTX, CC%, SES) do not — they have fixed-width multi-segment designs.

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

These rows only appear when active (hidden entirely when "none"):

| Row | Shows when |
|-----|-----------|
| AGENT | Agent/Task tool is running |
| SKILL | Skill loaded, offered, or declined |
| INTENT | Capability routing matched |
| NAME | Session has been renamed via `/rename` |
