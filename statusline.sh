#!/opt/homebrew/bin/bash
# NOTE: No set -e or set -o pipefail — statusline must ALWAYS exit 0.
# A non-zero exit causes Claude Code to hide the statusline across all sessions.
# Custom Claude Code Status Line (Powerline Style) - SPEED-OPTIMIZED
# Single jq call extracts all fields. Target: <50ms total execution.
#
# Rows: Activity, MODEL, CTX, USAGE, API$, NAME, REPO, CLONE+ID, GUIDE, SKILL, INTENT, LEARN, LIMITS

# ANSI Color codes — basic 16-color only (8-bit breaks Claude Code TUI redraws)
RESET="\033[0m"
BOLD="\033[1m"
FG_BLACK="\033[30m"
FG_WHITE="\033[97m"

# ── Row: Model ───────────────────────────────────────────────────
# NOTE: Variable names are legacy — actual ANSI colors noted in comments
BG_CYAN="\033[45m"          # magenta (45m)
FG_CYAN="\033[35m"
BG_GRAY="\033[44m"          # blue (44m)
FG_GRAY="\033[34m"
BG_GREEN="\033[42m"         # green (42m) — Thinking ON
FG_GREEN="\033[32m"
BG_RED="\033[41m"           # red (41m) — Thinking OFF
FG_RED="\033[31m"

# ── Row: CTX ─────────────────────────────────────────────────────
BG_YELLOW="\033[46m"        # cyan (46m)
FG_YELLOW="\033[36m"
BG_BLUE="\033[44m"          # blue (44m)
FG_BLUE="\033[34m"
BG_CTX_LEFT="\033[42m"      # CTX left%         green
FG_CTX_LEFT="\033[32m"

# ── Rows: Location ───────────────────────────────────────────────
BG_FOREST="\033[42m"        # REPO              green
FG_FOREST="\033[32m"
BG_ORANGE="\033[43m"        # CLONE             amber/yellow  (distinct from REPO green)
FG_ORANGE="\033[33m"

# Powerline arrow (keeping the character — it's the escape codes that break things)
ARROW=""

# Base overhead - system prompts, CLAUDE.md, tools, hooks, etc.
BASE_OVERHEAD=30500

# ========== SINGLE JQ CALL — extract everything at once ==========
INPUT=$(cat)

# Save JSON to temp file for other scripts to read (global + per-session)
echo "$INPUT" > "$HOME/.claude/temp/statusline_data.json" 2>/dev/null &

# One jq call extracts all fields, separated by Unit Separator (0x1F)
# CRITICAL: Tab (\t) cannot be used — bash read treats consecutive tabs as one
# delimiter, losing empty fields and shifting all subsequent values.
IFS=$'\x1f' read -r MODEL CC_VERSION PROJECT_DIR CONTEXT_SIZE \
     INPUT_TOKENS CACHE_CREATE CACHE_READ TOTAL_INPUT \
     _CC_PERCENT_USED _CC_PERCENT_LEFT \
     _SES_TOTAL_OUTPUT SES_COST _SES_DURATION_MS \
     SESSION_ID TRANSCRIPT_PATH \
