#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib/common.sh"

# PocketBase is loopback-only (127.0.0.1:8080); public exposure was closed off
# during the pfori-blog network hardening. Only reachable from the VPS itself.
http_check "http://127.0.0.1:8080/api/health"
