Requirements

I need a small web app that can run on my phone. It serves as watchdog for my blog pfori-blog that runs on my Hetzner vps under exvestigate.com. It should check every 5 minutes (configurable) if everything is still working. It needs to check in version one: if the site is still up, if the quiz module (pfori-quiz) is still working, if Pocketbase is up and running. 

My idea is to create a dir on the VPS under /var/www/project-xv/ called watchdog. In the main directory is the webapp and a script that is called every 5 minutes. The script runs all scripts in the subdir /scripts. Each script checks a specific part of my setup and writes the results to a standard logfile for exvestigate.com.

The web app can read the logfile and show things in a simple dashboard. Each part of the setup is green or red via a traffic light. Best is when errors in the logfile are pushed to the app or the app refreshes often. 

## Implementation status

Built as described, with a few decisions made along the way:

- **Checks vs. dashboard split.** `scripts/check-*.sh` are dependency-free bash+curl scripts (one per thing checked, easy to add more); `run-checks.js` (Node) orchestrates them and owns JSON output (`watchdog.log` audit trail + atomic `status.json` snapshot) rather than hand-rolling JSON in bash, which is error-prone. The dashboard (`app/`) is a separate Express process/systemd service from the Astro blog on purpose — a watchdog sharing fate with the thing it watches isn't much of a watchdog.
- **Checks run on the VPS itself**, since PocketBase (`127.0.0.1:8080`) and the quiz binary (`127.0.0.1:8090`) are loopback-only.
- **v1 scope, per discussion:** no push notifications (polling dashboard only, refreshes every 30s), simple HTTP basic auth via Caddy (not app code) since the dashboard is reachable at a public path (`exvestigate.com/watchdog/`), and current-status-only in the UI (no history browsing — raw history still lives in `watchdog.log` on the VPS).
- **Check interval** (default 5 min) is a systemd timer (`deploy/watchdog-checks.timer`'s `OnUnitActiveSec`), not a live-reloadable app setting — changing it means editing that file and redeploying.
- **Staleness detection**: since there's no push, the dashboard flags `status.json` as stale if its `run_ts` is older than `WATCHDOG_STALE_AFTER_MS`, so a dead timer/service reads as "unknown," not a false green.

See [README.md](README.md) for setup, configuration, and deployment.

### Deployment incidents (2026-09-13, initial VPS rollout)

- **Caddyfile `basic_auth` directive name.** The snippet originally used `basic_auth`, but this VPS runs Caddy 2.6.2, which uses the older `basicauth` (no underscore) — newer Caddy releases renamed it. `systemctl reload caddy` correctly refused to apply the broken config (validation runs before swap) and kept the old process serving throughout, so `exvestigate.com` itself was never actually down — the "site hangs" report during this was a stale client-side connection, not a real outage. Fixed in both the live Caddyfile and `deploy/Caddyfile.snippet`.
- **Bare `/watchdog` (no trailing slash) 404'd instead of prompting for auth.** `handle_path /watchdog/*` only matches paths that already have the trailing slash before the wildcard, so `/watchdog` fell through to the site's normal `reverse_proxy 127.0.0.1:3000` (Astro) and got a 404 from there instead of the basic-auth prompt. Fixed by adding `redir /watchdog /watchdog/ permanent` ahead of the `handle_path` block, in both the live config and the snippet.
- **`.env` initially created in the wrong directory** on the VPS (not `/var/www/project-xv/watchdog/.env`, where `app/server.js` and the systemd `EnvironmentFile=` both expect it) — moved to the correct path.
- **`watchdog-app.service` crash-looped** (`env: 'node': Permission denied`, exit 126) under its original `User=www-data`: `/usr/bin/node` on this VPS is a symlink into `/root/.nvm/...`, and `/root` isn't traversable by other users. Every other Node process on the box already runs as root for the same reason (`quiz.service`, the pm2-run `astro-frontend`) — changed `deploy/watchdog-app.service` to `User=root` to match.
- **`duration_ms` in check results was nonsense** (values in the tens of millions instead of plausible milliseconds). Cause: this VPS's `date` is `uutils coreutils`, whose `%N` ignores GNU date's `%3N` width-truncation and always returns the full 9-digit nanosecond value — `date +%s%3N` produced a 19-digit number, not epoch-milliseconds. Fixed by dropping the `date`-based timing in `scripts/lib/common.sh` in favor of curl's own `%{time_total}`, which sidesteps the coreutils difference and is more accurate (measures only the request, not shell overhead).

### v1.1: fourth check (memory) + dashboard clarity fixes

- **Added `memory` check** (`scripts/check-memory.sh`, `memory_check` in `common.sh`): reads `/proc/meminfo` directly (`MemAvailable`, not raw `MemFree`, since Linux counts reclaimable cache as free-ish), fails below `WATCHDOG_MEM_MIN_AVAILABLE_PCT` (default 10%). Confirms the "drop a script in `scripts/`, nothing else changes" design actually holds — no changes needed to `run-checks.js` or the dashboard for a new check to appear.
- **Found while wiring it up: `watchdog-checks.service` never had `EnvironmentFile=`** set, unlike `watchdog-app.service` — so `WATCHDOG_TIMEOUT`/`WATCHDOG_SCRIPT_TIMEOUT_MS` (and now the new memory threshold) were documented in `.env.example` but silently ignored by the actual timer-triggered checks. Fixed by adding the same `EnvironmentFile=-/var/www/project-xv/watchdog/.env` line to `watchdog-checks.service`.
- **Dashboard refresh button felt unresponsive on mobile**: no `:active` state and no signal distinguishing "refreshed, but data is identical" from "did nothing" (two checks 5 minutes apart produce byte-identical JSON between real check runs). Added tap feedback, a disabled "Refreshing…" state, and a "Checked for updates at HH:MM:SS" line that updates on every tap regardless of whether the check data changed.
- **Follow-up confusion: per-check "Xm ago" text looked frozen** across refreshes. That's correct — it reflects when that check last actually ran (every 5 min), not the page refresh. Added the absolute time next to it so it reads as a fixed timestamp rather than an apparently-broken live counter.
