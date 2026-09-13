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
