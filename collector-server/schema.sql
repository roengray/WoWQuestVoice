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
