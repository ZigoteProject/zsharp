// Z# runtime: allocation, panics, strings. Linked into every Z# program.
#define _GNU_SOURCE
#include <inttypes.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#ifdef __GLIBC__
#include <execinfo.h> // backtraces; musl (cross-compiled builds) has none
#endif

// Every heap object starts with an int64 reference count: 1+ = live, 0 = static (never freed).
// zs_int: Z#'s int, the machine word (also the header fields of every heap object)
typedef intptr_t zs_int;

typedef struct {
    zs_int rc;
    zs_int len;
    char data[]; // len bytes + NUL
} zs_str;

static int64_t live; // objects currently allocated, reported at exit when ZS_LEAKCHECK is set

// counting objects: atomic when the program runs code on Task.blocking's helper thread (the
// driver compiles this file with ZS_THREADS then), plain otherwise
#ifdef ZS_THREADS
#define COUNT(x, d) __atomic_fetch_add(&(x), (d), __ATOMIC_RELAXED)
#else
#define COUNT(x, d) ((x) += (d))
#endif

// A panic stops the program at once (no cleanup) with exit status 134, like abort() but without
// a core dump, so system crash reporters don't flag every panic. ZS_ABORT=1 aborts for real
// (a core file for a debugger).
static _Noreturn void stop(void) {
    if (getenv("ZS_ABORT")) abort();
    _exit(134);
}

// a C host's function, run on a panic before the process stops (zs_set_panic_hook)
static void (*panic_hook)(const char *message);

void zs_set_panic_hook(void (*hook)(const char *message)) { panic_hook = hook; }

_Noreturn void zs_panic_c(const char *msg) {
    fflush(stdout);
    fprintf(stderr, "panic: %s\n", msg);
#ifdef __GLIBC__
    const char *bt = getenv("ZS_BACKTRACE");
    if (!bt || strcmp(bt, "0") != 0) {
        void *frames[64];
        int n = backtrace(frames, 64);
        backtrace_symbols_fd(frames + 1, n - 1, 2);
    }
#endif
    void (*hook)(const char *) = panic_hook;
    panic_hook = NULL; // a panic inside the hook stops at once
    if (hook) hook(msg);
    stop();
}

_Noreturn void zs_panic(zs_str *msg) { zs_panic_c(msg->data); }

static int64_t allocations, mallocs;

void *zs_alloc(zs_int size) {
    void *p = malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    COUNT(live, 1);
    COUNT(allocations, 1);
    COUNT(mallocs, 1);
    return p;
}

/// Runtime.allocations (): heap objects allocated so far (tests check copy-on-write with it).
zs_int zs_allocations(void) { return allocations; }

/// Runtime.mallocs (): the times memory was taken from the system allocator, for an object or
/// for an arena's block.
zs_int zs_mallocs(void) { return mallocs; }

// Ptr.alloc / Ptr.free: C memory for n elements of a size, zeroed
void *zs_ptr_alloc(zs_int n, zs_int size) {
    if (n < 0) zs_panic_c("Ptr.alloc: negative count");
    void *p = calloc((size_t)(n ? n : 1), (size_t)size);
    if (!p) zs_panic_c("out of memory");
    return p;
}

void zs_ptr_free(void *p) { free(p); }

