# claustatus

A rich, real-time powerline-style status bar for [Claude Code](https://claude.ai/code) — built entirely in Bash and Python, running inside your terminal.

![statusline preview](docs/preview.png)

## What It Shows

```
✓ Ready for input
MODEL  Claude Opus 4.6 (1M context)  v2.1.63  🧠 ON
AGENT  Read codebase for architecture review  2m 14s    ← only when agent running
CTX    163,550  16% used  84% left
CC%    133,050  13% used  87% left
SES    23,204   $2.78     8m 11s API
NAME   statusline fix   REPO  PersonalOS-session-20260228-121307
CLONE  PersonalOS-session-20260228-121307
ID     3e6c5d9c-1014-4a3c-9fc6-9618e0756e88
GUIDE  master_debugging.md ('api_failure')
SKILL  maintenance (8)
LEARN  "rebase before push"
```

Plus conditional alerts:
- 🚨 **PRECOMPACT NOW!** — animated red/yellow when context hits ≤20%
- 🔔 **PASTE PRECOMPACT NOW** — animated green when `/precompact` output is ready to copy
- **AGENT** row — orange, appears between MODEL and CTX, shows description + elapsed time when agents/subagents are running; disappears when done

## Features

- **Real-time context tracking** — tokens used, percentage remaining, cost, API duration
- **Model awareness** — shows model name, version, thinking on/off state
- **Session identity** — session name (from `/rename`), clone directory, UUID
- **Agent activity** — AGENT row shows background subagent description and elapsed time
- **Progressive disclosure rows** — GUIDE, SKILL, INTENT, LEARN show what your hook system is doing (hidden when inactive)
- **Content wrapping** — rows with long content wrap at 42 chars instead of truncating
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
| Text | Blinking text allowed | ✅ checked (for PRECOMPACT alerts) |

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

To populate any of these rows, your `UserPromptSubmit` hook writes JSON to `~/.claude/temp/.{guide|skill|intent|learn}_route_{SESSION_ID}.json`. See [`hooks/route_file_format.md`](hooks/route_file_format.md) for the exact JSON schema and example hook code.

## PRECOMPACT Alerts

The statusline shows conditional double-height alerts:

- **🚨 PRECOMPACT NOW!** — appears when context is ≤20% remaining. Animated red/yellow with ANSI blink (requires iTerm2 **Settings > Profiles > Text > "Blinking text allowed"**)
- **🔔 PASTE PRECOMPACT NOW** — appears when `~/.claude/temp/.precompact_ready` exists and is <5 minutes old.

If you use a `/precompact` script, touch this file when your output is ready:
```bash
touch ~/.claude/temp/.precompact_ready
```

## Known Limitations

- **macOS only** in current form (uses BSD `stat`, macOS paths). Linux port needs minor changes.
- **iTerm2 only** for tab/window/badge sync. PRs welcome for other terminals.
- The `/model` switch in Claude Code resets some data between renders — handled gracefully.
- **Blink animation** requires iTerm2's "Blinking text allowed" setting.
- `statusline_title_sync.py` must be launched from the Scripts menu — not from a terminal shell.

## How It Works

Claude Code calls the statusline script on every API response, piping a JSON blob with session data to stdin. The script:

1. **Single `jq` call** — extracts all 16 fields at once using Unit Separator (`\x1f`) to avoid bash's whitespace-collapsing IFS behavior
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
