#!/usr/bin/env bash
# Claude Code status line — three-row layout
# See: docs/superpowers/specs/2026-05-09-statusline-enhancement-design.md
# Constraints (verified May 2026):
#   - No TTY: $COLUMNS is unset, tput cols returns 80, /dev/tty unavailable
#   - Leading whitespace stripped from each row by Claude Code renderer
#   - rate_limits.{five_hour,seven_day} may be independently absent
#   - context_window.used_percentage may be null before first API response
#   - Apple  (U+F8FF) renders via macOS system font fallback, not Hack Nerd Font

set -u

# ---- Read JSON from stdin ----
input=$(cat)

# ---- Single-pass jq extraction ----
read_jq() {
  jq -r "$1 // empty" <<< "$input" 2> /dev/null
}

cwd=$(read_jq '.workspace.current_dir // .cwd')
session_id=$(read_jq '.session_id')
model_name=$(read_jq '.model.display_name')
# Strip "(...context)" suffix — redundant with the separate 1M badge
model_name=$(printf '%s' "$model_name" | sed -E 's/[[:space:]]*\([^)]*context\)[[:space:]]*$//')
ctx_pct=$(read_jq '.context_window.used_percentage')
ctx_size=$(read_jq '.context_window.context_window_size')
effort=$(read_jq '.effort.level')
git_worktree=$(read_jq '.workspace.git_worktree')
fh_pct=$(read_jq '.rate_limits.five_hour.used_percentage')
fh_resets=$(read_jq '.rate_limits.five_hour.resets_at')
sd_pct=$(read_jq '.rate_limits.seven_day.used_percentage')
sd_resets=$(read_jq '.rate_limits.seven_day.resets_at')

ctx_pct_int=${ctx_pct%.*}
ctx_pct_int=${ctx_pct_int:-0}
fh_pct_int=${fh_pct%.*}
sd_pct_int=${sd_pct%.*}

# ---- ANSI / truecolor helpers ----
RESET=$'\033[0m'
# fg "R G B": takes the triplet as one string and splits it here, so callers
# can quote it
fg() {
  # shellcheck disable=SC2086 # deliberate word splitting of the triplet
  printf '\033[38;2;%d;%d;%dm' $1
}

# ---- Color palette (truecolor RGB triplets) ----
# Brightened 2026-05-09 post-live-verification: muted greens were
# indistinguishable from the dim empty cells in Warp's dark theme.
# Now: filled cells +30% luminance, empty cells darker for max contrast.
COLOR_GREEN_BG="92 191 108"  # #5cbf6c (was #4a8f4f)
COLOR_YELLOW_BG="224 168 46" # #e0a82e (was #b88a30)
COLOR_RED_BG="214 90 90"     # #d65a5a (was #a04547)
COLOR_GREEN_FG="126 183 127"
COLOR_YELLOW_FG="212 165 72"
COLOR_RED_FG="200 88 90"
COLOR_DIM="136 136 136"
COLOR_GREY="160 160 160"
COLOR_MAGENTA="204 102 153"
COLOR_CYAN="127 174 220"
COLOR_PURPLE="157 127 220"
COLOR_WHITE="255 255 255"
COLOR_DARK="26 26 26"

# ---- Threshold color picker (RED checked first) ----
threshold_colors() {
  local pct=$1
  if [ "$pct" -ge 90 ]; then
    echo "$COLOR_RED_BG $COLOR_WHITE"
  elif [ "$pct" -ge 70 ]; then
    echo "$COLOR_YELLOW_BG $COLOR_DARK"
  else
    echo "$COLOR_GREEN_BG $COLOR_WHITE"
  fi
}

# ---- Eighths-block characters ----
EIGHTHS=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
FULL_BLOCK="█"

