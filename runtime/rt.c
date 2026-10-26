// Z# runtime: allocation, panics, strings. Linked into every Z# program.
#define _GNU_SOURCE
#define _CRT_RAND_S // Windows's rand_s, the system's randomness (Random.shared)
#include <inttypes.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#if defined(__GLIBC__) || defined(__APPLE__)
#include <execinfo.h> // backtraces; musl (cross-compiled builds) has none
#endif

// Windows (x86_64-windows-gnu: mingw-w64 over the UCRT, threads through winpthreads): Winsock
// before windows.h, and the POSIX names the UCRT spells differently or lacks
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <afunix.h>
#include <windows.h>
#include <direct.h>
#include <fcntl.h>
#include <io.h>
#include <sys/utime.h>
#include <locale.h>
// no aligned_alloc: _aligned_malloc's memory goes back through _aligned_free, so every block
// the runtime frees as an object, an arena's block or a pool job comes from it
#define aligned_alloc(a, n) _aligned_malloc((n), (a))
#define obj_malloc(n) _aligned_malloc((n), 16)
#define obj_free _aligned_free
#define mkdir(path, mode) _mkdir(path)
// every open() here is close-on-exec, and on Windows binary (no \r\n translation) too
#define O_CLOEXEC (_O_NOINHERIT | _O_BINARY)
#else
#define obj_malloc malloc
#define obj_free free
#endif

#ifdef _WIN32
// LLVM's llvm.roundeven calls these, and mingw-w64's libm lacks them: the default rounding mode
// is to nearest, ties to even
#include <math.h>
double roundeven(double x) { return nearbyint(x); }
float roundevenf(float x) { return nearbyintf(x); }
#endif

// the processors online (ZS_WORKERS overrides it where threads are started)
static long cpu_count(void) {
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return (long)si.dwNumberOfProcessors;
#else
    return sysconf(_SC_NPROCESSORS_ONLN);
#endif
}

// zs_int: Z#'s int, the machine word
typedef intptr_t zs_int;

// Every heap object starts with a header word: a 32-bit reference count (1+ = live, 0 = static,
// never freed, below 0 = shared between threads), then the tag of a union's case (bytes 4-5) and
// where the object came from (byte 6, the pool's; zs_alloc sets it). C code sets the count and
// leaves the rest.
#define ZS_HEADER \
    int32_t rc;   \
    uint32_t meta

typedef struct {
    ZS_HEADER;
    zs_int len;
    char data[]; // len bytes + NUL
} zs_str;

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
    fflush(stderr); // the UCRT buffers it when it isn't a console
#if defined(__GLIBC__) || defined(__APPLE__)
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

// The objects counted: allocated now (reported at exit when ZS_LEAKCHECK is set), allocated in
// all (Runtime.allocations, ZS_STATS) and the system allocator's calls (Runtime.mallocs). With
// threads (the driver compiles this file with ZS_THREADS then) each thread counts its own, in a
// cache line of its own, so no allocation waits on another thread's; a total sums them all, the
// threads that ended too.
#ifdef ZS_THREADS
#include <pthread.h>
#include <stddef.h>
typedef struct counts {
    int64_t live, allocations, mallocs;
    struct counts *next;
} counts;
static counts *all_counts; // every thread's that counted, the newest first
static pthread_mutex_t counts_mu = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local counts *my_counts;

static counts *here(void) {
    counts *c = my_counts;
    if (!c) {
        c = aligned_alloc(64, 64);
        if (!c) zs_panic_c("out of memory");
        memset(c, 0, 64);
        pthread_mutex_lock(&counts_mu);
        c->next = all_counts;
        all_counts = c;
        pthread_mutex_unlock(&counts_mu);
        my_counts = c;
    }
    return c;
}

// only the thread itself writes its counts; another reads them whole
#define COUNT(x, d) do { counts *c_ = here(); __atomic_store_n(&c_->x, c_->x + (d), __ATOMIC_RELAXED); } while (0)

static int64_t total(size_t at) {
    int64_t n = 0;
    pthread_mutex_lock(&counts_mu);
    for (counts *c = all_counts; c; c = c->next) n += __atomic_load_n((int64_t *)((char *)c + at), __ATOMIC_RELAXED);
    pthread_mutex_unlock(&counts_mu);
    return n;
}
#define TOTAL(x) total(offsetof(counts, x))
#else
static int64_t live, allocations, mallocs;
#define COUNT(x, d) ((x) += (d))
#define TOTAL(x) (x)
#endif

// Objects come from a pool: 8-byte size classes up to 256 bytes, each with a free list, carved
// from 64 KB chunks; a freed object goes on its class's list, and the next allocation of that
// size takes it (no system allocator call either way). With threads, each thread has lists and a
// chunk of its own: an object goes on the list of the thread that frees it, whichever made it,
// so no lock and no atomic either. Byte 6 of the header says where an object came from: its
// class, or SYSTEM for malloc and aligned_alloc. With a sanitizer or valgrind (ZS_NO_POOL), it's
// plain malloc, so the tools see every object.
// ponytail: chunks are kept until exit; a program whose small objects peak once keeps that
// memory, and so does a thread that frees objects of a size it doesn't make (a consumer's)
#if !defined(ZS_NO_POOL)
#define ZS_POOL 1
#define POOL_MAX 256
#define POOL_CHUNK ((size_t)64 * 1024)
#define FROM(p) (((uint8_t *)(p))[6])
#define SYSTEM 0xFF
#ifdef ZS_THREADS
#define POOL_LOCAL _Thread_local
#else
#define POOL_LOCAL
#endif
static POOL_LOCAL void *pool_free[POOL_MAX / 8 + 1];
static POOL_LOCAL char *pool_next, *pool_end;

static void pool_chunk(void) {
    pool_next = malloc(POOL_CHUNK);
    if (!pool_next) zs_panic_c("out of memory");
    pool_end = pool_next + POOL_CHUNK;
    COUNT(mallocs, 1);
}
#endif

void *zs_alloc(zs_int size) {
    COUNT(live, 1);
    COUNT(allocations, 1);
#if ZS_POOL
    size_t total = ((size_t)size + 7) & ~(size_t)7;
    void *p;
    if (total <= POOL_MAX) {
        size_t c = total >> 3;
        p = pool_free[c];
        if (p) {
            pool_free[c] = *(void **)p;
        } else {
            if ((size_t)(pool_end - pool_next) < total) pool_chunk();
            p = pool_next;
            pool_next += total;
        }
        FROM(p) = (uint8_t)c;
        return p;
    }
    p = obj_malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    COUNT(mallocs, 1);
    FROM(p) = SYSTEM;
    return p;
#else
    void *p = obj_malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    COUNT(mallocs, 1);
    return p;
#endif
}

// zs_alloc for a program with SIMD vectors (the compiler swaps it in): each object aligned to
// 64 bytes, so a vector field or element is aligned as LLVM expects
void *zs_alloc_wide(zs_int size) {
    COUNT(live, 1);
    COUNT(allocations, 1);
    COUNT(mallocs, 1);
    void *p = aligned_alloc(64, ((size_t)size + 63) & ~(size_t)63);
    if (!p) zs_panic_c("out of memory");
#if ZS_POOL
    FROM(p) = SYSTEM;
#endif
    return p;
}

// a task's state machine: its face and coroutine frame, in one object 64-byte aligned (the frame
// may hold values that need 16)
void *zs_coro_alloc(zs_int size) { return zs_alloc_wide(size); }

/// Runtime.allocations (): heap objects allocated so far (tests check copy-on-write with it).
zs_int zs_allocations(void) { return TOTAL(allocations); }

/// Runtime.mallocs (): the times memory was taken from the system allocator, for an object or
/// for an arena's block.
zs_int zs_mallocs(void) { return TOTAL(mallocs); }

/// The objects marked shared at crossings to other threads (DESIGN §7.1; a moved value's own
/// objects aren't, decision 75): compiled code adds to it, Runtime.marks () reads it.
zs_int zs_marked;

zs_int zs_marks(void) { return __atomic_load_n(&zs_marked, __ATOMIC_RELAXED); }

