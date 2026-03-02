# Route File Format

The GUIDE, SKILL, INTENT, and LEARN statusline rows read from JSON files written by your `UserPromptSubmit` hooks. These are optional — rows show `none` if files don't exist.

## File Locations

Files go in `~/.claude/temp/` with session-specific names:

```
~/.claude/temp/.guidance_route_{SESSION_ID}.json
~/.claude/temp/.skill_route_{SESSION_ID}.json
~/.claude/temp/.intent_route_{SESSION_ID}.json
~/.claude/temp/.learn_route_{SESSION_ID}.json
```

The `SESSION_ID` is available in the hook's JSON input as `.session_id`.

## JSON Formats

### GUIDE row

```json
{
  "timestamp": 1234567890,
  "action": "loaded",
  "matched_file": "debugging.md",
  "trigger": "debug",
  "matched_word": "api_failure"
}
```

`action` values: `"loaded"` (green), `"cooldown"` or `"skipped"` (amber), anything else (gray/none)

### SKILL row

```json
{
  "timestamp": 1234567890,
  "action": "offered",
  "skill": "",
  "category": "code-quality",
  "count": 3
}
```

`action` values: `"loaded"` (green, shows skill name), `"offered"` (blue, shows "N options"), `"declined"` (amber)

### INTENT row

```json
{
  "timestamp": 1234567890,
  "action": "matched",
  "task": "web_search",
  "target": "perplexity-sonar"
}
```

`action` values: `"matched"` (blue, shows "task → target"), `"no_match"` (gray)

### LEARN row

```json
{
  "timestamp": 1234567890,
  "action": "loaded",
  "count": 3,
  "categories": "keyword,tool"
}
```

`action` values: `"loaded"` (green, shows count), `"skipped"` (amber)

## Example Hook Integration

Add this to your `UserPromptSubmit` hook bash script:

```bash
# After reading INPUT=$(cat):
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Write your route decision
if [ -n "$SESSION_ID" ]; then
    ROUTE_FILE="$HOME/.claude/temp/.intent_route_${SESSION_ID}.json"
    printf '{"timestamp":%s,"action":"matched","task":"web_search","target":"sonar"}\n' \
        "$(date +%s)" > "$ROUTE_FILE"
fi
```

## Expiry

Route files persist until overwritten. The statusline always reads the most recent file for each session. There is no automatic expiry — you control what's shown by writing new files on each prompt.
