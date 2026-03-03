# Product Requirements Document — claustatus

**Version:** 1.1.0
**Status:** Production
**Last Updated:** 2026-03-03

---

## 1. Overview

### 1.1 Product Summary

claustatus is a real-time powerline-style status bar for Claude Code that renders directly inside the Claude Code TUI. It shows session context, token usage, cost, model state, agent activity, session identity, and hook routing decisions — all updated on every API response, with sub-50ms execution time.

### 1.2 Problem Statement

Claude Code provides minimal session visibility. You cannot see at a glance:
- How much context you've used and how much is left
- What the current session is costing in real time
- Which Claude model and version is active
- Whether thinking mode is on
- Whether a background agent is currently running
- What guidance/skill/learning your hooks are surfacing for the current prompt
- Which session you're in (when running multiple sessions across terminals)

### 1.3 Solution

A Bash script invoked by Claude Code's `statusLine` hook on every API response. It reads the piped JSON blob, formats it into 10–15 powerline rows, and writes them to stdout. A companion Python script syncs session identity to iTerm2 window decorations.

---

## 2. Architecture

### 2.1 Component Map

```
Claude Code API response
        │
        ▼ (stdin: JSON blob with session data)
  statusline.sh  (~/.claude/scripts/statusline.sh)
        │
        ├── jq: extract 16 fields via \x1f Unit Separator
        │   (avoids bash IFS tab-collapse bug with empty fields)
        │
        ├── Route files: ~/.claude/temp/.{guide,skill,intent,learn}_route_{SID}.json
        │   (written by UserPromptSubmit hooks, read per-session)
        │
        ├── Settings: ~/.claude/settings.json → thinking mode, model name
        │
        ├── Agent activity: ~/.claude/temp/.agent_activity_{SID}.json
        │   (written by hook when subagent starts, deleted when done)
        │
        └── printf: 10-15 powerline rows → stdout (Claude Code renders)
                │
                └── Background subshell → /dev/tty{NNN} (parent TTY)
                    ├── OSC 1337 SetUserVar=cloneName   (tab title)
                    ├── OSC 1337 SetUserVar=sessionBadge (badge)
                    └── Writes .iterm_sync_{SID}.json

statusline_title_sync.py  (iTerm2 AutoLaunch Script)
        │
        ├── Polls every 5s: ~/.claude/temp/.iterm_sync_{SID}.json
        │
        ├── Matches iTerm2 sessions to Claude sessions via iterm_session_id
        │   (UUID after colon in "w6t0p0:UUID" format)
        │
        └── Sets via iTerm2 Python API:
            ├── tab.async_set_title(clone_name)         — repo/worktree directory
            ├── window.async_set_title(session_name)    — /rename name
            ├── session.async_set_variable("user.sessionBadge", session_name)
            └── session.async_set_name(claude_uuid)     — Session Name field = UUID
```

### 2.2 Data Flow

**Statusline rendering** (every API response, ~40ms):

1. Claude Code pipes JSON to `statusline.sh` stdin
2. Single `jq` call extracts 16 fields separated by `\x1f`
3. Bash `read` splits on `\x1f` into named variables
4. Route files read with `$(<file)` (no subprocess)
5. Each row computed with ANSI color codes and printf
6. All rows written to stdout for Claude Code TUI
7. Background subshell writes OSC sequences to parent TTY

**iTerm2 sync** (every 5 seconds):

1. Script reads all `.iterm_sync_{SID}.json` files
2. Builds index: iTerm2 session UUID → Claude sync data
3. Iterates all open sessions, matches by UUID in `iterm_session_id` field
4. Sets tab title, window title, badge, and Session Name via Python API
5. On profile change: re-applies all values immediately

### 2.3 File Locations

| File | Purpose |
|---|---|
| `~/.claude/scripts/statusline.sh` | Main renderer |
| `~/Library/Application Support/iTerm2/Scripts/AutoLaunch/statusline_title_sync.py` | iTerm2 sync |
| `~/.claude/temp/.iterm_sync_{SID}.json` | Per-session sync state |
| `~/.claude/temp/.{guide,skill,intent,learn}_route_{SID}.json` | Hook route files |
| `~/.claude/temp/.agent_activity_{SID}.json` | Agent state |
| `~/.claude/temp/.precompact_ready` | Precompact alert trigger |
| `~/.claude/temp/.iterm_sync_script.log` | Sync script debug log |
| `~/.claude/settings.json` | Claude Code config (statusLine hook) |

---

## 3. Rows Reference

### 3.1 Always-Rendered Rows

| Row | Content | Color scheme |
|---|---|---|
| MODEL | `{name} ({ctx_k}k context)  v{version}  {thinking_indicator}` | Blue BG |
| CTX | `{input_tokens}  {pct_used}% used  {pct_left}% left` | Dark BG |
| CC% | `{cc_tokens}  {pct_used}% used  {pct_left}% left` | Dark BG |
| SES | `{session_tokens}  ${cost}  {duration} API` | Dark BG |
| NAME | `{session_name}   REPO  {repo_name}` | Teal BG |
| CLONE | `{clone_dir_name}` | Navy BG |
| ID | `{session_uuid}` | Dark BG |

