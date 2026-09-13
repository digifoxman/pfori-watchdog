# pfori-watchdog

Uptime watchdog for [pfori-blog](https://exvestigate.com) and its backing
services (pfori-quiz, PocketBase), running on the same Hetzner VPS as the
things it monitors. See [design.md](design.md) for the full requirements and
architecture discussion.

## How it works

- `scripts/check-*.sh` — one script per thing being checked. Each is a
  standalone curl call with a timeout; add a new one by dropping a
  `check-<name>.sh` file in `scripts/` (source `scripts/lib/common.sh` for the
  `http_check URL [EXPECT_SUBSTRING]` helper). No other file needs to change.
- `run-checks.js` — runs every `check-*.sh`, appends one JSON-line result per
  check to `watchdog.log` (audit trail), and atomically writes `status.json`
  (latest result per check — this is what the dashboard reads).
- `app/` — a small Express app that serves `status.json` at `/api/status` and
  a static mobile-first dashboard at `/`.

Checks run **on the VPS itself**, because PocketBase (`127.0.0.1:8080`) and
the quiz binary (`127.0.0.1:8090`) are loopback-only and not reachable from
outside.

The dashboard app is a separate process from the Astro blog on purpose: if
the blog's Node process crashes, the watchdog (and its ability to report that
crash) must stay up.

## Checks (v1)

| Check | What it does |
|---|---|
| `site` | `GET https://exvestigate.com/`, expects HTTP 2xx/3xx |
| `quiz` | `GET http://127.0.0.1:8090/api/quiz/status?...`, expects HTTP 2xx and `"level"` in the body |
| `pocketbase` | `GET http://127.0.0.1:8080/api/health`, expects HTTP 2xx |

## Local development

```bash
# run the checks once (quiz/pocketbase will fail off the VPS - expected,
# since they're loopback-only there)
node run-checks.js
cat status.json

# run the dashboard
cd app
npm install
npm start
# open http://127.0.0.1:8091
```

## Configuration

Environment variables (see `.env.example`):

| Var | Purpose | Default |
|---|---|---|
| `WATCHDOG_APP_PORT` | Port the dashboard listens on | `8091` |
| `WATCHDOG_APP_HOST` | Host the dashboard binds to | `127.0.0.1` |
| `WATCHDOG_STALE_AFTER_MS` | Age after which the dashboard flags results as stale | `900000` (15 min) |
| `WATCHDOG_TIMEOUT` | Per-curl timeout (seconds) | `5` |
| `WATCHDOG_SCRIPT_TIMEOUT_MS` | Per-check-script wall-clock timeout (ms) | `10000` |

The check interval (default 5 minutes) is set in
`deploy/watchdog-checks.timer`'s `OnUnitActiveSec` — it's not read from an env
var, since systemd timers aren't dynamically configurable. Changing it means
editing that file and redeploying.

## Deployment

Requires the `projectxv` SSH alias (see pfori-vps) and an existing
`/var/www/project-xv/` on the VPS.

```bash
scripts/deploy.sh
```

This rsyncs `scripts/`, `run-checks.js` and `app/` to
`/var/www/project-xv/watchdog/`, runs `npm install` there, installs the
systemd units from `deploy/`, and enables/restarts them.

First-time setup on the VPS (not handled by `deploy.sh`, since it's a
one-off with no secrets to template):

1. Create `/var/www/project-xv/watchdog/.env` from `.env.example`.
2. Add the [Caddy snippet](deploy/Caddyfile.snippet) to the existing
   `exvestigate.com` site block, generating a password hash with
   `caddy hash-password`, then `systemctl reload caddy`.
3. Run `scripts/deploy.sh`.

Dashboard is then reachable at `https://exvestigate.com/watchdog/` behind
basic auth.

## Known limitations (v1)

- No push notifications — the dashboard is polling-only, you have to open it.
- No history — only the latest result per check is shown (raw history is
  still in `watchdog.log` on the VPS if needed for debugging).
- Changing the check interval requires editing a systemd unit and
  redeploying, not a running config value.
