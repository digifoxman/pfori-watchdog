'use strict';

const path = require('path');
const fs = require('fs');
const express = require('express');

const PORT = process.env.WATCHDOG_APP_PORT || 8091;
const HOST = process.env.WATCHDOG_APP_HOST || '127.0.0.1';
const STATUS_FILE = process.env.WATCHDOG_STATUS_FILE || path.join(__dirname, '..', 'status.json');
const STALE_AFTER_MS = Number(process.env.WATCHDOG_STALE_AFTER_MS || 15 * 60 * 1000);

const app = express();

app.get('/api/status', (req, res) => {
  let raw;
  try {
    raw = fs.readFileSync(STATUS_FILE, 'utf8');
  } catch (err) {
    res.status(503).json({ error: 'status file not found yet - checks may not have run', detail: err.code });
    return;
  }

  let data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    res.status(500).json({ error: 'status file is corrupt' });
    return;
  }

  const ageMs = Date.now() - new Date(data.run_ts).getTime();
  data.age_ms = ageMs;
  data.stale = ageMs > STALE_AFTER_MS;

  res.json(data);
});

app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, HOST, () => {
  console.log(`watchdog dashboard listening on ${HOST}:${PORT}`);
});