### 3.2 Conditional Rows

| Row | Trigger | Color |
|---|---|---|
| AGENT | `.agent_activity_{SID}.json` exists and has description | Orange BG |
| PRECOMPACT NOW | `context_remaining ≤ 20%` | Animated red/yellow |
| PASTE PRECOMPACT | `.precompact_ready` file < 5 min old | Animated green |

### 3.3 Route Rows (Hook-Driven)

All shown only when a route file exists for the current session. Gray when `none`.

| Row | State | Color | Example |
|---|---|---|---|
| GUIDE | loaded | Green | `master_debugging.md ('api_failure')` |
| GUIDE | cooldown | Amber | `cooldown` |
| SKILL | loaded | Green | `csv-protocol` |
| SKILL | offered | Blue | `maintenance (8)` |
| SKILL | declined | Amber | `declined` |
| INTENT | matched | Blue | `web_search → perplexity-sonar` |
| LEARN | found | Green | `"rebase before push"` |
| LEARN | skipped | Amber | `skipped` |

---

## 4. Route File Schema

Each hook writes a session-specific JSON file to `~/.claude/temp/` on every `UserPromptSubmit` event.

### 4.1 GUIDE Route

```json
{
  "session_id": "3e6c5d9c-...",
  "status": "loaded",
  "file": "master_debugging.md",
  "trigger": "api_failure",
  "timestamp": 1709500000
}
```

`status` values: `loaded`, `cooldown`, `none`

### 4.2 SKILL Route

```json
{
  "session_id": "3e6c5d9c-...",
  "status": "offered",
  "skill": "",
  "count": 8,
  "category": "maintenance",
  "timestamp": 1709500000
}
```

`status` values: `loaded` (single match), `offered` (multiple), `declined`, `none`

### 4.3 INTENT Route

```json
{
  "session_id": "3e6c5d9c-...",
  "status": "matched",
  "intent_type": "web_search",
  "tool": "perplexity-sonar",
  "timestamp": 1709500000
}
```

`status` values: `matched`, `none`

### 4.4 LEARN Route

```json
{
  "session_id": "3e6c5d9c-...",
  "status": "found",
  "title": "rebase before push",
  "count": 3,
  "timestamp": 1709500000
}
```

`status` values: `found`, `skipped`, `none`

`title` should be a ≤3-word `short_label` for statusline display. Fall back to truncated full title if unavailable.

---

## 5. Sync File Schema

Written by `statusline.sh` background section; read by `statusline_title_sync.py`.

```json
{
  "session_id": "3e6c5d9c-1014-4a3c-9fc6-9618e0756e88",
  "session_name": "statusline fix",
  "repo_name": "PersonalOS-session-20260228-121307",
  "iterm_session_id": "w6t0p0:A1B2C3D4-...",
  "timestamp": 1709500000
}
```

File location: `~/.claude/temp/.iterm_sync_{session_id}.json`

The `iterm_session_id` field contains iTerm2's internal session identifier in `{window_id}:{uuid}` format. The sync script splits on `:` and uses only the UUID portion to match against `session.session_id` from the Python API.

---

## 6. iTerm2 Integration

### 6.1 Variable Mapping

| Variable | Value | Used By |
|---|---|---|
| `user.cloneName` | Clone directory basename | Custom Tab Title |
| `user.sessionBadge` | Session name from `/rename` | Custom Window Title, Badge |
| Session Name (iTerm2 field) | Claude session UUID | Edit Current Session panel |

### 6.2 Profile Configuration

Dynamic Profiles require:

```json
{
  "Allow Title Setting": true,
  "Custom Tab Title": "\\(user.cloneName)",
  "Custom Window Title": "\\(user.sessionBadge)",
  "Badge Text": "\\(user.sessionBadge)"
}
```

The sync script also sets these templates programmatically on all profiles at startup via `iterm2.PartialProfile.async_query` → `full.async_set_badge_text(target)`. This bypasses the plist (which running iTerm2 ignores after launch).

### 6.3 Python Environment Requirement

`statusline_title_sync.py` uses `iterm2.notifications` which is only available in iTerm2's bundled Python environment. System Python3 and Homebrew Python3 both lack this module.

The script must be launched via:
- iTerm2 menu bar → Scripts → AutoLaunch → statusline_title_sync.py
- OR: restart iTerm2 (AutoLaunch scripts run automatically)

The `ITERM2_COOKIE` environment variable required for WebSocket authentication is only set by iTerm2's launcher. Running from a terminal shell results in HTTP 401.

### 6.4 Singleton Guard

