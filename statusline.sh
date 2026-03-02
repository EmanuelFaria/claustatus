#!/opt/homebrew/bin/bash
# NOTE: No set -e or set -o pipefail — statusline must ALWAYS exit 0.
# A non-zero exit causes Claude Code to hide the statusline across all sessions.
# Custom Claude Code Status Line (Powerline Style) - SPEED-OPTIMIZED
# Single jq call extracts all fields. Target: <50ms total execution.
#
# Rows: Activity, MODEL, CTX, CC%, SES, NAME+REPO, CLONE+ID, GUIDE, SKILL, INTENT, LEARN

# ANSI Color codes — basic 16-color only (8-bit breaks Claude Code TUI redraws)
RESET="\033[0m"
BOLD="\033[1m"
FG_BLACK="\033[30m"
FG_WHITE="\033[97m"

# ── Row: Model ───────────────────────────────────────────────────
BG_CYAN="\033[46m"          # Model name        cyan
FG_CYAN="\033[36m"
BG_GRAY="\033[44m"          # Version           blue
FG_GRAY="\033[34m"
BG_GREEN="\033[42m"         # Thinking ON       green
FG_GREEN="\033[32m"
BG_RED="\033[41m"           # Thinking OFF      red
FG_RED="\033[31m"

# ── Row: CTX ─────────────────────────────────────────────────────
BG_YELLOW="\033[46m"        # CTX label         cyan
FG_YELLOW="\033[36m"
BG_BLUE="\033[44m"          # CTX used%         blue
FG_BLUE="\033[34m"
BG_CTX_LEFT="\033[42m"      # CTX left%         green
FG_CTX_LEFT="\033[32m"

# ── Row: CC% ─────────────────────────────────────────────────────
BG_PURPLE="\033[45m"        # CC% label         magenta
FG_PURPLE="\033[35m"
BG_TEAL="\033[44m"          # CC% used%         blue
FG_TEAL="\033[34m"
BG_LIME="\033[46m"          # CC% left%         cyan
FG_LIME="\033[36m"

# ── Row: SES ─────────────────────────────────────────────────────
BG_SLATE="\033[43m"         # SES label         yellow
FG_SLATE="\033[33m"
BG_STEEL="\033[43m"         # SES cost          yellow
FG_STEEL="\033[33m"
BG_SKY="\033[43m"           # SES duration      yellow
FG_SKY="\033[33m"

# ── Rows: Location ───────────────────────────────────────────────
BG_FOREST="\033[42m"        # REPO              green
FG_FOREST="\033[32m"
BG_ORANGE="\033[42m"        # CLONE             green
FG_ORANGE="\033[32m"

# Powerline arrow (keeping the character — it's the escape codes that break things)
ARROW=""

# Base overhead - system prompts, CLAUDE.md, tools, hooks, etc.
# Must match in all 3 locations:
#   - ~/.claude/hooks/precompact_auto_warning.sh
#   - ~/.claude/scripts/global_transcript_summary_extract_relay.py
BASE_OVERHEAD=30500

# ========== SINGLE JQ CALL — extract everything at once ==========
INPUT=$(cat)

# Save JSON to temp file for other scripts to read
echo "$INPUT" > "$HOME/.claude/temp/statusline_data.json" 2>/dev/null &

