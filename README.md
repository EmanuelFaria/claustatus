# Claude Code Powerline Statusline

A rich, real-time powerline-style status bar for [Claude Code](https://claude.ai/code) — built entirely in Bash and Python, running inside your terminal.

![statusline preview](docs/preview.png)

## What It Shows

```
✓ Ready for input
MODEL  Claude Opus 4.6 (1M context)  v2.1.63  🧠 ON
CTX    163,550  16% used  84% left
CC%    133,050  13% used  87% left
SES    23,204   $2.78     8m 11s API
NAME   statusline fix   REPO  PersonalOS-session-20260228-121307
CLONE  PersonalOS-session-20260228-121307
ID     3e6c5d9c-1014-4a3c-9fc6-9618e0756e88
GUIDE  master_debugging.md ('api_failure')
SKILL  8 options
INTENT web_search → perplexity-sonar
LEARN  surfaced 1 past learning
```

Plus conditional alerts:
- 🚨 **PRECOMPACT NOW!** — animated red/yellow when context hits ≤20%
- 🔔 **PASTE PRECOMPACT NOW** — animated green when `/precompact` output is ready to copy

## Features

- **Real-time context tracking** — tokens used, percentage remaining, cost, API duration
- **Model awareness** — shows model name, version, thinking on/off state
- **Session identity** — session name, clone directory, UUID
- **Progressive disclosure rows** — GUIDE, SKILL, INTENT, LEARN show what your hook system is doing
- **iTerm2 integration** — tab title, window title, and badge update automatically per-session
- **Multi-session safe** — each session gets its own route files, no cross-contamination
- **Fast** — single `jq` call, pure bash computation, ~40ms execution

## Requirements

- macOS (or Linux with minor tweaks)
- Claude Code
- [Homebrew](https://brew.sh) bash: `brew install bash`
- `jq`: `brew install jq`
- A [Nerd Font](https://www.nerdfonts.com/) for the powerline arrows (optional but recommended)
- **iTerm2 integration**: iTerm2 + Python 3.10+ (for tab/window/badge sync)

## Quick Install

```bash
# Clone this repo
git clone https://github.com/EmanuelFaria/claude-code-powerline-statusline.git
cd claude-code-powerline-statusline

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
    "command": "/path/to/your/statusline.sh"
  }
}
```

Use your actual path — usually `~/.claude/scripts/statusline.sh` but note `~` doesn't expand in JSON, use the full path.

### 3. Test it

```bash
echo '{"model":{"display_name":"Test"},"version":"1.0","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"total_input_tokens":50000,"used_percentage":25,"remaining_percentage":75},"cost":{"total_cost_usd":0.5,"total_api_duration_ms":60000},"session_id":"test-123","transcript_path":""}' | bash ~/.claude/scripts/statusline.sh
```

## iTerm2 Tab/Window/Badge Sync (Optional)

If you use iTerm2, the `statusline_title_sync.py` script syncs session data to:
- **Tab title** → clone directory name
- **Window title** → session UUID
- **Badge** → session name (from `/rename`)

### Setup

```bash
# Copy to iTerm2 AutoLaunch
mkdir -p ~/.config/iterm2/AppSupport/Scripts/AutoLaunch
cp statusline_title_sync.py ~/.config/iterm2/AppSupport/Scripts/AutoLaunch/

# Install dependencies
pip3 install iterm2
```

Then restart iTerm2 or go to **Scripts > AutoLaunch > statusline_title_sync.py**.

### iTerm2 Profile Settings

In **Settings > Profiles**, for each profile:

1. **General tab** → check **"Applications in terminal may change the title"**
2. **Window tab** → set:
   - **Custom Tab Title**: `\(user.cloneName)`
   - **Custom Window Title**: `\(user.sessionId)`
3. **General tab → Badge**: `\(user.sessionBadge)`

## The GUIDE / SKILL / INTENT / LEARN Rows

These four rows show real-time decisions made by Claude Code hook scripts:

| Row | Shows | Powered by |
|-----|-------|-----------|
| **GUIDE** | Which guidance file was injected this prompt | `UserPromptSubmit` hook that writes `.guidance_route_{SID}.json` |
| **SKILL** | Which skill was routed | `UserPromptSubmit` hook that writes `.skill_route_{SID}.json` |
| **INTENT** | Detected task type → tool target | `UserPromptSubmit` hook that writes `.intent_route_{SID}.json` |
| **LEARN** | Past learnings surfaced from DB | `UserPromptSubmit` hook that writes `.learn_route_{SID}.json` |

These rows are **optional** — if the route files don't exist, the rows show `none`. To populate them, your `UserPromptSubmit` hook needs to write JSON to `~/.claude/temp/.{guide|skill|intent|learn}_route_{SESSION_ID}.json`.

See [`hooks/route_file_format.md`](hooks/route_file_format.md) for the JSON format and how to integrate this into your own hooks.

## PRECOMPACT Alerts

The statusline shows conditional double-height alerts:

- **🚨 PRECOMPACT NOW!** — appears when context is ≤20% remaining. Animated red/yellow with ANSI blink (requires iTerm2 **Settings > Profiles > Text > "Blinking text allowed"**)
- **🔔 PASTE PRECOMPACT NOW** — appears when `~/.claude/temp/.precompact_ready` exists and is <5 minutes old. This file is written by the `/precompact` command after it generates a compact summary ready to paste.

If you use a `/precompact` script, touch this file when your output is ready:
```bash
touch ~/.claude/temp/.precompact_ready
```

## Known Limitations

- **macOS only** in current form (uses BSD `stat`, macOS paths). Linux port would need minor changes.
- **iTerm2 only** for tab/window/badge sync. PRs welcome for other terminals.
- The `/model` switch in Claude Code resets some data between renders — statusline handles this gracefully now (no more cross-session crashes).
- **Blink animation** requires iTerm2's "Blinking text allowed" setting — most terminals support `\033[5m` but some disable it by default.

## How It Works

Claude Code calls the statusline script on every API response, piping a JSON blob with session data to stdin. The script:

1. **Single `jq` call** — extracts all 16 fields at once using Unit Separator (`\x1f`) to avoid bash's whitespace-collapsing IFS behavior
2. **Pure bash computation** — token math, percentages, string formatting
3. **Route file reads** — session-specific JSON files written by hooks
4. **Printf output** — all rows using 16-color ANSI codes (compatible with iTerm2's TUI)
5. **Background iTerm2 sync** — writes OSC sequences to parent TTY for tab/badge updates

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full data flow diagram.

## Contributing

PRs welcome! Areas that would benefit from community input:

- **Linux support** — mainly the `stat` command and path conventions
- **Other terminal emulators** — Ghostty, WezTerm, Kitty equivalents for tab/badge sync
- **More rows** — what other Claude Code data would be useful to surface?
- **Windows/WSL** — no idea if this works there, would love to know
- **Hook templates** — starter hooks that write the route files for common use cases (e.g. surfacing guidance from a notes folder)

Please open an issue before a large PR so we can discuss direction.

## License

MIT

---

*Built while debugging Claude Code sessions at 2am. Shared because it made my workflow significantly better and maybe it'll help yours too.*
