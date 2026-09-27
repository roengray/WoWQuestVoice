CREATE TABLE IF NOT EXISTS quest_texts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    locale TEXT NOT NULL,
    quest_id INTEGER NOT NULL,
    section TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    client_build TEXT NOT NULL DEFAULT '',
    addon_version TEXT NOT NULL DEFAULT '',
    first_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    submission_count INTEGER NOT NULL DEFAULT 1,
    UNIQUE(locale, quest_id, section, text_hash)
);

CREATE INDEX IF NOT EXISTS idx_quest_texts_quest
    ON quest_texts(locale, quest_id, section);

CREATE INDEX IF NOT EXISTS idx_quest_texts_last_seen
    ON quest_texts(last_seen);

-- Public installers intentionally contain no shared secret. The Worker turns
-- each source address into a server-keyed, date-scoped HMAC and stores only
-- that anonymous bucket for abuse throttling.
CREATE TABLE IF NOT EXISTS upload_rate_limits (
    bucket TEXT PRIMARY KEY,
    window_start INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    record_count INTEGER NOT NULL DEFAULT 0,
    expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_upload_rate_limits_expires
    ON upload_rate_limits(expires_at);