<<< "$(echo "$INPUT" | jq -r '[
    (.model.display_name // "Unknown"),
    (.version // ""),
    (.workspace.project_dir // ""),
    (.context_window.context_window_size // 0),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.total_input_tokens // 0),
    (.context_window.used_percentage // 0),
    (.context_window.remaining_percentage // 0),
    (.context_window.total_output_tokens // 0),
    (.cost.total_cost_usd // 0),
    (.cost.total_api_duration_ms // 0),
    (.session_id // ""),
    (.transcript_path // "")
] | map(tostring) | join("\u001f")')"

# Per-session data file — written AFTER percentage computation (see below, line ~140)
# so that overhead-aware PERCENT_REMAINING is included for the watcher daemon.

# ========== COMPUTED VALUES (pure bash, no subprocesses) ==========

# Repo name from project dir
if [ -n "$PROJECT_DIR" ]; then
    REPO_NAME="${PROJECT_DIR##*/}"
else
    REPO_NAME="--"
fi

# Git remote repo name — use 30-second cache to avoid slow git calls
GITHUB_REPO_NAME="$REPO_NAME"
if [ -n "$PROJECT_DIR" ]; then
    GLOBAL_GIT_CACHE="/tmp/statusline-git-${PROJECT_DIR//\//_}"
    CACHE_AGE=999
    [ -f "$GLOBAL_GIT_CACHE" ] && CACHE_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$GLOBAL_GIT_CACHE" 2>/dev/null || echo 0) ))
    if [ "$CACHE_AGE" -lt 30 ]; then
        GITHUB_REPO_NAME=$(cat "$GLOBAL_GIT_CACHE")
    else
        ORIGIN_URL=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || echo "")
        if [ -n "$ORIGIN_URL" ]; then
            GITHUB_REPO_NAME="${ORIGIN_URL##*/}"
            GITHUB_REPO_NAME="${GITHUB_REPO_NAME%.git}"
        fi
        echo "$GITHUB_REPO_NAME" > "$GLOBAL_GIT_CACHE" 2>/dev/null
    fi
fi

# Token math
RAW_TOKENS=0
if [ "${INPUT_TOKENS:-0}" != "0" ] || [ "${CACHE_CREATE:-0}" != "0" ] || [ "${CACHE_READ:-0}" != "0" ]; then
    RAW_TOKENS=$(( ${INPUT_TOKENS:-0} + ${CACHE_CREATE:-0} + ${CACHE_READ:-0} ))
fi
if [ "$RAW_TOKENS" -eq 0 ] && [ "${TOTAL_INPUT:-0}" != "0" ]; then
    RAW_TOKENS=${TOTAL_INPUT:-0}
fi
TOTAL_TOKENS=$((RAW_TOKENS + BASE_OVERHEAD))

# Format tokens with commas
TOKENS_DISPLAY=$(printf "%'d" "$TOTAL_TOKENS" 2>/dev/null || echo "$TOTAL_TOKENS")

# Context percentage
CONTEXT_SIZE=${CONTEXT_SIZE:-0}
if [ "$CONTEXT_SIZE" -le 0 ] 2>/dev/null; then
    if [[ "$MODEL" == *"1M"* ]]; then
        CONTEXT_SIZE=1000000
    else
        CONTEXT_SIZE=200000
    fi
fi
if [ "$CONTEXT_SIZE" -gt 0 ] && [ "$TOTAL_TOKENS" -gt 0 ]; then
    PERCENT=$((TOTAL_TOKENS * 100 / CONTEXT_SIZE))
else
    PERCENT=0
fi
PERCENT_REMAINING=$((100 - PERCENT))

# Per-session data file: augment Claude Code's JSON with overhead-aware percentages.
# The watcher daemon and hooks read this file — they need the computed values, not raw CC%.
if [[ -n "$SESSION_ID" ]]; then
    echo "$INPUT" | jq -c --argjson pct_used "$PERCENT" --argjson pct_left "$PERCENT_REMAINING" \
        '.context_window.used_percentage = $pct_used | .context_window.remaining_percentage = $pct_left' \
        > "$HOME/.claude/temp/statusline_data_${SESSION_ID}.json" 2>/dev/null &
fi

# Session tokens and cost (SES_COST is float — use printf, not arithmetic)
# Strip non-numeric suffixes from SES_COST in case of malformed input
SES_COST="${SES_COST:-0}"
SES_COST="${SES_COST%%[^0-9.e+-]*}"
SES_COST_DISPLAY=$(printf '$%.2f' "$SES_COST" 2>/dev/null || echo '$0.00')



# ── Cost tracking: monthly (API$) + weekly (USAGE) — delta computed once ────────
# Both accumulate the same per-session delta; SES_LAST_FILE is updated after both.
# Monthly file: YYYY-MM  |  Weekly file: YYYY-Www (ISO week)
MONTHLY_COST_FILE="$HOME/.claude/temp/.monthly_cost_$(date +%Y-%m)"
WEEKLY_COST_FILE="$HOME/.claude/temp/.weekly_cost_$(date +%Y-W%V)"
SES_LAST_FILE="$HOME/.claude/temp/.ses_last_${SESSION_ID}"
MONTHLY_MONTH=$(date +"%-m/%Y")
MONTHLY_COST_DISPLAY='$0.00'
WEEKLY_COST_DISPLAY='WK 0%'
WEEKLY_BUDGET_USD="${WEEKLY_BUDGET_USD:-100}"   # override: export WEEKLY_BUDGET_USD=50
BG_MTHS="\033[48;5;30m";  FG_MTHS="\033[38;5;30m"   # teal default (API$ row)
BG_USAGE="\033[48;5;25m"; FG_USAGE="\033[38;5;25m"  # blue default (USAGE row)

if [ -n "$SESSION_ID" ]; then
    read -r MONTHLY_TOTAL WEEKLY_TOTAL <<< "$(awk \
        -v cur="${SES_COST:-0}" \
        -v lf="$SES_LAST_FILE" \
        -v mf="$MONTHLY_COST_FILE" \
        -v wf="$WEEKLY_COST_FILE" \
    'BEGIN {
        last = 0; had_last = 0
        if ((getline l < lf) > 0) { last = l + 0; had_last = 1 }; close(lf)
        delta = cur - last; if (delta < 0) delta = 0
        # Phantom delta guard: missing last file means entire session cost becomes
        # a false delta on resume. Ignore large deltas when no last file existed.
        if (!had_last && delta > 5) delta = 0
        mtotal = 0
        if ((getline t < mf) > 0) mtotal = t + 0; close(mf)
        mtotal += delta
        wtotal = 0
        if ((getline t < wf) > 0) wtotal = t + 0; close(wf)
        wtotal += delta
        if (cur   > 0) { printf "%.4f\n", cur    > lf; close(lf) }
        if (delta > 0) { printf "%.4f\n", mtotal > mf; close(mf)
                         printf "%.4f\n", wtotal > wf; close(wf) }
        printf "%.4f %.4f", mtotal, wtotal
    }' /dev/null 2>/dev/null)"

    MONTHLY_COST_DISPLAY=$(printf '$%.2f' "${MONTHLY_TOTAL:-0}" 2>/dev/null || echo '$0.00')

    # Weekly percentage of configurable budget
    WK_PCT=$(awk -v w="${WEEKLY_TOTAL:-0}" -v b="${WEEKLY_BUDGET_USD:-100}" \
        'BEGIN { pct = (b > 0) ? int(w * 100 / b + 0.5) : 0; if (pct > 999) pct = 999; print pct }')
    WEEKLY_COST_DISPLAY="WK ${WK_PCT}%"

    # Color: API$ (monthly absolute $)
    MC_INT=$(printf '%.0f' "${MONTHLY_TOTAL:-0}" 2>/dev/null || echo 0)
    if   [ "${MC_INT:-0}" -ge 50 ] 2>/dev/null; then
        BG_MTHS="\033[48;5;196m"; FG_MTHS="\033[38;5;196m"   # red  ≥$50
    elif [ "${MC_INT:-0}" -ge 10 ] 2>/dev/null; then
        BG_MTHS="\033[48;5;130m"; FG_MTHS="\033[38;5;130m"   # orange ≥$10
    fi

    # Color: USAGE (weekly %)
    if   [ "${WK_PCT:-0}" -ge 90 ] 2>/dev/null; then
        BG_USAGE="\033[48;5;196m"; FG_USAGE="\033[38;5;196m"  # red   ≥90%
    elif [ "${WK_PCT:-0}" -ge 75 ] 2>/dev/null; then
        BG_USAGE="\033[48;5;130m"; FG_USAGE="\033[38;5;130m"  # orange ≥75%
    elif [ "${WK_PCT:-0}" -ge 50 ] 2>/dev/null; then
        BG_USAGE="\033[48;5;136m"; FG_USAGE="\033[38;5;136m"  # yellow ≥50%
    fi
fi
# Thinking status — read settings once with single jq call
SETTINGS="$HOME/.claude/settings.json"
read -r ALWAYS_THINKING THINKING_SETTING <<< "$(jq -r '[(.alwaysThinkingEnabled // false), (.thinking // "null")] | @tsv' "$SETTINGS" 2>/dev/null || echo "false null")"

if [ "$THINKING_SETTING" = "disabled" ] || [ "$THINKING_SETTING" = "false" ]; then
    THINK="🧠 OFF"; THINK_BG="$BG_RED"; THINK_FG_NEXT="$FG_RED"
elif [ "$ALWAYS_THINKING" = "true" ] || [ "$THINKING_SETTING" = "high" ] || [ "$THINKING_SETTING" = "medium" ] || [ "$THINKING_SETTING" = "low" ]; then
    THINK="🧠 ON"; THINK_BG="$BG_GREEN"; THINK_FG_NEXT="$FG_GREEN"
elif [[ "$MODEL" == *"Opus"* ]]; then
    THINK="🧠 ON"; THINK_BG="$BG_GREEN"; THINK_FG_NEXT="$FG_GREEN"
else
    THINK="🧠 OFF"; THINK_BG="$BG_RED"; THINK_FG_NEXT="$FG_RED"
fi

# Session name — always read from transcript so /rename is reflected immediately
# Cache is only used as fallback when transcript is unavailable
SESSION_NAME=""
SESSION_NAME_CACHE="/tmp/statusline-sessname-${SESSION_ID}"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    SESSION_NAME=$(grep '^{"type":"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null || true)
    SESSION_NAME="${SESSION_NAME% (Fork)}"
    # Update cache for iTerm2 sync script to read
    [ -n "$SESSION_NAME" ] && echo "$SESSION_NAME" > "$SESSION_NAME_CACHE" 2>/dev/null
elif [ -f "$SESSION_NAME_CACHE" ]; then
    SESSION_NAME=$(cat "$SESSION_NAME_CACHE")
fi

# Activity state — quick read, no subprocess
ACTIVITY_ICON="✓"
ACTIVITY_DETAIL="Ready for input"
ACTIVITY_BG="\033[48;5;248m"
ACTIVITY_FG="\033[38;5;248m"
ACTIVITY_FILE="$HOME/.claude/temp/.current_activity.json"
if [ -f "$ACTIVITY_FILE" ]; then
    ACTIVITY_JSON=$(<"$ACTIVITY_FILE")
    if [ -n "$ACTIVITY_JSON" ]; then
        read -r A_STATUS A_TOOL A_DETAIL A_TS <<< "$(echo "$ACTIVITY_JSON" | jq -r '[(.status // "unknown"), (.tool // ""), (.detail // ""), (.timestamp // 0)] | @tsv' 2>/dev/null || echo "unknown   0")"
        NOW=$(date +%s)
        A_TS="${A_TS:-0}"; A_TS="${A_TS%.*}"
        AGE=$((NOW - ${A_TS:-0}))
        if [ "$AGE" -lt 30 ]; then
            case "$A_STATUS" in
                "running_tool")
                    ACTIVITY_ICON="⚙️"; ACTIVITY_DETAIL="${A_TOOL}: ${A_DETAIL:0:50}"
                    ACTIVITY_BG="\033[48;5;214m"; ACTIVITY_FG="\033[38;5;214m" ;;
                "processing")
                    ACTIVITY_ICON="💭"; ACTIVITY_DETAIL="Processing..."
                    ACTIVITY_BG="\033[48;5;33m"; ACTIVITY_FG="\033[38;5;33m" ;;
                "waiting_for_approval")
                    ACTIVITY_ICON="⏳"; ACTIVITY_DETAIL="Awaiting permission"
                    ACTIVITY_BG="\033[48;5;226m"; ACTIVITY_FG="\033[38;5;226m" ;;
            esac
        fi
    fi
fi

# ========== FAST JSON PARSER — no jq for route files ==========
# Extract a JSON string value using bash builtins only (~0ms vs ~15ms per jq call)
json_val() { local k="\"$1\""; local s="${2#*$k:}"; s="${s#*\"}"; echo "${s%%\"*}"; }
json_num() { local k="\"$1\""; local s="${2#*$k:}"; echo "${s%%[!0-9]*}"; }

# ========== ROW PRINTER — wraps content at 42 chars (matches MODEL row width) ==========
# Usage: print_row BG_VAR FG_VAR "LABEL" "content"
# If content > 42 chars: wraps at last word boundary before 42, continuation on next line
MAX_ROW_CONTENT=34
print_row() {
    local bg="$1" fg="$2" label="$3" content="$4"
    local label_width=$(( ${#label} + 2 ))   # label + spaces
    if [ "${#content}" -le "$MAX_ROW_CONTENT" ]; then
        printf "${bg}${FG_WHITE}${BOLD} %s ${RESET}${bg}${FG_WHITE}%s ${RESET}${fg}${ARROW}${RESET}\n" \
            "$label" "$content"
    else
        # Find last space at or before MAX_ROW_CONTENT
        local line1="${content:0:$MAX_ROW_CONTENT}"
        local break_at=$MAX_ROW_CONTENT
        # Walk back to find last space
        while [ "$break_at" -gt 10 ] && [ "${line1:$((break_at-1)):1}" != " " ]; do
            break_at=$((break_at - 1))
        done
        local part1="${content:0:$break_at}"
        local part2="${content:$break_at}"
        part1="${part1%" "}"; part2="${part2# }"  # trim boundary spaces
        printf "${bg}${FG_WHITE}${BOLD} %s ${RESET}${bg}${FG_WHITE}%s ${RESET}${fg}${ARROW}${RESET}\n" \
            "$label" "$part1"
        printf "${bg}${FG_WHITE} %s ${RESET}${fg}${ARROW}${RESET}\n" \
            "$part2"
    fi
}

# ── Width-aware layout ─────────────────────────────────────────────────────────
# AVAIL_W = terminal width minus space reserved for Claude Code's right-side messages.
# Override: export CC_RIGHT_RESERVE=55  (default 42)
: "${COLUMNS:=120}"
: "${CC_RIGHT_RESERVE:=42}"
AVAIL_W=$(( COLUMNS - CC_RIGHT_RESERVE ))
(( AVAIL_W < 50 )) && AVAIL_W=50

# flex_segments: renders a powerline row from named segments.
# Args in groups of 4: BG_ESC  FG_ESC  LABEL  CONTENT
#   LABEL   — bold label text; empty string uses "·" when stacked
#   CONTENT — plain text (no ANSI); used to measure width
# Single-line when total visible width ≤ AVAIL_W; stacks to separate rows otherwise.
flex_segments() {
    local -a a=("$@")
    local n=$(( ${#a[@]} / 4 ))
    # Estimate total visible width
    local w=1
    for (( i=0; i<n; i++ )); do
        local lbl="${a[$((i*4+2))]}" con="${a[$((i*4+3))]}"
        [[ -n "$lbl" ]] && w=$(( w + ${#lbl} + ${#con} + 5 )) \
                        || w=$(( w + ${#con} + 3 ))
    done
    if (( w <= AVAIL_W )); then
        # ── Single-line powerline ──────────────────────────────────────────────
        local prev_fg=""
        for (( i=0; i<n; i++ )); do
            local bg="${a[$((i*4))]}" fg="${a[$((i*4+1))]}"
            local lbl="${a[$((i*4+2))]}" con="${a[$((i*4+3))]}"
            (( i > 0 )) && printf "%b%b%b" "$bg" "$prev_fg" "$ARROW"
            if [[ -n "$lbl" ]]; then
                printf "%b%b%b %s %b%b" "$bg" "$FG_WHITE" "$BOLD" "$lbl" "$RESET" "$bg"
                printf "%b%s %b" "$FG_WHITE" "$con" "$RESET"
            else
                printf "%b %s %b" "$FG_WHITE" "$con" "$RESET"
            fi
            prev_fg="$fg"
        done
        printf "%b%b%b\n" "$prev_fg" "$ARROW" "$RESET"
    else
        # ── Stacked: one print_row per segment ────────────────────────────────
        for (( i=0; i<n; i++ )); do
            local bg="${a[$((i*4))]}" fg="${a[$((i*4+1))]}"
            local lbl="${a[$((i*4+2))]}" con="${a[$((i*4+3))]}"
            print_row "$bg" "$fg" "${lbl:-·}" "$con"
        done
    fi
}

# Pre-read route files (pure bash, no subprocesses)
GUIDE_TEXT="none"; SKILL_TEXT="none"; INTENT_TEXT="none"; LEARN_TEXT="none"
BG_GUIDE_R="\033[48;5;240m"; FG_GUIDE_R="\033[38;5;240m"
BG_SKILL_R="\033[48;5;240m"; FG_SKILL_R="\033[38;5;240m"
BG_INTENT_R="\033[48;5;240m"; FG_INTENT_R="\033[38;5;240m"
BG_LEARN_R="\033[48;5;240m"; FG_LEARN_R="\033[38;5;240m"

# Session-specific route files with global fallback
GF="$HOME/.claude/temp/.guidance_route_${SESSION_ID}.json"
[ -f "$GF" ] || GF="$HOME/.claude/temp/.guidance_route.json"
if [ -f "$GF" ]; then
    GJ=$(<"$GF")
    GA=$(json_val action "$GJ")
    case "$GA" in
        loaded) BG_GUIDE_R="\033[48;5;28m"; FG_GUIDE_R="\033[38;5;28m"
            GM=$(json_val matched_file "$GJ"); GW=$(json_val matched_word "$GJ")
            [ -n "$GW" ] && [ "$GW" != "null" ] && GUIDE_TEXT="$GM ('$GW')" || GUIDE_TEXT="$GM" ;;
        cooldown|skipped) BG_GUIDE_R="\033[48;5;136m"; FG_GUIDE_R="\033[38;5;136m"; GUIDE_TEXT="cooldown" ;;
    esac
fi

SF="$HOME/.claude/temp/.skill_route_${SESSION_ID}.json"
[ -f "$SF" ] || SF="$HOME/.claude/temp/.skill_route.json"
if [ -f "$SF" ]; then
    SJ=$(<"$SF")
    SA=$(json_val action "$SJ")
    case "$SA" in
        loaded) BG_SKILL_R="\033[48;5;28m"; FG_SKILL_R="\033[38;5;28m"; SKILL_TEXT=$(json_val skill "$SJ") ;;
        offered) BG_SKILL_R="\033[48;5;24m"; FG_SKILL_R="\033[38;5;24m"
            SC=$(json_num count "$SJ")
            SSKILLS=$(json_val skills "$SJ")
            SCAT=$(json_val category "$SJ")
            if [ -n "$SSKILLS" ] && [ "$SSKILLS" != "null" ]; then
                # Show first 2 skill names + overflow count
                SKILL_TEXT="${SSKILLS}"
                [ "${SC:-0}" -gt 2 ] && SKILL_TEXT="${SSKILLS} +$((SC-2))"
            elif [ -n "$SCAT" ]; then
                SKILL_TEXT="${SCAT} (${SC:-0})"
            else
                SKILL_TEXT="${SC:-0} options"
            fi ;;
        declined) BG_SKILL_R="\033[48;5;136m"; FG_SKILL_R="\033[38;5;136m"; SKILL_TEXT="declined" ;;
    esac
fi

NF="$HOME/.claude/temp/.intent_route_${SESSION_ID}.json"
[ -f "$NF" ] || NF="$HOME/.claude/temp/.intent_route.json"
if [ -f "$NF" ]; then
    NJ=$(<"$NF")
    NA=$(json_val action "$NJ")
    case "$NA" in
        matched) BG_INTENT_R="\033[48;5;24m"; FG_INTENT_R="\033[38;5;24m"
            NT=$(json_val task "$NJ"); NTG=$(json_val target "$NJ")
            INTENT_TEXT="$NT → $NTG" ;;
        no_match) ;; # defaults already set
    esac
fi

LF="$HOME/.claude/temp/.learn_route_${SESSION_ID}.json"
[ -f "$LF" ] || LF="$HOME/.claude/temp/.learn_route.json"
if [ -f "$LF" ]; then
    LJ=$(<"$LF")
    LA=$(json_val action "$LJ")
    case "$LA" in
        loaded) BG_LEARN_R="\033[48;5;28m"; FG_LEARN_R="\033[38;5;28m"
            LC=$(json_num count "$LJ")
            LT=$(json_val title "$LJ")
            if [ -n "$LT" ] && [ "$LT" != "null" ]; then
                # Show learning title snippet (truncate if >45 chars)
                [ "${#LT}" -gt 45 ] && LT="${LT:0:42}..."
                [ "${LC:-0}" -gt 1 ] && LEARN_TEXT="\"$LT\" +$((LC-1))" || LEARN_TEXT="\"$LT\""
            else
                [ "${LC:-0}" = "1" ] && LEARN_TEXT="surfaced 1 past learning" || LEARN_TEXT="surfaced ${LC:-0} past learnings"
            fi ;;
        skipped) BG_LEARN_R="\033[48;5;136m"; FG_LEARN_R="\033[38;5;136m"; LEARN_TEXT="skipped" ;;
    esac
fi

# ── API rate limits (from background-refreshed cache) ─────────────────────────
# Background subshell below fetches headers from api.anthropic.com every 10 min.
# Requires ANTHROPIC_API_KEY in env, or stored in Keychain as "anthropic_api_key".
LIMITS_TEXT="none"
BG_LIMITS_R="\033[48;5;240m"; FG_LIMITS_R="\033[38;5;240m"
API_LIMITS_FILE="$HOME/.claude/temp/.api_limits.json"

if [ -f "$API_LIMITS_FILE" ]; then
    LIMITS_CACHE_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$API_LIMITS_FILE" 2>/dev/null || echo 0) ))
    if [ "$LIMITS_CACHE_AGE" -lt 1200 ]; then   # show if cache <20 min old
        LMJ=$(<"$API_LIMITS_FILE")
        LR_REM=$(json_num req_remaining "$LMJ")
        LR_LIM=$(json_num req_limit "$LMJ")
        LT_REM=$(json_num tok_remaining "$LMJ")
        LT_LIM=$(json_num tok_limit "$LMJ")
        if [ -n "$LR_LIM" ] && [ "${LR_LIM:-0}" -gt 0 ] 2>/dev/null; then
            LT_REM_K=$(( ${LT_REM:-0} / 1000 ))
            LT_LIM_K=$(( ${LT_LIM:-0} / 1000 ))
            LIMITS_TEXT="${LR_REM}/${LR_LIM} req  ${LT_REM_K}K/${LT_LIM_K}K tok/min"
            LIMITS_REQ_TEXT="${LR_REM}/${LR_LIM} req"
            LIMITS_TOK_TEXT="${LT_REM_K}K/${LT_LIM_K}K tok/min"
            LR_PCT=$(( ${LR_REM:-0} * 100 / ${LR_LIM:-1} ))
            if [ "${LR_PCT:-100}" -le 10 ] 2>/dev/null; then
                BG_LIMITS_R="\033[48;5;196m"; FG_LIMITS_R="\033[38;5;196m"   # red
            elif [ "${LR_PCT:-100}" -le 30 ] 2>/dev/null; then
                BG_LIMITS_R="\033[48;5;136m"; FG_LIMITS_R="\033[38;5;136m"   # amber
            else
                BG_LIMITS_R="\033[48;5;28m"; FG_LIMITS_R="\033[38;5;28m"     # green
            fi
        fi
    fi
fi

# ── Rolling usage caps (5h/7d, from background-refreshed cache) ────────────────
# Background subshell below fetches from /api/oauth/usage every ~60 min.
# Same API key as LIMITS. Shows actual Anthropic throttle percentages (Max plan).
CAP_TEXT="none"
BG_CAP_R="\033[48;5;240m"; FG_CAP_R="\033[38;5;240m"
USAGE_CAPS_FILE="$HOME/.claude/temp/.usage_caps.json"

if [ -f "$USAGE_CAPS_FILE" ]; then
    CAP_CACHE_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$USAGE_CAPS_FILE" 2>/dev/null || echo 0) ))
    if [ "$CAP_CACHE_AGE" -lt 7200 ]; then   # show if cache <2h old
        CAPJ=$(<"$USAGE_CAPS_FILE")
        CAP_5H=$(json_num five_hour "$CAPJ")
        CAP_7D=$(json_num seven_day "$CAPJ")
        if [ "${CAP_5H:-0}" -gt 0 ] 2>/dev/null || [ "${CAP_7D:-0}" -gt 0 ] 2>/dev/null; then
            CAP_TEXT="DY ${CAP_5H:-0}%  WK ${CAP_7D:-0}%"
            # Color by whichever window is more consumed
            CAP_MAX=$(( ${CAP_5H:-0} > ${CAP_7D:-0} ? ${CAP_5H:-0} : ${CAP_7D:-0} ))
            if [ "${CAP_MAX:-0}" -gt 75 ] 2>/dev/null; then
                BG_CAP_R="\033[48;5;196m"; FG_CAP_R="\033[38;5;196m"   # red
            elif [ "${CAP_MAX:-0}" -gt 50 ] 2>/dev/null; then
                BG_CAP_R="\033[48;5;136m"; FG_CAP_R="\033[38;5;136m"   # amber
            else
                BG_CAP_R="\033[48;5;28m"; FG_CAP_R="\033[38;5;28m"     # green
            fi
        fi
    fi
fi

# ========== PARENT TTY (needed for iTerm2 fireworks + badge, resolved once) ==========
PARENT_TTY="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"

# ========== OUTPUT — all 12 rows, all printf ==========

# Row 0: PRECOMPACT alerts (conditional, double-height)
# Priority: PASTE PRECOMPACT (flag exists) > PRECOMPACT NOW (≤15% remaining)
# Animation: swap two rows on alternating seconds — creates visible flash effect
# Per-session flags prevent multi-session cross-contamination
PRECOMPACT_READY_FILE_GLOBAL="$HOME/.claude/temp/.precompact_ready"
PRECOMPACT_READY_FILE_SESSION="$HOME/.claude/temp/.precompact_ready_${SESSION_ID}"
PRECOMPACT_RUNNING_FILE="$HOME/.claude/temp/.precompact_running"
PRECOMPACT_RUNNING_FILE_SESSION="$HOME/.claude/temp/.precompact_running_${SESSION_ID}"
PRECOMPACT_ALERTED_FILE="$HOME/.claude/temp/.precompact_alerted_${SESSION_ID}"
PRECOMPACT_READY=false

# Check if precompact output is ready to paste (5-min expiry)
# Per-session file only — global file causes cross-session contamination
_READY_FILE=""
if [ -n "$SESSION_ID" ] && [ -f "$PRECOMPACT_READY_FILE_SESSION" ]; then
    _READY_FILE="$PRECOMPACT_READY_FILE_SESSION"
elif [ -z "$SESSION_ID" ] && [ -f "$PRECOMPACT_READY_FILE_GLOBAL" ]; then
    _READY_FILE="$PRECOMPACT_READY_FILE_GLOBAL"
fi
if [ -n "$_READY_FILE" ]; then
    READY_MTIME=$(/usr/bin/stat -f %m "$_READY_FILE" 2>/dev/null || echo 0)
    READY_AGE=$(( $(date +%s) - READY_MTIME ))
    if [ "$READY_AGE" -lt 300 ]; then
        PRECOMPACT_READY=true
    else
        rm -f "$_READY_FILE"
    fi
fi

# Check if precompact is currently running (suppress PRECOMPACT NOW while running)
PRECOMPACT_RUNNING=false
_RUN_FILE=""
if [ -n "$SESSION_ID" ] && [ -f "$PRECOMPACT_RUNNING_FILE_SESSION" ]; then
    _RUN_FILE="$PRECOMPACT_RUNNING_FILE_SESSION"
elif [ -z "$SESSION_ID" ] && [ -f "$PRECOMPACT_RUNNING_FILE" ]; then
    _RUN_FILE="$PRECOMPACT_RUNNING_FILE"
fi
if [ -n "$_RUN_FILE" ]; then
    RUN_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$_RUN_FILE" 2>/dev/null || echo 0) ))
    [ "$RUN_AGE" -lt 120 ] && PRECOMPACT_RUNNING=true || rm -f "$_RUN_FILE"
fi

# Claude Code TUI strips \033[5m (blink) before rendering.
# Workaround: swap the two rows on alternating seconds — each re-render flips the
# color bands, creating a visible "flash" effect tied to the clock.
BLINK_STATE=$(( $(date +%S) % 2 ))

if [ "$PRECOMPACT_READY" = true ]; then
    # PASTE PRECOMPACT NOW — two rows, bright/dark green swap positions each render
    # Clear sentinels — output is ready, no need to keep warning or re-trigger alerts
    rm -f "$PRECOMPACT_ALERTED_FILE" 2>/dev/null
    [ -n "${SESSION_ID:-}" ] && rm -f "$HOME/.claude/temp/.precompact_needed_${SESSION_ID}" 2>/dev/null
    if [ "$BLINK_STATE" -eq 0 ]; then
        printf "\033[42m\033[97m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
        printf "\033[48;5;22m\033[92m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
    else
        printf "\033[48;5;22m\033[92m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
        printf "\033[42m\033[97m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
    fi
elif [ "$PRECOMPACT_RUNNING" = false ] && [ "${PERCENT_REMAINING:-100}" -le 20 ] 2>/dev/null && [ "${PERCENT_REMAINING:-100}" -gt 0 ] 2>/dev/null; then
    # Two-tier alert (per statusline_architecture.md):
    #   ≤20%: write sentinel (AI sees "wrap up" via PostToolUse hook) + visual banner
    #   ≤15%: full alert — sound, fireworks, Pushover (via watcher daemon)
    # Uses PERCENT_REMAINING (overhead-aware), NOT _CC_PERCENT_LEFT (Claude Code's raw %).

    # Sentinel file: written at ≤20% so PostToolUse hook injects "wrap up" into AI conversation
    if [ -n "$SESSION_ID" ]; then
        SENTINEL_FILE="$HOME/.claude/temp/.precompact_needed_${SESSION_ID}"
        if [ ! -f "$SENTINEL_FILE" ] || [ $(( $(date +%s) - $(/usr/bin/stat -f %m "$SENTINEL_FILE" 2>/dev/null || echo 0) )) -gt 120 ]; then
            ITERM_WIN="window ?"
            if [ -n "${ITERM_SESSION_ID:-}" ]; then
                _W_PART="${ITERM_SESSION_ID%%t*}"
                _W_NUM="${_W_PART#w}"
                ITERM_WIN="window $(( _W_NUM + 1 ))" 2>/dev/null || true
            fi
            printf '%s' "${PERCENT_REMAINING}% context left in ${ITERM_WIN} (${SESSION_NAME:-${REPO_NAME:-session}})" > "$SENTINEL_FILE" 2>/dev/null
        fi
    fi

    if [ "${PERCENT_REMAINING:-100}" -le 15 ] 2>/dev/null; then
        # ≤15%: PRECOMPACT NOW — full alert with sound, fireworks, flashing banner
        if [ "$BLINK_STATE" -eq 0 ]; then
            printf "\033[41m\033[93m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
            printf "\033[43m\033[31m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
        else
            printf "\033[43m\033[31m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
            printf "\033[41m\033[93m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
        fi
        # One-shot urgent sound + fireworks
        if [ ! -f "$PRECOMPACT_ALERTED_FILE" ]; then
            touch "$PRECOMPACT_ALERTED_FILE"
            [ -c "$PARENT_TTY" ] && printf '\e]1337;RequestAttention=fireworks\a' > "$PARENT_TTY"
            afplay /System/Library/Sounds/Sosumi.aiff 2>/dev/null &
        fi
    else
        # 16-20%: soft visual warning — amber banner, no sound
        if [ "$BLINK_STATE" -eq 0 ]; then
            printf "\033[43m\033[30m\033[1m ⚠️  CONTEXT LOW — WRAP UP  ⚠️ \033[0m\n"
        else
            printf "\033[48;5;136m\033[97m\033[1m ⚠️  CONTEXT LOW — WRAP UP  ⚠️ \033[0m\n"
        fi
    fi
else
    # Context is healthy — clear the alert sentinel so it re-fires if threshold crossed again
    rm -f "$PRECOMPACT_ALERTED_FILE" 2>/dev/null
fi

# Row 1: Activity
printf "${ACTIVITY_BG}${FG_BLACK}${BOLD} %s %s ${RESET}${ACTIVITY_FG}${ARROW}${RESET}\n" "$ACTIVITY_ICON" "$ACTIVITY_DETAIL"

# Row 2: MODEL | Version | Thinking  (stacks when narrow)
flex_segments \
    "$BG_CYAN"   "$FG_CYAN"       "MODEL" "$MODEL" \
    "$BG_GRAY"   "$FG_GRAY"       ""      "v$CC_VERSION" \
    "$THINK_BG"  "$THINK_FG_NEXT" ""      "$THINK"

# Row 2.5: AGENT — only shown when an agent/task is actively running
AF="$HOME/.claude/temp/.agent_activity_${SESSION_ID}.json"
[ -f "$AF" ] || AF="$HOME/.claude/temp/.agent_activity.json"
if [ -f "$AF" ]; then
    AJ=$(<"$AF")
    AGENT_DESC=$(json_val description "$AJ")
    AGENT_STARTED=$(json_num started "$AJ")
    AGENT_ELAPSED=$(( $(date +%s) - ${AGENT_STARTED:-0} ))
    AGENT_MINS=$((AGENT_ELAPSED / 60)); AGENT_SECS=$((AGENT_ELAPSED % 60))
    [ "$AGENT_MINS" -gt 0 ] && AGENT_TIME="${AGENT_MINS}m ${AGENT_SECS}s" || AGENT_TIME="${AGENT_SECS}s"
    print_row "\033[48;5;208m" "\033[38;5;208m" "AGENT" "${AGENT_DESC}  ${AGENT_TIME}"
fi

# Row 3: CTX  (stacks when narrow)
flex_segments \
    "$BG_YELLOW"    "$FG_YELLOW"    "CTX" "$TOKENS_DISPLAY" \
    "$BG_BLUE"      "$FG_BLUE"      ""    "${PERCENT}% used" \
    "$BG_CTX_LEFT"  "$FG_CTX_LEFT"  ""    "${PERCENT_REMAINING}% left"

# Row 4: CAP | REPO  (CAP = rolling usage caps, REPO = git remote name)
if [ "$CAP_TEXT" != "none" ]; then
    flex_segments \
        "$BG_CAP_R"   "$FG_CAP_R"   "CAP"  "$CAP_TEXT" \
        "$BG_FOREST"  "$FG_FOREST"  "REPO" "$GITHUB_REPO_NAME"
else
    print_row "$BG_FOREST" "$FG_FOREST" "REPO" "$GITHUB_REPO_NAME"
fi

# Row 5: NAME (own line — only shown when session has a name)
BG_NAME="\033[48;5;25m"; FG_NAME="\033[38;5;25m"
[ -n "$SESSION_NAME" ] && print_row "$BG_NAME" "$FG_NAME" "NAME" "$SESSION_NAME"

# Row 7: CLONE (own line)
# Row 8: ID (own line — UUID is long, splitting prevents truncation on narrow terminals)
BG_LB="\033[48;5;237m"; FG_LB="\033[38;5;244m"
printf "${BG_ORANGE}${FG_BLACK}${BOLD} CLONE ${RESET}${BG_ORANGE}${FG_BLACK} %s ${RESET}${FG_ORANGE}${ARROW}${RESET}\n" "$REPO_NAME"
printf "${BG_LB}${FG_LB}${BOLD} ID ${RESET}${BG_LB}${FG_LB} %s ${RESET}${FG_LB}${ARROW}${RESET}\n" "$SESSION_ID"

# Row 9: GUIDE
print_row "$BG_GUIDE_R" "$FG_GUIDE_R" "GUIDE" "$GUIDE_TEXT"

# Row 10: SKILL — only shown when a skill was loaded, offered, or declined (hidden when "none")
[ "$SKILL_TEXT" != "none" ] && print_row "$BG_SKILL_R" "$FG_SKILL_R" "SKILL" "$SKILL_TEXT"

# Row 11: INTENT — only shown when a capability was actually routed (hidden when "none")
[ "$INTENT_TEXT" != "none" ] && print_row "$BG_INTENT_R" "$FG_INTENT_R" "INTENT" "$INTENT_TEXT"

# Row 12: LEARN
print_row "$BG_LEARN_R" "$FG_LEARN_R" "LEARN" "$LEARN_TEXT"

# Row 13: LIMITS (API rate limits — stacks req/tok when narrow)
[ "$LIMITS_TEXT" != "none" ] && flex_segments \
    "$BG_LIMITS_R" "$FG_LIMITS_R" "LIMITS" "$LIMITS_REQ_TEXT" \
    "$BG_LIMITS_R" "$FG_LIMITS_R" ""       "$LIMITS_TOK_TEXT"

# ========== API LIMITS REFRESH (background, throttled to once per 10 min) ==========
# Fetches anthropic-ratelimit-* headers from a cheap HEAD call to api.anthropic.com.
# Uses ANTHROPIC_API_KEY from env, or macOS Keychain key "anthropic_api_key".
# Lock file prevents concurrent refreshes. Writes to ~/.claude/temp/.api_limits.json.
{
    REFRESH_LOCK="$HOME/.claude/temp/.api_limits_refresh.lock"
    # Skip if a refresh is already in progress (<30s old lock)
    if [ -f "$REFRESH_LOCK" ]; then
        LOCK_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$REFRESH_LOCK" 2>/dev/null || echo 0) ))
        [ "$LOCK_AGE" -lt 30 ] && exit 0
    fi
    # Skip if cache is still fresh (<10 min)
    if [ -f "$API_LIMITS_FILE" ]; then
        FRESH=$(( $(date +%s) - $(/usr/bin/stat -f %m "$API_LIMITS_FILE" 2>/dev/null || echo 0) ))
        [ "$FRESH" -lt 600 ] && exit 0
    fi
    touch "$REFRESH_LOCK" 2>/dev/null
    # Resolve API key: env → Keychain "anthropic_api_key" → Keychain "ANTHROPIC_API_KEY"
    AKEY="${ANTHROPIC_API_KEY:-}"
    if [ -z "$AKEY" ]; then
        AKEY=$(security find-generic-password -s "anthropic_api_key" -w 2>/dev/null || \
               security find-generic-password -s "ANTHROPIC_API_KEY" -w 2>/dev/null || echo "")
    fi
    rm -f "$REFRESH_LOCK" 2>/dev/null
    [ -z "$AKEY" ] && exit 0
    # HEAD request — no body, just headers, minimal cost
    HDRS=$(curl -s -I -m 10 \
        -H "x-api-key: $AKEY" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/models" 2>/dev/null)
    [ -z "$HDRS" ] && exit 0
    RQ_LIM=$(echo "$HDRS" | grep -i "^anthropic-ratelimit-requests-limit:"     | tr -d '\r' | awk '{print $2}')
    RQ_REM=$(echo "$HDRS" | grep -i "^anthropic-ratelimit-requests-remaining:"  | tr -d '\r' | awk '{print $2}')
    RT_LIM=$(echo "$HDRS" | grep -i "^anthropic-ratelimit-tokens-limit:"        | tr -d '\r' | awk '{print $2}')
    RT_REM=$(echo "$HDRS" | grep -i "^anthropic-ratelimit-tokens-remaining:"    | tr -d '\r' | awk '{print $2}')
    RT_RST=$(echo "$HDRS" | grep -i "^anthropic-ratelimit-tokens-reset:"        | tr -d '\r' | awk '{print $2}')
    [ -z "$RQ_LIM" ] && exit 0
    printf '{"timestamp":%s,"req_limit":%s,"req_remaining":%s,"tok_limit":%s,"tok_remaining":%s,"tok_reset":"%s"}\n' \
        "$(date +%s)" \
        "${RQ_LIM:-0}" "${RQ_REM:-0}" \
        "${RT_LIM:-0}" "${RT_REM:-0}" \
        "${RT_RST:-unknown}" > "$API_LIMITS_FILE" 2>/dev/null
} &

# ========== USAGE CAPS REFRESH (background, throttled to once per 60 min) ==========
# Fetches 5-hour and 7-day rolling usage cap percentages from /api/oauth/usage.
# Same API key resolution as LIMITS above. The endpoint returns retry-after ~3500s,
# so we cache aggressively (60 min). Shows actual Anthropic throttle risk for Max plans.
{
    CAP_LOCK="$HOME/.claude/temp/.usage_caps_refresh.lock"
    # Skip if a refresh is already in progress (<60s old lock)
    if [ -f "$CAP_LOCK" ]; then
        LOCK_AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$CAP_LOCK" 2>/dev/null || echo 0) ))
        [ "$LOCK_AGE" -lt 60 ] && exit 0
    fi
    # Skip if cache is still fresh (<60 min)
    if [ -f "$USAGE_CAPS_FILE" ]; then
        FRESH=$(( $(date +%s) - $(/usr/bin/stat -f %m "$USAGE_CAPS_FILE" 2>/dev/null || echo 0) ))
        [ "$FRESH" -lt 3600 ] && exit 0
    fi
    touch "$CAP_LOCK" 2>/dev/null

    # Auth strategy: sessionKey cookie (from Claude Desktop's encrypted cookies) → API key
    # The sessionKey is decrypted once by a helper and cached at ~/.claude/temp/.claude_session_key
    SESSION_KEY_FILE="$HOME/.claude/temp/.claude_session_key"
    RESP=""

    # Strategy 1: sessionKey cookie (preferred — same auth as claude.ai/settings/usage)
    if [ -f "$SESSION_KEY_FILE" ]; then
        SK=$(<"$SESSION_KEY_FILE")
        if [ -n "$SK" ]; then
            RESP=$(curl -s -m 15 \
                -H "Cookie: sessionKey=$SK" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "Accept: application/json" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        fi
    fi

    # Strategy 2: API key (fallback)
    if [ -z "$RESP" ] || echo "$RESP" | grep -q '"error"'; then
        AKEY="${ANTHROPIC_API_KEY:-}"
        if [ -z "$AKEY" ]; then
            AKEY=$(security find-generic-password -s "anthropic_api_key" -w 2>/dev/null || \
                   security find-generic-password -s "ANTHROPIC_API_KEY" -w 2>/dev/null || echo "")
        fi
        if [ -n "$AKEY" ]; then
            RESP=$(curl -s -m 15 \
                -H "x-api-key: $AKEY" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "anthropic-version: 2023-06-01" \
                -H "Accept: application/json" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        fi
    fi

    rm -f "$CAP_LOCK" 2>/dev/null
    [ -z "$RESP" ] && exit 0
    # Check for error response (rate limit or auth failure) — don't write bad data
    echo "$RESP" | grep -q '"error"' && exit 0
    # Extract five_hour and seven_day (integers or null)
    FH=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('five_hour') or 0)" 2>/dev/null || echo "")
    SD=$(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('seven_day') or 0)" 2>/dev/null || echo "")
    [ -z "$FH" ] && exit 0
    printf '{"timestamp":%s,"five_hour":%s,"seven_day":%s}\n' \
        "$(date +%s)" "${FH:-0}" "${SD:-0}" > "$USAGE_CAPS_FILE" 2>/dev/null
} &

# ========== ITERM2 SYNC (write directly to parent TTY, background) ==========
# Claude Code's TUI captures stdout — OSC sequences must bypass it via /dev/ttyNNN
# Tab title = clone dir name, Window title = session ID, Badge = session name
{
    # PARENT_TTY already resolved at line 462
    if [ -c "$PARENT_TTY" ]; then
        [ -n "${SESSION_NAME:-}" ] && printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$SESSION_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
        if [ -n "$SESSION_ID" ]; then
            printf '\033]1337;SetUserVar=sessionId=%s\007' "$(printf '%s' "$SESSION_ID" | base64 | tr -d '\n')" > "$PARENT_TTY"
            [ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "--" ] && printf '\033]1337;SetUserVar=cloneName=%s\007' "$(printf '%s' "$REPO_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
            [ -n "${SESSION_NAME:-}" ] && printf '\033]1337;SetUserVar=sessionBadge=%s\007' "$(printf '%s' "$SESSION_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
            RESUME_CMD=""
            [ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "--" ] && RESUME_CMD="cd ${HOME}/github/open-session-clones/${REPO_NAME} && claude --resume ${SESSION_ID}"
            [ -n "$RESUME_CMD" ] && printf '\033]1337;SetUserVar=resumeCmd=%s\007' "$(printf '%s' "$RESUME_CMD" | base64 | tr -d '\n')" > "$PARENT_TTY"
        fi
    fi
    # Always write sync file for external consumers (including precompact_alert_watcher)
    if [ -n "$SESSION_ID" ]; then
        SYNC_FILE="$HOME/.claude/temp/.iterm_sync_${SESSION_ID}.json"
        TTY_RAW=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
        printf '{"session_id":"%s","repo_name":"%s","session_name":"%s","resume_cmd":"%s","iterm_session_id":"%s","tty":"/dev/%s","timestamp":%s}\n' \
            "$SESSION_ID" "${REPO_NAME:-}" "${SESSION_NAME:-}" "${RESUME_CMD:-}" "${ITERM_SESSION_ID:-}" "${TTY_RAW:-null}" "$(date +%s)" > "$SYNC_FILE" 2>/dev/null
    fi
} &