#include <time.h>
/// Runtime.ticks (): a monotonic clock in nanoseconds (on a Cortex-M: SysTick counts).
int64_t zs_ticks(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

void zs_free(void *p) {
    COUNT(live, -1);
    free(p);
}

// ---- handles: a Z# object held by C (zs_handle in a generated header). A handle has a count of
// its own (zs_retain, zs_release) and holds one reference to the object, which the object's drop
// function gives up when the handle's last reference goes.
typedef struct {
    zs_int rc;
    void (*drop)(void *);
    void *obj;
} zs_handle;

zs_handle *zs_handle_new(void *obj, void (*drop)(void *)) {
    zs_handle *h = zs_alloc((zs_int)sizeof(zs_handle));
    h->rc = 1;
    h->drop = drop;
    h->obj = obj;
    return h;
}

// the object, with a new reference for Z#
void *zs_handle_get(zs_handle *h) {
    if (!h) zs_panic_c("a null zs_handle was passed to Z#");
    zs_int *rc = h->obj;
    if (*rc > 0) (*rc)++;
    return h->obj;
}

void zs_retain(zs_handle *h) {
    if (h) h->rc++;
}

void zs_release(zs_handle *h) {
    if (!h || --h->rc > 0) return;
    void *obj = h->obj;
    void (*drop)(void *) = h->drop;
    zs_free(h);
    drop(obj);
}

// ---- a table from addresses to pointers (open addressing, linear probing), for weak references
// and arenas. Its memory is the C library's, and goes when the table is empty again.
typedef struct {
    void **keys, **vals;
    size_t cap, count;
} ptrtab;

// Fibonacci hashing: the product's high half, so aligned addresses (an arena's blocks are on
// 64 KB boundaries) spread over the table
static size_t tab_slot(const ptrtab *t, const void *k) {
    return (size_t)(((uint64_t)(uintptr_t)k * 0x9E3779B97F4A7C15ull) >> 32) & (t->cap - 1);
}

static void *tab_get(const ptrtab *t, const void *k) {
    if (!t->count) return NULL;
    for (size_t i = tab_slot(t, k);; i = (i + 1) & (t->cap - 1)) {
        if (t->keys[i] == k) return t->vals[i];
        if (!t->keys[i]) return NULL;
    }
}

static void tab_put(ptrtab *t, void *k, void *v) {
    if (2 * (t->count + 1) > t->cap) {
        ptrtab n = {calloc(t->cap ? 2 * t->cap : 16, sizeof(void *)), calloc(t->cap ? 2 * t->cap : 16, sizeof(void *)), t->cap ? 2 * t->cap : 16, 0};
        if (!n.keys || !n.vals) zs_panic_c("out of memory");
        for (size_t i = 0; i < t->cap; i++)
            if (t->keys[i]) tab_put(&n, t->keys[i], t->vals[i]);
        free(t->keys);
        free(t->vals);
        *t = n;
    }
    size_t i = tab_slot(t, k);
    while (t->keys[i]) i = (i + 1) & (t->cap - 1);
    t->keys[i] = k;
    t->vals[i] = v;
    t->count++;
}

// removes k and returns its value (NULL if it isn't there); later entries of its run move back
static void *tab_remove(ptrtab *t, const void *k) {
    if (!t->count) return NULL;
    size_t m = t->cap - 1, i = tab_slot(t, k);
    while (t->keys[i] != k) {
        if (!t->keys[i]) return NULL;
        i = (i + 1) & m;
    }
    void *v = t->vals[i];
    for (size_t j = (i + 1) & m; t->keys[j]; j = (j + 1) & m) {
        size_t home = tab_slot(t, t->keys[j]);
        bool stays = i < j ? (i < home && home <= j) : (i < home || home <= j);
        if (!stays) {
            t->keys[i] = t->keys[j];
            t->vals[i] = t->vals[j];
            i = j;
        }
    }
    t->keys[i] = t->vals[i] = NULL;
    if (--t->count == 0) {
        free(t->keys);
        free(t->vals);
        *t = (ptrtab){0};
    }
    return v;
}

// ---- weak references (weak<T>): references that don't keep their object alive. The weak
// references to one object share a cell { count, object }, found from the object in a table, and
// the object dying (freed, or its cell reused for another) empties the cell. A program that uses
// weak references or arenas allocates and frees through zs_alloc_checked and zs_free_checked.
typedef struct {
    zs_int rc;
    void *target;
} zs_weak;

static ptrtab weaks;

// with threads, the tables of weak cells and arena blocks are under one lock
#ifdef ZS_THREADS
#include <pthread.h>
static pthread_mutex_t heap_mu = PTHREAD_MUTEX_INITIALIZER;
#define HEAP_LOCK() pthread_mutex_lock(&heap_mu)
#define HEAP_UNLOCK() pthread_mutex_unlock(&heap_mu)
#else
#define HEAP_LOCK() ((void)0)
#define HEAP_UNLOCK() ((void)0)
#endif

zs_weak *zs_weak_new(void *target) {
    HEAP_LOCK();
    bool dies = __atomic_load_n((zs_int *)target, __ATOMIC_RELAXED) != 0; // a static object never does: its cells aren't in the table
    zs_weak *w = dies ? tab_get(&weaks, target) : NULL;
    if (w) {
        w->rc++;
    } else {
        w = zs_alloc((zs_int)sizeof(zs_weak));
        w->rc = 1;
        w->target = dies ? target : (void *)((uintptr_t)target | 1); // the low bit: static
        if (dies) tab_put(&weaks, target, w);
    }
    HEAP_UNLOCK();
    return w;
}

// the object, with a new reference, or NULL once it has died. A shared object (count below 0)
// gets its reference only while its count isn't 0: at 0 another thread is freeing it
void *zs_weak_target(zs_weak *w) {
    if ((uintptr_t)w->target & 1) return (void *)((uintptr_t)w->target & ~(uintptr_t)1);
    HEAP_LOCK();
    zs_int *t = w->target;
    if (t) {
        zs_int c = __atomic_load_n(t, __ATOMIC_RELAXED);
        if (c > 0) {
            *t = c + 1; // thread-local: this thread's, as the weak reference is
        } else {
            for (;;) {
                if (c == 0) { // another thread is freeing it
                    t = NULL;
                    break;
                }
                if (__atomic_compare_exchange_n(t, &c, c - 1, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break;
            }
        }
    }
    HEAP_UNLOCK();
    return t;
}

// the cell's last reference has gone
void zs_weak_free(zs_weak *w) {
    HEAP_LOCK();
    if (w->target && !((uintptr_t)w->target & 1)) tab_remove(&weaks, w->target);
    HEAP_UNLOCK();
    zs_free(w);
}

// ---- arenas (Arena.with): what a function allocates comes from large blocks, bumped through. An
// object dying frees nothing; the arena's blocks go at once when its last object has died: when
// the function returns, or later if something it made lives on. The arena's own record is in its
// first block, so it takes one malloc per block.
#define ARENA_BLOCK ((size_t)64 * 1024)

typedef struct zs_arena {
    struct zs_arena *parent; // the arena open around this one
    void *blocks;            // the newest first, each starting with a block_head
    char *next, *end;        // the free part of the newest block
    zs_int live;             // objects in the arena that haven't died
    bool open;               // Arena.with hasn't returned yet
} zs_arena;

typedef struct {
    void *next;
    zs_arena *arena;
} block_head;

#define ARENA_HEAD ((sizeof(block_head) + 15) & ~(size_t)15)

#ifdef ZS_THREADS
static _Thread_local zs_arena *arena; // this thread's innermost open arena
#else
static zs_arena *arena; // the innermost open arena
#endif
static ptrtab arena_blocks; // each block's address -> its arena

static char *arena_block(zs_arena *a) {
    char *b = aligned_alloc(ARENA_BLOCK, ARENA_BLOCK);
    if (!b) zs_panic_c("out of memory");
    COUNT(mallocs, 1);
    *(block_head *)b = (block_head){a ? a->blocks : NULL, a};
    return b;
}

void zs_arena_open(void) {
    char *b = arena_block(NULL);
    zs_arena *a = (zs_arena *)(b + ARENA_HEAD);
    *a = (zs_arena){arena, b, b + ARENA_HEAD + ((sizeof(zs_arena) + 15) & ~(size_t)15), b + ARENA_BLOCK, 0, true};
    ((block_head *)b)->arena = a;
    HEAP_LOCK();
    tab_put(&arena_blocks, b, a);
    HEAP_UNLOCK();
    arena = a;
}

static void arena_release(zs_arena *a) {
    for (void *b = a->blocks, *next; b; b = next) { // the oldest block, holding *a, is the last
        next = ((block_head *)b)->next;
        tab_remove(&arena_blocks, b);
        free(b);
    }
}

void zs_arena_close(void) {
    zs_arena *a = arena;
    arena = a->parent;
    HEAP_LOCK();
    a->open = false;
    if (a->live == 0) arena_release(a);
    HEAP_UNLOCK();
}

void *zs_alloc_checked(zs_int size) {
    zs_arena *a = arena;
    if (!a || (size_t)size > ARENA_BLOCK / 4) return zs_alloc(size); // a big object is malloc's
    size_t n = ((size_t)size + 15) & ~(size_t)15;
    HEAP_LOCK();
    if (a->next + n > a->end) {
        char *b = arena_block(a);
        a->blocks = b;
        tab_put(&arena_blocks, b, a);
        a->next = b + ARENA_HEAD;
        a->end = b + ARENA_BLOCK;
    }
    void *p = a->next;
    a->next += n;
    a->live++;
    HEAP_UNLOCK();
    COUNT(live, 1);
    COUNT(allocations, 1);
    return p;
}

void zs_free_checked(void *p) {
    HEAP_LOCK();
    zs_weak *w = weaks.count ? tab_remove(&weaks, p) : NULL;
    if (w) w->target = NULL;
    zs_arena *a = arena_blocks.count ? tab_get(&arena_blocks, (void *)((uintptr_t)p & ~(uintptr_t)(ARENA_BLOCK - 1))) : NULL;
    if (a) {
        COUNT(live, -1);
        if (--a->live == 0 && !a->open) arena_release(a);
    }
    HEAP_UNLOCK();
    if (!a) zs_free(p);
}

// a cell Perceus reuses for another object: the object it held has died
void zs_reused(void *p) {
    HEAP_LOCK();
    zs_weak *w = weaks.count ? tab_remove(&weaks, p) : NULL;
    if (w) w->target = NULL;
    HEAP_UNLOCK();
}

static void leak_report(void) {
    if (getenv("ZS_LEAKCHECK") && live != 0)
        fprintf(stderr, "leak check: %" PRId64 " object(s) still allocated\n", live);
}

__attribute__((constructor)) static void zs_init(void) { atexit(leak_report); }

static zs_str *str_new(zs_int len) {
    zs_str *s = zs_alloc((int64_t)sizeof(zs_str) + len + 1);
    s->rc = 1;
    s->len = len;
    s->data[len] = 0;
    return s;
}

static zs_str *str_of(const char *buf, zs_int len) {
    zs_str *s = str_new(len);
    memcpy(s->data, buf, (size_t)len);
    return s;
}

// String operations borrow their arguments; the caller drops them.
zs_str *zs_str_concat(zs_str *a, zs_str *b) {
    zs_str *s = str_new(a->len + b->len);
    memcpy(s->data, a->data, (size_t)a->len);
    memcpy(s->data + a->len, b->data, (size_t)b->len);
    return s;
}

// -1, 0 or 1
zs_int zs_str_cmp(zs_str *a, zs_str *b) {
    zs_int n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->data, b->data, (size_t)n);
    if (c != 0) return c < 0 ? -1 : 1;
    return a->len < b->len ? -1 : a->len > b->len;
}

// FNV-1a
zs_int zs_str_hash(zs_str *s) {
    uint64_t h = 14695981039346656037ull;
    for (int64_t i = 0; i < s->len; i++) h = (h ^ (uint8_t)s->data[i]) * 1099511628211ull;
    return sizeof(zs_int) < 8 ? (zs_int)(h ^ (h >> 32)) : (zs_int)h; // fold on a 32-bit chip
}

zs_str *zs_str_of_i64(int64_t v) {
    char buf[32];
    return str_of(buf, snprintf(buf, sizeof buf, "%" PRId64, v));
}

zs_str *zs_str_of_u64(uint64_t v) {
    char buf[32];
    return str_of(buf, snprintf(buf, sizeof buf, "%" PRIu64, v));
}

// Shortest representation that reads back as the same double; whole numbers print like ints.
zs_str *zs_str_of_f64(double v) {
    char buf[40];
    int n = 0;
    for (int prec = 15; prec <= 17; prec++) {
        n = snprintf(buf, sizeof buf, "%.*g", prec, v);
        if (strtod(buf, NULL) == v) break;
    }
    return str_of(buf, n);
}

// the shortest text that reads back as the same f32 (0.3f prints "0.3", not its double value)
zs_str *zs_str_of_f32(float v) {
    char buf[40];
    int n = 0;
    for (int prec = 6; prec <= 9; prec++) {
        n = snprintf(buf, sizeof buf, "%.*g", prec, (double)v);
        if (strtof(buf, NULL) == v) break;
    }
    return str_of(buf, n);
}

// a char's text: its UTF-8 encoding (a value that isn't a Unicode scalar becomes U+FFFD)
zs_str *zs_str_of_char(int32_t c) {
    char b[4];
    int n;
    if (c < 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) c = 0xFFFD;
    if (c < 0x80) {
        b[0] = (char)c;
        n = 1;
    } else if (c < 0x800) {
        b[0] = (char)(0xC0 | (c >> 6));
        b[1] = (char)(0x80 | (c & 0x3F));
        n = 2;
    } else if (c < 0x10000) {
        b[0] = (char)(0xE0 | (c >> 12));
        b[1] = (char)(0x80 | ((c >> 6) & 0x3F));
        b[2] = (char)(0x80 | (c & 0x3F));
        n = 3;
    } else {
        b[0] = (char)(0xF0 | (c >> 18));
        b[1] = (char)(0x80 | ((c >> 12) & 0x3F));
        b[2] = (char)(0x80 | ((c >> 6) & 0x3F));
        b[3] = (char)(0x80 | (c & 0x3F));
        n = 4;
    }
    return str_of(b, n);
}

zs_str *zs_str_from_c(const char *c) { return str_of(c, (int64_t)strlen(c)); }

zs_str *zs_str_of_bool(bool v) { return v ? str_of("true", 4) : str_of("false", 5); }

// ---- string primitives (arguments borrowed; results owned)

static void check_range(zs_str *s, zs_int start, zs_int len) {
    if (start < 0 || len < 0 || start > s->len || len > s->len - start) zs_panic_c("string index out of range");
}

zs_str *zs_str_sub(zs_str *s, zs_int start, zs_int len) {
    check_range(s, start, len);
    return str_of(s->data + start, len);
}

uint8_t zs_str_byte(zs_str *s, zs_int i) {
    check_range(s, i, 1);
    return (uint8_t)s->data[i];
}

zs_str *zs_str_of_byte(uint8_t b) {
    char c = (char)b;
    return str_of(&c, 1);
}

zs_int zs_str_index_of(zs_str *s, zs_str *sub, zs_int from) {
    if (from < 0) from = 0;
    for (zs_int i = from; i + sub->len <= s->len; i++)
        if (memcmp(s->data + i, sub->data, (size_t)sub->len) == 0) return i;
    return -1;
}

zs_str *zs_str_trim(zs_str *s) {
    int64_t a = 0, b = s->len;
    while (a < b && (s->data[a] == ' ' || s->data[a] == '\t' || s->data[a] == '\n' || s->data[a] == '\r')) a++;
    while (b > a && (s->data[b - 1] == ' ' || s->data[b - 1] == '\t' || s->data[b - 1] == '\n' || s->data[b - 1] == '\r')) b--;
    return str_of(s->data + a, b - a);
}

static zs_str *map_ascii(zs_str *s, int upper) {
    zs_str *r = str_of(s->data, s->len);
    for (int64_t i = 0; i < r->len; i++) {
        char c = r->data[i];
        if (upper && c >= 'a' && c <= 'z') r->data[i] = (char)(c - 32);
        if (!upper && c >= 'A' && c <= 'Z') r->data[i] = (char)(c + 32);
    }
    return r;
}

zs_str *zs_str_upper(zs_str *s) { return map_ascii(s, 1); }
zs_str *zs_str_lower(zs_str *s) { return map_ascii(s, 0); }

zs_str *zs_str_replace(zs_str *s, zs_str *old, zs_str *with) {
    if (old->len == 0) return str_of(s->data, s->len);
    int64_t n = 0;
    for (int64_t i = 0; (i = zs_str_index_of(s, old, i)) >= 0; i += old->len) n++;
    zs_str *r = str_new(s->len + n * (with->len - old->len));
    int64_t i = 0, o = 0, j;
    while ((j = zs_str_index_of(s, old, i)) >= 0) {
        memcpy(r->data + o, s->data + i, (size_t)(j - i));
        o += j - i;
        memcpy(r->data + o, with->data, (size_t)with->len);
        o += with->len;
        i = j + old->len;
    }
    memcpy(r->data + o, s->data + i, (size_t)(s->len - i));
    return r;
}

bool zs_str_is_float(zs_str *s) {
    char *end;
    if (s->len == 0) return false;
    strtod(s->data, &end);
    return end == s->data + s->len;
}

double zs_str_to_float(zs_str *s) { return strtod(s->data, NULL); }

// ---- console

static bool at_eof;

zs_str *zs_read_line(void) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t n = getline(&line, &cap, stdin);
    at_eof = n < 0;
    if (n > 0 && line[n - 1] == '\n') n--;
    zs_str *s = str_of(line ? line : "", n < 0 ? 0 : n);
    free(line);
    return s;
}

bool zs_eof(void) { return at_eof; }

void zs_eprintln(zs_str *s) {
    fflush(stdout);
    fwrite(s->data, 1, (size_t)s->len, stderr);
    fputc('\n', stderr);
}

void zs_print(zs_str *s) { fwrite(s->data, 1, (size_t)s->len, stdout); }

void zs_println(zs_str *s) {
    fwrite(s->data, 1, (size_t)s->len, stdout);
    fputc('\n', stdout);
}

// ---- CLI: arguments, environment, files, directories, processes
// Fallible calls set io_error ("" on success); the prelude turns that into a result.
// Lists cross as one string with NUL-separated items.

#include <dirent.h>
#include <errno.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

extern char **environ;
static int g_argc;
static char **g_argv;
static _Thread_local zs_str *io_error; // per thread: Task.blocking's helper reads files too

void zs_set_args(int32_t argc, char **argv) {
    g_argc = argc;
    g_argv = argv;
}

zs_int zs_argc(void) { return g_argc; }

zs_str *zs_arg(zs_int i) { return i >= 0 && i < g_argc ? zs_str_from_c(g_argv[i]) : str_of("", 0); }

static void set_error(const char *what, zs_str *path) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s %s: %s", what, path ? path->data : "", strerror(errno));
    if (io_error) zs_free(io_error);
    io_error = zs_str_from_c(buf);
}

