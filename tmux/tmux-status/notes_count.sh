#!/usr/bin/env bash
set -euo pipefail

window_id=$(tmux display-message -p '#{window_id}' 2>/dev/null || true)
[[ -z "$window_id" ]] && exit 0

CACHE_FILE="/tmp/tmux-tracker-cache.json"
[[ ! -f "$CACHE_FILE" ]] && exit 0

state=$(cat "$CACHE_FILE" 2>/dev/null || true)
[[ -z "$state" ]] && exit 0

# Count notes visible in current window:
# - scope=window AND window_id matches
# - scope=session AND session_id matches
# - scope=all OR (scope is empty/null AND no window_id AND no session_id) = Global
session_id=$(tmux display-message -p '#{session_id}' 2>/dev/null || true)
count=$(echo "$state" | jq -r --arg wid "$window_id" --arg sid "$session_id" '
  [.notes // [] | .[] | select(
    .archived != true and
    .completed != true and
    (
      (.scope == "window" and .window_id == $wid) or
      (.scope == "session" and .session_id == $sid) or
      (.scope == "all") or
      ((.scope == null or .scope == "") and (.window_id == null or .window_id == "") and (.session_id == null or .session_id == ""))
    )
  )] | length
' 2>/dev/null || echo "0")

if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
  printf ' %s ' "$count"
fi
