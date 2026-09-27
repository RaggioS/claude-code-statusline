#!/bin/sh
input=$(cat)

cwd=$(echo "$input"      | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input"    | jq -r '.model.display_name // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used_tok=$(echo "$input" | jq -r '(.context_window.current_usage.input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0) + (.context_window.current_usage.cache_creation_input_tokens // 0)')
cost=$(echo "$input"     | jq -r '.cost.total_cost_usd // empty')
rl5_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl5_rst=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // empty')
rl7_pct=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl7_rst=$(echo "$input"  | jq -r '.rate_limits.seven_day.resets_at // empty')

dir=$(basename "$cwd")
now=$(date +%H:%M)

# ── Terminal width ─────────────────────────────────────────────────────────────
cols=""
[ -n "$COLUMNS" ] && cols="$COLUMNS"
if [ -z "$cols" ] && [ -e /dev/tty ]; then
  { cols=$(stty size </dev/tty | awk '{print $2}'); } 2>/dev/null
  { [ -z "$cols" ] && cols=$(tput cols </dev/tty); } 2>/dev/null
fi
[ -z "$cols" ] && cols=$(tput cols 2>/dev/null)
[ -z "$cols" ] && cols=80

effective=$(( cols - 4 ))

# ── Git ───────────────────────────────────────────────────────────────────────
git_branch="" git_dirty="" git_sync=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ]; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ]; then
    true
    true
  fi
fi