# ---- render_bar PCT [WIDTH] ----
# Foreground-only rendering (background colors are dimmed by Warp's themes).
# Filled cells outside text region: █ in threshold color (foreground).
# Empty cells outside text region: ░ in dim grey.
# Filled cells in text region (5-9): the digit char in threshold color.
# Empty cells in text region: the digit char in dim grey.
# Boundary fractional cell: an eighths-block char in threshold color.
render_bar() {
  local pct=$1
  local width=${2:-12}
  [ -z "$pct" ] && pct=0
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100

  # Color picker: foreground color for the FILL state.
  # We reuse threshold_colors() but only need the BG triplet (which we now
  # apply as foreground because Warp dims actual backgrounds).
  local pair fill_rgb
  pair=$(threshold_colors "$pct")
  fill_rgb=$(echo "$pair" | cut -d' ' -f1-3)

  local total_eighths=$((pct * width * 8 / 100))
  local full_cells=$((total_eighths / 8))
  local frac=$((total_eighths % 8))

  local pct_text
  printf -v pct_text " %2d%% " "$pct"

  local out=""
  local i
  for ((i = 1; i <= width; i++)); do
    if [ "$i" -ge 5 ] && [ "$i" -le 9 ]; then
      # Text overlay region — render the digit, color depending on fill state
      local text_idx=$((i - 5))
      local text_char="${pct_text:$text_idx:1}"
      if [ "$i" -le "$full_cells" ]; then
        # Cell is logically filled — use threshold color for the digit
        out+="$(fg "$fill_rgb")${text_char}"
      else
        # Cell is empty — use dim grey for the digit
        out+="$(fg "$COLOR_DIM")${text_char}"
      fi
    elif [ "$i" -eq $((full_cells + 1)) ] && [ "$frac" -gt 0 ]; then
      # Boundary cell with fractional fill — eighths-block in threshold color
      local frac_char="${EIGHTHS[$frac]}"
      out+="$(fg "$fill_rgb")${frac_char}"
    elif [ "$i" -le "$full_cells" ]; then
      # Fully filled cell — full block in threshold color
      out+="$(fg "$fill_rgb")${FULL_BLOCK}"
    else
      # Fully empty cell — light shade in dim grey
      out+="$(fg "$COLOR_DIM")░"
    fi
  done
  out+="$RESET"
  printf '%s' "$out"
}

# ---- format_5h_countdown EPOCH (red < 10m, yellow < 60m, dim default) ----
format_5h_countdown() {
  local resets_at=$1
  [ -z "$resets_at" ] && return
  local now
  now=$(date +%s)
  local delta=$((resets_at - now))
  [ "$delta" -lt 0 ] && delta=0
  local mins=$((delta / 60))
  local hours=$((mins / 60))
  mins=$((mins % 60))
  local text
  if [ "$hours" -gt 0 ]; then
    text="in ${hours}h ${mins}m"
  else
    text="in ${mins}m"
  fi
  local color
  if [ "$delta" -lt 600 ]; then
    color=$(fg "$COLOR_RED_FG")
  elif [ "$delta" -lt 3600 ]; then
    color=$(fg "$COLOR_YELLOW_FG")
  else
    color=$(fg "$COLOR_DIM")
  fi
  printf '%s%s%s' "$color" "$text" "$RESET"
}

# ---- format_7d_date EPOCH (macOS BSD date syntax) ----
format_7d_date() {
  local resets_at=$1
  [ -z "$resets_at" ] && return
  local text
  text=$(date -r "$resets_at" '+%b %d')
  printf '%s%s%s' "$(fg "$COLOR_DIM")" "$text" "$RESET"
}

# ---- git_cached_state CWD SESSION_ID WORKTREE_NAME (5s TTL, atomic write) ----
git_cached_state() {
  local cwd=$1
  local sid=$2
  local worktree_name=$3
  local cache_file="/tmp/statusline-git-cache-${sid}"
  local cache_max_age=5

  local cache_fresh=0
  if [ -f "$cache_file" ]; then
    local age=$(($(date +%s) - $(stat -f %m "$cache_file" 2> /dev/null || echo 0)))
    [ "$age" -lt "$cache_max_age" ] && cache_fresh=1
  fi

  if [ "$cache_fresh" -eq 0 ]; then
    local in_git=0 branch="" staged=0 modified=0 remote=""
    if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
      in_git=1
      branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2> /dev/null)
      staged=$(git -C "$cwd" --no-optional-locks diff --cached --numstat 2> /dev/null | wc -l | tr -d ' ')
      modified=$(git -C "$cwd" --no-optional-locks diff --numstat 2> /dev/null | wc -l | tr -d ' ')
      remote=$(git -C "$cwd" remote get-url origin 2> /dev/null \
        | sed 's|git@github\.com:|https://github.com/|' \
        | sed 's|\.git$||')
    fi
    # Atomic write: temp file + mv
    local tmp_cache="${cache_file}.tmp.$$"
    printf '%s|%s|%s|%s|%s|%s' "$in_git" "$branch" "$worktree_name" "$staged" "$modified" "$remote" > "$tmp_cache"
    mv "$tmp_cache" "$cache_file"
  fi

  cat "$cache_file"
}

