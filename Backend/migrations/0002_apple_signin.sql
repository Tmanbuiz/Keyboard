CREATE TABLE IF NOT EXISTS apple_accounts (
  subject_hash TEXT PRIMARY KEY,
  client_id TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS account_sessions (
  token_hash TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_by_client ON account_sessions(client_id);
CREATE TABLE IF NOT EXISTS auth_challenges (
  id TEXT PRIMARY KEY,
  nonce_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