static void clear_error(void) {
    if (io_error) zs_free(io_error);
    io_error = NULL;
}

bool zs_io_ok(void) { return io_error == NULL; }

// the error of the last fallible call (the caller owns it)
zs_str *zs_io_error(void) {
    zs_str *e = io_error ? io_error : str_of("", 0);
    io_error = NULL;
    return e;
}

bool zs_env_has(zs_str *name) { return getenv(name->data) != NULL; }

zs_str *zs_env_get(zs_str *name) {
    const char *v = getenv(name->data);
    return zs_str_from_c(v ? v : "");
}

// like a panic, no cleanup (and so no leak report): the process ends here
_Noreturn void zs_exit(zs_int code) {
    fflush(NULL);
    _exit((int)code);
}

zs_str *zs_file_read(zs_str *path) {
    clear_error();
    FILE *f = fopen(path->data, "rb");
    if (!f) {
        set_error("cannot open", path);
        return str_of("", 0);
    }
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    size_t n;
    while ((n = fread(buf + len, 1, cap - len, f)) > 0) {
        len += n;
        if (len == cap) buf = realloc(buf, cap *= 2);
    }
    if (ferror(f)) set_error("cannot read", path);
    fclose(f);
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}

static void file_put(zs_str *path, zs_str *text, const char *mode) {
    clear_error();
    FILE *f = fopen(path->data, mode);
    if (!f) {
        set_error("cannot open", path);
        return;
    }
    if (fwrite(text->data, 1, (size_t)text->len, f) != (size_t)text->len) set_error("cannot write", path);
    if (fclose(f) != 0 && !io_error) set_error("cannot write", path);
}

void zs_file_write(zs_str *path, zs_str *text) { file_put(path, text, "wb"); }
void zs_file_append(zs_str *path, zs_str *text) { file_put(path, text, "ab"); }

bool zs_file_exists(zs_str *path) {
    struct stat st;
    return stat(path->data, &st) == 0 && S_ISREG(st.st_mode);
}

bool zs_dir_exists(zs_str *path) {
    struct stat st;
    return stat(path->data, &st) == 0 && S_ISDIR(st.st_mode);
}

void zs_file_delete(zs_str *path) {
    clear_error();
    if (remove(path->data) != 0) set_error("cannot delete", path);
}

void zs_dir_create(zs_str *path) {
    clear_error();
    if (mkdir(path->data, 0777) != 0 && errno != EEXIST) set_error("cannot create", path);
}