# One jq call extracts all fields, separated by Unit Separator (0x1F)
# CRITICAL: Tab (\t) cannot be used — bash read treats consecutive tabs as one
# delimiter, losing empty fields and shifting all subsequent values.
IFS=$'\x1f' read -r MODEL CC_VERSION PROJECT_DIR CONTEXT_SIZE \
     INPUT_TOKENS CACHE_CREATE CACHE_READ TOTAL_INPUT \
     CC_PERCENT_USED CC_PERCENT_LEFT \
     SES_TOTAL_INPUT SES_TOTAL_OUTPUT SES_COST SES_DURATION_MS \
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
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.cost.total_cost_usd // 0),
    (.cost.total_api_duration_ms // 0),
    (.session_id // ""),
    (.transcript_path // "")
] | map(tostring) | join("\u001f")')"

# ========== COMPUTED VALUES (pure bash, no subprocesses) ==========

# Repo name from project dir
if [ -n "$PROJECT_DIR" ]; then
    REPO_NAME="${PROJECT_DIR##*/}"
else
    REPO_NAME="--"
fi

# Git remote repo name — use 5-second cache to avoid slow git calls
GIT_CACHE="/tmp/statusline-git-cache-$$"
GITHUB_REPO_NAME="$REPO_NAME"
if [ -n "$PROJECT_DIR" ]; then
    GLOBAL_GIT_CACHE="/tmp/statusline-git-${PROJECT_DIR//\//_}"
    if [ -f "$GLOBAL_GIT_CACHE" ]; then
        CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$GLOBAL_GIT_CACHE" 2>/dev/null || /usr/bin/stat -f %m "$GLOBAL_GIT_CACHE" 2>/dev/null || echo 0) ))
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
RAW_TOKENS_DISPLAY=$(printf "%'d" "$RAW_TOKENS" 2>/dev/null || echo "$RAW_TOKENS")

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

# Session tokens and cost (SES_COST is float — use printf, not arithmetic)
SES_TOTAL_INPUT=${SES_TOTAL_INPUT:-0}; SES_TOTAL_INPUT=${SES_TOTAL_INPUT%.*}
SES_TOTAL_OUTPUT=${SES_TOTAL_OUTPUT:-0}; SES_TOTAL_OUTPUT=${SES_TOTAL_OUTPUT%.*}
SES_TOKENS=$(( SES_TOTAL_INPUT + SES_TOTAL_OUTPUT ))
SES_TOKENS_DISPLAY=$(printf "%'d" "$SES_TOKENS" 2>/dev/null || echo "$SES_TOKENS")
# SES_COST may have trailing tab from read; strip it
SES_COST="${SES_COST:-0}"
SES_COST="${SES_COST%%[^0-9.e+-]*}"
SES_COST_DISPLAY=$(printf '$%.2f' "$SES_COST" 2>/dev/null || echo '$0.00')
SES_DURATION_MS=${SES_DURATION_MS:-0}; SES_DURATION_MS=${SES_DURATION_MS%.*}
SES_MINS=$((SES_DURATION_MS / 60000))
SES_SECS=$(((SES_DURATION_MS % 60000) / 1000))

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

# Session name — use cached value (updated by full script periodically)
SESSION_NAME=""
SESSION_NAME_CACHE="/tmp/statusline-sessname-${SESSION_ID}"
if [ -f "$SESSION_NAME_CACHE" ]; then
    SESSION_NAME=$(cat "$SESSION_NAME_CACHE")
elif [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    SESSION_NAME=$(grep '^{"type":"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.customTitle // empty' 2>/dev/null || true)
    SESSION_NAME="${SESSION_NAME% (Fork)}"
    [ -n "$SESSION_NAME" ] && echo "$SESSION_NAME" > "$SESSION_NAME_CACHE" 2>/dev/null
fi

# Activity state — quick read, no subprocess
ACTIVITY_ICON="✓"
ACTIVITY_DETAIL="Ready for input"
ACTIVITY_BG="\033[48;5;248m"
ACTIVITY_FG="\033[38;5;248m"
ACTIVITY_FILE="$HOME/.claude/temp/.current_activity.json"
if [ -f "$ACTIVITY_FILE" ]; then
    ACTIVITY_JSON=$(<"$ACTIVITY_FILE" 2>/dev/null)
    if [ -n "$ACTIVITY_JSON" ]; then
        read -r A_STATUS A_TOOL A_DETAIL A_TS <<< "$(echo "$ACTIVITY_JSON" | jq -r '[(.status // "unknown"), (.tool // ""), (.detail // ""), (.timestamp // 0)] | @tsv' 2>/dev/null || echo "unknown   0")"
        NOW=$(date +%s)
        AGE=$((NOW - ${A_TS%.*}))
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
            SC=$(json_num count "$SJ"); SKILL_TEXT="${SC:-0} options" ;;
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
            [ "${LC:-0}" = "1" ] && LEARN_TEXT="surfaced 1 past learning" || LEARN_TEXT="surfaced ${LC:-0} past learnings" ;;
        skipped) BG_LEARN_R="\033[48;5;136m"; FG_LEARN_R="\033[38;5;136m"; LEARN_TEXT="skipped" ;;
    esac
fi

# ========== OUTPUT — all 12 rows, all printf ==========

# Row 0: PRECOMPACT alerts (conditional, double-height)
# Priority: PASTE PRECOMPACT (flag exists) > PRECOMPACT NOW (≤20% remaining)
# Animation: \033[5m = ANSI blink (requires iTerm2 Profiles > Text > "Blinking text allowed")
PRECOMPACT_READY_FILE="$HOME/.claude/temp/.precompact_ready"
PRECOMPACT_READY=false

# Check if precompact output is ready to paste (5-min expiry)
if [ -f "$PRECOMPACT_READY_FILE" ]; then
    READY_MTIME=$(stat -c %Y "$PRECOMPACT_READY_FILE" 2>/dev/null || /usr/bin/stat -f %m "$PRECOMPACT_READY_FILE" 2>/dev/null || echo 0)
    READY_AGE=$(( $(date +%s) - READY_MTIME ))
    if [ "$READY_AGE" -lt 300 ]; then
        PRECOMPACT_READY=true
    else
        rm -f "$PRECOMPACT_READY_FILE"
    fi
fi

if [ "$PRECOMPACT_READY" = true ]; then
    # PASTE PRECOMPACT NOW — green, blink. Precompact text is ready to copy.
    printf "\033[5m\033[42m\033[97m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
    printf "\033[5m\033[42m\033[30m\033[1m 🔔🔔  PASTE PRECOMPACT NOW  🔔🔔 \033[0m\n"
elif [ "${PERCENT_REMAINING:-100}" -le 20 ] 2>/dev/null && [ "${PERCENT_REMAINING:-100}" -gt 0 ] 2>/dev/null; then
    # PRECOMPACT NOW — red/yellow, blink. Context running low, run /precompact.
    printf "\033[5m\033[41m\033[93m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
    printf "\033[5m\033[43m\033[31m\033[1m 🚨🚨🚨  PRECOMPACT NOW!  🚨🚨🚨 \033[0m\n"
fi

# Row 1: Activity
printf "${ACTIVITY_BG}${FG_BLACK}${BOLD} %s %s ${RESET}${ACTIVITY_FG}${ARROW}${RESET}\n" "$ACTIVITY_ICON" "$ACTIVITY_DETAIL"

# Row 2: MODEL | Version | Thinking
printf "${BG_CYAN}${FG_WHITE}${BOLD} MODEL ${RESET}${BG_CYAN}${FG_WHITE} %s ${RESET}${BG_GRAY}${FG_CYAN}${ARROW}${FG_WHITE} v%s ${RESET}${THINK_BG}${FG_GRAY}${ARROW}${FG_WHITE} %s ${RESET}${THINK_FG_NEXT}${ARROW}${RESET}\n" "$MODEL" "$CC_VERSION" "$THINK"

# Row 3: CTX
printf "${BG_YELLOW}${FG_WHITE}${BOLD} CTX ${RESET}${BG_YELLOW}${FG_WHITE} %s ${RESET}${BG_BLUE}${FG_YELLOW}${ARROW}${FG_WHITE} %s%% used ${RESET}${BG_CTX_LEFT}${FG_BLUE}${ARROW}${FG_BLACK} %s%% left ${RESET}${FG_CTX_LEFT}${ARROW}${RESET}\n" "$TOKENS_DISPLAY" "$PERCENT" "$PERCENT_REMAINING"

# Row 4: CC%
printf "${BG_PURPLE}${FG_WHITE}${BOLD} CC%% ${RESET}${BG_PURPLE}${FG_WHITE} %s ${RESET}${BG_TEAL}${FG_PURPLE}${ARROW}${FG_WHITE} %s%% used ${RESET}${BG_LIME}${FG_TEAL}${ARROW}${FG_WHITE} %s%% left ${RESET}${FG_LIME}${ARROW}${RESET}\n" "$RAW_TOKENS_DISPLAY" "${CC_PERCENT_USED:-0}" "${CC_PERCENT_LEFT:-0}"

# Row 5: SES
printf "${BG_SLATE}${FG_WHITE}${BOLD} SES ${RESET}${BG_SLATE}${FG_WHITE} %s ${RESET}${BG_STEEL}${FG_SLATE}${ARROW}${FG_WHITE} %s ${RESET}${BG_SKY}${FG_STEEL}${ARROW}${FG_BLACK} %sm %ss API ${RESET}${FG_SKY}${ARROW}${RESET}\n" "$SES_TOKENS_DISPLAY" "$SES_COST_DISPLAY" "${SES_MINS:-0}" "${SES_SECS:-0}"

# Row 6: NAME + REPO
BG_NAME="\033[48;5;25m"; FG_NAME="\033[38;5;25m"
if [ -n "$SESSION_NAME" ]; then
    printf "${BG_NAME}${FG_WHITE}${BOLD} NAME ${RESET}${BG_NAME}${FG_WHITE} %s ${RESET}${BG_FOREST}${FG_NAME}${ARROW}${FG_WHITE}${BOLD} REPO ${RESET}" "$SESSION_NAME"
else
    printf "${BG_FOREST}${FG_WHITE}${BOLD} REPO ${RESET}"
fi
printf "${BG_FOREST}${FG_WHITE} %s ${RESET}${FG_FOREST}${ARROW}${RESET}\n" "$GITHUB_REPO_NAME"

# Row 7: CLONE (own line)
# Row 8: ID (own line — UUID is long, splitting prevents truncation on narrow terminals)
BG_LB="\033[48;5;237m"; FG_LB="\033[38;5;244m"
printf "${BG_ORANGE}${FG_BLACK}${BOLD} CLONE ${RESET}${BG_ORANGE}${FG_BLACK} %s ${RESET}${FG_ORANGE}${ARROW}${RESET}\n" "$REPO_NAME"
printf "${BG_LB}${FG_LB}${BOLD} ID ${RESET}${BG_LB}${FG_LB} %s ${RESET}${FG_LB}${ARROW}${RESET}\n" "$SESSION_ID"

# Row 8: GUIDE
printf "${BG_GUIDE_R}${FG_WHITE}${BOLD} GUIDE ${RESET}${BG_GUIDE_R}${FG_WHITE} %s ${RESET}${FG_GUIDE_R}${ARROW}${RESET}\n" "$GUIDE_TEXT"

# Row 9: SKILL
printf "${BG_SKILL_R}${FG_WHITE}${BOLD} SKILL ${RESET}${BG_SKILL_R}${FG_WHITE} %s ${RESET}${FG_SKILL_R}${ARROW}${RESET}\n" "$SKILL_TEXT"

# Row 10: INTENT
printf "${BG_INTENT_R}${FG_WHITE}${BOLD} INTENT ${RESET}${BG_INTENT_R}${FG_WHITE} %s ${RESET}${FG_INTENT_R}${ARROW}${RESET}\n" "$INTENT_TEXT"

# Row 11: LEARN
printf "${BG_LEARN_R}${FG_WHITE}${BOLD} LEARN ${RESET}${BG_LEARN_R}${FG_WHITE} %s ${RESET}${FG_LEARN_R}${ARROW}${RESET}\n" "$LEARN_TEXT"

# ========== ITERM2 SYNC (write directly to parent TTY, background) ==========
# Claude Code's TUI captures stdout — OSC sequences must bypass it via /dev/ttyNNN
# Tab title = clone dir name, Window title = session ID, Badge = session name
{
    PARENT_TTY="/dev/$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')"
    if [ -c "$PARENT_TTY" ]; then
        [ -n "${SESSION_NAME:-}" ] && printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$SESSION_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
        if [ -n "$SESSION_ID" ]; then
            printf '\033]1337;SetUserVar=sessionId=%s\007' "$(printf '%s' "$SESSION_ID" | base64 | tr -d '\n')" > "$PARENT_TTY"
            [ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "--" ] && printf '\033]1337;SetUserVar=cloneName=%s\007' "$(printf '%s' "$REPO_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
            [ -n "${SESSION_NAME:-}" ] && printf '\033]1337;SetUserVar=sessionBadge=%s\007' "$(printf '%s' "$SESSION_NAME" | base64 | tr -d '\n')" > "$PARENT_TTY"
            RESUME_CMD=""
            [ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "--" ] && RESUME_CMD="cd /Users/emanuelfarruda/github/open-session-clones/${REPO_NAME} && claude --resume ${SESSION_ID}"
            [ -n "$RESUME_CMD" ] && printf '\033]1337;SetUserVar=resumeCmd=%s\007' "$(printf '%s' "$RESUME_CMD" | base64 | tr -d '\n')" > "$PARENT_TTY"
        fi
    fi
    # Always write sync file for external consumers
    if [ -n "$SESSION_ID" ]; then
        SYNC_FILE="$HOME/.claude/temp/.iterm_sync_${SESSION_ID}.json"
        printf '{"session_id":"%s","repo_name":"%s","session_name":"%s","resume_cmd":"%s","iterm_session_id":"%s","timestamp":%s}\n' \
            "$SESSION_ID" "${REPO_NAME:-}" "${SESSION_NAME:-}" "${RESUME_CMD:-}" "${ITERM_SESSION_ID:-}" "$(date +%s)" > "$SYNC_FILE" 2>/dev/null
    fi
} &
