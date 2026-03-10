# claustatus

A rich, real-time powerline-style status bar for [Claude Code](https://claude.ai/code) — built entirely in Bash and Python, running inside your terminal.

![statusline preview](docs/preview.png)

## What It Shows

```
✓ Ready for input
MODEL  Claude Opus 4.6 (1M context)  v2.1.63  🧠 ON
AGENT  Read codebase for architecture...  2m 14s    ← only when agent running
CTX    163,550  16% used  84% left
USAGE  WK 12%    API$  $3.42
CAP    5h 63%  7d 41%                    ← only when API key is configured
NAME   statusline fix                    ← only when session has been /renamed
REPO   PersonalOS-session-20260228-...
CLONE  PersonalOS-session-20260228-121307
ID     3e6c5d9c-1014-4a3c-9fc6-9618e0756e88
GUIDE  master_debugging.md ('api_failure')
SKILL  maintenance (8)
LEARN  "rebase before push"
LIMITS 58/60 req  195K/200K tok/min       ← only when API key is configured
```

Plus conditional alerts:
- 🚨 **PRECOMPACT NOW!** — animated red/yellow when context hits ≤15%
- 🔔 **PASTE PRECOMPACT NOW** — animated green when `/precompact` output is ready to copy
- **AGENT** row — orange, appears between MODEL and CTX, shows description + elapsed time when agents/subagents are running; disappears when done

## Features

- **Real-time context tracking** — tokens used, percentage remaining
- **Cost tracking** — USAGE row shows weekly budget %, API$ row shows monthly total; both auto-reset
- **API rate limits** — LIMITS row shows requests and tokens remaining per minute (requires `ANTHROPIC_API_KEY`)
- **Model awareness** — shows model name, version, thinking on/off state
- **Session identity** — session name (from `/rename`), repo name, clone directory, UUID
- **Agent activity** — AGENT row shows background subagent description and elapsed time
- **Progressive disclosure rows** — GUIDE, SKILL, INTENT, LEARN show what your hook system is doing (hidden when inactive)
- **Content wrapping** — rows with long content wrap at 34 chars instead of truncating
- **iTerm2 integration** — tab title, window title, badge, and Session Name update automatically per-session
- **Multi-session safe** — each session gets its own route files, no cross-contamination
- **Fast** — single `jq` call, pure bash computation, ~40ms execution

## Requirements

- macOS (or Linux with minor tweaks)
- Claude Code
- [Homebrew](https://brew.sh) bash: `brew install bash`
- `jq`: `brew install jq`
- A [Nerd Font](https://www.nerdfonts.com/) for the powerline arrows (optional but recommended)
- **iTerm2 integration**: iTerm2 only (for tab/window/badge sync)

## Quick Install

```bash
# Clone this repo
git clone https://github.com/EmanuelFaria/claustatus.git
cd claustatus

# Run the installer
bash install.sh
```

The installer will:
1. Copy `statusline.sh` to `~/.claude/scripts/statusline.sh`
2. Configure `~/.claude/settings.json` to use it
3. Optionally install the iTerm2 title sync script

## Manual Install

### 1. Copy the script

```bash
mkdir -p ~/.claude/scripts
cp statusline.sh ~/.claude/scripts/statusline.sh
chmod +x ~/.claude/scripts/statusline.sh
```

### 2. Configure Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/YOUR_USERNAME/.claude/scripts/statusline.sh"
  }
}
```

Note: use the full absolute path — `~` does not expand in JSON.

### 3. Test it

```bash
echo '{"model":{"display_name":"Test"},"version":"1.0","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"total_input_tokens":50000,"used_percentage":25,"remaining_percentage":75},"cost":{"total_cost_usd":0.5,"total_api_duration_ms":60000},"session_id":"test-123","transcript_path":""}' | bash ~/.claude/scripts/statusline.sh
```

## iTerm2 Tab/Window/Badge Sync (Optional)

If you use iTerm2, `statusline_title_sync.py` syncs Claude session data to your terminal window in real time:

| iTerm2 Field | Value | How to see it |
|---|---|---|
| **Tab title** | Clone directory name (repo/worktree) | Tab bar |
| **Window title** | Session name from `/rename` | Title bar |
| **Badge** | Session name from `/rename` | Badge overlay on terminal |
| **Session Name** | Claude session UUID | Edit Current Session panel |

### Install the Sync Script

```bash
# Create the AutoLaunch directory if needed
mkdir -p ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch

# Copy the script
cp statusline_title_sync.py ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch/
```

### Launch It

**Do NOT run it from a terminal shell.** The script requires iTerm2's own Python environment and the `ITERM2_COOKIE` environment variable that only iTerm2 sets. Running it from a shell will get HTTP 401 errors.

Launch it from within iTerm2:

1. Open iTerm2 menu bar → **Scripts** → **AutoLaunch** → **statusline_title_sync.py**

Or restart iTerm2 entirely — AutoLaunch scripts run automatically on startup.

### After You Launch It

Check it's running:

```bash
cat ~/Library/Application\ Support/iTerm2/Scripts/AutoLaunch/../../../ScriptHistory/statusline_title_sync.py/status
```

Or check the log:

```bash
tail -f ~/.claude/temp/.iterm_sync_script.log
```

### If You Kill It

**Important:** If you kill the script with `pkill` or close its window, iTerm2 does NOT auto-restart it. You must restart it manually via the Scripts > AutoLaunch menu or restart iTerm2.

### iTerm2 Profile Settings

Configure each profile you use with Claude Code.

**Via the iTerm2 UI** (Settings → Profiles):

| Tab | Field | Value |
|---|---|---|
| General | Applications in terminal may change the title | ✅ checked |
| General | Badge | `\(user.sessionBadge)` |
| Window | Custom Tab Title | `\(user.cloneName)` |
| Window | Custom Window Title | `\(user.sessionBadge)` |
| Text | Blinking text allowed | ✅ checked (optional — alerts use row-swap, not blink) |

**Via Dynamic Profiles** (`~/Library/Application Support/iTerm2/DynamicProfiles/yourprofile.json`):

```json
{
  "Name": "Your Profile Name",
  "Guid": "your-unique-guid",
  "Allow Title Setting": true,
  "Custom Tab Title": "\\(user.cloneName)",
  "Custom Window Title": "\\(user.sessionBadge)",
  "Badge Text": "\\(user.sessionBadge)"
}
```

Note the double backslash (`\\`) in JSON — it renders as a single `\` which iTerm2 interprets as its variable interpolation syntax.

The `statusline_title_sync.py` script also automatically applies the badge template (`\(user.sessionBadge)`) to all your profiles on startup, bypassing profile plists that iTerm2 ignores after launch.

---

## The GUIDE / SKILL / INTENT / LEARN Rows

These four rows show real-time decisions made by Claude Code hook scripts. They're all **optional** — rows show `none` (gray) when no route file exists for the current session.

### GUIDE — Guidance injection

Shows which guidance/documentation file was automatically loaded into Claude's context for this prompt.

| State | Color | Example |
|-------|-------|---------|
| File loaded | 🟢 Green | `master_debugging.md ('api_failure')` |
| Cooldown (already loaded today) | 🟡 Amber | `cooldown` |
| No match | ⬜ Gray | `none` |

Source: your `UserPromptSubmit` hook writes `.guidance_route_{SID}.json` when it keyword-matches a prompt and injects a guidance file.

### SKILL — Skill routing

Shows which Claude Code skill was matched, or how many skill options were offered, plus the skill category.

| State | Color | Example |
|-------|-------|---------|
| Specific skill loaded | 🟢 Green | `csv-protocol` |
| Multiple skills matched, options offered | 🔵 Blue | `maintenance (8)` |
| User declined the options | 🟡 Amber | `declined` |
| No match | ⬜ Gray | `none` |

Source: your `UserPromptSubmit` hook writes `.skill_route_{SID}.json` based on prompt pattern matching.

### INTENT — Capability routing

Detects what type of task you're asking for and which tool it was routed to.

| Prompt contains... | INTENT shows |
|---|---|
| "search for", "find online", "look up" | `web_search → perplexity-sonar` |
| "review this code", "check for bugs" | `code_review → thinking` |
| "extract from", "parse this" | `extraction → claude-thinking` |
| "think through", "analyze deeply" | `reasoning → thinking` |
| "create hook", "can Claude do X" | `hook_creation ⚠️` |
| No pattern matched | `none` |

| State | Color | Example |
|-------|-------|---------|
| Task type matched | 🔵 Blue | `web_search → perplexity-sonar` |
| No match | ⬜ Gray | `none` |

Source: your `UserPromptSubmit` hook writes `.intent_route_{SID}.json`. Detection patterns live in `~/.claude/routing/capability_router.json`.

### LEARN — Past learnings surfaced

Shows the short label of the most relevant past learning that was surfaced from your knowledge base for this prompt.

| State | Color | Example |
|-------|-------|---------|
| Learning(s) found | 🟢 Green | `"rebase before push"` |
| Multiple learnings | 🟢 Green | `"bash IFS tab collapses" +2` |
| Skipped (throttled) | 🟡 Amber | `skipped` |
| No match | ⬜ Gray | `none` |

Source: your `UserPromptSubmit` hook queries a database of past learnings by keyword, writes `.learn_route_{SID}.json` with the best match's title (ideally a short ≤3-word label) and count.

---

## USAGE / API$ — Cost Tracking

Two rows track API spend:

```
USAGE  WK 12%    API$  $3.42
```

**USAGE** — Weekly percentage of a configurable budget (default $100/week, override: `export WEEKLY_BUDGET_USD=50`).
- Color: 🟢 blue default / 🟡 yellow ≥50% / 🟠 orange ≥75% / 🔴 red ≥90%

**API$** — Monthly total accumulated across all sessions.
- Color: 🟢 teal default / 🟠 orange ≥$10 / 🔴 red ≥$50
- Auto-resets on the first of each month

Both track the **delta** between each render's session cost and the previous render, adding only new spend. Per-session "last seen" file (`~/.claude/temp/.ses_last_{SID}`) prevents double-counting. All file I/O in a single `awk BEGIN` block for performance.

This tracks **direct API costs only**, not Claude Max subscription fees.

## LIMITS — API Rate Limits

The LIMITS row shows remaining requests and tokens for the current rate-limit window:

```
LIMITS  58/60 req  195K/200K tok/min
```

- Shown only when `~/.claude/temp/.api_limits.json` exists and is <20 minutes old
- Background refresh runs every 10 minutes via a `HEAD` request to `api.anthropic.com/v1/models`
- Requires `ANTHROPIC_API_KEY` in your shell environment or macOS Keychain as `anthropic_api_key`
- Color: 🟢 green >30% remaining / 🟡 amber ≤30% / 🔴 red ≤10%

To add your key to Keychain:
```bash
security add-generic-password -s "anthropic_api_key" -a "$USER" -w "sk-ant-..."
```

## CAP — Rolling Usage Caps

The CAP row shows Anthropic's actual 5-hour and 7-day rolling usage cap percentages — the numbers that determine when a Max subscriber gets throttled:

```
CAP    5h 63%  7d 41%
```

- Shown only when `~/.claude/temp/.usage_caps.json` exists and is <2 hours old
- Background refresh runs every 60 minutes via the `/api/oauth/usage` endpoint
- Uses the same `ANTHROPIC_API_KEY` as the LIMITS row
- Color: 🟢 green ≤50% / 🟡 amber ≤75% / 🔴 red >75% (based on whichever window is higher)

**USAGE vs CAP:** USAGE tracks your dollar spend vs a self-imposed budget. CAP tracks Anthropic's actual rolling limits. Max subscribers get throttled by CAP, not USAGE.

---

To populate the GUIDE/SKILL/INTENT/LEARN rows, your `UserPromptSubmit` hook writes JSON to `~/.claude/temp/.{guide|skill|intent|learn}_route_{SESSION_ID}.json`. See [`hooks/route_file_format.md`](hooks/route_file_format.md) for the exact JSON schema and example hook code.

## PRECOMPACT Alerts

The statusline shows conditional double-height alerts at the top:

- **🚨 PRECOMPACT NOW!** — appears when context is ≤15% remaining. Shown as two alternating rows that swap positions every second (even/odd of `date +%S`), creating a visible flash effect since ANSI blink is stripped by Claude Code's TUI. Hidden automatically while `/precompact` is running (no double-alert during the extraction).
- **🔔 PASTE PRECOMPACT NOW** — appears when `~/.claude/temp/.precompact_ready` exists and is <5 minutes old. Same two-row alternating display in green.

Priority: PASTE PRECOMPACT (if ready) > PRECOMPACT NOW > nothing.

Both alerts use the two-row swap for visibility; ANSI blink is not required and has no effect inside Claude Code's TUI.

### Native macOS Notifications + iTerm2 Tab Flash (Optional)

`~/.claude/scripts/precompact_alert_watcher.py` watches the same flag files and fires system-level alerts when either state triggers:

- **macOS notification** — banner with the alert type and window number (e.g. "window 19 — PRECOMPACT NOW")
- **iTerm2 tab flash** — turns the terminal tab red for 2 seconds, then resets
- **Dock fireworks** — bounces the iTerm2 dock icon

Runs via LaunchAgent `com.personalos.precompact-alert-watcher`, checks every 5 seconds, 2-minute cooldown between repeat notifications for the same alert.

The window number is extracted from the `iterm_session_id` field written by `statusline.sh` into `.iterm_sync_{SID}.json` (format: `w{N}t{M}p{L}:{UUID}` → window N+1). The TTY path is also written to that file so the watcher knows which terminal to flash.

### Integration with a `/precompact` script

If you use a `/precompact` script (or a PreCompact hook), signal the statusline at two points:

```bash
# 1. At the START of extraction — suppresses PRECOMPACT NOW while running
touch ~/.claude/temp/.precompact_running

# 2. When output is ready to paste — triggers PASTE PRECOMPACT NOW alert
touch ~/.claude/temp/.precompact_ready
rm -f ~/.claude/temp/.precompact_running
```

Both flag files are cleared as the very first action of any PreCompact hook — before the recursion guard runs — so the PASTE PRECOMPACT NOW alert disappears even if the hook exits early.

The `.precompact_running` flag expires automatically after 2 minutes if not removed. The `.precompact_ready` flag expires after 5 minutes.

## Known Limitations

- **macOS only** in current form (uses BSD `stat`, macOS paths). Linux port needs minor changes.
- **iTerm2 only** for tab/window/badge sync. PRs welcome for other terminals.
- The `/model` switch in Claude Code resets some data between renders — handled gracefully.
- **Flash animation** uses row-swap on each render (ANSI blink is stripped by Claude Code's TUI).
- `statusline_title_sync.py` must be launched from the Scripts menu — not from a terminal shell.

## How It Works

Claude Code calls the statusline script on every API response, piping a JSON blob with session data to stdin. The script:

1. **Single `jq` call** — extracts all 15 fields at once using Unit Separator (`\x1f`) to avoid bash's whitespace-collapsing IFS behavior
2. **Pure bash computation** — token math, percentages, string formatting
3. **Route file reads** — session-specific JSON files written by hooks
4. **Printf output** — all rows using 16-color ANSI codes (compatible with iTerm2's TUI)
5. **Background iTerm2 sync** — writes OSC sequences to parent TTY for tab/badge updates; Python script polls every 5s for window title, badge, and Session Name

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full data flow diagram.

If you want to modify the script, [`docs/HACKING.md`](docs/HACKING.md) explains the non-obvious decisions: why the field separator is `\x1f` instead of tab, why there's no `set -e`, what `BASE_OVERHEAD` is, and how to add a new row.

## Contributing

PRs welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

Areas that would benefit from community input:

- **Linux support** — mainly the `stat` command and path conventions
- **Other terminal emulators** — Ghostty, WezTerm, Kitty equivalents for tab/badge sync
- **More rows** — what other Claude Code data would be useful to surface?
- **Windows/WSL** — no idea if this works there, would love to know
- **Hook templates** — starter hooks that write the route files (e.g. surfacing guidance from a notes folder)

## License

MIT

---

*Built while debugging Claude Code sessions at 2am. Shared because it made my workflow significantly better and maybe it'll help yours too.*
