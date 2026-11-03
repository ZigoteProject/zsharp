-- a small schema, SQLite's dialect (0001): a table per record
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  "signed-up" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  score REAL,
  active BOOLEAN NOT NULL DEFAULT 1
);

/* orders reference users; the primary key is at the table's level */
CREATE TABLE IF NOT EXISTS orders (
  id INTEGER,
  user_id INTEGER NOT NULL REFERENCES users(id),
  total NUMERIC(10, 2) NOT NULL,
  note VARCHAR(255),
  payload BLOB,
  PRIMARY KEY (id),
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX orders_by_user ON orders (user_id);
