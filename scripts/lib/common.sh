# shared helpers for watchdog check scripts. Sourced, not executed.

TIMEOUT="${WATCHDOG_TIMEOUT:-5}"

# http_check URL [EXPECT_SUBSTRING]
# Curls URL and prints a single TSV line to stdout: "<ok|fail>\t<duration_ms>\t<message>"
# ok requires an HTTP 2xx/3xx status, and (if given) EXPECT_SUBSTRING present in the body.
http_check() {
  local url=$1 expect=${2:-}
  local start end duration_ms body http_code err_file curl_exit err

  err_file=$(mktemp)
  start=$(date +%s%3N)
  if body=$(curl -sS --max-time "$TIMEOUT" -o - -w $'\n%{http_code}' "$url" 2>"$err_file"); then
    curl_exit=0
  else
    curl_exit=$?
  fi
  end=$(date +%s%3N)
  duration_ms=$((end - start))

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
