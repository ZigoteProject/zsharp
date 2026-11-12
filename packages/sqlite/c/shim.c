// SQLite as this package builds it: the amalgamation (sqlite3.c, unmodified) with the options
// its documentation recommends for an application, and the few calls Z# can't write itself
// (SQLITE_TRANSIENT is a cast of -1 to a function pointer; an output parameter per handle).
#define SQLITE_THREADSAFE 1             // serialized: a connection may be used from any thread
#define SQLITE_DQS 0                    // "text" is an identifier, never a string
#define SQLITE_DEFAULT_FOREIGN_KEYS 1   // foreign keys are enforced
#define SQLITE_OMIT_LOAD_EXTENSION 1    // no code loaded from a file a query names
#define SQLITE_OMIT_DEPRECATED 1
#define SQLITE_OMIT_SHARED_CACHE 1
#define SQLITE_LIKE_DOESNT_MATCH_BLOBS 1
#define SQLITE_MAX_EXPR_DEPTH 0

#include "sqlite3.c"

// Opens the database at path (UTF-8, NUL-terminated) with sqlite3_open_v2's flags and a busy
// timeout in milliseconds. *out is the connection even on a failure (for sqlite3_errmsg, then
// sqlite3_close_v2), or NULL when there was no memory for one.
int zs_sqlite_open(const char *path, int flags, int busy_ms, sqlite3 **out) {
    int rc = sqlite3_open_v2(path, out, flags | SQLITE_OPEN_EXRESCODE, NULL);
    if (rc == SQLITE_OK) rc = sqlite3_busy_timeout(*out, busy_ms);
    return rc;
}

// Compiles the one statement in sql[0..n). More text after it than spaces and semicolons is
// -1 (no SQLite code) with *out NULL: the rest would otherwise be dropped with nothing said.
// Text with no statement in it is SQLITE_OK with *out NULL.
int zs_sqlite_prepare(sqlite3 *db, const char *sql, size_t n, sqlite3_stmt **out) {
    const char *text = n ? sql : "";
    const char *tail = NULL;
    *out = NULL;
    if (n > 0x7fffffff) return SQLITE_TOOBIG;
    int rc = sqlite3_prepare_v2(db, text, (int)n, out, &tail);
    if (rc != SQLITE_OK) return rc;
    for (const char *end = text + n; *out && tail && tail < end; tail++) {
        if (*tail != ' ' && *tail != '\t' && *tail != '\n' && *tail != '\r' && *tail != ';') {
            sqlite3_finalize(*out);
            *out = NULL;
            return -1;
        }
    }
    return SQLITE_OK;
}

// Binds a copy of the n bytes at p as text (UTF-8) or as a blob. An empty one is "" or a
// zero-length blob, not NULL, which a NULL pointer would bind.
int zs_sqlite_bind_text(sqlite3_stmt *s, int i, const char *p, size_t n) {
    return sqlite3_bind_text64(s, i, n ? p : "", n, SQLITE_TRANSIENT, SQLITE_UTF8);
}

int zs_sqlite_bind_blob(sqlite3_stmt *s, int i, const unsigned char *p, size_t n) {
    return sqlite3_bind_blob64(s, i, n ? (const void *)p : (const void *)"", n, SQLITE_TRANSIENT);
}
