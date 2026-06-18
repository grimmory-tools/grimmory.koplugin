CREATE TABLE IF NOT EXISTS grimmory_highlights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id TEXT NOT NULL,
    text TEXT NOT NULL,
    note TEXT,
    cfi TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    synced INTEGER DEFAULT 0
);