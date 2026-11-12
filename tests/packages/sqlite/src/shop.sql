-- the schema the sql provider reads for tests/packages/sqlite (rows = "sqlite")
CREATE TABLE customers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  credit REAL NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT 1,
  badge BLOB
);
