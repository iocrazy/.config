#!/usr/bin/env bash
set -euo pipefail

# hide entire right status if terminal width is below threshold
min_width=${TMUX_RIGHT_MIN_WIDTH:-90}
width=$(tmux display-message -p '#{client_width}' 2>/dev/null || true)
if [[ -z "${width:-}" || "$width" == "0" ]]; then
  width=$(tmux display-message -p '#{window_width}' 2>/dev/null || true)
fi
if [[ -z "${width:-}" || "$width" == "0" ]]; then
  width=${COLUMNS:-}
fi
if [[ -n "${width:-}" && "$width" =~ ^[0-9]+$ ]]; then
  if (( width < min_width )); then
    exit 0
  fi
fi

status_bg=$(tmux show -gqv status-bg)
if [[ -z "$status_bg" || "$status_bg" == "default" ]]; then
  status_bg=black
fi

segment_fg="#eceff4"
# Host (domain) colors to mirror left active style
host_bg="${TMUX_THEME_COLOR:-#b294bb}"
host_fg="#1d1f21"
separator=""
right_cap="█"
hostname=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'host')

# ═══════════════════════════════════════════════════════════════
# CPU/Memory segment (direct system query for macOS/Linux)
# ═══════════════════════════════════════════════════════════════
cpu_bg="#5e81ac"       # Nord blue
cpu_fg="#eceff4"
mem_bg="#a3be8c"       # Nord green
mem_fg="#2e3440"

# Get CPU and Memory usage
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS - use ps for fast CPU (sum of all processes, capped at 100%)
  cpu_raw=$(ps -A -o %cpu | awk '{s+=$1} END {print s}' 2>/dev/null || echo "0")
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
  cpu_avg=$(awk "BEGIN {v=$cpu_raw/$cores; if(v>100) v=100; printf \"%.0f\", v}" 2>/dev/null || echo "0")
  cpu_pct="${cpu_avg}%"

  # Memory: use memory_pressure (most reliable on macOS)
  mem_pct=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage:/ {printf "%.0f%%", 100-$5}' || echo "")

  # Fallback to vm_stat if memory_pressure fails
  if [[ -z "$mem_pct" ]]; then
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo "4096")
    total_mem=$(sysctl -n hw.memsize 2>/dev/null || echo "0")

    # Parse vm_stat more carefully
    pages_active=$(vm_stat 2>/dev/null | awk -F: '/Pages active/ {gsub(/[^0-9]/,"",$2); print $2}')
    pages_wired=$(vm_stat 2>/dev/null | awk -F: '/Pages wired/ {gsub(/[^0-9]/,"",$2); print $2}')

    pages_active=${pages_active:-0}
    pages_wired=${pages_wired:-0}

    if [[ "$pages_active" =~ ^[0-9]+$ && "$pages_wired" =~ ^[0-9]+$ && "$total_mem" -gt 0 ]]; then
      used_mem=$(( (pages_active + pages_wired) * page_size ))
      mem_pct=$(awk "BEGIN {printf \"%.0f%%\", ($used_mem / $total_mem) * 100}" 2>/dev/null || echo "")
    fi
  fi
else
  # Linux
  cpu_pct=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5); printf "%.0f%%", usage}' 2>/dev/null || echo "")
  mem_pct=$(free | awk '/Mem:/ {printf "%.0f%%", $3/$2*100}' 2>/dev/null || echo "")
fi

sysinfo_segment=""
if [[ -n "$cpu_pct" || -n "$mem_pct" ]]; then
  # CPU segment
  sysinfo_segment+=$(printf '#[fg=%s,bg=%s]%s' "$cpu_bg" "$status_bg" "$separator")
  sysinfo_segment+=$(printf '#[fg=%s,bg=%s]  %s ' "$cpu_fg" "$cpu_bg" "${cpu_pct:-N/A}")

  # Memory segment
  sysinfo_segment+=$(printf '#[fg=%s,bg=%s]%s' "$mem_bg" "$cpu_bg" "$separator")
  sysinfo_segment+=$(printf '#[fg=%s,bg=%s]  %s ' "$mem_fg" "$mem_bg" "${mem_pct:-N/A}")
fi

# ═══════════════════════════════════════════════════════════════
# Notes count for current window (red if > 0, hidden otherwise)
# ═══════════════════════════════════════════════════════════════
notes_segment=""
notes_count_script="$HOME/.config/tmux/tmux-status/notes_count.sh"
if [[ -x "$notes_count_script" ]]; then
  notes_output=$("$notes_count_script" 2>/dev/null || true)
  if [[ -n "$notes_output" ]]; then
    notes_connector_bg="$status_bg"
    if [[ -n "$sysinfo_segment" ]]; then
      notes_connector_bg="$mem_bg"
    fi
    notes_bg="#cc6666"
    notes_fg="#1d1f21"
    notes_segment=$(printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s,bold] %s #[default]' \
      "$notes_bg" "$notes_connector_bg" "$separator" \
      "$notes_fg" "$notes_bg" "$notes_output")
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Hostname segment
# ═══════════════════════════════════════════════════════════════
host_connector_bg="$status_bg"
if [[ -n "$notes_segment" ]]; then
  host_connector_bg="#cc6666"
elif [[ -n "$sysinfo_segment" ]]; then
  host_connector_bg="$mem_bg"
fi
host_prefix=$(printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s] ' \
  "$host_bg" "$host_connector_bg" "$separator" \
  "$host_fg" "$host_bg")

# ═══════════════════════════════════════════════════════════════
# Output: [CPU] [MEM] [Notes] [Hostname]
# ═══════════════════════════════════════════════════════════════
printf '%s%s%s%s #[fg=%s,bg=%s]%s' \
  "$sysinfo_segment" \
  "$notes_segment" \
  "$host_prefix" \
  "$hostname" \
  "$host_bg" "$status_bg" "$right_cap"