// entry names (without . and ..), NUL-separated, in directory order
zs_str *zs_dir_list(zs_str *path) {
    clear_error();
    DIR *d = opendir(path->data);
    if (!d) {
        set_error("cannot open", path);
        return str_of("", 0);
    }
    size_t cap = 256, len = 0;
    char *buf = malloc(cap);
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        size_t n = strlen(e->d_name) + 1;
        while (len + n > cap) buf = realloc(buf, cap *= 2);
        memcpy(buf + len, e->d_name, n);
        len += n;
    }
    closedir(d);
    zs_str *s = str_of(buf, len ? (int64_t)len - 1 : 0);
    free(buf);
    return s;
}

// Runs prog with NUL-separated args (no shell), stdout captured, stderr passed through.
static _Thread_local int64_t process_code;

zs_int zs_process_code(void) { return process_code; }

// prog as an executable path: as given when it has a '/', else the first match on PATH
// (looked up here so a missing program is the same error on every libc, and under valgrind)
static bool find_program(const char *prog, char *out, size_t size) {
    if (strchr(prog, '/')) {
        snprintf(out, size, "%s", prog);
        return access(out, X_OK) == 0;
    }
    const char *path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    while (*path) {
        const char *end = strchr(path, ':');
        size_t len = end ? (size_t)(end - path) : strlen(path);
        snprintf(out, size, "%.*s/%s", (int)len, len ? path : ".", prog);
        if (access(out, X_OK) == 0) return true;
        path += len + (end ? 1 : 0);
    }
    return false;
}

