#!/usr/bin/env bash
# Claude Code status line: model, context vs compaction window, cache state, plan limits.
# Invoked as `bash ~/.claude/statusline.sh`; stdin is the session JSON documented at
# code.claude.com/docs/en/statusline. Every field is optional, so each read has a fallback.
input=$(cat)
win=$(jq -r '.autoCompactWindow // 200000' ~/.claude/settings.json 2>/dev/null || echo 200000)
IFS=$'\t' read -r model effort ctx pct warm ttl hit five five_reset week <<<"$(printf '%s' "$input" | jq -r --argjson win "$win" '
  def n: if . == null then 0 else . end;
  [
    (.model.display_name // "?"),
    (.effort.level // "-"),
    (.context_window.total_input_tokens | n),
    (((.context_window.total_input_tokens | n) * 100 / $win) | floor),
    (if .prompt_cache.warm == true then "warm" elif .prompt_cache.caching_observed == true then "cold" else "-" end),
    (.prompt_cache.ttl // "-"),
    (if .prompt_cache.hit_ratio == null then "-" else ((.prompt_cache.hit_ratio * 100) | floor | tostring) + "%" end),
    (.rate_limits.five_hour.used_percentage // "-"),
    (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.used_percentage // "-")
  ] | @tsv' 2>/dev/null)"
[ -n "$model" ] || { echo "claude"; exit 0; }
esc=$'\033'; reset="${esc}[0m"; dim="${esc}[2m"
if   [ "${pct:-0}" -ge 75 ]; then col="${esc}[31m"
elif [ "${pct:-0}" -ge 50 ]; then col="${esc}[33m"
else col="${esc}[32m"; fi
ctx_k=$(( ctx / 1000 )); win_k=$(( win / 1000 ))
until=""
if [ "${five_reset:-0}" -gt 0 ]; then
  secs=$(( five_reset - $(date +%s) )); [ $secs -lt 0 ] && secs=0
  until=" (resets in $((secs/3600))h $(( (secs%3600)/60 ))m)"
fi
five_s="${five%.*}"; week_s="${week%.*}"
cache="$warm"; [ "$hit" != "-" ] && cache="$warm $hit"
printf '%s %s · %s%dk/%dk %d%%%s · cache %s · 5h %s%%%s · week %s%%\n' \
  "$model" "$effort" "$col" "$ctx_k" "$win_k" "$pct" "$reset" \
  "$cache" "${five_s:--}" "$until" "${week_s:--}"
