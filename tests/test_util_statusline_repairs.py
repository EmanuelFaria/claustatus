#!/usr/bin/env python3
"""Focused regressions for model-aware, session-isolated Powerline output."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path


STATUSLINE = Path(__file__).resolve().parents[1] / "statusline.sh"


def payload(session_id: str, *, window: int, tokens: int) -> dict:
    return {
        "model": {"display_name": "Opus 5"},
        "version": "test",
        "workspace": {"project_dir": "/tmp/powerline-test"},
        "context_window": {
            "context_window_size": window,
            "current_usage": {"input_tokens": tokens},
            "total_input_tokens": tokens,
        },
        "cost": {"total_cost_usd": 0, "total_api_duration_ms": 0},
        "session_id": session_id,
        "transcript_path": "",
    }


def run_statusline(
    tmp_path: Path,
    body: dict,
    *,
    terminal_id: str = "",
) -> subprocess.CompletedProcess[str]:
    (tmp_path / ".claude/temp").mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(tmp_path),
            "POWERLINE_DISABLE_BACKGROUND": "1",
            "POWERLINE_TEST_SECOND": "09",
        }
    )
    if terminal_id:
        env["ITERM_SESSION_ID"] = terminal_id
    else:
        for name in (
            "ITERM_SESSION_ID",
            "TERM_SESSION_ID",
            "TMUX_PANE",
            "WEZTERM_PANE",
        ):
            env.pop(name, None)
    return subprocess.run(
        [str(STATUSLINE)],
        input=json.dumps(body),
        text=True,
        capture_output=True,
        timeout=5,
        env=env,
    )


def plain(output: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", output)


def wait_for(path: Path) -> None:
    deadline = time.monotonic() + 2
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert path.exists()


def test_million_token_window_uses_actual_limit_and_clears_old_warning(
    tmp_path: Path,
) -> None:
    session_id = "million-window"
    sentinel = tmp_path / f".claude/temp/.precompact_needed_{session_id}"
    sentinel.parent.mkdir(parents=True)
    sentinel.write_text("stale warning", encoding="utf-8")

    result = run_statusline(
        tmp_path,
        payload(session_id, window=1_000_000, tokens=410_000),
    )

    assert result.returncode == 0
    assert result.stderr == ""
    assert "/ 1M" in result.stdout
    assert "CONTEXT LOW" not in result.stdout
    assert "PRECOMPACT NOW" not in result.stdout
    assert not sentinel.exists()

    status_path = tmp_path / f".claude/temp/statusline_data_{session_id}.json"
    wait_for(status_path)
    context = json.loads(status_path.read_text(encoding="utf-8"))["context_window"]
    assert context["effective_input_tokens"] == 440_500
    assert context["effective_remaining_tokens"] == 559_500


def test_absolute_reserve_triggers_only_near_real_window_end(tmp_path: Path) -> None:
    result = run_statusline(
        tmp_path,
        payload("near-limit", window=1_000_000, tokens=940_000),
    )

    assert result.returncode == 0
    assert "PRECOMPACT NOW" in result.stdout
    assert result.stderr == ""


def test_overfull_usage_clamps_percentages_and_remaining_tokens(tmp_path: Path) -> None:
    session_id = "overfull"
    result = run_statusline(
        tmp_path,
        payload(session_id, window=200_000, tokens=220_000),
    )

    assert result.returncode == 0
    assert "100% used" in plain(result.stdout)
    assert "0% left" in plain(result.stdout)
    assert "PRECOMPACT NOW" in result.stdout
    status_path = tmp_path / f".claude/temp/statusline_data_{session_id}.json"
    wait_for(status_path)
    context = json.loads(status_path.read_text(encoding="utf-8"))["context_window"]
    assert context["effective_remaining_tokens"] == 0


def test_agent_row_is_exact_session_running_and_not_a_fossil(tmp_path: Path) -> None:
    session_id = "agent-session"
    temp = tmp_path / ".claude/temp"
    temp.mkdir(parents=True)
    (temp / f".agent_activity_{session_id}.json").write_text(
        json.dumps(
            {
                "status": "running",
                "description": "Focused agent task",
                "started": int(time.time()) - 11,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (temp / ".agent_activity.json").write_text(
        json.dumps(
            {
                "status": "running",
                "description": "Other session task",
                "started": int(time.time()) - 20,
            }
        ),
        encoding="utf-8",
    )

    result = run_statusline(
        tmp_path,
        payload(session_id, window=1_000_000, tokens=100_000),
    )

    rendered = plain(result.stdout)
    assert "Focused agent task" in rendered
    assert "Other session task" not in rendered
    assert re.search(r"Focused agent task\s+1[0-9]s", rendered)

    (temp / f".agent_activity_{session_id}.json").write_text(
        json.dumps(
            {
                "status": "running",
                "description": "Ancient task",
                "started": int(time.time()) - 43_201,
            }
        ),
        encoding="utf-8",
    )
    fossil = run_statusline(
        tmp_path,
        payload(session_id, window=1_000_000, tokens=100_000),
    )
    assert "Ancient task" not in plain(fossil.stdout)


def test_terminal_binding_records_only_the_exact_session(tmp_path: Path) -> None:
    terminal_id = "w9t4p0:powerline-test"
    session_id = "11111111-1111-4111-8111-111111111111"

    result = run_statusline(
        tmp_path,
        payload(session_id, window=200_000, tokens=50_000),
        terminal_id=terminal_id,
    )

    assert result.returncode == 0
    key = hashlib.sha256(terminal_id.encode()).hexdigest()[:24]
    binding = tmp_path / f".claude/temp/.session_for_terminal_{key}"
    wait_for(binding)
    assert binding.read_text(encoding="utf-8") == session_id + "\n"


def test_leading_zero_second_has_clean_bounded_multiline_output(tmp_path: Path) -> None:
    result = run_statusline(
        tmp_path,
        payload("clean-render", window=200_000, tokens=50_000),
    )

    assert result.returncode == 0
    assert result.stderr == ""
    assert 8 <= len(result.stdout.splitlines()) <= 24
    rendered = plain(result.stdout)
    for label in ("MODEL", "CTX", "REPO", "ID", "GUIDE", "LEARN"):
        assert label in rendered
