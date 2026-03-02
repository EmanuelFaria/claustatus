#!/bin/bash
# install.sh — Claude Code Powerline Statusline installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS="$HOME/.claude/scripts"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE="$CLAUDE_SCRIPTS/statusline.sh"

echo "Claude Code Powerline Statusline Installer"
echo "==========================================="
echo ""

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required: brew install jq"
    exit 1
fi

if ! /opt/homebrew/bin/bash --version >/dev/null 2>&1 && ! bash --version | grep -q "5\."; then
    echo "⚠️  Bash 5+ recommended: brew install bash"
    echo "   (Using system bash may work but is untested)"
fi

# Install statusline.sh
echo "Installing statusline.sh..."
mkdir -p "$CLAUDE_SCRIPTS"
cp "$SCRIPT_DIR/statusline.sh" "$STATUSLINE"
chmod +x "$STATUSLINE"
echo "✅ Installed: $STATUSLINE"

# Configure settings.json
if [ -f "$CLAUDE_SETTINGS" ]; then
    if python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS') as f:
    s = json.load(f)
if 'statusLine' not in s:
    s['statusLine'] = {'type': 'command', 'command': '$STATUSLINE'}
    with open('$CLAUDE_SETTINGS', 'w') as f:
        json.dump(s, f, indent=2)
    print('configured')
else:
    print('already_set')
" 2>/dev/null | grep -q "configured"; then
        echo "✅ Configured: $CLAUDE_SETTINGS"
    else
        echo "⚠️  statusLine already set in settings.json — check it points to:"
        echo "   $STATUSLINE"
    fi
else
    python3 -c "
import json
with open('$CLAUDE_SETTINGS', 'w') as f:
    json.dump({'statusLine': {'type': 'command', 'command': '$STATUSLINE'}}, f, indent=2)
"
    echo "✅ Created: $CLAUDE_SETTINGS"
fi

# Test it
echo ""
echo "Testing statusline..."
TEST_OUTPUT=$(echo '{"model":{"display_name":"Test"},"version":"1.0","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":50000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"total_input_tokens":50000,"used_percentage":25,"remaining_percentage":75},"cost":{"total_cost_usd":0.5,"total_api_duration_ms":60000},"session_id":"test-install","transcript_path":""}' | bash "$STATUSLINE" 2>/dev/null | wc -l)

if [ "$TEST_OUTPUT" -gt 5 ]; then
    echo "✅ Statusline renders ($TEST_OUTPUT rows)"
else
    echo "⚠️  Only $TEST_OUTPUT rows rendered — check output above"
fi

echo ""
echo "==========================================="
echo "Done! Restart Claude Code to see the statusline."
echo ""
echo "Optional: Install iTerm2 tab/badge sync:"
echo "  See README.md → 'iTerm2 Tab/Window/Badge Sync'"
echo ""
