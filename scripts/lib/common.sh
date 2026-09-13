# shared helpers for watchdog check scripts. Sourced, not executed.

TIMEOUT="${WATCHDOG_TIMEOUT:-5}"

# http_check URL [EXPECT_SUBSTRING]
# Curls URL and prints a single TSV line to stdout: "<ok|fail>\t<duration_ms>\t<message>"
# ok requires an HTTP 2xx/3xx status, and (if given) EXPECT_SUBSTRING present in the body.
http_check() {
  local url=$1 expect=${2:-}
  local body http_code time_total duration_ms err_file curl_exit err

  # Ask curl for its own timing (%{time_total}, seconds with fractional part)
  # rather than wrapping the call in our own `date` calls - this VPS's `date`
  # is uutils coreutils, whose %N ignores GNU's %3N width truncation and
  # returns full nanoseconds, silently producing bogus millisecond deltas.
  err_file=$(mktemp)
  if body=$(curl -sS --max-time "$TIMEOUT" -o - -w $'\n%{http_code}\n%{time_total}' "$url" 2>"$err_file"); then
    curl_exit=0
  else
    curl_exit=$?
  fi

  time_total=$(printf '%s' "$body" | tail -n1)
  duration_ms=$(awk -v t="$time_total" 'BEGIN { printf "%d", t * 1000 }' 2>/dev/null)
  duration_ms=${duration_ms:-0}
  body=$(printf '%s' "$body" | sed '$d')

  if [[ $curl_exit -ne 0 ]]; then
    err=$(tr '\n' ' ' < "$err_file")
    rm -f "$err_file"
    printf 'fail\t%s\tcurl error (exit %s): %s\n' "$duration_ms" "$curl_exit" "${err:-unknown}"
    return 0
  fi
  rm -f "$err_file"

  http_code=$(printf '%s' "$body" | tail -n1)
  body=$(printf '%s' "$body" | sed '$d')

  if (( http_code < 200 || http_code >= 400 )); then
    printf 'fail\t%s\tHTTP %s\n' "$duration_ms" "$http_code"
    return 0
  fi

  if [[ -n "$expect" && "$body" != *"$expect"* ]]; then
    printf 'fail\t%s\tHTTP %s but response missing expected content\n' "$duration_ms" "$http_code"
    return 0
  fi

  printf 'ok\t%s\tHTTP %s\n' "$duration_ms" "$http_code"
}

# memory_check
# Reads /proc/meminfo directly (no `free` dependency) and prints a TSV
# result line, failing if available memory drops below
# WATCHDOG_MEM_MIN_AVAILABLE_PCT (default 10%). Uses MemAvailable, not raw
# MemFree, since Linux counts reclaimable cache/buffers as free-ish memory
# that MemFree alone would wrongly flag as "used".
memory_check() {
  local min_pct="${WATCHDOG_MEM_MIN_AVAILABLE_PCT:-10}"
  local mem_total_kb mem_avail_kb avail_pct total_mb avail_mb used_mb message

  mem_total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  mem_avail_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)

  if [[ -z "$mem_total_kb" || -z "$mem_avail_kb" ]]; then
    printf 'fail\t0\tcould not read /proc/meminfo\n'
    return 0
  fi

  total_mb=$((mem_total_kb / 1024))
  avail_mb=$((mem_avail_kb / 1024))
  used_mb=$((total_mb - avail_mb))
  avail_pct=$(awk -v a="$mem_avail_kb" -v t="$mem_total_kb" 'BEGIN { printf "%.1f", (a / t) * 100 }')
  message="${used_mb}MB/${total_mb}MB used, ${avail_mb}MB available (${avail_pct}% free)"

  if awk -v p="$avail_pct" -v m="$min_pct" 'BEGIN { exit !(p < m) }'; then
    printf 'fail\t0\t%s\n' "$message"
  else
    printf 'ok\t0\t%s\n' "$message"
  fi
}
