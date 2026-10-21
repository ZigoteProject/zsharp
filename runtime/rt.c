// Z# runtime: allocation, panics, strings. Linked into every Z# program.
#define _GNU_SOURCE
#include <inttypes.h>
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

// A panic stops the program at once (no cleanup) with exit status 134, like abort() but without
// a core dump, so system crash reporters don't flag every panic. ZS_ABORT=1 aborts for real
// (a core file for a debugger).
static _Noreturn void stop(void) {
    if (getenv("ZS_ABORT")) abort();
    _exit(134);
}

_Noreturn void zs_panic_c(const char *msg) {
    fflush(stdout);
    fprintf(stderr, "panic: %s\n", msg);
    const char *bt = getenv("ZS_BACKTRACE");
    if (bt && strcmp(bt, "0") == 0) stop();
#ifdef __GLIBC__
    void *frames[64];
    int n = backtrace(frames, 64);
    backtrace_symbols_fd(frames + 1, n - 1, 2);
#endif
    stop();
}

_Noreturn void zs_panic(zs_str *msg) { zs_panic_c(msg->data); }

static int64_t allocations;

void *zs_alloc(zs_int size) {
    void *p = malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    live++;
    allocations++;
    return p;
}

/// Runtime.allocations (): heap objects allocated so far (tests check copy-on-write with it).
zs_int zs_allocations(void) { return allocations; }

#include <time.h>
/// Runtime.ticks (): a monotonic clock in nanoseconds (on a Cortex-M: SysTick counts).
int64_t zs_ticks(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

void zs_free(void *p) {
    live--;
    free(p);
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
static zs_str *io_error;

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
static int64_t process_code;

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
