#!/usr/bin/env python3
"""
statusline_title_sync.py — iTerm2 AutoLaunch Script

Syncs Claude Code session data to iTerm2 session properties:
  - Tab title    → CLONE (repo/worktree basename)
  - Window title → ID (Claude session UUID)
  - Badge        → NAME (session name from /rename)
  - Session Name → resume command (cd ... && claude --resume ...)

Data source: ~/.claude/temp/.iterm_sync_<session_id>.json (per-session)

Architecture:
  - On startup: set all profiles' badge text to \\(user.sessionBadge) via API
  - Every 5s: scan sync files, match to sessions by iterm_session_id, set variables
  - On profile change: re-apply all values
"""
import asyncio
import fcntl
import glob
import json
import os
import re
import sys
import time

import iterm2
import iterm2.notifications

# Singleton guard: prevent multiple instances from running simultaneously
PID_FILE = os.path.expanduser("~/.claude/temp/.statusline_title_sync.pid")
_pid_fp = None

def acquire_singleton():
    """Ensure only one instance runs. Exit silently if another is already running."""
    global _pid_fp
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    _pid_fp = open(PID_FILE, "w")
    try:
        fcntl.flock(_pid_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _pid_fp.write(str(os.getpid()))
        _pid_fp.flush()
    except (BlockingIOError, OSError):
        sys.exit(0)  # Another instance holds the lock

acquire_singleton()

SYNC_DIR = os.path.expanduser("~/.claude/temp")
SYNC_PATTERN = os.path.join(SYNC_DIR, ".iterm_sync_*.json")
STATUSLINE_CACHE = os.path.join(SYNC_DIR, "statusline_data.json")
LOG_FILE = os.path.join(SYNC_DIR, ".iterm_sync_script.log")

# Profiles to NEVER modify automatically
PROTECTED_PROFILES = {"Guardian Debug"}

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

# Track applied values: iTerm2 session_id -> {name, badge, claude_sid}
_applied: dict[str, dict[str, str]] = {}

POLL_INTERVAL = 5
MAX_SYNC_AGE = 86400


def log(msg: str) -> None:
    """Log to file for debugging (viewable at ~/.claude/temp/.iterm_sync_script.log)."""
    try:
        ts = time.strftime("%H:%M:%S")
        with open(LOG_FILE, "a") as f:
            f.write(f"[{ts}] {msg}\n")
    except Exception:
        pass


def read_all_sync_files() -> dict[str, dict]:
    """Read all per-session sync files, keyed by Claude session ID."""
    result = {}
    for path in glob.glob(SYNC_PATTERN):
        try:
            with open(path) as f:
                data = json.load(f)
            sid = data.get("session_id", "")
            if sid and time.time() - data.get("timestamp", 0) < MAX_SYNC_AGE:
                result[sid] = data
        except Exception:
            continue
    return result


def build_iterm_index(all_sync: dict[str, dict]) -> dict[str, dict]:
    """Build iTerm2 session UUID -> sync_data for direct 1:1 matching.

    Sync files contain iterm_session_id like "w6t0p0:UUID".
    The UUID after the colon matches session.session_id in the Python API.
    """
    index = {}
    for sync_data in all_sync.values():
        iterm_sid = sync_data.get("iterm_session_id", "")
        if iterm_sid:
            parts = iterm_sid.split(":", 1)
            uuid_part = parts[1] if len(parts) == 2 else iterm_sid
            if uuid_part:
                index[uuid_part] = sync_data
    return index


def build_repo_index(all_sync: dict[str, dict]) -> dict[str, dict]:
    """Build repo_name -> sync_data mapping (fallback for sessions without iterm_session_id)."""
    index = {}
    for sync_data in all_sync.values():
        repo = sync_data.get("repo_name", "")
        if repo and repo != "--":
            index[repo] = sync_data
    return index


def read_cached_titles() -> tuple[str | None, str | None]:
    """Read CLONE and ID from shared statusline cache (fallback)."""
    try:
        with open(STATUSLINE_CACHE) as f:
            data = json.load(f)
        project_dir = data.get("workspace", {}).get("project_dir", "")
        repo_name = os.path.basename(project_dir) if project_dir else ""
        session_id = data.get("session_id", "")
        return repo_name or None, session_id or None
    except Exception:
        return None, None


async def setup_profile_badges(connection) -> None:
    """Set all profiles' badge text to \\(user.sessionBadge) via the Python API.

    This bypasses the plist (which running iTerm2 ignores) and directly
    modifies the in-memory profile objects. Guardian Debug is skipped.
    """
    log("Setting up profile badge templates...")
    try:
        profiles = await iterm2.PartialProfile.async_query(connection)
        for partial in profiles:
            if partial.name in PROTECTED_PROFILES:
                log(f"  Skipping protected profile: {partial.name}")
                continue
            try:
                full = await partial.async_get_full_profile()
                current_badge = full.badge_text
                target = "\\(user.sessionBadge)"
                if current_badge != target:
                    await full.async_set_badge_text(target)
                    log(f"  Set badge template on: {partial.name} (was: {repr(current_badge)})")
                else:
                    log(f"  Already correct: {partial.name}")
            except Exception as e:
                log(f"  Error on profile {partial.name}: {e}")
    except Exception as e:
        log(f"Failed to query profiles: {e}")


async def get_tab_title(session) -> str | None:
    """Get the tab title for a session (set by OSC 1 to clone name)."""
    try:
        title = await session.async_get_variable("tab.title")
        return str(title).strip() if title else None
    except Exception:
        return None


async def find_claude_session(
    session, iterm_index: dict[str, dict], repo_index: dict[str, dict]
) -> dict | None:
    """Match an iTerm2 session to Claude sync data.

    Strategy (priority order):
    1. Direct match: session.session_id against iterm_session_id from sync files (1:1)
    2. Cached mapping from previous successful match
    3. user.sessionId variable (set by this script on previous match)
    4. Fallback: tab title against repo_names (ambiguous — only for old sync files)
    """
    iterm_sid = session.session_id

    # 1. Direct 1:1 match via iterm_session_id (most reliable)
    if iterm_sid in iterm_index:
        return iterm_index[iterm_sid]

    # 2. Check our applied cache
    cached = _applied.get(iterm_sid, {})
    cached_claude_sid = cached.get("claude_sid")
    if cached_claude_sid:
        sync_data = read_all_sync_files().get(cached_claude_sid)
        if sync_data:
            return sync_data

    # 3. Try user.sessionId variable (set by us on previous successful match)
    try:
        user_sid = await session.async_get_variable("user.sessionId")
        if user_sid and UUID_RE.match(str(user_sid).strip()):
            claude_sid = str(user_sid).strip()
            all_sync = read_all_sync_files()
            if claude_sid in all_sync:
                return all_sync[claude_sid]
    except Exception:
        pass

    # 4. Fallback: tab title match (ambiguous, for sessions without iterm_session_id)
    tab_title = await get_tab_title(session)
    if tab_title and tab_title in repo_index:
        return repo_index[tab_title]

    return None


async def apply_session_data(
    session, sync_data: dict, force: bool = False
) -> None:
    """Apply all Claude session data to an iTerm2 session."""
    iterm_sid = session.session_id
    resume_cmd = sync_data.get("resume_cmd", "")
    session_name = sync_data.get("session_name", "")
    claude_sid = sync_data.get("session_id", "")

    current = _applied.get(iterm_sid, {})

    # Set user.sessionId for future fast matching
    if claude_sid and current.get("claude_sid") != claude_sid:
        try:
            await session.async_set_variable("user.sessionId", claude_sid)
        except Exception as e:
            log(f"  Error setting user.sessionId: {e}")

    # Set Session Name = resume command
    if resume_cmd and (force or current.get("name") != resume_cmd):
        try:
            await session.async_set_name(resume_cmd)
            current["name"] = resume_cmd
            log(f"  Set name on {iterm_sid[:8]}: {resume_cmd[:50]}...")
        except Exception as e:
            log(f"  Error setting name on {iterm_sid[:8]}: {e}")

    # Set Badge via user variable (profile badge text = \(user.sessionBadge))
    # Always set — no caching. Profile re-application can clear user variables,
    # and our cache would incorrectly skip re-applying.
    badge_val = session_name if session_name else ""
    try:
        await session.async_set_variable("user.sessionBadge", badge_val)
        if current.get("badge") != badge_val:
            log(f"  Set badge on {iterm_sid[:8]}: {badge_val}")
        current["badge"] = badge_val
    except Exception as e:
        log(f"  Error setting badge on {iterm_sid[:8]}: {e}")

    if claude_sid:
        current["claude_sid"] = claude_sid
    _applied[iterm_sid] = current


async def apply_titles(session, tab, window, sync_data: dict) -> None:
    """Re-apply tab and window titles from sync data."""
    repo_name = sync_data.get("repo_name", "")
    claude_sid = sync_data.get("session_id", "")
    if repo_name and repo_name != "--":
        try:
            await tab.async_set_title(repo_name)
        except Exception:
            pass
    if claude_sid:
        try:
            await window.async_set_title(claude_sid)
        except Exception:
            pass


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # Phase 1: Set profile badge templates via API (bypasses stale plist)
    await setup_profile_badges(connection)

    # Phase 2: Initial scan — apply to all existing sessions immediately
    log("Initial scan of existing sessions...")
    all_sync = read_all_sync_files()
    iterm_index = build_iterm_index(all_sync)
    repo_index = build_repo_index(all_sync)
    log(f"  Found {len(all_sync)} sync files, {len(iterm_index)} with iterm_session_id, {len(repo_index)} unique repos")

    for window in app.windows:
        for tab in window.tabs:
            for session in tab.sessions:
                sync_data = await find_claude_session(session, iterm_index, repo_index)
                if sync_data:
                    await apply_session_data(session, sync_data, force=True)
                    await apply_titles(session, tab, window, sync_data)
                    log(f"  Matched {session.session_id[:8]} → {sync_data.get('repo_name')} (claude: {sync_data.get('session_id', '')[:8]})")

    log("Initial scan complete. Entering poll loop.")

    # Phase 3: Profile change handler
    async def on_profile_changed(_connection, notification):
        """Re-apply all properties when a session's profile changes."""
        await asyncio.sleep(0.3)

        changed_iterm_sid = notification.identifier
        log(f"Profile changed on {changed_iterm_sid[:8]}")

        all_sync_now = read_all_sync_files()
        iterm_idx = build_iterm_index(all_sync_now)
        repo_idx = build_repo_index(all_sync_now)

        for window in app.windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    if session.session_id == changed_iterm_sid:
                        sync_data = await find_claude_session(session, iterm_idx, repo_idx)
                        if sync_data:
                            await apply_titles(session, tab, window, sync_data)
                            await apply_session_data(session, sync_data, force=True)
                            log(f"  Re-applied to {changed_iterm_sid[:8]}")
                            return

                        # Fallback: shared cache for titles only
                        repo_name, cached_sid = read_cached_titles()
                        if repo_name:
                            try:
                                await tab.async_set_title(repo_name)
                            except Exception:
                                pass
                        if cached_sid:
                            try:
                                await window.async_set_title(cached_sid)
                            except Exception:
                                pass
                        return

    await iterm2.notifications.async_subscribe_to_variable_change_notification(
        connection,
        on_profile_changed,
        scope=iterm2.VariableScopes.SESSION.value,
        name="profileName",
        identifier="all",
    )

    # Phase 4: Periodic scanner
    while True:
        await asyncio.sleep(POLL_INTERVAL)
        try:
            all_sync = read_all_sync_files()
            if not all_sync:
                continue

            iterm_index = build_iterm_index(all_sync)
            repo_index = build_repo_index(all_sync)

            for window in app.windows:
                for tab in window.tabs:
                    for session in tab.sessions:
                        sync_data = await find_claude_session(
                            session, iterm_index, repo_index
                        )
                        if sync_data:
                            await apply_session_data(session, sync_data)
                            await apply_titles(session, tab, window, sync_data)
        except Exception as e:
            log(f"Poll error: {e}")


iterm2.run_forever(main)
