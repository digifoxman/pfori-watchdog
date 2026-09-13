#!/usr/bin/env node
'use strict';

// Runs every scripts/check-*.sh, appends one JSON-line result per check to
// watchdog.log, and writes an atomic status.json snapshot of the latest
// result per check for the dashboard app to read.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = __dirname;
const SCRIPTS_DIR = path.join(ROOT, 'scripts');
const LOG_FILE = process.env.WATCHDOG_LOG_FILE || path.join(ROOT, 'watchdog.log');
const STATUS_FILE = process.env.WATCHDOG_STATUS_FILE || path.join(ROOT, 'status.json');
const SCRIPT_TIMEOUT_MS = Number(process.env.WATCHDOG_SCRIPT_TIMEOUT_MS || 10000);

function nowIso() {
  return new Date().toISOString();
}

function runCheck(scriptPath) {
  const name = path.basename(scriptPath, '.sh').replace(/^check-/, '');
  const ts = nowIso();
  const result = spawnSync(scriptPath, [], {
    timeout: SCRIPT_TIMEOUT_MS,
    encoding: 'utf8',
  });

  if (result.error || result.status !== 0) {
    const reason = result.error
      ? result.error.message
      : `exit code ${result.status}${result.stderr ? `: ${result.stderr.trim()}` : ''}`;
    return { name, ts, status: 'fail', duration_ms: null, message: `check script failed (${reason})` };
  }

  const line = (result.stdout || '').trim().split('\n').pop() || '';
  const [status, durationRaw, ...messageParts] = line.split('\t');
  const duration_ms = Number(durationRaw);

  if (status !== 'ok' && status !== 'fail') {
    return { name, ts, status: 'fail', duration_ms: null, message: `malformed check output: ${JSON.stringify(line)}` };
  }

  return {
    name,
    ts,
    status,
    duration_ms: Number.isFinite(duration_ms) ? duration_ms : null,
    message: messageParts.join('\t'),
  };
}

function main() {
  const scripts = fs
    .readdirSync(SCRIPTS_DIR)
    .filter((f) => f.startsWith('check-') && f.endsWith('.sh'))
    .sort()
    .map((f) => path.join(SCRIPTS_DIR, f));

  const results = scripts.map(runCheck);

  const logLines = results.map((r) => JSON.stringify(r)).join('\n') + '\n';
  fs.appendFileSync(LOG_FILE, logLines);

  const status = {
    run_ts: nowIso(),
    checks: Object.fromEntries(
      results.map((r) => [r.name, { status: r.status, message: r.message, duration_ms: r.duration_ms, ts: r.ts }])
    ),
  };

  const tmpFile = `${STATUS_FILE}.tmp`;
  fs.writeFileSync(tmpFile, JSON.stringify(status, null, 2));
  fs.renameSync(tmpFile, STATUS_FILE);

  const failed = results.filter((r) => r.status !== 'ok');
  if (failed.length > 0) {
    console.error(`watchdog: ${failed.length} check(s) failed: ${failed.map((r) => r.name).join(', ')}`);
    process.exitCode = 1;
  }
}

main();
