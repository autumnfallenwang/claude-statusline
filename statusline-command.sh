#!/bin/bash
# Claude Code rich status line — developer dashboard
# Layout: [model] │ [ctx bar pct] │ [$cost] │ [branch] [│ 5h% + resets HH:MM]
#
# =============================================================================
# COLOR SEMANTICS — every stateful value maps to a single R/Y/G tension gradient
# =============================================================================
#
# GREEN   — relief / safe / cheap / home / imminent good event
# YELLOW  — transitional midpoint / mid-budget / mid-intensity
# RED     — tension / expensive / off-home / far-from-good-event / limit-near
#
# DIM     — LABELS + SEPARATORS ONLY.  Used for `ctx`, `cost`, `on`, `5h`,
#           `resets`, and the `│` separator.  Never for state values.
# BOLD    — applied on top of R/Y/G when the signal is an extreme (e.g. reset
#           imminent = BOLD GREEN) so the pop is brightness-based, not a new hue.
#
# No identity colors (magenta/cyan) — everything on the bar is state, not ID.
#
# Per-slot rules:
#   model       Opus → RED, Sonnet → YELLOW, Haiku → GREEN, unknown → BOLD
#   ctx bar+%   ≥75% RED, ≥50% YELLOW, else GREEN  (bar and % agree — single color)
#   cost        ≥$200 RED, ≥$100 YELLOW, else GREEN
#   branch      main/master → GREEN, anything else → RED  (feature = active work)
#   5h %        ≥75% RED, ≥50% YELLOW, else GREEN
#   resets HH:M >2h RED, 30m–2h YELLOW, <30m BOLD GREEN  (close = relief incoming)
#
# If you add a new stateful slot, first decide which end of its gradient is
# "good" — then anchor GREEN there and flow through YELLOW to RED at the "bad"
# end.  If a value has no "good/bad" direction, it doesn't belong on the bar;
# move it to a log or remove it.
# =============================================================================

input=$(cat)

# ---------- ANSI palette ----------
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
# Soft lavender in place of red — the "tension" end of the gradient lives
# in a completely different hue family from green/yellow, so the gradient
# reads as three distinct state colors instead of a heat ramp.  No alarm
# connotation from red wavelengths; calm but clearly attention-worthy.
# (Variable name kept as RED because it's the semantic slot, not the hue.)
RED='\033[38;5;141m'

SEP="${DIM}│${RESET}"

# ---------- Model (Opus=RED tension, Sonnet=YELLOW mid, Haiku=GREEN cheap) ----------
# Strip trailing " (1M context)" annotation — it never changes per-session.
model_raw=$(echo "$input" | jq -r '.model.display_name // empty')
model=$(printf '%s' "$model_raw" | sed 's/ (1M context)$//')
case "$(printf '%s' "$model_raw" | tr '[:upper:]' '[:lower:]')" in
    *opus*)   model_color="$RED" ;;
    *sonnet*) model_color="$YELLOW" ;;
    *haiku*)  model_color="$GREEN" ;;
    *)        model_color="$BOLD" ;;
esac

# ---------- Context bar ----------
# Bar color and % number now share the same color (was BRIGHT_WHITE split — fixed).
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
    pct=$(printf '%.0f' "$used")
    filled=$(awk "BEGIN { printf \"%d\", $used * 16 / 100 }")
    empty=$((16 - filled))
    bar=""
    i=0; while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
    i=0; while [ $i -lt $empty  ]; do bar="${bar}░"; i=$((i+1)); done
    if   [ "$pct" -ge 75 ]; then ctx_color="$RED"
    elif [ "$pct" -ge 50 ]; then ctx_color="$YELLOW"
    else                         ctx_color="$GREEN"
    fi
    ctx_section="${DIM}ctx ${RESET}${ctx_color}${bar} ${pct}%${RESET}"
else
    ctx_section=""
fi

# ---------- Cost (thresholds tuned to actual ccusage distribution) ----------
cost_raw=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost_raw" ]; then
    cost_fmt=$(awk "BEGIN { printf \"\$%.2f\", $cost_raw }")
    cost_color=$(awk "BEGIN {
        c = $cost_raw
        if (c >= 200)      print \"red\"
        else if (c >= 100) print \"yellow\"
        else               print \"green\"
    }")
    case "$cost_color" in
        red)    cost_c="$RED" ;;
        yellow) cost_c="$YELLOW" ;;
        *)      cost_c="$GREEN" ;;
    esac
    cost_section="${DIM}cost ${RESET}${cost_c}${cost_fmt}${RESET}"
else
    cost_section=""
fi

# ---------- Git branch (cached per session, 5s TTL) ----------
# main/master = safe home = GREEN; feature branches = active work = RED.
session_id=$(echo "$input" | jq -r '.session_id // empty')
branch=""
if [ -n "$session_id" ]; then
    cache_file="/tmp/.claude_branch_cache_${session_id}"
    now=$(date +%s)
    if [ -f "$cache_file" ]; then
        cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        age=$((now - cache_time))
        if [ "$age" -le 5 ]; then
            branch=$(cat "$cache_file")
        fi
    fi
    if [ -z "$branch" ]; then
        branch=$(git -C "${CLAUDE_CWD:-$PWD}" branch --show-current 2>/dev/null || true)
        [ -n "$branch" ] && printf '%s' "$branch" > "$cache_file"
    fi
fi
if [ -n "$branch" ]; then
    case "$branch" in
        main|master) branch_color="$GREEN" ;;
        *)           branch_color="$RED" ;;
    esac
    branch_section="${DIM}on ${RESET}${branch_color}${branch}${RESET}"
else
    branch_section=""
fi

# ---------- Rate limits + reset clock ----------
# resets_at is Unix epoch seconds. Reset time itself uses the tension axis:
# far = RED (long wait to relief), near = GREEN (relief imminent).
rate_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$rate_pct" ]; then
    rate_int=$(printf '%.0f' "$rate_pct")
    if   [ "$rate_int" -ge 75 ]; then rate_color="$RED"
    elif [ "$rate_int" -ge 50 ]; then rate_color="$YELLOW"
    else                              rate_color="$GREEN"
    fi
    rate_section="${DIM}5h ${RESET}${rate_color}${rate_int}%${RESET}"
    resets_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$resets_epoch" ]; then
        resets_time=$(date -d "@${resets_epoch}" +%H:%M 2>/dev/null || true)
        if [ -n "$resets_time" ]; then
            seconds_left=$((resets_epoch - $(date +%s)))
            if   [ "$seconds_left" -lt 1800 ]; then reset_color="${BOLD}${GREEN}"   # < 30m
            elif [ "$seconds_left" -lt 7200 ]; then reset_color="$YELLOW"           # 30m–2h
            else                                    reset_color="$RED"              # > 2h
            fi
            rate_section="${rate_section} ${DIM}resets ${RESET}${reset_color}${resets_time}${RESET}"
        fi
    fi
else
    rate_section=""
fi

# ---------- Assemble ----------
parts=()
[ -n "$model"          ] && parts+=("${model_color}${model}${RESET}")
[ -n "$ctx_section"    ] && parts+=("$ctx_section")
[ -n "$cost_section"   ] && parts+=("$cost_section")
[ -n "$branch_section" ] && parts+=("$branch_section")
[ -n "$rate_section"   ] && parts+=("$rate_section")

if [ ${#parts[@]} -eq 0 ]; then
    exit 0
fi

line="${parts[0]}"
for part in "${parts[@]:1}"; do
    line="${line}  ${SEP}  ${part}"
done

printf '%b\n' "$line"
