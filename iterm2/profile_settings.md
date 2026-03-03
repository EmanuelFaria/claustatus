# iTerm2 Profile Settings

These are the settings needed in each iTerm2 profile to enable tab/window/badge sync.

## Manual Settings (via iTerm2 UI)

In **Settings > Profiles**, for each profile you use with Claude Code:

### General tab
- ✅ **"Applications in terminal may change the title"**
- **Badge**: `\(user.sessionBadge)`

### Window tab
- **Custom Tab Title**: `\(user.cloneName)`
- **Custom Window Title**: `\(user.sessionBadge)`

### Text tab
- ✅ **"Blinking text allowed"** — required for the PRECOMPACT NOW animated alerts

## Dynamic Profile (Automated)

If you use iTerm2 Dynamic Profiles, add these keys to your profile JSON in
`~/Library/Application Support/iTerm2/DynamicProfiles/`:

```json
{
  "Name": "Your Profile Name",
  "Guid": "your-unique-guid-here",
  "Allow Title Setting": true,
  "Custom Tab Title": "\\(user.cloneName)",
  "Custom Window Title": "\\(user.sessionBadge)",
  "Badge Text": "\\(user.sessionBadge)"
}
```

Note the double backslash (`\\`) in JSON — it renders as `\(user.cloneName)` which
iTerm2 then evaluates as an interpolated string.

## How the Variables Get Set

The `statusline_title_sync.py` script (running as an iTerm2 AutoLaunch script) sets
three user variables per session via the iTerm2 Python API:

| Variable | Value | Source |
|----------|-------|--------|
| `user.cloneName` | Directory name of the Claude session clone | `~/.claude/temp/.iterm_sync_{SID}.json` |
| `user.sessionBadge` | Session name (set via `/rename` in Claude Code) | Same sync file |

The script also sets the iTerm2 **Session Name** field to the Claude session UUID via `session.async_set_name()` — visible in Edit Current Session (⌘I).

These get updated every 5 seconds by the sync script, and immediately on profile changes.