# ── Caveman mode (optional badge; absent if plugin not installed) ───────────────
# Reads the same flag file the caveman plugin's own statusline uses. Same hardening:
# refuse symlinks, cap at 64 bytes, strip to [a-z0-9-], whitelist the mode. If the
# flag is missing (plugin not installed) or "off", nothing renders — never breaks a
# shared statusline.
cav_label=""
cav_flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ -f "$cav_flag" ] && [ ! -L "$cav_flag" ]; then
  cav_mode=$(head -c 64 "$cav_flag" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$cav_mode" in
    lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
      cav_label=$(printf '%s' "$cav_mode" | tr '[:lower:]' '[:upper:]') ;;
  esac
fi

# ── Ponytail mode (optional badge; absent if plugin not installed or off) ────────
# Same hardening as the caveman block: flag written by ponytail's SessionStart hook
# (~/.claude/.ponytail-active), symlinks refused, 64-byte cap, [a-z0-9-] only,
# whitelisted mode. Missing flag or "off" renders nothing.
pony_label=""
pony_flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.ponytail-active"
if [ -f "$pony_flag" ] && [ ! -L "$pony_flag" ]; then
  pony_mode=$(head -c 64 "$pony_flag" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$pony_mode" in
    lite|full|ultra|review)
      pony_label=$(printf '%s' "$pony_mode" | tr '[:lower:]' '[:upper:]') ;;
  esac
fi

# ── Context bar ───────────────────────────────────────────────────────────────
ctx_bar="" ctx_pct_label="" ctx_tok_label="" bar_color="\033[32m"
if [ -n "$used_pct" ]; then
  ctx=$(printf "%.0f" "$used_pct")
  filled=$(( ctx / 10 )); empty=$(( 10 - filled ))
  bar=""
  i=0; while [ $i -lt $filled ]; do bar="${bar}■"; i=$((i+1)); done
  i=0; while [ $i -lt $empty  ]; do bar="${bar}□"; i=$((i+1)); done
  ctx_bar="$bar"; ctx_pct_label="${ctx}%"
  if   [ "$ctx" -ge 90 ]; then bar_color="\033[31m"
  elif [ "$ctx" -ge 70 ]; then bar_color="\033[91m"
  elif [ "$ctx" -ge 50 ]; then bar_color="\033[33m"
  fi
  c_ctx_min=$(printf "${bar_color}%s %s\033[0m" "$ctx_bar" "$ctx_pct_label")   # bar+pct only, for the ultra-narrow fallback below
  if [ -n "$used_tok" ] && [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
    used_k=$(( used_tok / 1000 ))
    max_k=$(( ctx_size / 1000 ))
    [ "$max_k" -ge 1000 ] && max_label="$(( max_k / 1000 ))M" || max_label="${max_k}k"
    ctx_tok_label="${used_k}k/${max_label}"
  fi
fi

# ── Rate limit ────────────────────────────────────────────────────────────────
rl_label="" rl_color="\033[32m"
if [ -n "$rl5_pct" ]; then
  rl=$(printf "%.0f" "$rl5_pct")
  if   [ "$rl" -ge 90 ]; then rl_color="\033[31m"
  elif [ "$rl" -ge 70 ]; then rl_color="\033[91m"
  elif [ "$rl" -ge 50 ]; then rl_color="\033[33m"
  fi
  rl_label="${rl}%"
  if [ -n "$rl5_rst" ] && [ "$rl5_rst" -gt 0 ] 2>/dev/null; then
    now_ts=$(date +%s)
    mins=$(( (rl5_rst - now_ts) / 60 ))
    [ "$mins" -gt 0 ] && [ "$mins" -lt 360 ] && rl_label="${rl_label} ↺${mins}m"
  fi
fi

# ── Rate limit (weekly, if plan reports it) ─────────────────────────────────────
rl7_label="" rl7_color="\033[32m"
if [ -n "$rl7_pct" ]; then
  rl7=$(printf "%.0f" "$rl7_pct")
  if   [ "$rl7" -ge 90 ]; then rl7_color="\033[31m"
  elif [ "$rl7" -ge 70 ]; then rl7_color="\033[91m"
  elif [ "$rl7" -ge 50 ]; then rl7_color="\033[33m"
  fi
  rl7_label="${rl7}%"
  if [ -n "$rl7_rst" ] && [ "$rl7_rst" -gt 0 ] 2>/dev/null; then
    now_ts=$(date +%s)
    mins7=$(( (rl7_rst - now_ts) / 60 ))
    if [ "$mins7" -gt 0 ] && [ "$mins7" -lt 10080 ]; then
      if   [ "$mins7" -ge 1440 ]; then rl7_label="${rl7_label} ↺$(( mins7 / 1440 ))d"
      elif [ "$mins7" -ge 60 ];   then rl7_label="${rl7_label} ↺$(( mins7 / 60 ))h"
      else                             rl7_label="${rl7_label} ↺${mins7}m"
      fi
    fi
  fi
fi

# ── Cost ──────────────────────────────────────────────────────────────────────
cost_label=""
if [ -n "$cost" ]; then
  cost_fmt=$(printf "%.2f" "$cost" 2>/dev/null)
  [ -n "$cost_fmt" ] && cost_label="\$${cost_fmt}"
fi

# ── Visible widths of each group ──────────────────────────────────────────────
wA_fixed=$(( ${#dir} + 4 ))
[ -n "$git_dirty" ] && wA_dirty=$(( 1 + ${#git_dirty} )) || wA_dirty=0
[ -n "$git_sync"  ] && wA_sync=$(( 2 + ${#git_sync} ))   || wA_sync=0
wA_branch_overhead=$(( 2 + 3 + wA_dirty + wA_sync ))
# Caveman badge visible width: SP(2) + 🦴(2 cols) + space(1) + label
[ -n "$cav_label" ] && wA_caveman=$(( 2 + 3 + ${#cav_label} )) || wA_caveman=0
# Ponytail badge visible width: SP(2) + 🦄(2 cols) + space(1) + label. Folded into
# wA_caveman so the branch-truncation and layout math below need no further change.
if [ -n "$pony_label" ]; then
  wA_pony=$(( 2 + 3 + ${#pony_label} ))
  # Narrow terminal: dir + both badges would overflow line 1, so drop the ponytail badge.
  if [ $(( wA_fixed + wA_caveman + wA_pony )) -gt "$cols" ]; then
    pony_label=""
  else
    wA_caveman=$(( wA_caveman + wA_pony ))
  fi
fi

wC=$(( 4 + ${#now} ))
[ -n "$rl_label" ]   && wC=$(( wC + 1 + ${#rl_label} + 2 ))
[ -n "$rl7_label" ]  && wC=$(( wC + 1 + ${#rl7_label} + 2 ))
[ -n "$cost_label" ] && wC=$(( wC + ${#cost_label} + 3 + 2 ))

# Truncate model so model+ctx+rl+cost stay on ONE line (keeps 3-row layout)
ctx_w=0
if [ -n "$ctx_bar" ]; then
  ctx_w=$(( 2 + 10 + 1 + ${#ctx_pct_label} ))
  [ -n "$ctx_tok_label" ] && ctx_w=$(( ctx_w + 1 + ${#ctx_tok_label} ))
fi
max_model=$(( effective - 4 - ctx_w - wC ))
[ "$max_model" -lt 8 ] && max_model=8
if [ ${#model} -gt "$max_model" ]; then
  model=$(printf "%.$(( max_model - 1 ))s…" "$model")
fi

wB=$(( 2 + ${#model} ))
if [ -n "$ctx_bar" ]; then
  wB=$(( wB + 2 + 10 + 1 + ${#ctx_pct_label} ))
  [ -n "$ctx_tok_label" ] && wB=$(( wB + 1 + ${#ctx_tok_label} ))
fi

# ── Branch: truncate or drop to fit line 1 ───────────────────────────────────
branch_display="$git_branch"
show_sync="$git_sync"

if [ -n "$git_branch" ]; then
  max_branch=$(( effective - wA_fixed - wA_branch_overhead - wA_caveman ))

  if [ $max_branch -lt 7 ]; then
    branch_display=""
    wA_branch_overhead=0
    w1_nosync=$(( wA_fixed + (${#git_dirty} > 0 ? 1 + ${#git_dirty} : 0) ))
    [ $(( effective - w1_nosync )) -lt $(( 2 + ${#git_sync} )) ] && show_sync=""
  elif [ $max_branch -lt ${#git_branch} ]; then
    trunc=$(( max_branch - 3 ))
    [ $trunc -lt 4 ] && trunc=4
    branch_display=$(printf "%.${trunc}s..." "$git_branch")
  fi
fi

# ── Colored segments ──────────────────────────────────────────────────────────
SP="  "

c_dir=$(printf "\033[96m📂 %s\033[0m" "$dir")

c_branch=""
if [ -n "$branch_display" ]; then
  c_branch=$(printf "\033[32m⎇ %s\033[0m" "$branch_display")
  [ -n "$git_dirty" ] && c_branch="${c_branch}$(printf " \033[33m%s\033[0m" "$git_dirty")"
fi

c_sync=""
[ -n "$show_sync" ] && c_sync=$(printf "\033[34m%s\033[0m" "$show_sync")

c_caveman=""
[ -n "$cav_label" ] && c_caveman=$(printf "\033[38;5;172m🦴 %s\033[0m" "$cav_label")

c_pony=""
[ -n "$pony_label" ] && c_pony=$(printf "\033[38;5;177m🦄 %s\033[0m" "$pony_label")

c_model=$(printf "\033[35m◆ %s\033[0m" "$model")

c_ctx=""
if [ -n "$ctx_bar" ]; then
  c_ctx=$(printf "${bar_color}%s %s\033[0m" "$ctx_bar" "$ctx_pct_label")
  [ -n "$ctx_tok_label" ] && c_ctx="${c_ctx}$(printf " \033[2m%s\033[0m" "$ctx_tok_label")"
fi

c_rl=""
if [ -n "$rl_label" ]; then
  c_rl=$(printf "${rl_color}⚡%s\033[0m" "$rl_label")
fi

c_rl7=""
if [ -n "$rl7_label" ]; then
  c_rl7=$(printf "${rl7_color}🗓️ %s\033[0m" "$rl7_label")
fi

c_cost=""
[ -n "$cost_label" ] && c_cost=$(printf "\033[32m💰 %s\033[0m" "$cost_label")

c_time=""

# ── Layout decision ───────────────────────────────────────────────────────────
wA=$(( wA_fixed + wA_branch_overhead + ${#branch_display} + (${#show_sync} > 0 ? 2 + ${#show_sync} : 0) + wA_caveman ))
wBC=$(( wB + 2 + wC ))
w1=$(( wA + 2 + wBC ))

# ── Print helpers ─────────────────────────────────────────────────────────────
print_A() {
  printf "%s" "$c_dir"
  [ -n "$c_branch"  ] && printf "%s%s" "$SP" "$c_branch"
  [ -n "$c_sync"    ] && printf "%s%s" "$SP" "$c_sync"
  [ -n "$c_caveman" ] && printf "%s%s" "$SP" "$c_caveman"
  [ -n "$c_pony"    ] && printf "%s%s" "$SP" "$c_pony"
}
print_B() {
  printf "%s" "$c_model"
  [ -n "$c_ctx" ] && printf "%s%s" "$SP" "$c_ctx"
}
print_C() {
  local first=1
  if [ -n "$c_rl" ];   then [ $first -eq 0 ] && printf "%s" "$SP"; printf "%s" "$c_rl";   first=0; fi
  if [ -n "$c_rl7" ];  then [ $first -eq 0 ] && printf "%s" "$SP"; printf "%s" "$c_rl7";  first=0; fi
  if [ -n "$c_cost" ]; then [ $first -eq 0 ] && printf "%s" "$SP"; printf "%s" "$c_cost"; first=0; fi
}

# ── Output ────────────────────────────────────────────────────────────────────
if [ "$cols" -le 36 ]; then
  # Ultra-narrow fallback: dir must itself be truncated here, and ctx only
  # shown if bar+pct actually fit — the two-row layout below already truncates
  # dir/model/branch against $effective, but this single-line path never did.
  max_dir_n=$(( cols - 3 )); [ "$max_dir_n" -lt 3 ] && max_dir_n=3
  dir_n="$dir"
  if [ ${#dir_n} -gt "$max_dir_n" ]; then
    trunc_n=$(( max_dir_n - 1 )); [ $trunc_n -lt 1 ] && trunc_n=1
    dir_n=$(printf "%.${trunc_n}s…" "$dir_n")
  fi
  printf "\033[96m📂 %s\033[0m" "$dir_n"
  if [ -n "$c_ctx_min" ]; then
    ctx_min_w=$(( 10 + 1 + ${#ctx_pct_label} ))
    used_w=$(( 3 + ${#dir_n} + 1 ))
    [ $(( cols - used_w - ctx_min_w )) -ge 0 ] && printf " %s" "$c_ctx_min"
  fi
elif [ "$wBC" -le "$effective" ]; then
  print_A; printf "\n"; print_B; printf "%s" "$SP"; print_C
else
  print_A; printf "\n"; print_B; printf "\n"; print_C
fi
