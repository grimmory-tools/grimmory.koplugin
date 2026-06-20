CREATE TABLE IF NOT EXISTS grimmory_highlights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    note TEXT,
    cfi TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    synced INTEGER DEFAULT 0,
    color TEXT,
    chapter_title TEXT
);