The script uses `fcntl.LOCK_EX | fcntl.LOCK_NB` on a PID file (`~/.claude/temp/.statusline_title_sync.pid`) to prevent duplicate instances. If killed, it must be restarted via the Scripts menu — iTerm2 does not auto-restart killed AutoLaunch scripts.

### 6.5 Session Matching Strategy

Priority order for matching iTerm2 sessions to Claude sync files:

1. **Direct UUID match** — `session.session_id` vs UUID in `iterm_session_id` field (most reliable, 1:1)
2. **Cached match** — previous match from `_applied` dict, valid only if sync file < 30 minutes old
3. **user.sessionId variable** — set by script on previous match, same 30-minute recency check

Tab title fallback removed: matching by repo directory name caused wrong badges to bleed across windows when multiple sessions shared the same repo.

---

## 7. Performance Design

Target: < 50ms total execution.

| Technique | Saves |
|---|---|
| Single `jq` call for all 16 fields | ~14 subprocess forks |
| `$(<file)` for route file reads | Subprocess fork per file |
| 30-second git remote cache in `/tmp` | Git network call per render |
| Session name cache in `/tmp/statusline-sessname-{SID}` | File stat per render |
| iTerm2 sync in background subshell (`&`) | Doesn't block rendering |
| `json_val`/`json_num` bash functions (no jq for route files) | ~15ms × 4 route files |
| `BASE_OVERHEAD=30500` added to raw API counts | Matches Claude Code's used_percentage without subprocess |

---

## 8. Color System

### 8.1 Main Rows

All main rows (MODEL, CTX, CC%, SES, NAME, CLONE, ID) use 16-color ANSI codes (`\033[4Xm` for backgrounds, `\033[3Xm` for foregrounds). Not 8-bit 256-color. Claude Code's TUI has rendering issues with 8-bit codes on certain model configurations causing truncation.

### 8.2 Route Rows

GUIDE, SKILL, INTENT, LEARN use 8-bit 256-color for more expressive state representation (green/blue/amber/gray). These work because they appear after the TUI has committed to rendering the statusline area.

### 8.3 Alert Rows

PRECOMPACT NOW uses ANSI blink (`\033[5m`) + alternating red/yellow. PASTE PRECOMPACT uses green blink. Both require "Blinking text allowed" enabled in iTerm2 profile (Settings → Profiles → Text).

---

## 9. Multi-Session Design

All temp files are session-scoped using the Claude session UUID as a filename suffix:

- `.iterm_sync_{SID}.json`
- `.{guide,skill,intent,learn}_route_{SID}.json`
- `.agent_activity_{SID}.json`

This prevents cross-contamination when multiple Claude Code sessions write to the same `~/.claude/temp/` directory simultaneously.

Route rows fall back to showing `none` when no file exists for the current session — they never show stale data from another session.

---

## 10. Non-Requirements

These were explicitly considered and rejected:

| Feature | Decision |
|---|---|
| `set -e` / `set -o pipefail` | Rejected — non-zero exit hides statusline globally across ALL sessions |
| Tab-separated jq output | Rejected — bash `read` collapses consecutive tabs, loses empty fields |
| `pip3 install iterm2` from terminal | Not sufficient — `iterm2.notifications` only in bundled Python |
| Polling iTerm2 sync from terminal shell | Not possible — requires `ITERM2_COOKIE` from iTerm2 launcher |
| OSC 1 / OSC 2 escape sequences for titles | Rejected — depends on iTerm2 profile Title Components setting; Python API bypasses this |
| Shared (non-session-scoped) route files | Rejected — last-writer-wins causes cross-contamination in multi-session setups |

---

## 11. Known Limitations

- macOS only: uses BSD `stat`, macOS TTY paths (`/dev/tty{NNN}`)
- iTerm2 only for the Python sync component
- `statusline_title_sync.py` must be launched from the Scripts menu
- ANSI blink in PRECOMPACT alerts requires iTerm2's "Blinking text allowed" setting
- If the iTerm2 sync script is killed, it must be manually restarted via Scripts > AutoLaunch

---

## 12. Extension Points

### Adding a New Row

1. Add a `print_row` call in `statusline.sh` at the desired position
2. Assign a background color variable (16-color for main rows, 8-bit for route rows)
3. If data comes from a hook, define a new route file schema following `hooks/route_file_format.md`

### Hook Integration

Any `UserPromptSubmit` hook can drive any route row by writing a JSON file to:
```
~/.claude/temp/.{guide|skill|intent|learn}_route_{SESSION_ID}.json
```

The statusline reads these files on every render. No restart required.

### Other Terminal Emulators

The OSC escape sequences (`SetUserVar`) are iTerm2-specific. For other terminals:
- Ghostty, WezTerm, Kitty: need a different mechanism for tab/title/badge
- The core `statusline.sh` rendering is terminal-agnostic
- PRs welcome for terminal-specific adapters

---

*claustatus — a Claude Code visibility layer*