zs_str *zs_process_run(zs_str *prog, zs_str *args) {
    clear_error();
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) {
        errno = ENOENT;
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    int64_t count = args->len ? 1 : 0;
    for (int64_t i = 0; i < args->len; i++) count += args->data[i] == 0;
    char **argv = malloc(sizeof(char *) * (size_t)(count + 2));
    argv[0] = prog->data;
    int64_t k = 1;
    if (args->len) {
        argv[k++] = args->data;
        for (int64_t i = 0; i < args->len; i++)
            if (args->data[i] == 0) argv[k++] = args->data + i + 1;
    }
    argv[k] = NULL;
    int fds[2];
    if (pipe(fds) != 0) {
        free(argv);
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], 1);
    posix_spawn_file_actions_addclose(&fa, fds[0]);
    posix_spawn_file_actions_addclose(&fa, fds[1]);
    fflush(stdout);
    pid_t pid;
    int rc = posix_spawn(&pid, exe, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    free(argv);
    close(fds[1]);
    if (rc != 0) {
        close(fds[0]);
        errno = rc;
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    ssize_t n;
    while ((n = read(fds[0], buf + len, cap - len)) > 0) {
        len += (size_t)n;
        if (len == cap) buf = realloc(buf, cap *= 2);
    }
    close(fds[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    process_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}

// a test build's argument: which test to run
zs_int zs_test_index(void) { return g_argc > 1 ? strtoll(g_argv[1], NULL, 10) : -1; }

// ---- the event loop (Task.run): callbacks waiting for file descriptors, timers, a queue of
// callbacks ready to run, and jobs on a helper thread (Task.blocking). A callback is a Z#
// closure taking unit, which the loop owns: zs_clo_run calls it and gives up the loop's
// reference, zs_clo_drop just gives it up (both are in each program's IR). Each thread has a
// loop of its own; what other threads hand one (finished helper jobs, tasks spawned onto it,
// results of tasks it spawned) goes through its inbox, which a byte on a pipe announces.
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <sys/epoll.h>
#include <sys/socket.h>

void zs_clo_run(void *c);
void zs_clo_call(void *c);
void zs_clo_drop(void *c);
bool zs_loop_step(void);
void zs_loop_close(void);

typedef struct {
    void *read, *write; // the callbacks waiting for the descriptor to be readable, writable
    uint32_t armed;     // the events epoll watches for it
} fd_wait;

typedef struct {
    int64_t at; // CLOCK_MONOTONIC nanoseconds
    zs_int id;
    void *cb;
    size_t pos; // in the heap
} zs_timer;

// a helper job (work, then done here), a task spawned onto this loop (work only), or a spawned
// task's result coming back (done only: a token, zs_loop_expect)
typedef struct job {
    void *work, *done;
    struct inbox *box; // a token's loop
    struct job *next;
} job;

// what other threads hand a loop, under mu; freed when the loop has closed and no token for it
// is left
typedef struct inbox {
    pthread_mutex_t mu;
    pthread_cond_t cv;     // the helper thread waits on it for jobs
    job *todo, *todo_last; // Task.blocking's jobs, for the helper thread
    job *ready;            // what the loop takes next, newest first
    int wake[2];
    bool helping; // a helper thread runs
    pthread_t helper;
    int refs; // the loop's, and one per token not yet used
    bool closed;
} inbox;

static _Thread_local struct {
    bool stepping; // inside zs_loop_step: a callback can't run Task.run itself
    int ep;        // the epoll instance, -1 until it's needed
    fd_wait *fds;  // by descriptor
    size_t nfds;   // fds' length
    size_t waits;  // callbacks waiting for descriptors
    void **queue;  // ready callbacks, a ring
    size_t qhead, qlen, qcap;
    zs_timer **heap; // the timers, a min-heap by time
    size_t ntimers, heapcap;
    ptrtab timers; // id -> timer, to cancel one
    zs_int next_timer;
    int depth;     // continuations called inside others (zs_loop_enter)
    inbox *box;    // NULL until another thread has something for this loop
    size_t jobs;   // helper jobs and spawned tasks not finished yet
    bool stopping; // a loop thread told to stop (at exit)
} L = {.ep = -1};

static int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static void ensure_ep(void) {
    if (L.ep < 0 && (L.ep = epoll_create1(EPOLL_CLOEXEC)) < 0) zs_panic_c("epoll_create1 failed");
}

void zs_loop_post(void *cb) {
    if (L.qlen == L.qcap) {
        size_t cap = L.qcap ? 2 * L.qcap : 64;
        void **q = malloc(cap * sizeof(void *));
        if (!q) zs_panic_c("out of memory");
        for (size_t i = 0; i < L.qlen; i++) q[i] = L.queue[(L.qhead + i) % L.qcap];
        free(L.queue);
        L.queue = q;
        L.qhead = 0;
        L.qcap = cap;
    }
    L.queue[(L.qhead + L.qlen++) % L.qcap] = cb;
}

static void *queue_pop(void) {
    void *cb = L.queue[L.qhead];
    L.qhead = (L.qhead + 1) % L.qcap;
    L.qlen--;
    return cb;
}

// a continuation may be called inside the current one (true: the caller calls zs_loop_leave
// after it), or should go through the queue, so a run of awaits that complete at once doesn't
// grow the stack without end
bool zs_loop_enter(void) {
    if (L.depth >= 64) return false;
    L.depth++;
    return true;
}

void zs_loop_leave(void) { L.depth--; }

// the events epoll watches for fd: those it has callbacks for
static void fd_arm(zs_int fd) {
    fd_wait *w = &L.fds[fd];
    uint32_t want = (w->read ? EPOLLIN : 0) | (w->write ? EPOLLOUT : 0);
    if (want == w->armed) return;
    struct epoll_event ev = {.events = want, .data.fd = (int)fd};
    int op = !w->armed ? EPOLL_CTL_ADD : !want ? EPOLL_CTL_DEL : EPOLL_CTL_MOD;
    if (epoll_ctl(L.ep, op, (int)fd, &ev) != 0 && op != EPOLL_CTL_DEL) zs_panic_c("epoll_ctl failed (a descriptor that isn't a socket or pipe?)");
    w->armed = want;
}

// cb runs once fd is readable (or writable)
void zs_loop_wait(zs_int fd, bool write, void *cb) {
    ensure_ep();
    if ((size_t)fd >= L.nfds) {
        size_t n = L.nfds ? L.nfds : 64;
        while (n <= (size_t)fd) n *= 2;
        fd_wait *f = realloc(L.fds, n * sizeof(fd_wait));
        if (!f) zs_panic_c("out of memory");
        memset(f + L.nfds, 0, (n - L.nfds) * sizeof(fd_wait));
        L.fds = f;
        L.nfds = n;
    }
    void **slot = write ? &L.fds[fd].write : &L.fds[fd].read;
    if (*slot) zs_panic_c("two tasks wait for the same descriptor at once");
    *slot = cb;
    L.waits++;
    fd_arm(fd);
}

// the callback waiting for fd goes, uncalled (its task was cancelled)
void zs_loop_unwait(zs_int fd, bool write) {
    if ((size_t)fd >= L.nfds) return;
    void **slot = write ? &L.fds[fd].write : &L.fds[fd].read;
    void *cb = *slot;
    if (!cb) return;
    *slot = NULL;
    L.waits--;
    fd_arm(fd);
    zs_clo_drop(cb);
}

static void heap_set(size_t i, zs_timer *t) {
    L.heap[i] = t;
    t->pos = i;
}

static void heap_up(size_t i) {
    zs_timer *t = L.heap[i];
    while (i > 0 && L.heap[(i - 1) / 2]->at > t->at) {
        heap_set(i, L.heap[(i - 1) / 2]);
        i = (i - 1) / 2;
    }
    heap_set(i, t);
}

static void heap_down(size_t i) {
    zs_timer *t = L.heap[i];
    for (;;) {
        size_t c = 2 * i + 1;
        if (c >= L.ntimers) break;
        if (c + 1 < L.ntimers && L.heap[c + 1]->at < L.heap[c]->at) c++;
        if (L.heap[c]->at >= t->at) break;
        heap_set(i, L.heap[c]);
        i = c;
    }
    heap_set(i, t);
}

static void heap_remove(zs_timer *t) {
    size_t i = t->pos;
    zs_timer *last = L.heap[--L.ntimers];
    if (i < L.ntimers) {
        heap_set(i, last);
        heap_up(i);
        heap_down(last->pos);
    }
}

// cb runs in ms milliseconds; the result names the timer for zs_loop_untimer
zs_int zs_loop_timer(zs_int ms, void *cb) {
    if (L.ntimers == L.heapcap) {
        L.heapcap = L.heapcap ? 2 * L.heapcap : 64;
        zs_timer **h = realloc(L.heap, L.heapcap * sizeof(zs_timer *));
        if (!h) zs_panic_c("out of memory");
        L.heap = h;
    }
    zs_timer *t = malloc(sizeof(zs_timer));
    if (!t) zs_panic_c("out of memory");
    *t = (zs_timer){now_ns() + (ms > 0 ? ms : 0) * 1000000, ++L.next_timer, cb, 0};
    L.heap[L.ntimers++] = t;
    heap_up(L.ntimers - 1);
    tab_put(&L.timers, (void *)(uintptr_t)t->id, t);
    return t->id;
}

// the timer goes, its callback uncalled (its task was cancelled)
void zs_loop_untimer(zs_int id) {
    zs_timer *t = tab_remove(&L.timers, (void *)(uintptr_t)id);
    if (!t) return;
    heap_remove(t);
    void *cb = t->cb;
    free(t);
    zs_clo_drop(cb);
}

static void box_free(inbox *b) {
    pthread_mutex_destroy(&b->mu);
    pthread_cond_destroy(&b->cv);
    close(b->wake[0]);
    close(b->wake[1]);
    free(b);
}

// the loop's inbox, made (and watched) the first time another thread may hand it something
static inbox *box_get(void) {
    if (!L.box) {
        ensure_ep();
        inbox *b = calloc(1, sizeof(inbox));
        if (!b || pipe2(b->wake, O_CLOEXEC | O_NONBLOCK) != 0) zs_panic_c("pipe2 failed");
        pthread_mutex_init(&b->mu, NULL);
        pthread_cond_init(&b->cv, NULL);
        b->refs = 1;
        struct epoll_event ev = {.events = EPOLLIN, .data.fd = b->wake[0]};
        epoll_ctl(L.ep, EPOLL_CTL_ADD, b->wake[0], &ev);
        L.box = b;
    }
    return L.box;
}

// hands j to b's loop (under b->mu), waking it
static void box_put(inbox *b, job *j) {
    j->next = b->ready;
    b->ready = j;
    ssize_t w = write(b->wake[1], "x", 1);
    (void)w;
}

static void *helper_main(void *arg) {
    inbox *b = arg;
    pthread_mutex_lock(&b->mu);
    for (;;) {
        while (!b->todo && b->helping) pthread_cond_wait(&b->cv, &b->mu);
        if (!b->todo) break;
        job *j = b->todo;
        b->todo = j->next;
        pthread_mutex_unlock(&b->mu);
        zs_clo_call(j->work);
        pthread_mutex_lock(&b->mu);
        box_put(b, j);
    }
    pthread_mutex_unlock(&b->mu);
    return NULL;
}

// Task.blocking: work (whose objects the compiler marked shared) runs on the helper thread,
// then done runs here
void zs_loop_blocking(void *work, void *done) {
    inbox *b = box_get();
    job *j = malloc(sizeof(job));
    if (!j) zs_panic_c("out of memory");
    *j = (job){work, done, NULL, NULL};
    pthread_mutex_lock(&b->mu);
    if (!b->helping) {
        b->helping = true;
        if (pthread_create(&b->helper, NULL, helper_main, b) != 0) zs_panic_c("pthread_create failed");
    }
    if (b->todo) b->todo_last->next = j;
    else b->todo = j;
    b->todo_last = j;
    pthread_cond_signal(&b->cv);
    pthread_mutex_unlock(&b->mu);
    L.jobs++;
}

// a token for a result another thread will hand this loop (Task.spawn): zs_loop_fulfill(token)
// there makes done run here. Until then the loop waits for it.
zs_int zs_loop_expect(void *done) {
    inbox *b = box_get();
    job *j = malloc(sizeof(job));
    if (!j) zs_panic_c("out of memory");
    *j = (job){NULL, done, b, NULL};
    pthread_mutex_lock(&b->mu);
    b->refs++;
    pthread_mutex_unlock(&b->mu);
    L.jobs++;
    return (zs_int)(intptr_t)j;
}

// on any thread: the token's done goes to its loop. A loop that has closed meanwhile can't run
// it, and no other thread may drop it (its objects are that loop's): it's left
void zs_loop_fulfill(zs_int token) {
    job *j = (job *)(intptr_t)token;
    inbox *b = j->box;
    pthread_mutex_lock(&b->mu);
    if (!b->closed) box_put(b, j);
    else free(j);
    bool last = --b->refs == 0;
    pthread_mutex_unlock(&b->mu);
    if (last) box_free(b);
}

// what other threads have handed this loop, in the order they did: finished helper jobs (their
// work goes, their done runs), spawned tasks (they start), results of spawned tasks
static void box_take(void) {
    inbox *b = L.box;
    char buf[64];
    while (read(b->wake[0], buf, sizeof buf) > 0) {}
    pthread_mutex_lock(&b->mu);
    job *j = b->ready, *order = NULL;
    b->ready = NULL;
    pthread_mutex_unlock(&b->mu);
    for (job *next; j; j = next) { // newest first: reversed
        next = j->next;
        j->next = order;
        order = j;
    }
    for (job *next; order; order = next) {
        next = order->next;
        if (!order->work && !order->done) L.stopping = true; // the program is ending (loops_stop)
        if (order->work && order->done) zs_clo_drop(order->work);
        else if (order->work) zs_loop_post(order->work);
        if (order->done) {
            zs_loop_post(order->done);
            L.jobs--;
        }
        free(order);
    }
}

// ---- loop threads (Task.spawn): a thread per core, each running an event loop of its own for
// the tasks spawned onto it, which stay on it to the end. They stop when the program does.
static struct {
    int n;
    pthread_t *threads;
    inbox **boxes;
    atomic_uint next;
    atomic_bool stopping;
    pthread_mutex_t mu;
    pthread_cond_t cv;
    int ready; // threads whose inbox is in boxes
} T = {.mu = PTHREAD_MUTEX_INITIALIZER, .cv = PTHREAD_COND_INITIALIZER};

static pthread_once_t loops_once = PTHREAD_ONCE_INIT;

static void *loop_main(void *arg) {
    int k = (int)(intptr_t)arg;
    inbox *b = box_get();
    b->refs++; // spawns refer to it until loops_stop has joined the thread
    L.jobs++;  // and the loop waits for them
    pthread_mutex_lock(&T.mu);
    T.boxes[k] = b;
    T.ready++;
    pthread_cond_broadcast(&T.cv);
    pthread_mutex_unlock(&T.mu);
    while (!L.stopping) zs_loop_step();
    L.jobs--;
    zs_loop_close(); // the tasks still on it go, unfinished
    return NULL;
}

// at exit: each loop thread stops (after what it's running now) and is joined
static void loops_stop(void) {
    atomic_store(&T.stopping, true);
    for (int k = 0; k < T.n; k++) {
        job *j = calloc(1, sizeof(job)); // neither work nor done: stop
        if (!j) zs_panic_c("out of memory");
        pthread_mutex_lock(&T.boxes[k]->mu);
        box_put(T.boxes[k], j);
        pthread_mutex_unlock(&T.boxes[k]->mu);
    }
    for (int k = 0; k < T.n; k++) {
        pthread_join(T.threads[k], NULL);
        inbox *b = T.boxes[k];
        pthread_mutex_lock(&b->mu);
        bool last = --b->refs == 0;
        pthread_mutex_unlock(&b->mu);
        if (last) box_free(b);
    }
    free(T.boxes);
    free(T.threads);
}

static void loops_start(void) {
    const char *w = getenv("ZS_WORKERS");
    long n = w ? strtol(w, NULL, 10) : sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    T.n = (int)n;
    T.boxes = calloc((size_t)n, sizeof(inbox *));
    T.threads = calloc((size_t)n, sizeof(pthread_t));
    if (!T.boxes || !T.threads) zs_panic_c("out of memory");
    for (int k = 0; k < T.n; k++)
        if (pthread_create(&T.threads[k], NULL, loop_main, (void *)(intptr_t)k) != 0) zs_panic_c("pthread_create failed");
    pthread_mutex_lock(&T.mu);
    while (T.ready < T.n) pthread_cond_wait(&T.cv, &T.mu);
    pthread_mutex_unlock(&T.mu);
    atexit(loops_stop);
}

// starts work (a closure whose objects the compiler marked shared) on the next loop thread;
// once the program is ending, it doesn't start
void zs_loop_spawn(void *work) {
    pthread_once(&loops_once, loops_start);
    if (atomic_load(&T.stopping)) return; // ponytail: the work's closure is left, not dropped
    inbox *b = T.boxes[atomic_fetch_add(&T.next, 1) % (unsigned)T.n];
    job *j = malloc(sizeof(job));
    if (!j) zs_panic_c("out of memory");
    *j = (job){work, NULL, NULL, NULL};
    pthread_mutex_lock(&b->mu);
    box_put(b, j);
    pthread_mutex_unlock(&b->mu);
}

// Runs what's ready, then waits once for a descriptor, a timer or a job. False when nothing is
// left that could happen (Task.run then stops).
bool zs_loop_step(void) {
    if (L.stepping) zs_panic_c("Task.run inside a task: use let! there instead");
    L.stepping = true;
    for (size_t n = L.qlen; n > 0 && L.qlen; n--) zs_clo_run(queue_pop());
    L.stepping = false;
    int64_t now = now_ns();
    while (L.ntimers && L.heap[0]->at <= now) {
        zs_timer *t = L.heap[0];
        heap_remove(t);
        tab_remove(&L.timers, (void *)(uintptr_t)t->id);
        zs_loop_post(t->cb);
        free(t);
    }
    if (L.qlen) return true;
    if (!L.waits && !L.ntimers && !L.jobs) return false;
    int timeout = -1;
    if (L.ntimers) {
        int64_t d = L.heap[0]->at - now;
        timeout = d <= 0 ? 0 : (int)((d + 999999) / 1000000);
    }
    ensure_ep();
    struct epoll_event evs[256];
    int k = epoll_wait(L.ep, evs, 256, timeout);
    if (k < 0 && errno != EINTR) zs_panic_c("epoll_wait failed");
    for (int i = 0; i < k; i++) {
        int fd = evs[i].data.fd;
        if (L.box && fd == L.box->wake[0]) {
            box_take();
            continue;
        }
        fd_wait *w = &L.fds[fd];
        uint32_t e = evs[i].events;
        if (w->read && (e & (EPOLLIN | EPOLLHUP | EPOLLERR))) {
            zs_loop_post(w->read);
            w->read = NULL;
            L.waits--;
        }
        if (w->write && (e & (EPOLLOUT | EPOLLHUP | EPOLLERR))) {
            zs_loop_post(w->write);
            w->write = NULL;
            L.waits--;
        }
        fd_arm(fd);
    }
    return true;
}

// Task.run has finished: what still waits goes (uncalled), the helper thread stops, and the
// loop's memory is freed (a later Task.run starts afresh)
void zs_loop_close(void) {
    inbox *b = L.box;
    if (b) {
        pthread_mutex_lock(&b->mu);
        b->closed = true;
        bool helping = b->helping;
        b->helping = false;
        pthread_cond_signal(&b->cv);
        pthread_mutex_unlock(&b->mu);
        if (helping) pthread_join(b->helper, NULL);
        // what's left is this loop's: its closures go here
        for (job *j = b->todo, *next; j; j = next) {
            next = j->next;
            zs_clo_drop(j->work);
            zs_clo_drop(j->done);
            free(j);
        }
        pthread_mutex_lock(&b->mu);
        job *ready = b->ready;
        b->ready = NULL;
        bool last = --b->refs == 0; // tokens still out keep it for their zs_loop_fulfill
        pthread_mutex_unlock(&b->mu);
        for (job *j = ready, *next; j; j = next) {
            next = j->next;
            if (j->work) zs_clo_drop(j->work);
            if (j->done) zs_clo_drop(j->done);
            free(j);
        }
        if (last) box_free(b);
    }
    while (L.qlen) zs_clo_drop(queue_pop());
    for (size_t fd = 0; fd < L.nfds; fd++) {
        if (L.fds[fd].read) zs_clo_drop(L.fds[fd].read);
        if (L.fds[fd].write) zs_clo_drop(L.fds[fd].write);
    }
    while (L.ntimers) {
        zs_timer *t = L.heap[--L.ntimers];
        tab_remove(&L.timers, (void *)(uintptr_t)t->id);
        zs_clo_drop(t->cb);
        free(t);
    }
    if (L.ep >= 0) close(L.ep);
    free(L.fds);
    free(L.queue);
    free(L.heap);
    L = (typeof(L)){.ep = -1};
}

// ---- sockets and descriptors (Net.Tcp): non-blocking, so a task waits for them in the loop.
// Failures are -errno, and -1000 for "it would block, wait first"; Native.errorText gives the
// text.
typedef struct {
    zs_int rc, len;
    uint8_t data[];
} zs_bytes; // a Buffer<u8>, and a string's object too

static zs_int failed(void) { return errno == EAGAIN || errno == EWOULDBLOCK ? -1000 : -(zs_int)errno; }

static int resolve(zs_str *host, zs_int port, bool passive, struct addrinfo **res) {
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM, .ai_flags = passive ? AI_PASSIVE : 0};
    char p[24];
    snprintf(p, sizeof p, "%lld", (long long)port);
    int rc = getaddrinfo(host->len ? host->data : NULL, p, &hints, res);
    if (rc != 0) errno = rc == EAI_SYSTEM ? errno : EADDRNOTAVAIL;
    return rc;
}

zs_int zs_tcp_listen(zs_str *host, zs_int port) {
    struct addrinfo *res;
    if (resolve(host, port, true, &res) != 0) return failed();
    int fd = socket(res->ai_family, res->ai_socktype | SOCK_NONBLOCK | SOCK_CLOEXEC, res->ai_protocol);
    int one = 1;
    if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (fd < 0 || bind(fd, res->ai_addr, res->ai_addrlen) != 0 || listen(fd, 4096) != 0) {
        int e = errno;
        if (fd >= 0) close(fd);
        freeaddrinfo(res);
        errno = e;
        return failed();
    }
    freeaddrinfo(res);
    return fd;
}

zs_int zs_tcp_accept(zs_int fd) {
    int c = accept4((int)fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (c < 0) return failed();
    int one = 1;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    return c;
}

// a connection being made: writable once it's made (or failed: zs_socket_error says)
zs_int zs_tcp_connect(zs_str *host, zs_int port) {
    struct addrinfo *res;
    if (resolve(host, port, false, &res) != 0) return failed();
    int fd = socket(res->ai_family, res->ai_socktype | SOCK_NONBLOCK | SOCK_CLOEXEC, res->ai_protocol);
    if (fd < 0 || (connect(fd, res->ai_addr, res->ai_addrlen) != 0 && errno != EINPROGRESS)) {
        int e = errno;
        if (fd >= 0) close(fd);
        freeaddrinfo(res);
        errno = e;
        return failed();
    }
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    freeaddrinfo(res);
    return fd;
}

zs_int zs_socket_error(zs_int fd) {
    int e = 0;
    socklen_t n = sizeof e;
    getsockopt((int)fd, SOL_SOCKET, SO_ERROR, &e, &n);
    return e;
}

zs_int zs_fd_read(zs_int fd, zs_bytes *b, zs_int off, zs_int n) {
    if (off < 0 || n < 0 || off > b->len || n > b->len - off) zs_panic_c("read: range out of the buffer");
    ssize_t r = read((int)fd, b->data + off, (size_t)n);
    return r < 0 ? failed() : r;
}

// writes from a Buffer<u8> or a string's bytes; a closed connection is an error, not SIGPIPE
zs_int zs_fd_write(zs_int fd, zs_bytes *b, zs_int off, zs_int n) {
    if (off < 0 || n < 0 || off > b->len || n > b->len - off) zs_panic_c("write: range out of the data");
    ssize_t r = send((int)fd, b->data + off, (size_t)n, MSG_NOSIGNAL);
    if (r < 0 && errno == ENOTSOCK) r = write((int)fd, b->data + off, (size_t)n);
    return r < 0 ? failed() : r;
}

void zs_fd_close(zs_int fd) {
    if ((size_t)fd < L.nfds) { // what waits for it can't happen any more
        zs_loop_unwait(fd, false);
        zs_loop_unwait(fd, true);
        L.fds[fd].armed = 0;
    }
    close((int)fd);
}

zs_str *zs_error_text(zs_int e) { return zs_str_from_c(e == -1000 ? "it would block" : strerror((int)(e < 0 ? -e : e))); }

// ---- the thread pool (Parallel): a worker per core (ZS_WORKERS sets how many), each with a
// Chase–Lev deque of jobs (Lê et al., PPoPP 2013): its owner pushes and pops at the bottom, and
// idle workers steal from the top. Fork-join: zs_par_fork pushes a job on the calling thread's
// deque, and zs_par_join runs it there if no one has stolen it, or else runs other jobs until
// it's done. A job is a Z# closure whose objects the compiler marked shared, and a runner (in
// the program's IR) that calls it and stores its result in the job, for the joining thread.
// The deques' accesses are release/acquire or seq_cst operations rather than fences, which
// ThreadSanitizer doesn't model.

typedef struct {
    void (*run)(void *clo, void *out);
    void *clo;
    atomic_int done;
    _Alignas(16) char result[]; // what run stores
} par_job;

typedef struct {
    atomic_llong top, bottom;
    _Atomic(_Atomic(par_job *) *) buf;
    atomic_llong cap; // a power of two
} par_deque;

static struct {
    int n;             // threads that run jobs: the workers, and the thread that started the pool
    pthread_t *threads;
    par_deque *deques; // one each; the starting thread's is the last
    pthread_mutex_t mu;
    pthread_cond_t cv;
    atomic_int sleeping;
    atomic_bool stop;
    void **old; // buffers replaced by bigger ones (a thief may still read one), freed at exit
    size_t nold;
    pthread_mutex_t oldmu;
} P;

static pthread_once_t pool_once = PTHREAD_ONCE_INIT;
static _Thread_local int me = -1; // this thread's deque, -1 for a thread outside the pool

static void dq_init(par_deque *q) {
    atomic_init(&q->top, 0);
    atomic_init(&q->bottom, 0);
    atomic_init(&q->cap, 64);
    _Atomic(par_job *) *b = calloc(64, sizeof *b);
    if (!b) zs_panic_c("out of memory");
    atomic_init(&q->buf, b);
}

static void dq_push(par_deque *q, par_job *j) {
    long long b = atomic_load_explicit(&q->bottom, memory_order_relaxed);
    long long t = atomic_load_explicit(&q->top, memory_order_acquire);
    long long cap = atomic_load_explicit(&q->cap, memory_order_relaxed);
    _Atomic(par_job *) *a = atomic_load_explicit(&q->buf, memory_order_relaxed);
    if (b - t >= cap - 1) { // full: twice as big, the old one kept for thieves still reading it
        _Atomic(par_job *) *n = calloc((size_t)cap * 2, sizeof *n);
        if (!n) zs_panic_c("out of memory");
        for (long long i = t; i < b; i++)
            atomic_store_explicit(&n[i & (cap * 2 - 1)], atomic_load_explicit(&a[i & (cap - 1)], memory_order_relaxed), memory_order_relaxed);
        pthread_mutex_lock(&P.oldmu);
        void **o = realloc(P.old, (P.nold + 1) * sizeof(void *));
        if (!o) zs_panic_c("out of memory");
        P.old = o;
        P.old[P.nold++] = (void *)a;
        pthread_mutex_unlock(&P.oldmu);
        atomic_store_explicit(&q->buf, n, memory_order_release);
        atomic_store_explicit(&q->cap, cap * 2, memory_order_release);
        a = n;
        cap *= 2;
    }
    atomic_store_explicit(&a[b & (cap - 1)], j, memory_order_relaxed);
    atomic_store_explicit(&q->bottom, b + 1, memory_order_release); // publishes the job
}

static par_job *dq_pop(par_deque *q) {
    long long b = atomic_load_explicit(&q->bottom, memory_order_relaxed) - 1;
    _Atomic(par_job *) *a = atomic_load_explicit(&q->buf, memory_order_relaxed);
    long long cap = atomic_load_explicit(&q->cap, memory_order_relaxed);
    atomic_store_explicit(&q->bottom, b, memory_order_seq_cst);
    long long t = atomic_load_explicit(&q->top, memory_order_seq_cst);
    par_job *x = NULL;
    if (t <= b) {
        x = atomic_load_explicit(&a[b & (cap - 1)], memory_order_relaxed);
        if (t == b) { // the last one: a thief may be taking it too
            if (!atomic_compare_exchange_strong_explicit(&q->top, &t, t + 1, memory_order_seq_cst, memory_order_relaxed)) x = NULL;
            atomic_store_explicit(&q->bottom, b + 1, memory_order_relaxed);
        }
    } else {
        atomic_store_explicit(&q->bottom, b + 1, memory_order_relaxed);
    }
    return x;
}

static par_job *dq_steal(par_deque *q) {
    long long t = atomic_load_explicit(&q->top, memory_order_seq_cst);
    long long b = atomic_load_explicit(&q->bottom, memory_order_seq_cst);
    if (t >= b) return NULL;
    _Atomic(par_job *) *a = atomic_load_explicit(&q->buf, memory_order_acquire);
    long long cap = atomic_load_explicit(&q->cap, memory_order_acquire);
    par_job *x = atomic_load_explicit(&a[t & (cap - 1)], memory_order_relaxed);
    if (!atomic_compare_exchange_strong_explicit(&q->top, &t, t + 1, memory_order_seq_cst, memory_order_relaxed)) return NULL;
    return x;
}

static void run_job(par_job *j) {
    j->run(j->clo, j->result);
    atomic_store_explicit(&j->done, 1, memory_order_release);
}

// a job from another thread's deque, starting at a different one each time
static par_job *steal_any(unsigned *seed) {
    for (int k = 0; k < P.n; k++) {
        *seed = *seed * 1103515245u + 12345u;
        int v = (int)((*seed >> 8) % (unsigned)P.n);
        if (v == me) continue;
        par_job *x = dq_steal(&P.deques[v]);
        if (x) return x;
    }
    return NULL;
}

static bool work_left(void) {
    for (int k = 0; k < P.n; k++)
        if (atomic_load_explicit(&P.deques[k].top, memory_order_relaxed) < atomic_load_explicit(&P.deques[k].bottom, memory_order_relaxed)) return true;
    return false;
}

static void *worker_main(void *arg) {
    me = (int)(intptr_t)arg;
    unsigned seed = (unsigned)me * 2654435761u + 1;
    while (!atomic_load_explicit(&P.stop, memory_order_acquire)) {
        par_job *j = dq_pop(&P.deques[me]);
        if (!j) j = steal_any(&seed);
        if (j) {
            run_job(j);
            continue;
        }
        // nothing to do: look a little longer, then sleep until a fork wakes this thread
        bool found = false;
        for (int spin = 0; spin < 64 && !found; spin++) {
            sched_yield();
            found = work_left();
        }
        if (found) continue;
        pthread_mutex_lock(&P.mu);
        atomic_fetch_add(&P.sleeping, 1);
        while (!atomic_load(&P.stop) && !work_left()) {
            struct timespec t;
            clock_gettime(CLOCK_REALTIME, &t);
            t.tv_nsec += 1000000; // 1 ms: a wake-up that comes between the test and the wait isn't lost for long
            if (t.tv_nsec >= 1000000000) {
                t.tv_sec++;
                t.tv_nsec -= 1000000000;
            }
            pthread_cond_timedwait(&P.cv, &P.mu, &t);
        }
        atomic_fetch_sub(&P.sleeping, 1);
        pthread_mutex_unlock(&P.mu);
    }
    return NULL;
}

static void pool_stop(void) {
    atomic_store(&P.stop, true);
    pthread_mutex_lock(&P.mu);
    pthread_cond_broadcast(&P.cv);
    pthread_mutex_unlock(&P.mu);
    for (int k = 0; k < P.n - 1; k++) pthread_join(P.threads[k], NULL);
    for (int k = 0; k < P.n; k++) free((void *)atomic_load(&P.deques[k].buf));
    for (size_t k = 0; k < P.nold; k++) free(P.old[k]);
    free(P.old);
    free(P.deques);
    free(P.threads);
}

static void pool_start(void) {
    const char *w = getenv("ZS_WORKERS");
    long n = w ? strtol(w, NULL, 10) : sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    P.n = (int)n;
    P.deques = calloc((size_t)n, sizeof(par_deque));
    P.threads = calloc((size_t)n, sizeof(pthread_t));
    if (!P.deques || !P.threads) zs_panic_c("out of memory");
    for (int k = 0; k < P.n; k++) dq_init(&P.deques[k]);
    pthread_mutex_init(&P.mu, NULL);
    pthread_cond_init(&P.cv, NULL);
    pthread_mutex_init(&P.oldmu, NULL);
    me = P.n - 1; // the thread starting the pool runs jobs with the last deque
    for (int k = 0; k < P.n - 1; k++)
        if (pthread_create(&P.threads[k], NULL, worker_main, (void *)(intptr_t)k) != 0) zs_panic_c("pthread_create failed");
    atexit(pool_stop);
}

zs_int zs_par_workers(void) {
    pthread_once(&pool_once, pool_start);
    return P.n;
}

// a job running clo (the job takes its reference) with run, whose result takes size bytes
void *zs_par_fork(void *clo, void (*run)(void *, void *), zs_int size) {
    pthread_once(&pool_once, pool_start);
    par_job *j = aligned_alloc(16, (sizeof(par_job) + (size_t)size + 15) & ~(size_t)15);
    if (!j) zs_panic_c("out of memory");
    j->run = run;
    j->clo = clo;
    atomic_init(&j->done, 0);
    if (me < 0) { // a thread outside the pool (Task.blocking's helper, a task's loop): here
        run_job(j);
        return j;
    }
    dq_push(&P.deques[me], j);
    if (atomic_load_explicit(&P.sleeping, memory_order_relaxed) > 0) {
        pthread_mutex_lock(&P.mu);
        pthread_cond_signal(&P.cv);
        pthread_mutex_unlock(&P.mu);
    }
    return j;
}

// waits for the job, running others meanwhile: its result, which the caller moves out before
// zs_par_free
void *zs_par_join(void *jv) {
    par_job *j = jv;
    unsigned seed = (unsigned)(uintptr_t)j;
    while (!atomic_load_explicit(&j->done, memory_order_acquire)) {
        // the newest job on our deque is this one unless it was stolen: then help with others
        par_job *x = me >= 0 ? dq_pop(&P.deques[me]) : NULL;
        if (!x && me >= 0) x = steal_any(&seed);
        if (x) run_job(x);
        else sched_yield();
    }
    return j->result;
}

void zs_par_free(void *j) { free(j); }

// ---- locks (Mutex): a 32-bit word, 0 free, 1 held, 2 held with threads waiting (Drepper,
// "Futexes are tricky"); on Linux the waiting threads sleep in the kernel
#ifdef __linux__
#include <linux/futex.h>
#include <sys/syscall.h>
static void futex_wait(atomic_int *l, int v) { syscall(SYS_futex, l, FUTEX_WAIT_PRIVATE, v, NULL, NULL, 0); }
static void futex_wake(atomic_int *l) { syscall(SYS_futex, l, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0); }
#else
static void futex_wait(atomic_int *l, int v) { (void)l, (void)v, sched_yield(); }
static void futex_wake(atomic_int *l) { (void)l; }
#endif

void zs_lock(atomic_int *l) {
    int c = 0;
    if (atomic_compare_exchange_strong_explicit(l, &c, 1, memory_order_acquire, memory_order_relaxed)) return;
    if (c != 2) c = atomic_exchange_explicit(l, 2, memory_order_acquire);
    while (c != 0) {
        futex_wait(l, 2);
        c = atomic_exchange_explicit(l, 2, memory_order_acquire);
    }
}

void zs_unlock(atomic_int *l) {
    if (atomic_fetch_sub_explicit(l, 1, memory_order_release) != 1) {
        atomic_store_explicit(l, 0, memory_order_release);
        futex_wake(l);
    }
}

// ---- channels (Channel): a bounded queue for any number of senders and receivers, a ring of
// fixed-size slots holding the values' bytes (the compiler marked them shared), under a lock.
// A Z# object: its count is the header, and the drop function it was made with drops what's
// still in it when it's freed.
typedef struct {
    zs_int rc;
    pthread_mutex_t mu;
    pthread_cond_t not_empty, not_full;
    zs_int cap, size, head, len;
    bool closed;
    void (*drop)(void *slot);
    char *slots;
} zs_chan;

void *zs_chan_new(zs_int cap, zs_int size, void (*drop)(void *)) {
    zs_chan *c = zs_alloc((zs_int)sizeof(zs_chan));
    c->rc = 1;
    pthread_mutex_init(&c->mu, NULL);
    pthread_cond_init(&c->not_empty, NULL);
    pthread_cond_init(&c->not_full, NULL);
    c->cap = cap;
    c->size = size;
    c->head = c->len = 0;
    c->closed = false;
    c->drop = drop;
    c->slots = malloc((size_t)(cap * (size ? size : 1)));
    if (!c->slots) zs_panic_c("out of memory");
    return c;
}

// waits while it's full; the value's bytes move in
void zs_chan_send(zs_chan *c, void *slot) {
    pthread_mutex_lock(&c->mu);
    while (c->len == c->cap && !c->closed) pthread_cond_wait(&c->not_full, &c->mu);
    if (c->closed) {
        pthread_mutex_unlock(&c->mu);
        zs_panic_c("Channel.send: the channel is closed");
    }
    memcpy(c->slots + ((c->head + c->len) % c->cap) * c->size, slot, (size_t)c->size);
    c->len++;
    pthread_cond_signal(&c->not_empty);
    pthread_mutex_unlock(&c->mu);
}

// waits for a value (true: its bytes moved into slot), or until it's closed and empty (false)
bool zs_chan_recv(zs_chan *c, void *slot) {
    pthread_mutex_lock(&c->mu);
    while (c->len == 0 && !c->closed) pthread_cond_wait(&c->not_empty, &c->mu);
    bool got = c->len > 0;
    if (got) {
        memcpy(slot, c->slots + c->head * c->size, (size_t)c->size);
        c->head = (c->head + 1) % c->cap;
        c->len--;
        pthread_cond_signal(&c->not_full);
    }
    pthread_mutex_unlock(&c->mu);
    return got;
}

// no more values: receivers get what's left, then None; a send panics
void zs_chan_close(zs_chan *c) {
    pthread_mutex_lock(&c->mu);
    c->closed = true;
    pthread_cond_broadcast(&c->not_empty);
    pthread_cond_broadcast(&c->not_full);
    pthread_mutex_unlock(&c->mu);
}

void zs_chan_free(zs_chan *c) {
    if (c->drop)
        for (zs_int i = 0; i < c->len; i++) c->drop(c->slots + ((c->head + i) % c->cap) * c->size);
    pthread_mutex_destroy(&c->mu);
    pthread_cond_destroy(&c->not_empty);
    pthread_cond_destroy(&c->not_full);
    free(c->slots);
    zs_free(c);
}
