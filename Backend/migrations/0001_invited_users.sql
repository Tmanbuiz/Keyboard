CREATE TABLE IF NOT EXISTS clients (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  daily_limit INTEGER NOT NULL CHECK (daily_limit BETWEEN 1 AND 1000),
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS usage_events (
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  day TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS usage_by_day ON usage_events(day);
CREATE INDEX IF NOT EXISTS usage_by_client_day ON usage_events(client_id, day);
