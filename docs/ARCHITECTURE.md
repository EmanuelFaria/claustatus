# Architecture

## Data Flow

```
Claude Code API response
        │
        ▼ (stdin: JSON blob)
  statusline.sh
        │
        ├── jq: extract 16 fields via Unit Separator (avoids bash IFS tab-collapse bug)
        │
        ├── Route files: ~/.claude/temp/.{guide,skill,intent,learn}_route_{SID}.json
        │   └── Written by UserPromptSubmit hooks, read by statusline
        │
        ├── Settings: ~/.claude/settings.json → thinking mode, model
        │
        ├── Activity: ~/.claude/temp/.current_activity.json
        │
        └── printf: 12-15 powerline rows → stdout (Claude Code renders these)
                │
                └── Background: /dev/ttysNNN (parent TTY)
                    ├── SetUserVar=cloneName
                    ├── SetUserVar=sessionId
                    └── SetUserVar=sessionBadge

iTerm2 (statusline_title_sync.py — runs every 5s)
        │
        ├── Reads: ~/.claude/temp/.iterm_sync_{SID}.json
        │   (written by statusline.sh background section)
        │
        ├── Matches iTerm2 sessions to Claude sessions via iterm_session_id
        │
        └── Sets via Python API:
            ├── tab.async_set_title(clone_name)
            ├── window.async_set_title(session_uuid)
            └── session.async_set_variable("user.sessionBadge", name)
```

## Key Design Decisions

### Why Unit Separator instead of Tab for IFS?

Bash's `read` treats tab as whitespace — consecutive tabs collapse to one, losing empty fields. When `workspace.project_dir` is empty (common), this shifts all subsequent fields by 1, landing the session UUID in `SES_DURATION_MS` and crashing arithmetic. `\x1f` (ASCII 31, Unit Separator) is non-whitespace, so consecutive separators create empty fields correctly.

### Why no `set -e` or `set -o pipefail`?

Claude Code uses the statusline script's exit code as a health signal — non-zero exits cause it to hide the statusline **globally across all sessions**. Removing these prevents transient jq failures (which happen on model switches when JSON structure changes) from taking down every open session.

### Why session-specific route files?

Multiple Claude Code sessions share `~/.claude/temp/`. Without session IDs in filenames, the last hook to write wins — all sessions display the same GUIDE/SKILL/INTENT/LEARN data. Session-specific files with global fallback give each session its own state while remaining backward-compatible.

### Why write to `/dev/ttysNNN` for iTerm2?

Claude Code's TUI captures the statusline script's stdout to render in its status area. OSC escape sequences in stdout are lost. Writing directly to the parent process's TTY (`/dev/$(ps -o tty= -p $PPID)`) bypasses the TUI and reaches iTerm2 directly. This is how the `SetUserVar` sequences work.

### Why a Python script for iTerm2 sync instead of just escape codes?

`\033]1;title\007` and `\033]2;title\007` set "session name" and "window title" internally in iTerm2, but whether they display depends on iTerm2's profile Title Components settings. The Python API (`tab.async_set_title`, `window.async_set_title`) bypasses the profile settings and sets titles directly. The Python script also handles the profile change event — re-applying titles when you switch profiles in iTerm2.

## Row Rendering

All rows use basic 16-color ANSI codes (`\033[4Xm` for backgrounds), not 8-bit 256-color. The reason: Claude Code's TUI has trouble with 8-bit codes on certain model configurations, causing truncation. 16-color codes are universally compatible with the TUI's rendering pipeline.

The route rows (GUIDE, SKILL, INTENT, LEARN) are an exception — they use 8-bit colors for more expressive state representation (green/blue/amber/gray). These work because they appear after the TUI has already committed to rendering the statusline area.

## Performance

Target: <50ms total execution.

- Single `jq` call for all JSON extraction
- No subprocesses for route file reads (`$(<file)` bash built-in)
- Git remote lookup: 30-second cache in `/tmp`
- Session name lookup: cached in `/tmp/statusline-sessname-{SID}`
- iTerm2 sync: background subshell (`&`) — doesn't block rendering