# ---- OSC 8 hyperlink helper ----
osc8_link() {
  local url=$1
  local text=$2
  if [ -n "$url" ]; then
    # shellcheck disable=SC1003 # \\ is printf's literal backslash: ESC \ ends the OSC 8 sequence
    printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$text"
  else
    printf '%s' "$text"
  fi
}

# ---- build_row1: identity ----
build_row1() {
  local out=""
  out+="$(render_bar "$ctx_pct_int")"
  out+="   $(fg "$COLOR_MAGENTA")$(printf '\xee\xa3\xbf')$RESET "
  local repo_basename="${cwd##*/}"
  [ -z "$repo_basename" ] && repo_basename="?"
  out+="$(fg "$COLOR_CYAN")$(osc8_link "$remote" "$repo_basename")$RESET"
  if [ -n "$model_name" ]; then
    out+="  $(fg "$COLOR_GREY")$model_name$RESET"
  fi
  if [ "$ctx_size" = "1000000" ]; then
    out+=" $(fg "$COLOR_PURPLE")1M$RESET"
  fi
  case "$effort" in
    high) out+="  $(fg "$COLOR_CYAN")high$RESET" ;;
    xhigh) out+="  $(fg "$COLOR_YELLOW_FG")xhigh$RESET" ;;
    max) out+="  $(fg "$COLOR_RED_FG")max$RESET" ;;
  esac
  printf '%s' "$out"
}

# ---- build_row2: workspace (empty if not in git) ----
build_row2() {
  if [ "$in_git" != "1" ]; then
    return
  fi
  local out="   "
  out+="$(fg "$COLOR_CYAN")$(printf '\xee\x82\xa0')$RESET "
  local label
  if [ -n "$worktree" ]; then
    label="$worktree"
  else
    label="$branch"
  fi
  [ -z "$label" ] && label="(detached)"
  out+="$(fg "$COLOR_CYAN")$label$RESET"
  if [ -n "$staged" ] && [ "$staged" -gt 0 ]; then
    out+=" $(fg "$COLOR_GREEN_FG")+$staged$RESET"
  fi
  if [ -n "$modified" ] && [ "$modified" -gt 0 ]; then
    out+=" $(fg "$COLOR_YELLOW_FG")~$modified$RESET"
  fi
  printf '%s' "$out"
}

# ---- build_row3: rate limits (skipped if both absent) ----
build_row3() {
  local has_5h=0 has_7d=0
  [ -n "$fh_pct" ] && has_5h=1
  [ -n "$sd_pct" ] && has_7d=1

  if [ "$has_5h" -eq 0 ] && [ "$has_7d" -eq 0 ]; then
    return
  fi

  local out=""
  if [ "$has_5h" -eq 1 ]; then
    out+="5h $(render_bar "$fh_pct_int")"
    if [ -n "$fh_resets" ]; then
      out+=" $(format_5h_countdown "$fh_resets")"
    fi
  fi
  if [ "$has_5h" -eq 1 ] && [ "$has_7d" -eq 1 ]; then
    out+="  $(fg "$COLOR_DIM")│$RESET  "
  fi
  if [ "$has_7d" -eq 1 ]; then
    out+="7d $(render_bar "$sd_pct_int")"
    if [ -n "$sd_resets" ]; then
      out+=" $(format_7d_date "$sd_resets")"
    fi
  fi
  printf '%s' "$out"
}

# ---- Main: extract git state, then emit up to 3 rows ----
state=$(git_cached_state "$cwd" "$session_id" "$git_worktree")
IFS='|' read -r in_git branch worktree staged modified remote <<< "$state"

build_row1
echo

row2_out=$(build_row2)
[ -n "$row2_out" ] && echo "$row2_out"

row3_out=$(build_row3)
[ -n "$row3_out" ] && echo "$row3_out"

exit 0
