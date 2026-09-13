#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

# Quiz binary is loopback-only (127.0.0.1:8090), normally reached only via the
# Astro proxy. This runs on the VPS itself, so it can hit it directly.
http_check "http://127.0.0.1:8090/api/quiz/status?userId=watchdog&role=visitor" '"level"'
