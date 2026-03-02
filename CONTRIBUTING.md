# Contributing

Thanks for taking a look. This started as a personal tool and I've gotten it to a point where it works well for my setup, but there's definitely more that could be done.

## What Would Be Most Useful

- **Linux support** — the `stat` command, path conventions, and the TTY approach all need Linux equivalents
- **Other terminals** — Ghostty, WezTerm, Kitty all have their own title-setting APIs. The Python script is iTerm2-specific right now
- **Hook templates** — example hooks that write the route files for common use cases (surfacing notes, tracking tool usage, etc.)
- **Windows/WSL** — I genuinely don't know if any of this works there
- **Narrower terminal support** — I've split CLONE and ID onto separate rows but there might be more width issues on very narrow terminals

## How It's Structured

```
statusline.sh              — core renderer, runs on every Claude Code response
statusline_title_sync.py  — iTerm2 Python API script, runs continuously
install.sh                 — setup script
hooks/route_file_format.md — how to add GUIDE/SKILL/INTENT/LEARN rows
docs/ARCHITECTURE.md       — how everything connects
```

## Before You Submit a PR

1. Test with both `bash statusline.sh` (via mock JSON) and inside a live Claude Code session
2. Check that the script still exits 0 on malformed input — a non-zero exit hides the statusline across ALL sessions, which is a bad user experience
3. Keep performance in mind — target <50ms execution

## Opening Issues

If something's broken, include:
- Your OS and bash version (`bash --version`)
- Whether you're using iTerm2 or another terminal
- The output of `echo '{}' | bash ~/.claude/scripts/statusline.sh` with stderr visible

## License

By contributing, you agree your changes will be released under the MIT license.