// ZS_STATS=1: what reference counting cost, on standard error at exit
static void print_stats(void) {
    fprintf(stderr, "zs stats: %lld allocations, %lld objects marked shared\n", (long long)TOTAL(allocations), (long long)zs_marks());
}

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
// the real-time clock, in nanoseconds since 1970-01-01T00:00:00Z (DateTime.utcNow)
int64_t zs_clock_realtime(void) {
    struct timespec t;
    clock_gettime(CLOCK_REALTIME, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

// Random.shared's seed: 8 bytes of the operating system's randomness
#ifdef __APPLE__
#include <sys/random.h>
#endif
uint64_t zs_random_seed(void) {
    uint64_t s = 0;
#ifdef _WIN32
    unsigned int a = 0, b = 0;
    rand_s(&a);
    rand_s(&b);
    s = (uint64_t)a << 32 | b;
#else
    if (getentropy(&s, sizeof s) != 0) s = (uint64_t)zs_clock_realtime() ^ (uint64_t)getpid() << 32;
#endif
    return s;
}

int64_t zs_ticks(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

void zs_free(void *p) {
    COUNT(live, -1);
#if ZS_POOL
    size_t c = FROM(p);
    if (c - 1 < POOL_MAX / 8) {
        *(void **)p = pool_free[c];
        pool_free[c] = p;
    } else if (c == SYSTEM) {
        obj_free(p);
    } else {
        zs_panic_c("an object's header was overwritten (zs_free)");
    }
#else
    obj_free(p);
#endif
}

// ---- handles: a Z# object held by C (zs_handle in a generated header). A handle has a count of
// its own (zs_retain, zs_release) and holds one reference to the object, which the object's drop
// function gives up when the handle's last reference goes. A Share value's handle (shared) may
// be used from any thread: its objects are marked shared, and its count is atomic. Any other
// belongs to the thread that made it, and a use on another one panics, naming its type.
#include <pthread.h>

typedef struct {
    ZS_HEADER;
    void (*drop)(void *);
    void *obj;
    const char *type;
    pthread_t owner;
    bool shared;
} zs_handle;

zs_handle *zs_handle_new(void *obj, void (*drop)(void *), bool shared, const char *type) {
    zs_handle *h = zs_alloc((zs_int)sizeof(zs_handle));
    h->rc = 1;
    h->drop = drop;
    h->obj = obj;
    h->type = type;
    h->owner = pthread_self();
    h->shared = shared;
    return h;
}

// a thread's handle used on another thread: a panic naming what it holds
static void handle_check(zs_handle *h, const char *what) {
    if (h->shared || pthread_equal(h->owner, pthread_self())) return;
    char msg[512];
    snprintf(msg, sizeof msg, "%s: a handle of %s used from another thread (make its type Share, or use it on the thread that made it)", what, h->type);
    zs_panic_c(msg);
}

// the object, with a new reference for Z#
void *zs_handle_get(zs_handle *h) {
    if (!h) zs_panic_c("a null zs_handle was passed to Z#");
    handle_check(h, "a call into Z#");
    int32_t *rc = h->obj;
    if (*rc > 0) (*rc)++;
    else if (*rc < 0) __atomic_fetch_sub(rc, 1, __ATOMIC_RELAXED); // a shared object's count
    return h->obj;
}

void zs_retain(zs_handle *h) {
    if (!h) return;
    handle_check(h, "zs_retain");
    if (h->shared) __atomic_fetch_add(&h->rc, 1, __ATOMIC_RELAXED);
    else h->rc++;
}

void zs_release(zs_handle *h) {
    if (!h) return;
    handle_check(h, "zs_release");
    if (h->shared ? __atomic_fetch_sub(&h->rc, 1, __ATOMIC_ACQ_REL) > 1 : --h->rc > 0) return;
    void *obj = h->obj;
    void (*drop)(void *) = h->drop;
    zs_free(h);
    drop(obj);
}

// a callback C calls on another thread than the one that passed it (callback<F>, unless
// declared callback<share<F>>): a panic naming its type
void zs_callback_thread(pthread_t *owner, const char *type) {
    if (pthread_equal(*owner, pthread_self())) return;
    char msg[512];
    snprintf(msg, sizeof msg, "a callback<%s> called from another thread (declare the parameter callback<share<%s>>, and pass a share<%s>, for one C may call on any thread)", type, type, type);
    zs_panic_c(msg);
}

// where a callback is passed: the thread it may be called on
void zs_callback_owner(pthread_t *owner) { *owner = pthread_self(); }

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
    ZS_HEADER;
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
    bool dies = __atomic_load_n((int32_t *)target, __ATOMIC_RELAXED) != 0; // a static object never does: its cells aren't in the table
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
    int32_t *t = w->target;
    if (t) {
        int32_t c = __atomic_load_n(t, __ATOMIC_RELAXED);
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
        obj_free(b);
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
    size_t n = ((size_t)size + 7) & ~(size_t)7; // 8-byte aligned, as the pool's (a program with vectors has no arenas: its objects are zs_alloc_wide's)
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

static void boxes_sweep(void);

static void leak_report(void) {
    if (getenv("ZS_LEAKCHECK") && TOTAL(live) != 0)
        fprintf(stderr, "leak check: %" PRId64 " object(s) still allocated\n", TOTAL(live));
}

__attribute__((constructor)) static void zs_init(void) {
    atexit(leak_report);
    atexit(boxes_sweep); // before the leak report; after what's registered later (the loop threads' stop)
}

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

// a vector's lanes as text, <1, 2, 3>: kind is the element type (0 f32, 1 f64, 2 i8, 3 i16,
// 4 i32, 5 i64, 6 u8, 7 u16, 8 u32, 9 u64; 10 a mask's lanes, as bytes), n the number of lanes
zs_str *zs_str_of_lanes(const void *p, zs_int kind, zs_int n) {
    static const int sizes[] = {4, 8, 1, 2, 4, 8, 1, 2, 4, 8, 1};
    size_t cap = 64, len = 0;
    char *buf = malloc(cap);
    if (!buf) zs_panic_c("out of memory");
    buf[len++] = '<';
    for (zs_int i = 0; i < n; i++) {
        const char *q = (const char *)p + i * sizes[kind];
        zs_str *s;
        switch (kind) {
        case 0: s = zs_str_of_f32(*(const float *)q); break;
        case 1: s = zs_str_of_f64(*(const double *)q); break;
        case 2: s = zs_str_of_i64(*(const int8_t *)q); break;
        case 3: s = zs_str_of_i64(*(const int16_t *)q); break;
        case 4: s = zs_str_of_i64(*(const int32_t *)q); break;
        case 5: s = zs_str_of_i64(*(const int64_t *)q); break;
        case 6: s = zs_str_of_u64(*(const uint8_t *)q); break;
        case 7: s = zs_str_of_u64(*(const uint16_t *)q); break;
        case 8: s = zs_str_of_u64(*(const uint32_t *)q); break;
        case 9: s = zs_str_of_u64(*(const uint64_t *)q); break;
        default: s = zs_str_of_bool(*(const uint8_t *)q != 0); break;
        }
        if (len + (size_t)s->len + 3 > cap) {
            cap = 2 * (len + (size_t)s->len + 3);
            char *nb = realloc(buf, cap);
            if (!nb) zs_panic_c("out of memory");
            buf = nb;
        }
        if (i > 0) {
            buf[len++] = ',';
            buf[len++] = ' ';
        }
        memcpy(buf + len, s->data, (size_t)s->len);
        len += (size_t)s->len;
        zs_free(s);
    }
    buf[len++] = '>';
    zs_str *r = str_of(buf, (zs_int)len);
    free(buf);
    return r;
}


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

static int int_text(zs_int v, char *out) { return snprintf(out, 24, "%lld", (long long)v); }

// ---- slices and spans

static int text_of(const char *t, char *out) {
    int k = 0;
    while (t[k]) {
        out[k] = t[k];
        k++;
    }
    return k;
}

// a slice i..j (inclusive) of something of length n that doesn't fit in it
_Noreturn void zs_slice_fail(zs_int i, zs_int j, zs_int n, zs_int kind) {
    static const char *what[] = { "an array", "a Buffer", "a span", "a string" };
    char msg[128];
    int k = text_of("slice ", msg);
    k += int_text(i, msg + k);
    k += text_of("..", msg + k);
    k += int_text(j, msg + k);
    k += text_of(" of ", msg + k);
    k += text_of(what[kind & 3], msg + k);
    k += text_of(" of length ", msg + k);
    k += int_text(n, msg + k);
    msg[k] = 0;
    zs_panic_c(msg);
}

// Fixed.ofArray of an array that hasn't the type's length
_Noreturn void zs_fixed_fail(const char *type, zs_int len) {
    char msg[160];
    int k = text_of(type, msg);
    k += text_of(" from an array of length ", msg + k);
    k += int_text(len, msg + k);
    msg[k] = 0;
    zs_panic_c(msg);
}

static bool inside_char(zs_str *s, zs_int at) { return at > 0 && at < s->len && ((uint8_t)s->data[at] & 0xC0) == 0x80; }

// s.[i..j]: a copy of bytes i to j, which mustn't cut a character
zs_str *zs_str_slice(zs_str *s, zs_int i, zs_int j) {
    if (i < 0 || j >= s->len || i > j + 1) zs_slice_fail(i, j, s->len, 3);
    zs_int at = inside_char(s, i) ? i : inside_char(s, j + 1) ? j + 1 : -1;
    if (at >= 0) {
        char msg[64];
        int k = text_of("byte ", msg);
        k += int_text(at, msg + k);
        k += text_of(" is inside a character", msg + k);
        msg[k] = 0;
        zs_panic_c(msg);
    }
    return str_of(s->data + i, j - i + 1);
}

// the length of the UTF-8 sequence at p (n bytes left) as String.decodeAt reads it, or 0 when
// it's malformed
static zs_int utf8_seq(const uint8_t *p, zs_int n) {
    zs_int k = p[0] < 0x80 ? 1 : (p[0] & 0xE0) == 0xC0 ? 2 : (p[0] & 0xF0) == 0xE0 ? 3 : (p[0] & 0xF8) == 0xF0 ? 4 : 0;
    if (k == 0 || k > n) return 0;
    for (zs_int i = 1; i < k; i++)
        if ((p[i] & 0xC0) != 0x80) return 0;
    return k;
}

// String.ofBytes: a copy of the bytes, each malformed one replaced by U+FFFD (decision 28)
zs_str *zs_str_of_bytes(const uint8_t *p, zs_int n) {
    zs_int len = 0;
    for (zs_int i = 0; i < n;) {
        uint64_t w;
        if (i + 8 <= n && (memcpy(&w, p + i, 8), (w & 0x8080808080808080ull) == 0)) {
            len += 8; // eight ASCII bytes
            i += 8;
            continue;
        }
        zs_int k = utf8_seq(p + i, n - i);
        len += k ? k : 3;
        i += k ? k : 1;
    }
    if (len == n) return str_of((const char *)p, n); // well-formed (a malformed byte counts 3)
    zs_str *s = str_new(len);
    char *out = s->data;
    for (zs_int i = 0; i < n;) {
        zs_int k = utf8_seq(p + i, n - i);
        memcpy(out, k ? (const char *)p + i : "\xEF\xBF\xBD", (size_t)(k ? k : 3));
        out += k ? k : 3;
        i += k ? k : 1;
    }
    return s;
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

// ---- format specifiers ($"{x:F2}", 0024): .NET's standard numeric formats, invariant

// a specifier's letter and its digits (-1 when it has none)
static void spec_of(zs_str *spec, char *letter, int *digits) {
    *letter = spec->len > 0 ? spec->data[0] : 'G';
    *digits = -1;
    if (spec->len > 1) {
        *digits = 0;
        for (zs_int i = 1; i < spec->len && i < 3; i++) *digits = *digits * 10 + (spec->data[i] - '0');
    }
}

// the digits of a decimal text's integer part with a comma every three (N)
static int group(const char *in, char *out) {
    int k = 0, start = in[0] == '-' ? 1 : 0;
    const char *point = strchr(in, '.');
    int whole = (int)(point ? point - in : (long)strlen(in)) - start;
    if (start) out[k++] = '-';
    for (int i = 0; i < whole; i++) {
        if (i > 0 && (whole - i) % 3 == 0) out[k++] = ',';
        out[k++] = in[start + i];
    }
    if (point) { strcpy(out + k, point); k += (int)strlen(point); }
    out[k] = 0;
    return k;
}

// x with d decimals, a tie rounded away from zero (as .NET's F does); glibc's %f rounds the
// exact value, ties to even, so a tie is found in the exact expansion and rounded here
static int fixed(double x, int d, char *out, size_t cap) {
    char exact[1500]; // on the stack: any thread formats
    snprintf(exact, sizeof exact, "%.*f", 1100, x); // every digit of a double's expansion
    char *point = strchr(exact, '.');
    bool tie = point && point[d + 1] == '5';
    for (int i = d + 2; tie && point[i]; i++) tie = point[i] == '0';
    if (!tie) return snprintf(out, cap, "%.*f", d, x);
    // the expansion cut after d decimals, then one more in its last digit
    int n = (int)(point - exact) + (d > 0 ? d + 1 : 0);
    exact[n] = 0;
    for (int i = n - 1; i >= 0; i--) {
        if (exact[i] == '.' || exact[i] == '-') continue;
        if (exact[i] < '9') { exact[i]++; return snprintf(out, cap, "%s", exact); }
        exact[i] = '0';
    }
    // all nines: one more digit in front
    bool neg = exact[0] == '-';
    return snprintf(out, cap, "%s1%s", neg ? "-" : "", exact + (neg ? 1 : 0));
}

zs_str *zs_format_float(double x, zs_str *spec) {
    char buf[1600], grouped[2200];
    char letter;
    int d, n;
    spec_of(spec, &letter, &d);
    switch (letter) {
    case 'F': n = fixed(x, d < 0 ? 2 : d, buf, sizeof buf); break;
    case 'N': fixed(x, d < 0 ? 2 : d, buf, sizeof buf); n = group(buf, grouped); return str_of(grouped, n);
    case 'E': {
        // 1.23E+003: the exponent with its sign and at least three digits
        n = snprintf(buf, sizeof buf, "%.*E", d < 0 ? 6 : d, x);
        char *e = strchr(buf, 'E');
        if (e) {
            int exp = atoi(e + 1);
            n = (int)(e - buf) + snprintf(e, sizeof buf - (size_t)(e - buf), "E%c%03d", exp < 0 ? '-' : '+', exp < 0 ? -exp : exp);
        }
        break;
    }
    default: // G
        if (d <= 0) return zs_str_of_f64(x);
        n = snprintf(buf, sizeof buf, "%.*G", d, x);
    }
    return str_of(buf, n);
}

// v at a width of bits bits (unsigned: its bits as they are), under a specifier
zs_str *zs_format_int(int64_t v, int64_t bits, bool isUnsigned, zs_str *spec) {
    char buf[200], grouped[300];
    char letter;
    int d, n;
    spec_of(spec, &letter, &d);
    uint64_t mask = bits >= 64 ? ~(uint64_t)0 : ((uint64_t)1 << bits) - 1;
    uint64_t u = (uint64_t)v & mask; // two's complement at the type's width
    switch (letter) {
    case 'X':
    case 'x':
        n = snprintf(buf, sizeof buf, letter == 'X' ? "%0*llX" : "%0*llx", d < 0 ? 1 : d, (unsigned long long)u);
        break;
    case 'B':
    case 'b': {
        // the bits from the highest set one, zero-padded to d
        int k = 0;
        for (int i = 63; i >= 0; i--)
            if (k > 0 || ((u >> i) & 1) || i == 0) buf[k++] = (char)('0' + ((u >> i) & 1));
        int pad = d > k ? d - k : 0;
        memmove(buf + pad, buf, (size_t)k);
        memset(buf, '0', (size_t)pad);
        n = k + pad;
        break;
    }
    case 'F':
    case 'N': {
        char whole[40];
        if (isUnsigned) snprintf(whole, sizeof whole, "%llu", (unsigned long long)u);
        else snprintf(whole, sizeof whole, "%lld", (long long)v);
        int decimals = d < 0 ? 2 : d;
        n = snprintf(buf, sizeof buf, decimals > 0 ? "%s.%0*d" : "%s", whole, decimals, 0);
        if (letter == 'N') { n = group(buf, grouped); return str_of(grouped, n); }
        break;
    }
    default: // D
        if (isUnsigned) n = snprintf(buf, sizeof buf, "%0*llu", d < 0 ? 1 : d, (unsigned long long)u);
        else if (v < 0) n = snprintf(buf, sizeof buf, "-%0*llu", d < 0 ? 1 : d, (unsigned long long)-(uint64_t)v);
        else n = snprintf(buf, sizeof buf, "%0*lld", d < 0 ? 1 : d, (long long)v);
    }
    return str_of(buf, n);
}

// ---- Int.parse and Float.parse (0024)

// the integer s writes in radix 2 to 36 (an optional sign, then its digits, letters in either
// case, and nothing else), at a type of bits bits; false for anything else or a value out of
// the type's range. *out holds the value's bits (a u64 above i64's range too).
bool zs_parse_int(zs_str *s, int64_t radix, bool isUnsigned, int64_t bits, int64_t *out) {
    zs_int i = 0, n = s->len;
    bool neg = false;
    if (n > 0 && (s->data[0] == '-' || s->data[0] == '+')) { neg = s->data[0] == '-'; i = 1; }
    if (i == n || radix < 2 || radix > 36) return false;
    uint64_t acc = 0;
    for (; i < n; i++) {
        char c = s->data[i];
        int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'z' ? c - 'a' + 10 : c >= 'A' && c <= 'Z' ? c - 'A' + 10 : 99;
        if (d >= radix) return false;
        if (acc > (UINT64_MAX - (uint64_t)d) / (uint64_t)radix) return false;
        acc = acc * (uint64_t)radix + (uint64_t)d;
    }
    if (isUnsigned) {
        uint64_t max = bits >= 64 ? UINT64_MAX : ((uint64_t)1 << bits) - 1;
        if ((neg && acc != 0) || acc > max) return false;
        *out = (int64_t)acc;
    } else {
        uint64_t limit = (uint64_t)1 << (bits - 1); // the magnitude of the lowest value
        if (acc > (neg ? limit : limit - 1)) return false;
        *out = neg ? (int64_t)(0 - acc) : (int64_t)acc;
    }
    return true;
}

// the number s writes: a sign, digits, a point, an exponent; inf and nan; nothing else (no
// spaces, no hexadecimal, no 1,5)
bool zs_parse_float(zs_str *s, double *out) {
    char buf[400];
    if (s->len == 0 || s->len >= (zs_int)sizeof buf) return false;
    for (zs_int i = 0; i < s->len; i++) {
        char c = s->data[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 'x' || c == 'X' || c == 0) return false;
    }
    memcpy(buf, s->data, (size_t)s->len);
    buf[s->len] = 0;
    char *end;
    double v = strtod(buf, &end);
    if (end != buf + s->len) return false;
    *out = v;
    return true;
}

// ---- console

static bool at_eof;

#ifdef _WIN32
// the UCRT has no getline
static ssize_t getline(char **line, size_t *cap, FILE *f) {
    size_t n = 0;
    int c = EOF;
    while ((c = fgetc(f)) != EOF) {
        if (n + 2 > *cap) {
            *cap = *cap ? 2 * *cap : 128;
            char *l = realloc(*line, *cap);
            if (!l) zs_panic_c("out of memory");
            *line = l;
        }
        (*line)[n++] = (char)c;
        if (c == '\n') break;
    }
    if (n == 0) return -1;
    (*line)[n] = 0;
    return (ssize_t)n;
}
#endif

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
#include <sys/stat.h>
#ifndef _WIN32
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;
#endif
static int g_argc;
static char **g_argv;
static _Thread_local zs_str *io_error; // per thread: Task.blocking's helper reads files too

void zs_set_args(int32_t argc, char **argv) {
    g_argc = argc;
    g_argv = argv;
#ifdef _WIN32
    // the console in UTF-8, and standard output and error as bytes: println writes what Show
    // made, \n not turned into \r\n (an executable's manifest makes the rest UTF-8: argv, paths)
    setlocale(LC_CTYPE, ".UTF8"); // the C runtime's calls in UTF-8 too, as the manifest has the system's
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    setvbuf(stderr, NULL, _IONBF, 0); // unbuffered, as C has it (the UCRT buffers a pipe)
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    const char *stats = getenv("ZS_STATS");
    if (stats && *stats && strcmp(stats, "0") != 0) atexit(print_stats);
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

// ---- files and directories (0024)

#include <fcntl.h>

// path opened to read (0), to write from nothing (1) or to append (2): its fd, or -1 with the
// error for Native.ioError
zs_int zs_file_open(zs_str *path, zs_int mode) {
    clear_error();
#ifdef _WIN32
    // shared for deleting too, so an open file can be deleted or renamed, as on POSIX
    HANDLE h = CreateFileA(path->data, mode == 0 ? GENERIC_READ : mode == 1 ? GENERIC_WRITE : FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                           mode == 0 ? OPEN_EXISTING : mode == 1 ? CREATE_ALWAYS : OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    int fd = h == INVALID_HANDLE_VALUE ? -1 : _open_osfhandle((intptr_t)h, _O_BINARY | (mode == 0 ? _O_RDONLY : mode == 1 ? _O_WRONLY : _O_WRONLY | _O_APPEND));
    if (h == INVALID_HANDLE_VALUE) errno = GetLastError() == ERROR_FILE_NOT_FOUND || GetLastError() == ERROR_PATH_NOT_FOUND ? ENOENT : EACCES;
#else
    int flags = mode == 0 ? O_RDONLY : mode == 1 ? O_WRONLY | O_CREAT | O_TRUNC : O_WRONLY | O_CREAT | O_APPEND;
    int fd = open(path->data, flags | O_CLOEXEC, 0666);
#endif
    if (fd < 0) set_error("cannot open", path);
    return fd;
}

// the modification time in nanoseconds since 1970, and the size in bytes (-1 on an error)
int64_t zs_file_mtime(zs_str *path) {
    clear_error();
    struct stat st;
    if (stat(path->data, &st) != 0) {
        set_error("cannot read", path);
        return 0;
    }
#ifdef __APPLE__
    return (int64_t)st.st_mtimespec.tv_sec * 1000000000 + st.st_mtimespec.tv_nsec;
#elif defined(_WIN32)
    // stat has seconds only: the FILETIME's 100 ns ticks since 1601
    WIN32_FILE_ATTRIBUTE_DATA fa;
    if (!GetFileAttributesExA(path->data, GetFileExInfoStandard, &fa)) return (int64_t)st.st_mtime * 1000000000;
    int64_t ticks = (int64_t)(((uint64_t)fa.ftLastWriteTime.dwHighDateTime << 32) | fa.ftLastWriteTime.dwLowDateTime);
    return (ticks - 116444736000000000LL) * 100;
#else
    return (int64_t)st.st_mtim.tv_sec * 1000000000 + st.st_mtim.tv_nsec;
#endif
}

int64_t zs_file_size(zs_str *path) {
    clear_error();
    struct stat st;
    if (stat(path->data, &st) != 0) {
        set_error("cannot read", path);
        return 0;
    }
    return (int64_t)st.st_size;
}

// the file's modification time set to now (a cache's "used lately")
void zs_file_touch(zs_str *path) {
    clear_error();
#ifdef _WIN32
    if (_utime(path->data, NULL) != 0) set_error("cannot touch", path);
#else
    if (utimensat(AT_FDCWD, path->data, NULL, 0) != 0) set_error("cannot touch", path);
#endif
}

static bool copy_file(zs_str *from, zs_str *to) {
    int in = open(from->data, O_RDONLY | O_CLOEXEC);
    if (in < 0) {
        set_error("cannot open", from);
        return false;
    }
    int out = open(to->data, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
    if (out < 0) {
        set_error("cannot create", to);
        close(in);
        return false;
    }
    char buf[65536];
    ssize_t n;
    bool ok = true;
    while (ok && (n = read(in, buf, sizeof buf)) > 0)
        for (ssize_t done = 0; ok && done < n;) {
            ssize_t w = write(out, buf + done, (size_t)(n - done));
            if (w < 0) ok = false; else done += w;
        }
    if (n < 0 || !ok) set_error("cannot copy to", to);
    close(in);
    if (close(out) != 0 && ok) { set_error("cannot copy to", to); ok = false; }
    return ok && n >= 0;
}

void zs_file_copy(zs_str *from, zs_str *to) {
    clear_error();
    copy_file(from, to);
}

// a rename, or across file systems a copy and a delete
void zs_file_move(zs_str *from, zs_str *to) {
    clear_error();
#ifdef _WIN32
    // rename doesn't replace an existing file on Windows
    if (!MoveFileExA(from->data, to->data, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED)) {
        errno = EACCES;
        set_error("cannot move", from);
    }
    return;
#endif
    if (rename(from->data, to->data) == 0) return;
    if (errno != EXDEV) {
        set_error("cannot move", from);
        return;
    }
    if (copy_file(from, to) && remove(from->data) != 0) set_error("cannot delete", from);
}

// a new empty file (mode 0600) or directory in the temporary directory ($TMPDIR, else /tmp),
// named prefix and six characters: its path
static void temp_path(zs_str *prefix, char *path, size_t size) {
    const char *tmp = getenv("TMPDIR");
#ifdef _WIN32
    // else Windows's own: TMP, TEMP or the profile's (it ends with a backslash)
    char dir[MAX_PATH + 1] = ".\\";
    if (!tmp || !*tmp) GetTempPathA(sizeof dir, dir), tmp = dir;
    size_t n = strlen(tmp);
    snprintf(path, size, "%s%s%sXXXXXX", tmp, n && (tmp[n - 1] == '\\' || tmp[n - 1] == '/') ? "" : "\\", prefix->data);
#else
    snprintf(path, size, "%s/%sXXXXXX", tmp && *tmp ? tmp : "/tmp", prefix->data);
#endif
}

#ifdef _WIN32
// the UCRT has _mktemp_s, not mkdtemp (mingw-w64 has mkstemp): a name, then made if no one
// took it first; under a name of its own, as newer mingw-w64 headers declare one
#define mkdtemp zs_mkdtemp
static char *mkdtemp(char *path) {
    size_t n = strlen(path);
    for (int tries = 0; tries < 100; tries++) {
        memcpy(path + n - 6, "XXXXXX", 6);
        if (_mktemp_s(path, n + 1) != 0) return NULL;
        if (_mkdir(path) == 0) return path;
        if (errno != EEXIST) return NULL;
    }
    return NULL;
}
#endif

zs_str *zs_temp_file(zs_str *prefix) {
    clear_error();
    char path[4096];
    temp_path(prefix, path, sizeof path);
    int fd = mkstemp(path);
    if (fd < 0) {
        set_error("cannot create a temporary file", prefix);
        return str_of("", 0);
    }
    close(fd);
    return zs_str_from_c(path);
}

zs_str *zs_temp_dir(zs_str *prefix) {
    clear_error();
    char path[4096];
    temp_path(prefix, path, sizeof path);
    if (mkdtemp(path) == NULL) {
        set_error("cannot create a temporary directory", prefix);
        return str_of("", 0);
    }
    return zs_str_from_c(path);
}

void zs_dir_delete(zs_str *path) {
    clear_error();
    if (rmdir(path->data) != 0) set_error("cannot delete", path);
}

bool zs_is_symlink(zs_str *path) {
#ifdef _WIN32
    DWORD a = GetFileAttributesA(path->data);
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_REPARSE_POINT);
#else
    struct stat st;
    return lstat(path->data, &st) == 0 && S_ISLNK(st.st_mode);
#endif
}

zs_str *zs_current_dir(void) {
    char buf[4096];
    return zs_str_from_c(getcwd(buf, sizeof buf) ? buf : ".");
}

// Runs prog with NUL-separated args (no shell), stdout captured, stderr passed through.
static _Thread_local int64_t process_code;

zs_int zs_process_code(void) { return process_code; }

#ifdef _WIN32
// prog as an executable path: as given when it has a separator, else the first match on PATH
// (';'-separated); either way with ".exe" added when the name alone isn't a file
static bool is_file(const char *p) {
    DWORD a = GetFileAttributesA(p);
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

static bool find_program(const char *prog, char *out, size_t size) {
    if (strchr(prog, '/') || strchr(prog, '\\')) {
        snprintf(out, size, "%s", prog);
        if (is_file(out)) return true;
        snprintf(out, size, "%s.exe", prog);
        return is_file(out);
    }
    const char *path = getenv("PATH");
    for (; path && *path;) {
        const char *end = strchr(path, ';');
        size_t len = end ? (size_t)(end - path) : strlen(path);
        snprintf(out, size, "%.*s\\%s", (int)len, path, prog);
        if (len && is_file(out)) return true;
        snprintf(out, size, "%.*s\\%s.exe", (int)len, path, prog);
        if (len && is_file(out)) return true;
        path += len + (end ? 1 : 0);
    }
    return false;
}

// appends arg to the command line, quoted as CommandLineToArgvW parses it back
static void quote_arg(char **buf, size_t *len, size_t *cap, const char *arg) {
    size_t n = strlen(arg);
    if (*len + 2 * n + 4 > *cap) {
        *cap = 2 * (*len + 2 * n + 4);
        *buf = realloc(*buf, *cap);
        if (!*buf) zs_panic_c("out of memory");
    }
    char *b = *buf;
    if (*len) b[(*len)++] = ' ';
    if (n && !strpbrk(arg, " \t\n\v\"")) {
        memcpy(b + *len, arg, n);
        *len += n;
        b[*len] = 0;
        return;
    }
    b[(*len)++] = '"';
    for (size_t i = 0;; i++) {
        size_t slashes = 0;
        while (i < n && arg[i] == '\\') i++, slashes++;
        if (i == n) { // before the closing quote, every backslash doubled
            for (size_t k = 0; k < 2 * slashes; k++) b[(*len)++] = '\\';
            break;
        }
        // before a quote, doubled and one more for the quote; elsewhere as they are
        size_t m = arg[i] == '"' ? 2 * slashes + 1 : slashes;
        for (size_t k = 0; k < m; k++) b[(*len)++] = '\\';
        b[(*len)++] = arg[i];
    }
    b[(*len)++] = '"';
    b[*len] = 0;
}

static _Thread_local zs_int started[4]; // the last start's process and pipes, for Native.processPipe

zs_int zs_process_pipe(zs_int k) { return k >= 0 && k < 3 ? started[k + 1] : -1; }

// starts prog with args (NUL-separated), as zs_process_start's POSIX version: the process's
// handle as its "pid", or -errno. Each piped stream's end here is a CRT descriptor.
// ponytail: the child's ends are inheritable while CreateProcess runs, so a process another
// thread starts at that moment inherits them too; PROC_THREAD_ATTRIBUTE_HANDLE_LIST if it matters
zs_int zs_process_start(zs_str *prog, zs_str *args, zs_str *env, bool hasEnv, zs_str *dir, zs_int in, zs_int outm, zs_int errm) {
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) return -ENOENT;
    size_t len = 0, cap = 0;
    char *cmd = NULL;
    quote_arg(&cmd, &len, &cap, prog->data);
    if (args->len)
        for (int64_t i = 0; i <= args->len; i += (int64_t)strlen(args->data + i) + 1) quote_arg(&cmd, &len, &cap, args->data + i);
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    STARTUPINFOA si = {.cb = sizeof si, .dwFlags = STARTF_USESTDHANDLES};
    HANDLE *std[3] = {&si.hStdInput, &si.hStdOutput, &si.hStdError};
    DWORD which[3] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    zs_int modes[3] = {in, outm, errm};
    HANDLE theirs[3] = {NULL, NULL, NULL};
    for (int k = 0; k < 3; k++) {
        started[k + 1] = -1;
        if (modes[k] == 1) {
            HANDLE r, w;
            if (!CreatePipe(&r, &w, &sa, 0)) continue;
            HANDLE mine = k == 0 ? w : r;
            theirs[k] = k == 0 ? r : w;
            SetHandleInformation(mine, HANDLE_FLAG_INHERIT, 0);
            started[k + 1] = _open_osfhandle((intptr_t)mine, _O_BINARY | (k == 0 ? _O_WRONLY : _O_RDONLY));
            *std[k] = theirs[k];
        } else if (modes[k] == 2) {
            theirs[k] = CreateFileA("NUL", k == 0 ? GENERIC_READ : GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
            *std[k] = theirs[k];
        } else {
            *std[k] = GetStdHandle(which[k]);
        }
    }
    // the environment block: NAME=value strings, each NUL-ended, and one NUL more
    char *block = NULL;
    if (hasEnv) {
        block = calloc((size_t)env->len + 2, 1);
        memcpy(block, env->data, (size_t)env->len);
    }
    fflush(stdout);
    PROCESS_INFORMATION pi;
    BOOL ok = CreateProcessA(exe, cmd, NULL, NULL, TRUE, 0, block, dir->len ? dir->data : NULL, &si, &pi);
    DWORD e = GetLastError();
    free(cmd);
    free(block);
    for (int k = 0; k < 3; k++)
        if (theirs[k]) CloseHandle(theirs[k]);
    if (!ok) {
        for (int k = 0; k < 3; k++)
            if (started[k + 1] >= 0) _close((int)started[k + 1]), started[k + 1] = -1;
        return e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND ? -ENOENT : -EACCES;
    }
    CloseHandle(pi.hThread);
    started[0] = (zs_int)(intptr_t)pi.hProcess;
    return started[0];
}

// waits for the process: its exit code (an NTSTATUS such as 0xC0000005 when it crashed)
zs_int zs_process_wait(zs_int pid) {
    HANDLE h = (HANDLE)(intptr_t)pid;
    DWORD code = 0;
    if (WaitForSingleObject(h, INFINITE) != WAIT_OBJECT_0 || !GetExitCodeProcess(h, &code)) return -1;
    CloseHandle(h);
    return (zs_int)code;
}

zs_int zs_process_kill(zs_int pid) { return TerminateProcess((HANDLE)(intptr_t)pid, 137) ? 0 : -EPERM; }

// Runs prog with NUL-separated args (no shell), stdout captured, stderr passed through
zs_str *zs_process_run(zs_str *prog, zs_str *args) {
    clear_error();
    zs_str none = {0};
    zs_int h = zs_process_start(prog, args, &none, false, &none, 0, 1, 0);
    if (h < 0) {
        errno = (int)-h;
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    int fd = (int)started[2];
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap);
    int n;
    while ((n = _read(fd, buf + len, (unsigned)(cap - len))) > 0) {
        len += (size_t)n;
        if (len == cap) buf = realloc(buf, cap *= 2);
    }
    _close(fd);
    process_code = zs_process_wait(h);
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}
#else
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

#ifndef _WIN32
// a pipe, both ends close-on-exec (and non-blocking with nonblock); macOS has no pipe2
static int pipe_cloexec(int p[2], bool nonblock) {
#ifdef __APPLE__
    if (pipe(p) != 0) return -1;
    for (int i = 0; i < 2; i++) {
        fcntl(p[i], F_SETFD, FD_CLOEXEC);
        if (nonblock) fcntl(p[i], F_SETFL, O_NONBLOCK);
    }
    return 0;
#else
    return pipe2(p, O_CLOEXEC | (nonblock ? O_NONBLOCK : 0));
#endif
}
#endif

// ---- Process.start (0024): posix_spawn with each stream inherited, piped or /dev/null

// the NUL-separated strings of s as an argv-style array (with first in front, NULL after)
static char **split_nul(zs_str *s, char *first) {
    int64_t count = s->len ? 1 : 0;
    for (int64_t i = 0; i < s->len; i++) count += s->data[i] == 0;
    char **v = malloc(sizeof(char *) * (size_t)(count + 2));
    int64_t k = 0;
    if (first) v[k++] = first;
    if (s->len) {
        v[k++] = s->data;
        for (int64_t i = 0; i < s->len - 1; i++)
            if (s->data[i] == 0) v[k++] = s->data + i + 1;
    }
    v[k] = NULL;
    return v;
}

// starts prog with args (NUL-separated); env: NUL-separated NAME=value pairs, used when hasEnv;
// dir: its working directory ("" for this one's); modes per stream (0 inherit, 1 piped, 2
// /dev/null). The pid, or -errno; zs_process_pipe(k) gives this end of stream k's pipe (-1
// when it isn't piped).
static _Thread_local zs_int started[4]; // the last start's pid and pipes, for Native.processPipe

zs_int zs_process_pipe(zs_int k) { return k >= 0 && k < 3 ? started[k + 1] : -1; }

zs_int zs_process_start(zs_str *prog, zs_str *args, zs_str *env, bool hasEnv, zs_str *dir, zs_int in, zs_int outm, zs_int errm) {
    zs_int *out = started;
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) return -ENOENT;
    zs_int modes[3] = {in, outm, errm};
    int pipes[3][2] = {{-1, -1}, {-1, -1}, {-1, -1}};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    int rc = 0;
    for (int k = 0; k < 3 && rc == 0; k++) {
        if (modes[k] == 1) {
            if (pipe_cloexec(pipes[k], false) != 0) { rc = errno; break; }
            // the child's end becomes its stream; the pipes are close-on-exec otherwise
            posix_spawn_file_actions_adddup2(&fa, pipes[k][k == 0 ? 0 : 1], k);
        } else if (modes[k] == 2) {
            posix_spawn_file_actions_addopen(&fa, k, "/dev/null", k == 0 ? O_RDONLY : O_WRONLY, 0);
        }
    }
    if (rc == 0 && dir->len > 0) rc = posix_spawn_file_actions_addchdir_np(&fa, dir->data);
    pid_t pid = 0;
    if (rc == 0) {
        char **argv = split_nul(args, prog->data);
        char **envp = hasEnv ? split_nul(env, NULL) : environ;
        fflush(stdout);
        rc = posix_spawn(&pid, exe, &fa, NULL, argv, envp);
        free(argv);
        if (hasEnv) free(envp);
    }
    posix_spawn_file_actions_destroy(&fa);
    for (int k = 0; k < 3; k++) {
        int mine = k == 0 ? 1 : 0, theirs = k == 0 ? 0 : 1;
        if (pipes[k][theirs] >= 0) close(pipes[k][theirs]);
        out[k + 1] = -1;
        if (pipes[k][mine] >= 0) {
            if (rc == 0) out[k + 1] = pipes[k][mine];
            else close(pipes[k][mine]);
        }
    }
    if (rc != 0) return -(zs_int)rc;
    out[0] = pid;
    return pid;
}

// waits for the process: its exit code, or 128 plus the signal that ended it
zs_int zs_process_wait(zs_int pid) {
    int status = 0;
    while (waitpid((pid_t)pid, &status, 0) < 0)
        if (errno != EINTR) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
}

zs_int zs_process_kill(zs_int pid) { return kill((pid_t)pid, SIGKILL) == 0 ? 0 : -(zs_int)errno; }
#endif

// ---- the event loop (Task.run): callbacks waiting for file descriptors, timers, a queue of
// callbacks ready to run, and jobs on a helper thread (Task.blocking). A callback is a Z#
// closure taking unit, which the loop owns: zs_clo_run calls it and gives up the loop's
// reference, zs_clo_drop just gives it up (both are in each program's IR). Each thread has a
// loop of its own; what other threads hand one (finished helper jobs, tasks spawned onto it,
// results of tasks it spawned) goes through its inbox, which a byte on a pipe announces.
#include <fcntl.h>
#include <pthread.h>
#ifndef _WIN32
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#endif

// Descriptors the loop waits for. On Windows they're sockets only (wepoll's), each a small index
// above SOCK_BASE into a table of SOCKETs: a SOCKET is a handle, not a small integer, and a CRT
// descriptor (a file, a pipe) can't be told from one otherwise. FD_SLOT is the loop's index.
#ifdef _WIN32
#define SOCK_BASE 0x40000000
static SOCKET *socks;
static size_t nsocks, freesock = (size_t)-1; // the free slots, a list through socks
static pthread_mutex_t socks_mu = PTHREAD_MUTEX_INITIALIZER;

static bool is_sock(zs_int fd) { return fd >= SOCK_BASE && (size_t)(fd - SOCK_BASE) < nsocks; }
static SOCKET sk_of(zs_int fd) { return socks[fd - SOCK_BASE]; }

static int sk_add(SOCKET s) {
    if (s == INVALID_SOCKET) return -1;
    pthread_mutex_lock(&socks_mu);
    size_t i = freesock;
    if (i != (size_t)-1) {
        freesock = (size_t)socks[i];
    } else {
        SOCKET *t = realloc(socks, (nsocks + 1) * sizeof(SOCKET));
        if (!t) zs_panic_c("out of memory");
        socks = t;
        i = nsocks++;
    }
    socks[i] = s;
    pthread_mutex_unlock(&socks_mu);
    return SOCK_BASE + (int)i;
}

static void sk_close(zs_int fd) {
    pthread_mutex_lock(&socks_mu);
    closesocket(socks[fd - SOCK_BASE]);
    socks[fd - SOCK_BASE] = (SOCKET)freesock;
    freesock = (size_t)(fd - SOCK_BASE);
    pthread_mutex_unlock(&socks_mu);
}
#define FD_SLOT(fd) ((fd) - SOCK_BASE)
#define S(fd) sk_of(fd)
#else
#define FD_SLOT(fd) (fd)
#define S(fd) (fd)
#endif

// the kernel's readiness queue: epoll on Linux, kqueue on macOS. poll_set changes what it
// watches a descriptor for (LOOP_IN, LOOP_OUT) from had to want; poll_wait gives what's ready,
// a hang-up or an error as both
#define LOOP_IN 1u
#define LOOP_OUT 2u
typedef struct { int fd; uint32_t ready; } poll_event;
#ifdef _WIN32
#include "wepoll/wepoll.c"
typedef HANDLE poll_q;
#define POLL_NONE NULL
static poll_q poll_new(void) { return epoll_create1(0); }
static void poll_close(poll_q q) { epoll_close(q); }
static int poll_set(poll_q q, int fd, uint32_t had, uint32_t want) {
    struct epoll_event ev = {.events = (want & LOOP_IN ? EPOLLIN : 0) | (want & LOOP_OUT ? EPOLLOUT : 0), .data.fd = fd};
    int op = !had ? EPOLL_CTL_ADD : !want ? EPOLL_CTL_DEL : EPOLL_CTL_MOD;
    return epoll_ctl(q, op, sk_of(fd), &ev) != 0 && op != EPOLL_CTL_DEL ? -1 : 0;
}
static int poll_wait(poll_q q, poll_event *evs, int max, int timeout_ms) {
    struct epoll_event es[256];
    int k = epoll_wait(q, es, max < 256 ? max : 256, timeout_ms);
    for (int i = 0; i < k; i++) {
        evs[i].fd = es[i].data.fd;
        uint32_t e = es[i].events;
        evs[i].ready = (e & (EPOLLHUP | EPOLLERR) ? LOOP_IN | LOOP_OUT : 0) | (e & EPOLLIN ? LOOP_IN : 0) | (e & EPOLLOUT ? LOOP_OUT : 0);
    }
    return k;
}
#elif defined(__APPLE__)
#include <sys/event.h>
typedef int poll_q;
#define POLL_NONE (-1)
static poll_q poll_new(void) { return kqueue(); }
static void poll_close(poll_q q) { close(q); }
static int poll_set(poll_q q, int fd, uint32_t had, uint32_t want) {
    struct kevent ch[2];
    int n = 0;
    if ((had ^ want) & LOOP_IN) EV_SET(&ch[n++], fd, EVFILT_READ, want & LOOP_IN ? EV_ADD : EV_DELETE, 0, 0, NULL);
    if ((had ^ want) & LOOP_OUT) EV_SET(&ch[n++], fd, EVFILT_WRITE, want & LOOP_OUT ? EV_ADD : EV_DELETE, 0, 0, NULL);
    int r = n ? kevent(q, ch, n, NULL, 0, NULL) : 0;
    return want ? r : 0; // removing a closed descriptor's filters may fail, as epoll's DEL does
}
static int poll_wait(poll_q q, poll_event *evs, int max, int timeout_ms) {
    struct kevent ks[256];
    struct timespec t = {timeout_ms / 1000, (long)(timeout_ms % 1000) * 1000000};
    int k = kevent(q, NULL, 0, ks, max < 256 ? max : 256, timeout_ms < 0 ? NULL : &t);
    for (int i = 0; i < k; i++) {
        evs[i].fd = (int)ks[i].ident;
        evs[i].ready = ks[i].flags & (EV_EOF | EV_ERROR) ? LOOP_IN | LOOP_OUT : ks[i].filter == EVFILT_READ ? LOOP_IN : LOOP_OUT;
    }
    return k;
}
#else
#include <sys/epoll.h>
typedef int poll_q;
#define POLL_NONE (-1)
static poll_q poll_new(void) { return epoll_create1(EPOLL_CLOEXEC); }
static void poll_close(poll_q q) { close(q); }
static int poll_set(poll_q q, int fd, uint32_t had, uint32_t want) {
    struct epoll_event ev = {.events = (want & LOOP_IN ? EPOLLIN : 0) | (want & LOOP_OUT ? EPOLLOUT : 0), .data.fd = fd};
    int op = !had ? EPOLL_CTL_ADD : !want ? EPOLL_CTL_DEL : EPOLL_CTL_MOD;
    return epoll_ctl(q, op, fd, &ev) != 0 && op != EPOLL_CTL_DEL ? -1 : 0;
}
static int poll_wait(poll_q q, poll_event *evs, int max, int timeout_ms) {
    struct epoll_event es[256];
    int k = epoll_wait(q, es, max < 256 ? max : 256, timeout_ms);
    for (int i = 0; i < k; i++) {
        evs[i].fd = es[i].data.fd;
        uint32_t e = es[i].events;
        evs[i].ready = (e & (EPOLLHUP | EPOLLERR) ? LOOP_IN | LOOP_OUT : 0) | (e & EPOLLIN ? LOOP_IN : 0) | (e & EPOLLOUT ? LOOP_OUT : 0);
    }
    return k;
}
#endif

// the inbox's wake: a byte written to wake[1] makes wake[0] readable. A pipe, and on Windows (where
// wepoll watches sockets only) a loopback connection, as libuv and CPython's socketpair make
#ifdef _WIN32
static int wake_pair(int w[2]) {
    SOCKET l = socket(AF_INET, SOCK_STREAM, 0), a = INVALID_SOCKET, c = INVALID_SOCKET;
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    int n = sizeof addr;
    u_long one = 1;
    if (l != INVALID_SOCKET && bind(l, (struct sockaddr *)&addr, sizeof addr) == 0 && getsockname(l, (struct sockaddr *)&addr, &n) == 0 && listen(l, 1) == 0 &&
        (c = socket(AF_INET, SOCK_STREAM, 0)) != INVALID_SOCKET && connect(c, (struct sockaddr *)&addr, sizeof addr) == 0)
        a = accept(l, NULL, NULL);
    if (l != INVALID_SOCKET) closesocket(l);
    if (a == INVALID_SOCKET) {
        if (c != INVALID_SOCKET) closesocket(c);
        return -1;
    }
    ioctlsocket(a, FIONBIO, &one);
    ioctlsocket(c, FIONBIO, &one);
    w[0] = sk_add(a);
    w[1] = sk_add(c);
    return 0;
}
static void wake_send(int fd) { send(sk_of(fd), "x", 1, 0); }
static void wake_drain(int fd) {
    char buf[64];
    while (recv(sk_of(fd), buf, sizeof buf, 0) > 0) {}
}
static void wake_close(int fd) { sk_close(fd); }
#else
static int wake_pair(int w[2]) { return pipe_cloexec(w, true); }
static void wake_send(int fd) {
    ssize_t w = write(fd, "x", 1);
    (void)w;
}
static void wake_drain(int fd) {
    char buf[64];
    while (read(fd, buf, sizeof buf) > 0) {}
}
static void wake_close(int fd) { close(fd); }
#endif

void zs_clo_run(void *c);
void zs_clo_call(void *c);
void zs_clo_drop(void *c);
bool zs_loop_step(void);
void zs_loop_close(void);

typedef struct {
    void *read, *write; // the callbacks waiting for the descriptor to be readable, writable
    uint32_t armed;     // what the kernel's queue watches it for (LOOP_IN, LOOP_OUT)
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
    struct inbox *box;        // a token's loop
    struct job *next;
    struct job *prev_t, *next_t; // a token not yet used, in its loop's list of them
    int refs;                    // a token's: its loop's and the spawned task's (under box->mu)
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
    job *tokens;             // not yet used (a loop that closes drops their done closures, its own)
    struct inbox *next_box;  // in all_boxes
} inbox;

// every inbox, so those a token outlived (its spawned task dropped at exit) go at exit too
static inbox *all_boxes;
static pthread_mutex_t boxes_mu = PTHREAD_MUTEX_INITIALIZER;

static _Thread_local struct {
    bool stepping; // inside zs_loop_step: a callback can't run Task.run itself
    poll_q ep;     // the kernel's queue (poll_new), POLL_NONE until it's needed
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
} L = {.ep = POLL_NONE};

static int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static void ensure_ep(void) {
    if (L.ep == POLL_NONE && (L.ep = poll_new()) == POLL_NONE) zs_panic_c("epoll_create1 or kqueue failed");
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

// what the kernel's queue watches fd for: what it has callbacks for
static void fd_arm(zs_int fd) {
    fd_wait *w = &L.fds[FD_SLOT(fd)];
    uint32_t want = (w->read ? LOOP_IN : 0) | (w->write ? LOOP_OUT : 0);
    if (want == w->armed) return;
    if (poll_set(L.ep, (int)fd, w->armed, want) != 0) zs_panic_c("epoll_ctl or kevent failed (a descriptor that isn't a socket or pipe?)");
    w->armed = want;
}

// cb runs once fd is readable (or writable)
void zs_loop_wait(zs_int fd, bool write, void *cb) {
    ensure_ep();
#ifdef _WIN32
    if (!is_sock(fd)) zs_panic_c("only a socket can be waited for on Windows");
#endif
    if ((size_t)FD_SLOT(fd) >= L.nfds) {
        size_t n = L.nfds ? L.nfds : 64;
        while (n <= (size_t)FD_SLOT(fd)) n *= 2;
        fd_wait *f = realloc(L.fds, n * sizeof(fd_wait));
        if (!f) zs_panic_c("out of memory");
        memset(f + L.nfds, 0, (n - L.nfds) * sizeof(fd_wait));
        L.fds = f;
        L.nfds = n;
    }
    void **slot = write ? &L.fds[FD_SLOT(fd)].write : &L.fds[FD_SLOT(fd)].read;
    if (*slot) zs_panic_c("two tasks wait for the same descriptor at once");
    *slot = cb;
    L.waits++;
    fd_arm(fd);
}

// the callback waiting for fd goes, uncalled (its task was cancelled)
void zs_loop_unwait(zs_int fd, bool write) {
    if ((size_t)FD_SLOT(fd) >= L.nfds) return;
    void **slot = write ? &L.fds[FD_SLOT(fd)].write : &L.fds[FD_SLOT(fd)].read;
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
    pthread_mutex_lock(&boxes_mu);
    for (inbox **p = &all_boxes; *p; p = &(*p)->next_box)
        if (*p == b) {
            *p = b->next_box;
            break;
        }
    pthread_mutex_unlock(&boxes_mu);
    pthread_mutex_destroy(&b->mu);
    pthread_cond_destroy(&b->cv);
    wake_close(b->wake[0]);
    wake_close(b->wake[1]);
    free(b);
}

// the loop's inbox, made (and watched) the first time another thread may hand it something
static inbox *box_get(void) {
    if (!L.box) {
        ensure_ep();
        inbox *b = calloc(1, sizeof(inbox));
        if (!b || wake_pair(b->wake) != 0) zs_panic_c("pipe failed");
        pthread_mutex_init(&b->mu, NULL);
        pthread_cond_init(&b->cv, NULL);
        b->refs = 1;
        poll_set(L.ep, b->wake[0], 0, LOOP_IN);
        pthread_mutex_lock(&boxes_mu);
        b->next_box = all_boxes;
        all_boxes = b;
        pthread_mutex_unlock(&boxes_mu);
        L.box = b;
    }
    return L.box;
}

// hands j to b's loop (under b->mu), waking it
static void box_put(inbox *b, job *j) {
    j->next = b->ready;
    b->ready = j;
    wake_send(b->wake[1]);
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
    *j = (job){work, done, NULL, NULL, NULL, NULL, 0};
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
    *j = (job){NULL, done, b, NULL, NULL, NULL, 2};
    pthread_mutex_lock(&b->mu);
    b->refs++;
    j->next_t = b->tokens;
    if (b->tokens) b->tokens->prev_t = j;
    b->tokens = j;
    pthread_mutex_unlock(&b->mu);
    L.jobs++;
    return (zs_int)(intptr_t)j;
}

// on any thread: the token's done goes to its loop (a loop that has closed meanwhile dropped it)
void zs_loop_fulfill(zs_int token) {
    job *j = (job *)(intptr_t)token;
    inbox *b = j->box;
    pthread_mutex_lock(&b->mu);
    j->refs--; // the spawned task's
    // out of the list of tokens not yet used: to the loop, or (it has closed, and dropped the
    // done closure) gone
    if (j->prev_t) j->prev_t->next_t = j->next_t;
    else b->tokens = j->next_t;
    if (j->next_t) j->next_t->prev_t = j->prev_t;
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
    wake_drain(b->wake[0]);
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
        free(order); // a token: the spawned task let go when it fulfilled it
    }
}

// at exit, once the threads that run tasks have stopped: the inboxes left (closed, with tokens
// of tasks that were dropped unfinished) and those tokens
static void boxes_sweep(void) {
    pthread_mutex_lock(&boxes_mu);
    inbox *b = all_boxes;
    all_boxes = NULL;
    pthread_mutex_unlock(&boxes_mu);
    for (inbox *next; b; b = next) {
        next = b->next_box;
        if (!b->closed) { // a loop still open (exit called inside a task): left as it is
            pthread_mutex_lock(&boxes_mu);
            b->next_box = all_boxes;
            all_boxes = b;
            pthread_mutex_unlock(&boxes_mu);
            continue;
        }
        for (job *j = b->tokens, *nj; j; j = nj) {
            nj = j->next_t;
            free(j);
        }
        pthread_mutex_destroy(&b->mu);
        pthread_cond_destroy(&b->cv);
        wake_close(b->wake[0]);
        wake_close(b->wake[1]);
        free(b);
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
    long n = w ? strtol(w, NULL, 10) : cpu_count();
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
    *j = (job){work, NULL, NULL, NULL, NULL, NULL, 0};
    pthread_mutex_lock(&b->mu);
    box_put(b, j);
    pthread_mutex_unlock(&b->mu);
}

// Runs what's ready, then waits once for a descriptor, a timer or a job. False when nothing is
// left that could happen (Task.run then stops).
// helper jobs and spawned tasks this loop still waits on (Task.run waits for them all, so a
// cancelled spawned task has disposed what it holds before the program goes on)
zs_int zs_loop_jobs(void) { return (zs_int)L.jobs; }

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
    poll_event evs[256];
    int k = poll_wait(L.ep, evs, 256, timeout);
    if (k < 0 && errno != EINTR) zs_panic_c("epoll_wait or kevent failed");
    for (int i = 0; i < k; i++) {
        int fd = evs[i].fd;
        if (L.box && fd == L.box->wake[0]) {
            box_take();
            continue;
        }
        fd_wait *w = &L.fds[FD_SLOT(fd)];
        uint32_t e = evs[i].ready;
        if (w->read && (e & LOOP_IN)) {
            zs_loop_post(w->read);
            w->read = NULL;
            L.waits--;
        }
        if (w->write && (e & LOOP_OUT)) {
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
        // the tokens still out: their done closures are this loop's (dropped here); a token
        // stays in the list until its zs_loop_fulfill comes, or the program ends
        for (job *j = b->tokens; j; j = j->next_t) {
            zs_clo_drop(j->done);
            j->done = NULL;
            j->refs--;
        }
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
    if (L.ep != POLL_NONE) poll_close(L.ep);
    free(L.fds);
    free(L.queue);
    free(L.heap);
    L = (typeof(L)){.ep = POLL_NONE};
}

// ---- sockets and descriptors (Net.Tcp): non-blocking, so a task waits for them in the loop.
// Failures are -errno, and -1000 for "it would block, wait first"; Native.errorText gives the
// text.
// a new socket, non-blocking and close-on-exec, and (macOS: no MSG_NOSIGNAL) without SIGPIPE
#ifdef _WIN32
#define MSG_NOSIGNAL 0
static int sk_ready(SOCKET s) {
    u_long one = 1;
    if (s != INVALID_SOCKET) ioctlsocket(s, FIONBIO, &one);
    return sk_add(s);
}
static int sk_new(int domain, int type, int proto) { return sk_ready(WSASocketW(domain, type, proto, NULL, 0, WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT)); }
static int sk_accept(int fd) { return sk_ready(accept(sk_of(fd), NULL, NULL)); }
// Winsock's errors are WSAGetLastError's, not errno
static int sk_err(void) { return WSAGetLastError(); }
static void sk_seterr(int e) { WSASetLastError(e); }
static void sk_drop(int fd) { sk_close(fd); }
static bool in_progress(void) { return WSAGetLastError() == WSAEWOULDBLOCK; }
#elif defined(__APPLE__)
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
static int sk_ready(int fd) {
    if (fd < 0) return fd;
    int one = 1;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(fd, F_SETFL, O_NONBLOCK);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    return fd;
}
static int sk_new(int domain, int type, int proto) { return sk_ready(socket(domain, type, proto)); }
static int sk_accept(int fd) { return sk_ready(accept(fd, NULL, NULL)); }
#else
static int sk_new(int domain, int type, int proto) { return socket(domain, type | SOCK_NONBLOCK | SOCK_CLOEXEC, proto); }
static int sk_accept(int fd) { return accept4(fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC); }
#endif
#ifndef _WIN32
static int sk_err(void) { return errno; }
static void sk_seterr(int e) { errno = e; }
static void sk_drop(int fd) { close(fd); }
static bool in_progress(void) { return errno == EINPROGRESS || errno == EAGAIN; }
#endif

#ifdef _WIN32
static zs_int failed(void) {
    int e = WSAGetLastError();
    return e == WSAEWOULDBLOCK ? -1000 : e ? -(zs_int)e : -(zs_int)errno;
}
#else
static zs_int failed(void) { return errno == EAGAIN || errno == EWOULDBLOCK ? -1000 : -(zs_int)errno; }
#endif

static int resolve(zs_str *host, zs_int port, bool passive, struct addrinfo **res) {
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM, .ai_flags = passive ? AI_PASSIVE : 0};
    char p[24];
    snprintf(p, sizeof p, "%lld", (long long)port);
    int rc = getaddrinfo(host->len ? host->data : NULL, p, &hints, res);
#ifdef _WIN32
    if (rc != 0) WSASetLastError(rc);
#else
    if (rc != 0) errno = rc == EAI_SYSTEM ? errno : EADDRNOTAVAIL;
#endif
    return rc;
}

zs_int zs_tcp_listen(zs_str *host, zs_int port) {
    struct addrinfo *res;
    if (resolve(host, port, true, &res) != 0) return failed();
    int fd = sk_new(res->ai_family, res->ai_socktype, res->ai_protocol);
#ifndef _WIN32 // there it would let another socket take the port
    int one = 1;
    if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
#endif
    if (fd < 0 || bind(S(fd), res->ai_addr, (int)res->ai_addrlen) != 0 || listen(S(fd), 4096) != 0) {
        int e = sk_err();
        if (fd >= 0) sk_drop(fd);
        freeaddrinfo(res);
        sk_seterr(e);
        return failed();
    }
    freeaddrinfo(res);
    return fd;
}

zs_int zs_tcp_accept(zs_int fd) {
    int c = sk_accept((int)fd);
    if (c < 0) return failed();
    int one = 1;
    setsockopt(S(c), IPPROTO_TCP, TCP_NODELAY, (void *)&one, sizeof one);
    return c;
}

// a connection being made: writable once it's made (or failed: zs_socket_error says)
zs_int zs_tcp_connect(zs_str *host, zs_int port) {
    struct addrinfo *res;
    if (resolve(host, port, false, &res) != 0) return failed();
    int fd = sk_new(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0 || (connect(S(fd), res->ai_addr, (int)res->ai_addrlen) != 0 && !in_progress())) {
        int e = sk_err();
        if (fd >= 0) sk_drop(fd);
        freeaddrinfo(res);
        sk_seterr(e);
        return failed();
    }
    int one = 1;
    setsockopt(S(fd), IPPROTO_TCP, TCP_NODELAY, (void *)&one, sizeof one);
    freeaddrinfo(res);
    return fd;
}

#ifndef _WIN32
#include <sys/un.h>
#endif

// a Unix socket's address: the path, which must fit sun_path
static int unix_address(zs_str *path, struct sockaddr_un *a) {
    zs_int n = path->len;
    if (n == 0 || n >= (zs_int)sizeof a->sun_path) { errno = ENAMETOOLONG; return -1; }
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    memcpy(a->sun_path, path->data, (size_t)n);
    return 0;
}

// a socket listening at the path (a file left from an earlier run is removed first)
zs_int zs_unix_listen(zs_str *path) {
    struct sockaddr_un a;
    if (unix_address(path, &a) != 0) return failed();
    unlink(a.sun_path);
    int fd = sk_new(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || bind(S(fd), (struct sockaddr *)&a, sizeof a) != 0 || listen(S(fd), 4096) != 0) {
        int e = sk_err();
        if (fd >= 0) sk_drop(fd);
        sk_seterr(e);
        return failed();
    }
    return fd;
}

// a connection to the socket at the path being made, as zs_tcp_connect's
zs_int zs_unix_connect(zs_str *path) {
    struct sockaddr_un a;
    if (unix_address(path, &a) != 0) return failed();
    int fd = sk_new(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || (connect(S(fd), (struct sockaddr *)&a, sizeof a) != 0 && !in_progress())) {
        int e = sk_err();
        if (fd >= 0) sk_drop(fd);
        sk_seterr(e);
        return failed();
    }
    return fd;
}

zs_int zs_socket_error(zs_int fd) {
    int e = 0;
    socklen_t n = sizeof e;
    getsockopt(S(fd), SOL_SOCKET, SO_ERROR, (void *)&e, &n);
    return e;
}

// into bytes off to off + n - 1 of a Buffer<u8>'s data (len bytes)
zs_int zs_fd_read(zs_int fd, uint8_t *data, zs_int len, zs_int off, zs_int n) {
    if (off < 0 || n < 0 || off > len || n > len - off) zs_panic_c("read: range out of the buffer");
#ifdef _WIN32
    if (is_sock(fd)) {
        int r = recv(sk_of(fd), (char *)data + off, (int)n, 0);
        return r < 0 ? failed() : r;
    }
    int r = _read((int)fd, data + off, (unsigned)n);
    return r < 0 ? -(zs_int)errno : r;
#else
    ssize_t r = read((int)fd, data + off, (size_t)n);
    return r < 0 ? failed() : r;
#endif
}

// writes from a Buffer<u8> or a string's bytes; a closed connection is an error, not SIGPIPE
zs_int zs_fd_write(zs_int fd, const uint8_t *data, zs_int len, zs_int off, zs_int n) {
    if (off < 0 || n < 0 || off > len || n > len - off) zs_panic_c("write: range out of the data");
#ifdef _WIN32
    if (is_sock(fd)) {
        int r = send(sk_of(fd), (const char *)data + off, (int)n, 0);
        return r < 0 ? failed() : r;
    }
    int r = _write((int)fd, data + off, (unsigned)n);
    return r < 0 ? -(zs_int)errno : r;
#else
    ssize_t r = send((int)fd, data + off, (size_t)n, MSG_NOSIGNAL);
    if (r < 0 && errno == ENOTSOCK) r = write((int)fd, data + off, (size_t)n);
    return r < 0 ? failed() : r;
#endif
}

void zs_fd_close(zs_int fd) {
    if ((size_t)FD_SLOT(fd) < L.nfds) { // what waits for it can't happen any more
        zs_loop_unwait(fd, false);
        zs_loop_unwait(fd, true);
        L.fds[FD_SLOT(fd)].armed = 0;
    }
#ifdef _WIN32
    if (is_sock(fd)) {
        sk_close(fd);
        return;
    }
#endif
    close((int)fd);
}

zs_str *zs_error_text(zs_int e) {
    int code = (int)(e < 0 ? -e : e);
#ifdef _WIN32
    if (code >= WSABASEERR && e != -1000) { // Winsock's
        char buf[512];
        DWORD n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)code, 0, buf, sizeof buf, NULL);
        while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == '.')) buf[--n] = 0;
        return zs_str_from_c(n ? buf : "socket error");
    }
#endif
    return zs_str_from_c(e == -1000 ? "it would block" : strerror(code));
}

// ---- the thread pool (Parallel): a worker per core (ZS_WORKERS sets how many), each with a
// Chase–Lev deque of jobs (Lê et al., PPoPP 2013): its owner pushes and pops at the bottom, and
// idle workers steal from the top. Fork-join: zs_par_fork pushes a job on the calling thread's
// deque, and zs_par_join runs it there if no one has stolen it, or else runs other jobs until
// it's done. A job is a Z# closure whose objects the compiler marked shared, and a runner (in
// the program's IR) that calls it and stores its result in the job, for the joining thread.
// The deques' accesses are release/acquire or seq_cst operations rather than fences, which
// ThreadSanitizer doesn't model.
//
// Any thread may fork: one outside the pool (a task's loop thread, Task.blocking's helper)
// takes a deque of its own the first time, given back when it ends. A worker waiting in a
// channel tells the pool, which starts a spare worker while fewer threads than it has cores are
// left to run jobs (Java's ForkJoinPool does this for a managed blocker): a job waiting for what
// another job sends isn't left waiting for a thread to run that one. A spare that finds nothing
// to do while enough others can sleeps until it's needed again.

typedef struct {
    void (*run)(void *clo, void *out);
    void *clo;
    atomic_int done;
    _Alignas(64) char result[]; // what run stores (a SIMD vector, say)
} par_job;

typedef struct {
    atomic_llong top, bottom;
    _Atomic(_Atomic(par_job *) *) buf;
    atomic_llong cap; // a power of two
} par_deque;

#define PAR_OTHERS 1024 // deques for threads that aren't workers: forking threads and spares

static struct {
    int n;             // the cores it uses: n - 1 workers and the thread that started it
    pthread_t *threads;
    par_deque *deques; // the workers', the starting thread's (n - 1), then the others'
    int cap;           // deques there are
    atomic_int slots;  // deques in use, the others' handed out in order
    int *freed;        // deques given back by threads that ended, to hand out again (under mu)
    int nfreed;
    pthread_mutex_t mu;
    pthread_cond_t cv;
    atomic_int sleeping;
    atomic_bool stop;
    atomic_int blocked; // workers and spares waiting in a channel
    atomic_int spares;  // spares running
    int parked;         // spares asleep (under mu), woken before another is started
    int wakes;          // spares woken and not yet up (under mu)
    pthread_cond_t sparecv;
    pthread_t *spareThreads; // every spare started, joined at exit (under mu)
    int nspare;
    void **old; // buffers replaced by bigger ones (a thief may still read one), freed at exit
    size_t nold;
    pthread_mutex_t oldmu;
} P;

static pthread_once_t pool_once = PTHREAD_ONCE_INIT;
static _Thread_local int me = -1;         // this thread's deque, -1 for a thread without one
static _Thread_local bool runsJobs;      // a worker or a spare: what the pool counts on
static pthread_key_t slotKey;            // gives a forking thread's deque back when it ends

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
    // publishes the job; seq_cst, as is zs_par_fork's look for sleepers after it (see run_jobs)
    atomic_store_explicit(&q->bottom, b + 1, memory_order_seq_cst);
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
    int n = atomic_load_explicit(&P.slots, memory_order_acquire);
    for (int k = 0; k < n; k++) {
        *seed = *seed * 1103515245u + 12345u;
        int v = (int)((*seed >> 8) % (unsigned)n);
        if (v == me) continue;
        par_job *x = dq_steal(&P.deques[v]);
        if (x) return x;
    }
    return NULL;
}

// whether a deque has a job: its bottom read seq_cst, for a worker going to sleep (run_jobs)
static bool work_left(void) {
    int n = atomic_load_explicit(&P.slots, memory_order_acquire);
    for (int k = 0; k < n; k++)
        if (atomic_load_explicit(&P.deques[k].top, memory_order_relaxed) < atomic_load(&P.deques[k].bottom)) return true;
    return false;
}

// a deque for this thread, which hasn't one: one given back, or the next
static void slot_take(void) {
    pthread_mutex_lock(&P.mu);
    int k;
    if (P.nfreed > 0) k = P.freed[--P.nfreed];
    else {
        k = atomic_load(&P.slots);
        if (k >= P.cap) zs_panic_c("too many threads use the thread pool at once");
        dq_init(&P.deques[k]);
        atomic_store_explicit(&P.slots, k + 1, memory_order_release); // after the deque is there
    }
    pthread_mutex_unlock(&P.mu);
    me = k;
}

// a thread that forked ends: its deque (empty: it joined what it forked) is handed out again
static void slot_give(void *arg) {
    (void)arg;
    if (me < 0) return;
    pthread_mutex_lock(&P.mu);
    P.freed[P.nfreed++] = me;
    pthread_mutex_unlock(&P.mu);
    me = -1;
}

// threads free to run jobs: the workers and spares not waiting in a channel
static int free_runners(void) { return P.n - 1 + atomic_load(&P.spares) - atomic_load(&P.blocked); }

// how many the pool wants free: a worker per core but the starting thread's, and at least one
static int wanted_runners(void) { return P.n > 1 ? P.n - 1 : 1; }

static void *spare_main(void *arg);

// a job is about to wait in a channel: if that leaves too few threads to run jobs, a spare
// starts (a sleeping one wakes)
static void par_block(void) {
    if (me < 0) return; // not running jobs: its waiting holds nothing of the pool
    if (runsJobs) atomic_fetch_add(&P.blocked, 1);
    if (free_runners() >= wanted_runners()) return;
    pthread_mutex_lock(&P.mu);
    if (P.parked == 0 && P.nspare >= 2 * P.n) {
        // at most twice the cores: with none left free, every job waits for another, for good
        int blocked = atomic_load(&P.blocked);
        pthread_mutex_unlock(&P.mu);
        if (free_runners() > 0) return;
        char msg[160];
        snprintf(msg, sizeof msg, "the thread pool's spare threads are exhausted (%d blocked jobs): jobs wait for each other in channels or mutexes", blocked);
        zs_panic_c(msg);
    }
    atomic_fetch_add(&P.spares, 1);
    if (P.parked > 0) {
        P.parked--;
        P.wakes++;
        pthread_cond_signal(&P.sparecv);
    } else {
        pthread_t *t = realloc(P.spareThreads, (size_t)(P.nspare + 1) * sizeof(pthread_t));
        if (!t) zs_panic_c("out of memory");
        P.spareThreads = t;
        if (pthread_create(&P.spareThreads[P.nspare], NULL, spare_main, NULL) != 0) zs_panic_c("pthread_create failed");
        P.nspare++;
    }
    pthread_mutex_unlock(&P.mu);
}

static void par_unblock(void) {
    if (me >= 0 && runsJobs) atomic_fetch_sub(&P.blocked, 1);
}

// runs jobs until the pool stops; a spare also stops when enough others are free, sleeping
// until another wait needs it
static void run_jobs(bool spare) {
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
        if (spare && free_runners() > wanted_runners()) {
            // not needed: asleep until a wait wakes it (which counts it again)
            atomic_fetch_sub(&P.spares, 1);
            P.parked++;
            while (P.wakes == 0 && !atomic_load(&P.stop)) pthread_cond_wait(&P.sparecv, &P.mu);
            if (P.wakes > 0) P.wakes--;
            pthread_mutex_unlock(&P.mu);
            continue;
        }
        // no wake-up is lost: a fork pushes its job, then reads sleeping; this thread counts
        // itself in sleeping, then looks at the deques. All four are seq_cst, so one of the two
        // sees the other: the fork signals, or this thread finds the job
        atomic_fetch_add(&P.sleeping, 1);
        while (!atomic_load(&P.stop) && !work_left()) pthread_cond_wait(&P.cv, &P.mu);
        atomic_fetch_sub(&P.sleeping, 1);
        pthread_mutex_unlock(&P.mu);
    }
}

static void *worker_main(void *arg) {
    me = (int)(intptr_t)arg;
    runsJobs = true;
    run_jobs(false);
    return NULL;
}

static void *spare_main(void *arg) {
    (void)arg;
    slot_take();
    runsJobs = true;
    run_jobs(true);
    return NULL;
}

static void pool_stop(void) {
    atomic_store(&P.stop, true);
    pthread_mutex_lock(&P.mu);
    pthread_cond_broadcast(&P.cv);
    pthread_cond_broadcast(&P.sparecv);
    int nspare = P.nspare;
    pthread_mutex_unlock(&P.mu);
    for (int k = 0; k < P.n - 1; k++) pthread_join(P.threads[k], NULL);
    for (int k = 0; k < nspare; k++) pthread_join(P.spareThreads[k], NULL);
    int used = atomic_load(&P.slots);
    for (int k = 0; k < used; k++) free((void *)atomic_load(&P.deques[k].buf));
    for (size_t k = 0; k < P.nold; k++) free(P.old[k]);
    free(P.old);
    free(P.deques);
    free(P.freed);
    free(P.threads);
    free(P.spareThreads);
}

static void pool_start(void) {
    const char *w = getenv("ZS_WORKERS");
    long n = w ? strtol(w, NULL, 10) : cpu_count();
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    P.n = (int)n;
    P.cap = P.n + PAR_OTHERS;
    P.deques = calloc((size_t)P.cap, sizeof(par_deque));
    P.freed = calloc((size_t)P.cap, sizeof(int));
    P.threads = calloc((size_t)n, sizeof(pthread_t));
    if (!P.deques || !P.freed || !P.threads) zs_panic_c("out of memory");
    for (int k = 0; k < P.n; k++) dq_init(&P.deques[k]);
    atomic_init(&P.slots, P.n);
    pthread_mutex_init(&P.mu, NULL);
    pthread_cond_init(&P.cv, NULL);
    pthread_cond_init(&P.sparecv, NULL);
    pthread_mutex_init(&P.oldmu, NULL);
    pthread_key_create(&slotKey, slot_give);
    me = P.n - 1; // the thread starting the pool runs jobs with the last deque
    for (int k = 0; k < P.n - 1; k++)
        if (pthread_create(&P.threads[k], NULL, worker_main, (void *)(intptr_t)k) != 0) zs_panic_c("pthread_create failed");
    atexit(pool_stop);
}

// a thread forking without a deque (a task's loop thread, Task.blocking's helper) takes one,
// given back when it ends
static void par_enter(void) {
    pthread_once(&pool_once, pool_start);
    if (me >= 0) return;
    slot_take();
    pthread_setspecific(slotKey, (void *)1);
}

zs_int zs_par_workers(void) {
    pthread_once(&pool_once, pool_start);
    return P.n;
}

// a job running clo (the job takes its reference) with run, whose result takes size bytes
void *zs_par_fork(void *clo, void (*run)(void *, void *), zs_int size) {
    par_enter();
    par_job *j = aligned_alloc(64, (sizeof(par_job) + (size_t)size + 63) & ~(size_t)63);
    if (!j) zs_panic_c("out of memory");
    j->run = run;
    j->clo = clo;
    atomic_init(&j->done, 0);
    dq_push(&P.deques[me], j);
    if (atomic_load(&P.sleeping) > 0) { // seq_cst, after the push's: see run_jobs
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
        par_job *x = dq_pop(&P.deques[me]);
        if (!x) x = steal_any(&seed);
        if (x) run_job(x);
        else sched_yield();
    }
    return j->result;
}

void zs_par_free(void *j) { obj_free(j); }

// ---- locks (Mutex): a 32-bit word, 0 free, 1 held, 2 held with threads waiting (Drepper,
// "Futexes are tricky"); on Linux, macOS and Windows the waiting threads sleep in the kernel
#ifdef __linux__
#include <linux/futex.h>
#include <sys/syscall.h>
static void futex_wait(atomic_int *l, int v) { syscall(SYS_futex, l, FUTEX_WAIT_PRIVATE, v, NULL, NULL, 0); }
static void futex_wake(atomic_int *l) { syscall(SYS_futex, l, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0); }
#elif defined(_WIN32)
static void futex_wait(atomic_int *l, int v) { WaitOnAddress(l, &v, sizeof v, INFINITE); }
static void futex_wake(atomic_int *l) { WakeByAddressSingle(l); }
#elif defined(__APPLE__)
// libSystem's address wait (what libc++'s atomic wait uses): UL_COMPARE_AND_WAIT, no errno
int __ulock_wait(uint32_t op, void *addr, uint64_t value, uint32_t timeout_us);
int __ulock_wake(uint32_t op, void *addr, uint64_t wake_value);
static void futex_wait(atomic_int *l, int v) { __ulock_wait(1 | 0x01000000, l, (uint64_t)v, 0); }
static void futex_wake(atomic_int *l) { __ulock_wake(1 | 0x01000000, l, 0); }
#else
static void futex_wait(atomic_int *l, int v) { (void)l, (void)v, sched_yield(); }
static void futex_wake(atomic_int *l) { (void)l; }
#endif

// a lock held a little while is waited for spinning; a longer wait tells the thread pool (a job
// waiting here may be what a spare worker is for, as in a channel)
void zs_lock(atomic_int *l) {
    int c = 0;
    if (atomic_compare_exchange_strong_explicit(l, &c, 1, memory_order_acquire, memory_order_relaxed)) return;
    for (int spin = 0; spin < 100; spin++) {
        c = 0;
        if (atomic_compare_exchange_weak_explicit(l, &c, 1, memory_order_acquire, memory_order_relaxed)) return;
        sched_yield();
    }
    if (c != 2) c = atomic_exchange_explicit(l, 2, memory_order_acquire);
    if (c == 0) return;
    par_block();
    while (c != 0) {
        futex_wait(l, 2);
        c = atomic_exchange_explicit(l, 2, memory_order_acquire);
    }
    par_unblock();
}

void zs_unlock(atomic_int *l) {
    if (atomic_fetch_sub_explicit(l, 1, memory_order_release) != 1) {
        atomic_store_explicit(l, 0, memory_order_release);
        futex_wake(l);
    }
}

// ---- channels (Channel): a bounded queue for any number of senders and receivers, a ring of
// fixed-size slots holding the values' bytes (the compiler marked them shared), under a lock.
// With capacity 0, a send waits for a receiver to take its value (a rendezvous): the ring is
// one slot, and the sender waits until what's taken passes its value. A wait tells the thread
// pool, which may start a spare worker meanwhile. A Z# object: its count is the header, and the
// drop function it was made with drops what's still in it when it's freed.
typedef struct {
    ZS_HEADER;
    pthread_mutex_t mu;
    pthread_cond_t not_empty, not_full, taken;
    zs_int cap, size, head, len;
    bool rendezvous;
    unsigned long long sent, received; // values ever sent and taken (a rendezvous waits on them)
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
    pthread_cond_init(&c->taken, NULL);
    c->rendezvous = cap == 0;
    c->cap = cap == 0 ? 1 : cap;
    c->size = size;
    c->head = c->len = 0;
    c->sent = c->received = 0;
    c->closed = false;
    c->drop = drop;
    c->slots = malloc((size_t)(c->cap * (size ? size : 1)));
    if (!c->slots) zs_panic_c("out of memory");
    return c;
}

// pthread_cond_wait, with the pool told (once per wait in a channel operation)
static void chan_wait(pthread_cond_t *cv, pthread_mutex_t *mu, bool *told) {
    if (!*told) {
        *told = true;
        pthread_mutex_unlock(mu);
        par_block();
        pthread_mutex_lock(mu);
        return; // tested again before waiting: the pool may have run what this waits for
    }
    pthread_cond_wait(cv, mu);
}

// waits while it's full (with capacity 0, until a receiver has taken it); the value's bytes
// move in
void zs_chan_send(zs_chan *c, void *slot) {
    bool told = false;
    pthread_mutex_lock(&c->mu);
    while (c->len == c->cap && !c->closed) chan_wait(&c->not_full, &c->mu, &told);
    if (c->closed) {
        pthread_mutex_unlock(&c->mu);
        if (told) par_unblock();
        zs_panic_c("Channel.send: the channel is closed");
    }
    memcpy(c->slots + ((c->head + c->len) % c->cap) * c->size, slot, (size_t)c->size);
    c->len++;
    unsigned long long mine = ++c->sent;
    pthread_cond_signal(&c->not_empty);
    if (c->rendezvous)
        while (c->received < mine && !c->closed) chan_wait(&c->taken, &c->mu, &told);
    pthread_mutex_unlock(&c->mu);
    if (told) par_unblock();
}

// waits for a value (true: its bytes moved into slot), or until it's closed and empty (false)
bool zs_chan_recv(zs_chan *c, void *slot) {
    bool told = false;
    pthread_mutex_lock(&c->mu);
    while (c->len == 0 && !c->closed) chan_wait(&c->not_empty, &c->mu, &told);
    bool got = c->len > 0;
    if (got) {
        memcpy(slot, c->slots + c->head * c->size, (size_t)c->size);
        c->head = (c->head + 1) % c->cap;
        c->len--;
        c->received++;
        pthread_cond_signal(&c->not_full);
        if (c->rendezvous) pthread_cond_broadcast(&c->taken);
    }
    pthread_mutex_unlock(&c->mu);
    if (told) par_unblock();
    return got;
}

// no more values: receivers get what's left, then None; a send panics
void zs_chan_close(zs_chan *c) {
    pthread_mutex_lock(&c->mu);
    c->closed = true;
    pthread_cond_broadcast(&c->not_empty);
    pthread_cond_broadcast(&c->not_full);
    pthread_cond_broadcast(&c->taken);
    pthread_mutex_unlock(&c->mu);
}

void zs_chan_free(zs_chan *c) {
    if (c->drop)
        for (zs_int i = 0; i < c->len; i++) c->drop(c->slots + ((c->head + i) % c->cap) * c->size);
    pthread_mutex_destroy(&c->mu);
    pthread_cond_destroy(&c->not_empty);
    pthread_cond_destroy(&c->not_full);
    pthread_cond_destroy(&c->taken);
    free(c->slots);
    zs_free(c);
}

// ---- CPU features ([<Multiversion>]): whether the CPU has each of the features, named as LLVM
// names them and separated by commas ("avx2,fma"). A name it doesn't know is a feature it
// doesn't have.
#if (defined(__x86_64__) || defined(__i386__)) && (defined(__APPLE__) || defined(_WIN32))
// cpuid itself: Zig's compiler-rt has __builtin_cpu_supports's tables (__cpu_model) on Linux only.
// AVX and AVX-512 also need the OS to save their registers (xgetbv)
#include <cpuid.h>
static bool cpu_has(const char *f, size_t n) {
    unsigned a, b, c, d, b7 = 0, c7 = 0, d7 = 0;
    if (!__get_cpuid(1, &a, &b, &c, &d)) return false;
    __get_cpuid_count(7, 0, &a, &b7, &c7, &d7);
    unsigned long long xcr0 = 0;
    if (c & (1u << 27)) {
        unsigned lo, hi;
        __asm__("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
        xcr0 = ((unsigned long long)hi << 32) | lo;
    }
    bool ymm = (xcr0 & 6) == 6, zmm = (xcr0 & 0xe6) == 0xe6;
#define HAS(name, bits) \
    if (n == sizeof(name) - 1 && !memcmp(f, name, n)) return (bits) != 0
    HAS("cmov", d & (1u << 15));
    HAS("popcnt", c & (1u << 23));
    HAS("sse", d & (1u << 25));
    HAS("sse2", d & (1u << 26));
    HAS("sse3", c & 1u);
    HAS("ssse3", c & (1u << 9));
    HAS("sse4.1", c & (1u << 19));
    HAS("sse4.2", c & (1u << 20));
    HAS("avx", ymm && (c & (1u << 28)));
    HAS("avx2", ymm && (b7 & (1u << 5)));
    HAS("fma", ymm && (c & (1u << 12)));
    HAS("bmi", b7 & (1u << 3));
    HAS("bmi2", b7 & (1u << 8));
    HAS("aes", c & (1u << 25));
    HAS("pclmul", c & (1u << 1));
    HAS("avx512f", zmm && (b7 & (1u << 16)));
    HAS("avx512vl", zmm && (b7 & (1u << 31)));
    HAS("avx512bw", zmm && (b7 & (1u << 30)));
    HAS("avx512dq", zmm && (b7 & (1u << 17)));
    HAS("avx512cd", zmm && (b7 & (1u << 28)));
#undef HAS
    return false;
}
#elif defined(__x86_64__) || defined(__i386__)
static bool cpu_has(const char *f, size_t n) {
#define HAS(name) \
    if (n == sizeof(name) - 1 && !memcmp(f, name, n)) return __builtin_cpu_supports(name)
    HAS("cmov");
    HAS("popcnt");
    HAS("sse");
    HAS("sse2");
    HAS("sse3");
    HAS("ssse3");
    HAS("sse4.1");
    HAS("sse4.2");
    HAS("avx");
    HAS("avx2");
    HAS("fma");
    HAS("bmi");
    HAS("bmi2");
    HAS("aes");
    HAS("pclmul");
    HAS("avx512f");
    HAS("avx512vl");
    HAS("avx512bw");
    HAS("avx512dq");
    HAS("avx512cd");
#undef HAS
    return false;
}
#elif defined(__aarch64__) && defined(__linux__)
#include <sys/auxv.h>
static bool cpu_has(const char *f, size_t n) {
    // the kernel's hwcap bits (asm/hwcap.h), written out for older headers
    unsigned long hw = getauxval(AT_HWCAP), hw2 = getauxval(AT_HWCAP2);
#define HAS(name, bits) \
    if (n == sizeof(name) - 1 && !memcmp(f, name, n)) return (bits) != 0
    HAS("neon", 1);
    HAS("fp-armv8", 1);
    HAS("aes", hw & (1ul << 3));
    HAS("sha2", hw & (1ul << 6));
    HAS("crc", hw & (1ul << 7));
    HAS("lse", hw & (1ul << 8));
    HAS("fullfp16", hw & (1ul << 10));
    HAS("dotprod", hw & (1ul << 20));
    HAS("sve", hw & (1ul << 22));
    HAS("sve2", hw2 & (1ul << 1));
    HAS("i8mm", hw2 & (1ul << 13));
    HAS("bf16", hw2 & (1ul << 14));
#undef HAS
    return false;
}
#elif defined(__aarch64__) && defined(__APPLE__)
#include <sys/sysctl.h>
static bool cpu_has(const char *f, size_t n) {
    // every Apple arm64 CPU has these (ARMv8.4-A at least); the rest the kernel names
    static const char *const base[] = {"neon", "fp-armv8", "aes", "sha2", "crc", "lse", "fullfp16", "dotprod"};
    for (size_t i = 0; i < sizeof base / sizeof *base; i++)
        if (n == strlen(base[i]) && !memcmp(f, base[i], n)) return true;
    const char *key = n == 4 && !memcmp(f, "i8mm", 4) ? "hw.optional.arm.FEAT_I8MM"
                    : n == 4 && !memcmp(f, "bf16", 4) ? "hw.optional.arm.FEAT_BF16"
                    : NULL;
    int v = 0;
    size_t sz = sizeof v;
    return key && sysctlbyname(key, &v, &sz, NULL, 0) == 0 && v;
}
#else
static bool cpu_has(const char *f, size_t n) {
    (void)f, (void)n;
    return false;
}
#endif

bool zs_cpu_supports(const char *features) {
    for (const char *p = features; *p;) {
        const char *e = strchr(p, ',');
        size_t n = e ? (size_t)(e - p) : strlen(p);
        if (!cpu_has(p, n)) return false;
        p += n + (e ? 1 : 0);
    }
    return true;
}
