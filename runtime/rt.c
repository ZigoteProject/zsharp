// Z# runtime: allocation, panics, strings. Linked into every Z# program.
#define _GNU_SOURCE
#define _CRT_RAND_S // Windows's rand_s, the system's randomness (Random.shared)
#include <inttypes.h>
#include <limits.h>
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

#if defined(_WIN32) || defined(__APPLE__)
// LLVM's llvm.roundeven calls these where the processor has no instruction for it (an Intel Mac's
// baseline), and mingw-w64's libm and the macOS one a cross build links lack them: the default
// rounding mode is to nearest, ties to even
#include <math.h>
double roundeven(double x) { return nearbyint(x); }
float roundevenf(float x) { return nearbyintf(x); }
#endif

#include <errno.h>
#include <pthread.h>
#ifndef _WIN32
#include <signal.h>
#include <sys/resource.h>
#endif

// A stack overflow is a panic that says so, not a bare SIGSEGV: a program's threads (the main
// one and those spawn starts) take the fault on a stack of their own, and a fault next to the
// thread's stack pointer ends the program as a panic does. Not under a sanitizer (it reports
// overflows itself), and not in a library (zs_set_args is a program's: a C host's signals are
// its own).
#if defined(__has_feature)
#if __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
#define ZS_SANITIZED 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__) || defined(__SANITIZE_THREAD__)
#define ZS_SANITIZED 1
#endif
#if (defined(__linux__) || defined(__APPLE__)) && !defined(ZS_SANITIZED)
#define ZS_OVERFLOW_GUARD 1
#endif

#ifdef ZS_OVERFLOW_GUARD
#include <sys/ucontext.h>
#define ALT_STACK_SIZE (64 << 10)
static bool guard_on; // set once by zs_set_args, before any thread is spawned

// the stack pointer of the thread that faulted (0 where it isn't known)
static uintptr_t fault_sp(void *context) {
    ucontext_t *uc = context;
#if defined(__APPLE__) && defined(__x86_64__)
    return (uintptr_t)uc->uc_mcontext->__ss.__rsp;
#elif defined(__APPLE__) && defined(__aarch64__) && defined(__darwin_arm_thread_state64_get_sp)
    return (uintptr_t)__darwin_arm_thread_state64_get_sp(uc->uc_mcontext->__ss);
#elif defined(__APPLE__) && defined(__aarch64__)
    return (uintptr_t)uc->uc_mcontext->__ss.__sp;
#elif defined(__linux__) && defined(__x86_64__)
    return (uintptr_t)uc->uc_mcontext.gregs[REG_RSP];
#elif defined(__linux__) && defined(__aarch64__)
    return (uintptr_t)uc->uc_mcontext.sp;
#elif defined(__linux__) && defined(__arm__)
    return (uintptr_t)uc->uc_mcontext.arm_sp;
#else
    (void)uc;
    return 0;
#endif
}

static void on_fault(int sig, siginfo_t *info, void *context) {
    uintptr_t at = (uintptr_t)info->si_addr, sp = fault_sp(context);
    // an access within a frame's reach of the stack pointer that faulted: the stack ran into its
    // guard (a push, a call, or a store into a frame just made below it)
    if (sp && at + ((uintptr_t)64 << 10) >= sp && at <= sp + ((uintptr_t)64 << 10)) {
        // one thread says so and stops the program; another overflowing meanwhile waits for that
        static atomic_flag panicking = ATOMIC_FLAG_INIT;
        if (atomic_flag_test_and_set(&panicking))
            for (;;) pause();
        // what was printed before it, as a panic flushes it; unless another thread is writing
        // (waiting for it here could be forever), and a fault inside the flush ends the program
        // as the overflow would have
        if (ftrylockfile(stdout) == 0) {
            fflush(stdout);
            funlockfile(stdout);
        }
        static const char msg[] = "panic: stack overflow (recursion too deep)\n";
        ssize_t w = write(2, msg, sizeof msg - 1);
        (void)w;
        if (getenv("ZS_ABORT")) {
            signal(SIGABRT, SIG_DFL);
            abort();
        }
        _exit(134);
    }
    // any other fault as if no one caught it: the instruction runs again, with the default action
    signal(sig, SIG_DFL);
}

static void guard_thread(char *alt) {
    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_sp = alt;
    ss.ss_size = ALT_STACK_SIZE;
    sigaltstack(&ss, NULL);
}

// the main thread's guard, and the handler, unless the program already has one
static void guard_install(void) {
    static char alt[ALT_STACK_SIZE];
    struct sigaction old;
    if (sigaction(SIGSEGV, NULL, &old) != 0 || (old.sa_flags & SA_SIGINFO) || old.sa_handler != SIG_DFL) return;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_fault;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    guard_thread(alt);
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    guard_on = true;
}
#endif

// what spawn starts: the body, its own stack for a fault first
typedef struct {
    void *(*body)(void *);
    void *arg;
} spawned;

static void *spawned_main(void *p) {
    spawned s = *(spawned *)p;
    free(p);
#ifdef ZS_OVERFLOW_GUARD
    // at the top of this thread's stack, which overflows at the bottom
    char alt[ALT_STACK_SIZE];
    if (guard_on) guard_thread(alt);
#endif
    void *r = s.body(s.arg);
#ifdef ZS_OVERFLOW_GUARD
    if (guard_on) {
        stack_t off;
        memset(&off, 0, sizeof off);
        off.ss_flags = SS_DISABLE;
        sigaltstack(&off, NULL);
    }
#endif
    return r;
}

// The stack a program's threads get at least, whatever RLIMIT_STACK says (unlimited included):
// 0, but the compiler's own, 256 MB (src/host.c), for passes as deep as the program it reads nests
size_t zs_thread_stack;

// A thread's stack: the main thread's usual 8 MB at least (macOS gives a new thread 512 KB, which
// deep recursion, a compiler's passes over a long list literal, runs out of where Linux's 8 MB
// doesn't), or the soft RLIMIT_STACK when that's more, as glibc sizes its threads (ulimit -s
// raises it; the compiler raises its own, src/host.c), or zs_thread_stack. At most 1 GB, and
// 8 MB with 32-bit words.
static size_t thread_stack_size(void) {
    size_t size = (size_t)8 << 20;
#ifndef _WIN32
    size_t most = sizeof(void *) >= 8 ? (size_t)1 << 30 : size;
    struct rlimit rl;
    if (getrlimit(RLIMIT_STACK, &rl) == 0 && rl.rlim_cur != RLIM_INFINITY && rl.rlim_cur > size)
        size = rl.rlim_cur > most ? most : (size_t)rl.rlim_cur;
    if (zs_thread_stack > size) size = zs_thread_stack > most ? most : zs_thread_stack;
#endif
    return size;
}

// a thread whose large stack the address space has no room for (ulimit -v, many cores, each
// thread's stack the 256 MB a compiler running it left in RLIMIT_STACK) gets the usual 8 MB
// instead of failing
static int spawn(pthread_t *t, void *(*body)(void *), void *arg) {
    spawned *s = malloc(sizeof *s);
    if (!s) return -1;
    s->body = body;
    s->arg = arg;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    size_t size = thread_stack_size();
    pthread_attr_setstacksize(&attr, size);
    int r = pthread_create(t, &attr, spawned_main, s);
    if ((r == EAGAIN || r == ENOMEM) && size > ((size_t)8 << 20)) {
        pthread_attr_setstacksize(&attr, (size_t)8 << 20);
        r = pthread_create(t, &attr, spawned_main, s);
    }
    pthread_attr_destroy(&attr);
    if (r != 0) free(s);
    return r;
}

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
#ifdef ZS_FUZZ
    abort(); // libFuzzer records the crash
#endif
    if (getenv("ZS_ABORT")) abort();
    _exit(134);
}

// ---- zs fuzz (0010): the test binary's runner hands libFuzzer a property; each input it makes
// runs the property's case on those bytes (a callback<span<u8> -> unit>). args: the corpus
// directory and libFuzzer's flags, a line each. In a build without ZS_FUZZ there's no libFuzzer:
// said so, and 2.
#ifdef ZS_FUZZ
int LLVMFuzzerRunDriver(int *argc, char ***argv, int (*cb)(const uint8_t *data, size_t size));
static void (*fuzz_cb)(void *, const uint8_t *);
static void *fuzz_user;
static intptr_t fuzz_size;
static int fuzz_one(const uint8_t *data, size_t size) {
    fuzz_size = (intptr_t)size;
    fuzz_cb(fuzz_user, data);
    return 0;
}
#endif

// the input's length, for the callback (a callback takes one argument)
intptr_t zs_fuzz_size(void) {
#ifdef ZS_FUZZ
    return fuzz_size;
#else
    return 0;
#endif
}

int32_t zs_fuzz_drive(void (*cb)(void *, const uint8_t *), void *user, const char *args) {
#ifdef ZS_FUZZ
    fuzz_cb = cb;
    fuzz_user = user;
    // argv: the program, then a line each
    int n = 1;
    for (const char *p = args; *p; p++)
        if (*p == '\n') n++;
    char **argv = malloc((size_t)(n + 2) * sizeof *argv);
    char *text = strdup(args);
    if (!argv || !text) abort();
    int argc = 0;
    argv[argc++] = "zs-fuzz";
    for (char *p = text, *start = text;; p++) {
        if (*p == '\n' || *p == 0) {
            bool last = *p == 0;
            *p = 0;
            if (*start) argv[argc++] = start;
            if (last) break;
            start = p + 1;
        }
    }
    argv[argc] = NULL;
    return LLVMFuzzerRunDriver(&argc, &argv, fuzz_one);
#else
    (void)cb;
    (void)user;
    (void)args;
    fprintf(stderr, "not a fuzz build: zs fuzz builds the tests with libFuzzer\n");
    return 2;
#endif
}

// ---- Z# names in a panic's backtrace (0011): the program's own symbol table (.symtab, which
// a build keeps; its functions are internal, so nothing else names them), read from the
// executable at the panic and sorted by address; a frame's function is the nearest symbol at or
// below it. Linux's ELF; elsewhere the C library's backtrace_symbols_fd stands.
#if defined(__linux__)
#include <elf.h>

_Noreturn void zs_panic_c(const char *msg);

typedef struct {
    uintptr_t addr;
    const char *name;
} zs_symbol;

static zs_symbol *symbols;
static size_t symbol_count;
static uintptr_t symbol_base; // where the executable is loaded, for a position-independent one
static bool symbol_base_found;

static int symbol_order(const void *a, const void *b) {
    uintptr_t x = ((const zs_symbol *)a)->addr, y = ((const zs_symbol *)b)->addr;
    return x < y ? -1 : x > y;
}

static bool load_symbols(void) {
    if (symbols) return true;
    FILE *f = fopen("/proc/self/exe", "rb");
    if (!f) return false;
    if (fseek(f, 0, SEEK_END) != 0) return false;
    long size = ftell(f);
    if (size <= 0 || fseek(f, 0, SEEK_SET) != 0) return false;
    unsigned char *image = malloc((size_t)size);
    if (!image || fread(image, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        return false;
    }
    fclose(f);
    const Elf64_Ehdr *eh = (const Elf64_Ehdr *)image;
    if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 || eh->e_ident[EI_CLASS] != ELFCLASS64) return false;
    const Elf64_Shdr *sh = (const Elf64_Shdr *)(image + eh->e_shoff);
    for (int i = 0; i < eh->e_shnum; i++) {
        if (sh[i].sh_type != SHT_SYMTAB) continue;
        const Elf64_Sym *syms = (const Elf64_Sym *)(image + sh[i].sh_offset);
        size_t n = sh[i].sh_size / sizeof(Elf64_Sym);
        const char *strings = (const char *)(image + sh[sh[i].sh_link].sh_offset);
        symbols = malloc(n * sizeof *symbols);
        if (!symbols) return false;
        for (size_t k = 0; k < n; k++) {
            if (ELF64_ST_TYPE(syms[k].st_info) != STT_FUNC || syms[k].st_value == 0) continue;
            const char *name = strings + syms[k].st_name;
            symbols[symbol_count++] = (zs_symbol){(uintptr_t)syms[k].st_value, name};
            if (strcmp(name, "zs_panic_c") == 0) {
                symbol_base = (uintptr_t)(void *)zs_panic_c - (uintptr_t)syms[k].st_value;
                symbol_base_found = true;
            }
        }
        qsort(symbols, symbol_count, sizeof *symbols, symbol_order);
        // the image stays: its strings are the names. The table names this code only if it has
        // zs_panic_c (in a library built into another program, the executable is the host's)
        return symbol_count > 0 && symbol_base_found;
    }
    return false;
}

// the function a return address is in: the last symbol at or below it
static const char *symbol_at(void *frame) {
    // the call before the return address: a call that ends a function returns past its end
    uintptr_t a = (uintptr_t)frame - 1 - symbol_base;
    size_t lo = 0, hi = symbol_count;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (symbols[mid].addr <= a) lo = mid + 1;
        else hi = mid;
    }
    return lo == 0 ? NULL : symbols[lo - 1].name;
}

// the frames as Z# names: "zs." dropped, the runtime's own (zs_*) and the C library's left out,
// the program's main last
static void print_frames(void **frames, int n) {
    for (int i = 0; i < n; i++) {
        const char *name = symbol_at(frames[i]);
        if (!name || strncmp(name, "zs_", 3) == 0) continue;
        if (strncmp(name, "zs.", 3) == 0) name += 3;
        else if (strcmp(name, "main") != 0) continue;
        fprintf(stderr, "  at %s\n", name);
        if (strcmp(name, "main") == 0) break;
    }
}
#endif

// a C host's function, run on a panic before the process stops (zs_set_panic_hook)
static void (*panic_hook)(const char *message);

void zs_set_panic_hook(void (*hook)(const char *message)) { panic_hook = hook; }

// ---- coverage (zs build --coverage): each module's lines, a counter each, written at exit (a
// panic's too) to <program>.zscov, one line per line: the file, the line and the count, tabs
// between; zs test --coverage reads them
typedef struct {
    const char *file;
    int32_t line;
} zs_cov_line;

typedef struct {
    const zs_cov_line *table;
    int64_t *counts;
    int64_t n;
} cov_module;

static cov_module *cov_modules;
static int cov_count, cov_cap;
static char **g_argv;

// written once per process (a panic's stop, Environment.exit and exit's handlers may each come
// here, on several threads at once): a later caller waits for the first's write to finish, so
// the process doesn't end with it half written
static pthread_mutex_t cov_mu = PTHREAD_MUTEX_INITIALIZER;
static bool cov_written;

static void coverage_dump(void) {
    pthread_mutex_lock(&cov_mu);
    if (cov_written || !cov_count) {
        pthread_mutex_unlock(&cov_mu);
        return;
    }
    cov_written = true;
    const char *exe = g_argv && g_argv[0] ? g_argv[0] : "program";
    size_t len = strlen(exe) + 7;
    char *path = malloc(len);
    FILE *f = NULL;
    if (path) {
        snprintf(path, len, "%s.zscov", exe);
        // as bytes: Windows' text mode would end each line \r\n, which zs test doesn't read
        f = fopen(path, "ab");
        free(path);
    }
    if (f) {
        for (int m = 0; m < cov_count; m++)
            for (int64_t i = 0; i < cov_modules[m].n; i++)
                fprintf(f, "%s\t%d\t%" PRId64 "\n", cov_modules[m].table[i].file, cov_modules[m].table[i].line, cov_modules[m].counts[i]);
        fclose(f);
    }
    pthread_mutex_unlock(&cov_mu);
}

void zs_coverage_register(const zs_cov_line *table, int64_t *counts, int64_t n) {
    if (cov_count == cov_cap) {
        cov_cap = cov_cap ? 2 * cov_cap : 8;
        cov_modules = realloc(cov_modules, (size_t)cov_cap * sizeof *cov_modules);
        if (!cov_modules) abort();
    }
    if (!cov_count) atexit(coverage_dump);
    cov_modules[cov_count++] = (cov_module){table, counts, n};
}

// one panic at a time: a second thread's panic waits for the first's stop (which ends the
// process), and a panic inside the panic (its hook, a dump, the backtrace) stops at once
static atomic_flag panicking = ATOMIC_FLAG_INIT;
static _Thread_local bool in_panic;

// the message by its length: a Z# string may hold a NUL (a property's case shown in it), which
// would end it early as a C string
_Noreturn static void panic_with(const char *msg, size_t len) {
    if (in_panic) stop();
    in_panic = true;
    if (atomic_flag_test_and_set(&panicking))
        for (;;) {
#ifdef _WIN32
            Sleep(1000);
#else
            pause();
#endif
        }
    coverage_dump();
    fflush(stdout);
    fputs("panic: ", stderr);
    fwrite(msg, 1, len, stderr);
    fputc('\n', stderr);
    fflush(stderr); // the UCRT buffers it when it isn't a console
#if defined(__GLIBC__) || defined(__APPLE__)
    const char *bt = getenv("ZS_BACKTRACE");
    if (!bt || strcmp(bt, "0") != 0) {
        void *frames[64];
        int n = backtrace(frames, 64);
#if defined(__linux__)
        if (load_symbols()) print_frames(frames + 1, n - 1);
        else backtrace_symbols_fd(frames + 1, n - 1, 2);
#else
        backtrace_symbols_fd(frames + 1, n - 1, 2);
#endif
    }
#endif
    void (*hook)(const char *) = panic_hook;
    panic_hook = NULL; // a panic inside the hook stops at once
    if (hook) hook(msg);
    stop();
}

_Noreturn void zs_panic_c(const char *msg) { panic_with(msg, strlen(msg)); }

_Noreturn void zs_panic(zs_str *msg) { panic_with(msg->data, (size_t)msg->len); }

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
#define TOTAL(x) (x)
#endif

// Objects come from a pool: 8-byte size classes up to 256 bytes, each with a free list, carved
// from 64 KB chunks; a freed object goes on its class's list, and the next allocation of that
// size takes it (no system allocator call either way). With threads, each thread has lists and a
// chunk of its own: an object goes on the list of the thread that frees it, whichever made it,
// so no lock and no atomic either. Byte 6 of the header says where an object came from: its
// class, or SYSTEM for malloc and aligned_alloc. With a sanitizer or valgrind (ZS_NO_POOL), it's
// plain malloc, so the tools see every object. A thread that ends leaves its lists and the rest
// of its chunk to the next thread to start (heap_state).
// ponytail: chunks are kept until exit; a program whose small objects peak once keeps that
// memory, and so does a thread that frees objects of a size it doesn't make (a consumer's)
#if !defined(ZS_NO_POOL)
#define ZS_POOL 1
#define POOL_MAX 256
#define POOL_CHUNK ((size_t)64 * 1024)
#define FROM(p) (((uint8_t *)(p))[6])
#define SYSTEM 0xFF
#endif

// What the allocator keeps for a thread: its counts (with threads) and the pool's free lists and
// chunk, in one record, so an allocation looks up one thread-local (on macOS, a call).
typedef struct heap_state {
#ifdef ZS_THREADS
    counts *counts;
    struct heap_state *spare; // the next of the ended threads'
#endif
#if ZS_POOL
    void *free[POOL_MAX / 8 + 1];
    char *next, *end;
#endif
    char unused; // a member whatever the build
} heap_state;

#ifdef ZS_THREADS
// A thread's state is made at its first allocation or free, and outlives it: when the thread
// ends (a C host's come and go, and Task.blocking's helper ends with its Task.run), its key's
// destructor gives the state up, and the next thread to start takes it whole, its free lists,
// the rest of its chunk and its counts (which stay in all_counts, so the totals keep them). The
// thread-local is a pointer to it, as on macOS dyld may free a thread's thread-locals before that
// destructor runs. The spare states are under counts_mu.
static _Thread_local heap_state *heap_mine;
static heap_state *spare_states;
static pthread_key_t heap_key;
static pthread_once_t heap_once = PTHREAD_ONCE_INIT;
static bool heap_keyed; // heap_key made, and not deleted yet

static void heap_end(void *arg) {
    heap_state *h = arg;
    pthread_mutex_lock(&counts_mu);
    h->spare = spare_states;
    spare_states = h;
    pthread_mutex_unlock(&counts_mu);
    // a destructor after this one that allocates takes a state again, given up in the next round
    heap_mine = NULL;
}

static void heap_key_make(void) {
    if (pthread_key_create(&heap_key, heap_end) != 0) zs_panic_c("pthread_key_create failed");
    __atomic_store_n(&heap_keyed, true, __ATOMIC_RELEASE);
}

// The key's destructor is code in this image: a host that unloads a library holding this runtime
// (dlclose, FreeLibrary) while threads that called it live on would have each of them run it, in
// unmapped code, when it ends. So the key goes with the image (at exit too), and a thread ending
// after that keeps its state.
__attribute__((destructor)) static void heap_unload(void) {
    if (__atomic_exchange_n(&heap_keyed, false, __ATOMIC_ACQ_REL)) pthread_key_delete(heap_key);
#if !ZS_POOL
    // Without the pool (a sanitizer's or valgrind's build) a state holds no memory but its own:
    // this thread's and the ended threads' are freed with their counts, so valgrind reports none
    // at exit. A thread that lives on keeps its own, and one that allocates after this takes a new.
    pthread_mutex_lock(&counts_mu);
    heap_state *h = heap_mine;
    heap_mine = NULL;
    if (h) h->spare = spare_states; else h = spare_states;
    spare_states = NULL;
    while (h) {
        heap_state *next = h->spare;
        for (counts **c = &all_counts; *c; c = &(*c)->next)
            if (*c == h->counts) { *c = h->counts->next; break; }
        free(h->counts);
        free(h);
        h = next;
    }
    pthread_mutex_unlock(&counts_mu);
#endif
}

__attribute__((noinline)) static heap_state *heap_new(void) {
    pthread_once(&heap_once, heap_key_make);
    bool keyed = __atomic_load_n(&heap_keyed, __ATOMIC_ACQUIRE);
    // this thread's own, when its thread-locals went before its destructors ran (macOS)
    heap_state *h = keyed ? pthread_getspecific(heap_key) : NULL;
    if (h) return heap_mine = h;
    pthread_mutex_lock(&counts_mu);
    h = spare_states;
    if (h) spare_states = h->spare;
    pthread_mutex_unlock(&counts_mu);
    if (!h) {
        h = aligned_alloc(64, (sizeof(heap_state) + 63) & ~(size_t)63); // a cache line of its own
        counts *c = aligned_alloc(64, 64);
        if (!h || !c) zs_panic_c("out of memory");
        memset(h, 0, sizeof *h);
        memset(c, 0, 64);
        h->counts = c;
        pthread_mutex_lock(&counts_mu);
        c->next = all_counts;
        all_counts = c;
        pthread_mutex_unlock(&counts_mu);
    }
    h->spare = NULL;
    heap_mine = h;
    if (keyed) pthread_setspecific(heap_key, h);
    return h;
}

static inline heap_state *heap_of_thread(void) {
    heap_state *h = heap_mine;
    return h ? h : heap_new();
}

// only the thread itself writes its counts; another reads them whole
#define COUNT_IN(h, x, d) do { counts *c_ = (h)->counts; __atomic_store_n(&c_->x, c_->x + (d), __ATOMIC_RELAXED); } while (0)
#else
static heap_state heap_here;
static inline heap_state *heap_of_thread(void) { return &heap_here; }
#define COUNT_IN(h, x, d) ((void)(h), (x) += (d))
#endif
// a count changed where the thread's state isn't at hand already
#define COUNT(x, d) COUNT_IN(heap_of_thread(), x, d)

#if ZS_POOL
static void pool_chunk(heap_state *h) {
    h->next = malloc(POOL_CHUNK);
    if (!h->next) zs_panic_c("out of memory");
    h->end = h->next + POOL_CHUNK;
    COUNT_IN(h, mallocs, 1);
}
#endif

void *zs_alloc(zs_int size) {
    heap_state *h = heap_of_thread();
    COUNT_IN(h, live, 1);
    COUNT_IN(h, allocations, 1);
#if ZS_POOL
    size_t total = ((size_t)size + 7) & ~(size_t)7;
    void *p;
    if (total <= POOL_MAX) {
        size_t c = total >> 3;
        p = h->free[c];
        if (p) {
            h->free[c] = *(void **)p;
        } else {
            if ((size_t)(h->end - h->next) < total) pool_chunk(h);
            p = h->next;
            h->next += total;
        }
        FROM(p) = (uint8_t)c;
        return p;
    }
    p = obj_malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    COUNT_IN(h, mallocs, 1);
    FROM(p) = SYSTEM;
    return p;
#else
    void *p = obj_malloc((size_t)size);
    if (!p) zs_panic_c("out of memory");
    COUNT_IN(h, mallocs, 1);
    return p;
#endif
}

// zs_alloc for a program whose objects may hold SIMD vectors (the compiler swaps it in, see
// Compile.wideVectors): each object aligned to 64 bytes, so a vector field or element is aligned
// as LLVM expects
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
    heap_state *h = heap_of_thread();
    COUNT_IN(h, live, -1);
#if ZS_POOL
    size_t c = FROM(p);
    if (c - 1 < POOL_MAX / 8) {
        *(void **)p = h->free[c];
        h->free[c] = p;
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

// ---- weak references (weak<T>): references that don't keep their object alive. A thread's weak
// references to one object share a cell { count, object }, found from the object in a table, and
// the object dying (freed, or its cell reused for another) empties the cell. A program that uses
// weak references or arenas allocates and frees through zs_alloc_checked and zs_free_checked.
// A weak reference isn't Share, so a cell stays on the thread that made it, and compiled code
// counts it there, not atomically: another thread's weak references to the same object (a shared
// one) have a cell of their own, chained to the first, which the table holds.
typedef struct zs_weak {
    ZS_HEADER;
    void *target;
    struct zs_weak *next; // the object's cell of another thread
    pthread_t owner;
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
    pthread_t self = pthread_self();
    HEAP_LOCK();
    bool dies = __atomic_load_n((int32_t *)target, __ATOMIC_RELAXED) != 0; // a static object never does: its cells aren't in the table
    zs_weak *first = dies ? tab_get(&weaks, target) : NULL, *w = first;
    while (w && !pthread_equal(w->owner, self)) w = w->next;
    if (w) {
        w->rc++;
    } else {
        w = zs_alloc((zs_int)sizeof(zs_weak));
        w->rc = 1;
        w->target = dies ? target : (void *)((uintptr_t)target | 1); // the low bit: static
        w->owner = self;
        w->next = NULL;
        if (first) {
            w->next = first->next;
            first->next = w;
        } else if (dies) {
            tab_put(&weaks, target, w);
        }
    }
    HEAP_UNLOCK();
    return w;
}

// the object, with a new reference, or NULL once it has died. A shared object (count below 0)
// gets its reference only while its count isn't 0: at 0 another thread is freeing it. A
// thread-local one is this thread's, as the weak reference is: with threads, code generation
// marks a Share object shared when a weak reference to it is made, so no crossing moves it to
// another thread unmarked
void *zs_weak_target(zs_weak *w) {
    // read before the lock: the low bit is the cell's from its making, and another thread may
    // empty the cell meantime (its object dying there)
    void *at = __atomic_load_n(&w->target, __ATOMIC_RELAXED);
    if ((uintptr_t)at & 1) return (void *)((uintptr_t)at & ~(uintptr_t)1);
    HEAP_LOCK();
    int32_t *t = w->target;
    if (t) {
        int32_t c = __atomic_load_n(t, __ATOMIC_RELAXED);
        if (c > 0) {
            *t = c + 1;
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
void zs_free_checked(void *p);

void zs_weak_free(zs_weak *w) {
    HEAP_LOCK();
    if (w->target && !((uintptr_t)w->target & 1)) {
        // out of its object's chain
        zs_weak *first = tab_get(&weaks, w->target);
        if (first == w) {
            tab_remove(&weaks, w->target);
            if (w->next) tab_put(&weaks, w->target, w->next);
        } else {
            for (zs_weak *p = first; p; p = p->next)
                if (p->next == w) {
                    p->next = w->next;
                    break;
                }
        }
    }
    HEAP_UNLOCK();
    zs_free_checked(w);
}

// the object p has died: every thread's cell of it is emptied (under the lock)
static void weaks_die(void *p) {
    zs_weak *w = weaks.count ? tab_remove(&weaks, p) : NULL;
    while (w) {
        zs_weak *next = w->next;
        __atomic_store_n(&w->target, NULL, __ATOMIC_RELAXED); // its thread may be reading it
        w->next = NULL;
        w = next;
    }
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
    size_t n = ((size_t)size + 7) & ~(size_t)7; // 8-byte aligned, as the pool's (a program whose objects may hold vectors has no arenas: its objects are zs_alloc_wide's)
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
    weaks_die(p);
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
    weaks_die(p);
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

// a string of len bytes and its NUL: a length past what a word holds (a sum or product of
// lengths on a 32-bit target) can't be allocated, and mustn't wrap to a small object
static zs_str *str_new(int64_t len) {
    if (len < 0 || len > (int64_t)INTPTR_MAX - (int64_t)sizeof(zs_str) - 1) zs_panic_c("out of memory");
    zs_str *s = zs_alloc((zs_int)sizeof(zs_str) + (zs_int)len + 1);
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
    zs_str *s = str_new((int64_t)a->len + b->len);
    memcpy(s->data, a->data, (size_t)a->len);
    memcpy(s->data + a->len, b->data, (size_t)b->len);
    return s;
}

// pieces[0] to pieces[n - 1] joined into one new string (a chain of +, an interpolation's
// pieces): one allocation, where a + at a time makes n - 1. Borrows them; the caller drops them.
zs_str *zs_str_concat_n(zs_str **pieces, zs_int n) {
    int64_t len = 0;
    for (zs_int i = 0; i < n; i++) len += pieces[i]->len;
    zs_str *s = str_new(len);
    char *d = s->data;
    for (zs_int i = 0; i < n; i++) {
        memcpy(d, pieces[i]->data, (size_t)pieces[i]->len);
        d += pieces[i]->len;
    }
    return s;
}

// -1, 0 or 1
zs_int zs_str_cmp(zs_str *a, zs_str *b) {
    zs_int n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->data, b->data, (size_t)n);
    if (c != 0) return c < 0 ? -1 : 1;
    return a->len < b->len ? -1 : a->len > b->len;
}

// A string's hash is SipHash-1-3 (Rust's HashMap's) under a key drawn once a process: one the
// same in every run (FNV-1a's was) lets whoever picks the keys (a JSON object's, from a socket)
// put them all in one HashMap bucket, every lookup then walking all of them (HashDoS). Drawn
// before main, so every thread hashes with the same key.
// ponytail: ints still hash to themselves; a keyed mix in the hash primitive if their keys come
// from outside
static uint64_t hash_key[2];
__attribute__((constructor)) static void hash_key_draw(void) {
    hash_key[0] = zs_random_seed();
    hash_key[1] = zs_random_seed();
}

#define SIP_ROTL(x, b) (((x) << (b)) | ((x) >> (64 - (b))))
#define SIP_ROUND \
    do { \
        v0 += v1, v1 = SIP_ROTL(v1, 13), v1 ^= v0, v0 = SIP_ROTL(v0, 32); \
        v2 += v3, v3 = SIP_ROTL(v3, 16), v3 ^= v2; \
        v0 += v3, v3 = SIP_ROTL(v3, 21), v3 ^= v0; \
        v2 += v1, v1 = SIP_ROTL(v1, 17), v1 ^= v2, v2 = SIP_ROTL(v2, 32); \
    } while (0)

zs_int zs_str_hash(zs_str *s) {
    uint64_t k0 = hash_key[0], k1 = hash_key[1];
    uint64_t v0 = k0 ^ 0x736f6d6570736575ull, v1 = k1 ^ 0x646f72616e646f6dull;
    uint64_t v2 = k0 ^ 0x6c7967656e657261ull, v3 = k1 ^ 0x7465646279746573ull;
    const uint8_t *p = (const uint8_t *)s->data;
    size_t n = (size_t)s->len, whole = n & ~(size_t)7;
    for (size_t i = 0; i < whole; i += 8) {
        uint64_t m;
        memcpy(&m, p + i, 8);
        v3 ^= m;
        SIP_ROUND;
        v0 ^= m;
    }
    uint64_t last = (uint64_t)n << 56; // the length's low byte, over the last 0 to 7 bytes
    for (size_t i = whole; i < n; i++) last |= (uint64_t)p[i] << (8 * (i - whole));
    v3 ^= last;
    SIP_ROUND;
    v0 ^= last;
    v2 ^= 0xff;
    SIP_ROUND;
    SIP_ROUND;
    SIP_ROUND;
    uint64_t h = v0 ^ v1 ^ v2 ^ v3;
    return sizeof(zs_int) < 8 ? (zs_int)(h ^ (h >> 32)) : (zs_int)h; // fold on a 32-bit chip
}

// digits by hand: snprintf's locale and format cost more than the number
static int u64_text(uint64_t v, char *out) {
    char tmp[24];
    int n = 0;
    do {
        tmp[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    for (int i = 0; i < n; i++) out[i] = tmp[n - 1 - i];
    return n;
}

zs_str *zs_str_of_i64(int64_t v) {
    char buf[24];
    int n = 0;
    if (v < 0) buf[n++] = '-';
    n += u64_text(v < 0 ? (uint64_t)(-(v + 1)) + 1 : (uint64_t)v, buf + n);
    return str_of(buf, n);
}

zs_str *zs_str_of_u64(uint64_t v) {
    char buf[24];
    return str_of(buf, u64_text(v, buf));
}

// Numbers are written and read with a '.': printf and strtod use the locale's decimal point,
// which setlocale (a C library's: GTK's, ncurses programs') changes, de_DE's printing 1.5 as
// "1,5" (invalid JSON, two CSV fields) and reading "1.5" as 1. LC_NUMERIC "C", per call.
// ponytail: Windows keeps the CRT's locale; a _create_locale "C" one for c_snprintf's NULL, and
// _strtod_l, if a Windows library calls setlocale
#ifdef _WIN32
#include <stdarg.h>
#define c_strtod strtod
#define c_strtof strtof
// the UCRT's own printf (C99's snprintf, and its rounding), not mingw-w64's that _GNU_SOURCE
// makes snprintf: where a long double is a double (aarch64), that one widens a subnormal double
// to an 80-bit normal, then scales it as an 80-bit subnormal (2^-1074 * 63551 as 6.52e-4932)
static int c_snprintf(char *buf, size_t size, const char *format, ...) {
    va_list args;
    va_start(args, format);
    int n = __stdio_common_vsprintf(_CRT_INTERNAL_PRINTF_STANDARD_SNPRINTF_BEHAVIOR | _CRT_INTERNAL_PRINTF_STANDARD_ROUNDING, buf, size, format, NULL, args);
    va_end(args);
    return n;
}
#else
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
#include <stdarg.h>
static locale_t c_numeric;
__attribute__((constructor)) static void c_numeric_make(void) { c_numeric = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0); }

static double c_strtod(const char *s, char **end) {
    locale_t was = uselocale(c_numeric); // (locale_t)0 if newlocale failed: no change
    double v = strtod(s, end);
    uselocale(was);
    return v;
}

static float c_strtof(const char *s, char **end) {
    locale_t was = uselocale(c_numeric);
    float v = strtof(s, end);
    uselocale(was);
    return v;
}

static int c_snprintf(char *buf, size_t size, const char *format, ...) {
    va_list args;
    va_start(args, format);
    locale_t was = uselocale(c_numeric);
    int n = vsnprintf(buf, size, format, args);
    uselocale(was);
    va_end(args);
    return n;
}
#endif

// a NaN as the positive quiet one, which every C library writes "nan": they differ on the sign
// (glibc's "-nan" for x86's 0.0 / 0.0) and the kind (the UCRT's "-nan(ind)", "nan(snan)")
static double plain_nan(double v) { return v != v ? __builtin_nan("") : v; }

// a double that is a decimal of at most 15 digits, from 1e-4 to under 1e15 (and 0), written by
// hand: what "%.15g" writes for it, which reads back as it. Most numbers a program prints are
// one, and snprintf with strtod costs some 2,000 instructions. 0 for any other double (-0.0 too).
// m is v * 10^k to the nearest integer, exact under 2^53 as 10^k is, so m / 10^k is the double
// nearest that decimal: equal to v, the decimal reads back as v, and no other of 15 digits does.
static int f64_decimal_text(double v, char *out) {
    double a = v < 0 ? -v : v;
    if (!(a >= 1e-4 && a < 1e15) && !(v == 0 && !__builtin_signbit(v))) return 0;
    double p = 1;
    uint64_t ip = 1;
    for (int k = 0; a * p < 1e15; k++, p *= 10, ip *= 10) {
        uint64_t m = (uint64_t)(a * p + 0.5);
        if ((double)m / p != a) continue;
        int n = 0;
        if (v < 0) out[n++] = '-';
        n += u64_text(m / ip, out + n);
        if (k) {
            out[n++] = '.';
            uint64_t f = m % ip;
            for (int i = k - 1; i >= 0; i--, f /= 10) out[n + i] = (char)('0' + f % 10);
            n += k;
        }
        return n;
    }
    return 0;
}

// Shortest representation that reads back as the same double; whole numbers print like ints.
zs_str *zs_str_of_f64(double v) {
    char buf[40];
    int n = f64_decimal_text(v, buf);
    if (n) return str_of(buf, n);
    v = plain_nan(v);
    for (int prec = 15; prec <= 17; prec++) {
        n = c_snprintf(buf, sizeof buf, "%.*g", prec, v);
        if (c_strtod(buf, NULL) == v) break;
    }
    return str_of(buf, n);
}

// the shortest text that reads back as the same f32 (0.3f prints "0.3", not its double value)
zs_str *zs_str_of_f32(float v) {
    char buf[40];
    int n = 0;
    for (int prec = 6; prec <= 9; prec++) {
        n = c_snprintf(buf, sizeof buf, "%.*g", prec, plain_nan(v));
        if (c_strtof(buf, NULL) == v) break;
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

static int int_text(zs_int v, char *out) {
    if (v >= 0) return u64_text((uint64_t)v, out);
    out[0] = '-';
    return 1 + u64_text((uint64_t)0 - (uint64_t)v, out + 1);
}

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

// t in at most room bytes (3 or more), its end "..." when it doesn't fit
static int text_upto(const char *t, char *out, int room) {
    int k = 0;
    while (t[k] && k < room) {
        out[k] = t[k];
        k++;
    }
    if (t[k]) k = k - 3 + text_of("...", out + k - 3);
    return k;
}

// Fixed.ofArray of an array that hasn't the type's length; the type's text is the compiler's,
// as long as its element type's (a module's path, generic arguments, a tuple's parts), so it's
// cut to leave room for the rest, a length's 20 characters and the NUL
_Noreturn void zs_fixed_fail(const char *type, zs_int len) {
    char msg[160];
    int k = text_upto(type, msg, (int)sizeof msg - 25 - 20 - 1);
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

// the length of the well-formed UTF-8 sequence at p (n bytes left) as String.decodeAt reads it,
// or 0 when it's malformed: RFC 3629's, as Utf8.validate's, so no overlong form (C0 AF would
// decode to a '/' that a check of the bytes never saw), surrogate or value past U+10FFFF
static zs_int utf8_seq(const uint8_t *p, zs_int n) {
    uint8_t b = p[0];
    if (b < 0x80) return 1;
    zs_int k = b >= 0xC2 && b <= 0xDF ? 2 : b >= 0xE0 && b <= 0xEF ? 3 : b >= 0xF0 && b <= 0xF4 ? 4 : 0;
    if (k == 0 || k > n) return 0;
    // the second byte's range: narrower after E0 and F0 (overlong), ED (surrogates) and F4 (past U+10FFFF)
    uint8_t lo = b == 0xE0 ? 0xA0 : b == 0xF0 ? 0x90 : 0x80, hi = b == 0xED ? 0x9F : b == 0xF4 ? 0x8F : 0xBF;
    if (p[1] < lo || p[1] > hi) return 0;
    for (zs_int i = 2; i < k; i++)
        if ((p[i] & 0xC0) != 0x80) return 0;
    return k;
}

// String.ofBytes: a copy of the bytes, each malformed one replaced by U+FFFD (decision 28)
zs_str *zs_str_of_bytes(const uint8_t *p, zs_int n) {
    int64_t len = 0; // a malformed byte becomes 3
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
    zs_int n = sub->len;
    if (from > s->len - n) return -1;
    if (n == 0) return from;
    // memchr to each place the first byte is, memcmp there for the rest
    const char *p = s->data + from, *last = s->data + s->len - n;
    while ((p = memchr(p, sub->data[0], (size_t)(last - p + 1)))) {
        if (memcmp(p + 1, sub->data + 1, (size_t)(n - 1)) == 0) return p - s->data;
        if (p++ == last) break;
    }
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
    int64_t n = 0, grow, len;
    for (int64_t i = 0; (i = zs_str_index_of(s, old, i)) >= 0; i += old->len) n++;
    if (__builtin_mul_overflow(n, (int64_t)with->len - old->len, &grow) || __builtin_add_overflow((int64_t)s->len, grow, &len)) zs_panic_c("out of memory");
    zs_str *r = str_new(len);
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


// ---- format specifiers ($"{x:F2}", 0024): .NET's standard numeric formats, invariant

// a specifier the compiler would refuse in a hole: the panic quotes it (its first bytes, any but
// printable ASCII as '?'), or names the letters the type takes
_Noreturn static void spec_fail(zs_str *spec, const char *kind, const char *letters) {
    char msg[160];
    int k;
    if (kind) {
        k = text_of("'", msg);
        msg[k++] = spec->data[0];
        k += text_of("' isn't a format specifier for ", msg + k);
        k += text_of(kind, msg + k);
        k += text_of(": it takes ", msg + k);
        for (int i = 0; letters[i]; i++) {
            if (i > 0) k += text_of(", ", msg + k);
            msg[k++] = letters[i];
        }
    } else {
        k = text_of("a format specifier is a letter and at most two digits, as F2 or X8, not '", msg);
        for (zs_int i = 0; i < spec->len && i < 16; i++) {
            unsigned char c = (unsigned char)spec->data[i];
            msg[k++] = c >= 32 && c < 127 ? (char)c : '?';
        }
        if (spec->len > 16) k += text_of("...", msg + k);
        msg[k++] = '\'';
    }
    panic_with(msg, (size_t)k);
}

// a specifier's letter, one of the type's letters, and its digits (-1 when it has none). A
// hole's is checked at compile time; Format.format's, which may be made at run time, is checked
// here by the same rules (a letter and at most two ASCII digits), so a width or a precision is
// at most 99, which every buffer below holds; anything else panics
static void spec_of(zs_str *spec, const char *kind, const char *letters, char *letter, int *digits) {
    const unsigned char *s = (const unsigned char *)spec->data;
    zs_int n = spec->len;
    bool ok = n >= 1 && n <= 3 && ((s[0] >= 'A' && s[0] <= 'Z') || (s[0] >= 'a' && s[0] <= 'z'));
    for (zs_int i = 1; ok && i < n; i++) ok = s[i] >= '0' && s[i] <= '9';
    if (!ok) spec_fail(spec, NULL, NULL);
    if (!strchr(letters, s[0])) spec_fail(spec, kind, letters);
    *letter = (char)s[0];
    *digits = -1;
    if (n > 1) {
        *digits = 0;
        for (zs_int i = 1; i < n; i++) *digits = *digits * 10 + (s[i] - '0');
    }
}

// what snprintf wrote: it counts what it would have, past the buffer when it cut the text
static zs_str *str_written(const char *buf, int n, size_t cap) {
    return str_of(buf, n < 0 ? 0 : (size_t)n >= cap ? (zs_int)cap - 1 : n);
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
    c_snprintf(exact, sizeof exact, "%.*f", 1100, x); // every digit of a double's expansion
    char *point = strchr(exact, '.');
    bool tie = point && point[d + 1] == '5';
    for (int i = d + 2; tie && point[i]; i++) tie = point[i] == '0';
    if (!tie) return c_snprintf(out, cap, "%.*f", d, x);
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
    spec_of(spec, "a float", "FNEG", &letter, &d);
    x = plain_nan(x);
    switch (letter) {
    case 'F': n = fixed(x, d < 0 ? 2 : d, buf, sizeof buf); break;
    case 'N': fixed(x, d < 0 ? 2 : d, buf, sizeof buf); n = group(buf, grouped); return str_of(grouped, n);
    case 'E': {
        // 1.23E+003: the exponent with its sign and at least three digits
        n = c_snprintf(buf, sizeof buf, "%.*E", d < 0 ? 6 : d, x);
        char *e = strchr(buf, 'E');
        if (e) {
            int exp = atoi(e + 1);
            n = (int)(e - buf) + snprintf(e, sizeof buf - (size_t)(e - buf), "E%c%03d", exp < 0 ? '-' : '+', exp < 0 ? -exp : exp);
        }
        break;
    }
    default: // G
        if (d <= 0) return zs_str_of_f64(x);
        n = c_snprintf(buf, sizeof buf, "%.*G", d, x);
    }
    return str_written(buf, n, sizeof buf);
}

// v at a width of bits bits (unsigned: its bits as they are), under a specifier
zs_str *zs_format_int(int64_t v, int64_t bits, bool isUnsigned, zs_str *spec) {
    char buf[200], grouped[300];
    char letter;
    int d, n;
    spec_of(spec, "an integer", "FNDXxBb", &letter, &d);
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
        if (pad > (int)sizeof buf - k) pad = (int)sizeof buf - k;
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
    return str_written(buf, n, sizeof buf);
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
// spaces, no hexadecimal, no 1,5). Any length: a constant pasted with 500 digits rounds as
// strtod rounds it, its copy on the heap past the stack's buffer
bool zs_parse_float(zs_str *s, double *out) {
    char small[400];
    if (s->len == 0) return false;
    for (zs_int i = 0; i < s->len; i++) {
        char c = s->data[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 'x' || c == 'X' || c == 0) return false;
    }
    char *buf = small;
    if (s->len >= (zs_int)sizeof small) {
        buf = malloc((size_t)s->len + 1);
        if (!buf) zs_panic_c("out of memory");
    }
    memcpy(buf, s->data, (size_t)s->len);
    buf[s->len] = 0;
    char *end;
    double v = c_strtod(buf, &end);
    bool ok = end == buf + s->len;
    if (buf != small) free(buf);
    if (!ok) return false;
    *out = v;
    return true;
}

// String.isFloat and String.toFloat, over the same reading (strtod alone took leading spaces
// and hex, which Float.parse refuses)
bool zs_str_is_float(zs_str *s) {
    double x;
    return zs_parse_float(s, &x);
}

double zs_str_to_float(zs_str *s) {
    double x = 0;
    zs_parse_float(s, &x);
    return x;
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

// A program ignores SIGPIPE (zs_set_args), so writing to a pipe whose reader has gone (a child's
// standard input) is an Error, not the end of the program. Standard output or error gone (`| head`
// has read what it wants) still ends it as SIGPIPE did: console_failed after a failed write. A
// library leaves its host's signals alone.
#include <errno.h>
#ifndef _WIN32
static bool sigpipe_ignored;
#endif

static void console_failed(void) {
#ifndef _WIN32
    if (!sigpipe_ignored || errno != EPIPE) return;
    signal(SIGPIPE, SIG_DFL);
    raise(SIGPIPE);
    _exit(128 + SIGPIPE); // blocked in this thread: the status it would have ended with
#endif
}

static void console_flush(void) {
    if (fflush(stdout) != 0) console_failed();
}

void zs_eprintln(zs_str *s) {
    console_flush();
    if (fwrite(s->data, 1, (size_t)s->len, stderr) != (size_t)s->len || fputc('\n', stderr) == EOF) console_failed();
}

void zs_print(zs_str *s) {
    if (fwrite(s->data, 1, (size_t)s->len, stdout) != (size_t)s->len) console_failed();
}

void zs_println(zs_str *s) {
    // a short line and its newline in one write: one lock of stdout, and no other thread's
    // text between them
    char line[256];
    if (s->len < (zs_int)sizeof line) {
        memcpy(line, s->data, (size_t)s->len);
        line[s->len] = '\n';
        if (fwrite(line, 1, (size_t)s->len + 1, stdout) != (size_t)s->len + 1) console_failed();
    } else if (fwrite(s->data, 1, (size_t)s->len, stdout) != (size_t)s->len || fputc('\n', stdout) == EOF) {
        console_failed();
    }
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
#else
    // a write to a pipe whose reader has gone is an Error (standard output's ends the program
    // still: console_failed, and at exit console_flush); SIGCHLD as the system has it, which
    // waitpid needs (ignored, as a parent may hand it down, children are reaped unasked and
    // waitpid fails). Children start with both as the system has them (spawn_attr).
    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, SIG_DFL);
    sigpipe_ignored = true;
    atexit(console_flush); // after the exit handlers registered later; C's own flush is quiet
#endif
    const char *stats = getenv("ZS_STATS");
    if (stats && *stats && strcmp(stats, "0") != 0) atexit(print_stats);
#ifdef ZS_OVERFLOW_GUARD
    guard_install();
#endif
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

// whether the OS reads the name as given: it stops at a NUL, so one holding a NUL would name
// something shorter ("secret\0.txt" the file secret, "evil.example\0.trusted.example" a host);
// it fails instead, EINVAL
static bool os_name(zs_str *s) {
    if (!memchr(s->data, 0, (size_t)s->len)) return true;
    errno = EINVAL;
    return false;
}

bool zs_env_has(zs_str *name) { return os_name(name) && getenv(name->data) != NULL; }

zs_str *zs_env_get(zs_str *name) {
    const char *v = os_name(name) ? getenv(name->data) : NULL;
    return zs_str_from_c(v ? v : "");
}

// like a panic, no cleanup (and so no leak report): the process ends here, the coverage counts
// written first (_exit skips atexit's)
_Noreturn void zs_exit(zs_int code) {
    coverage_dump();
    console_flush();
    fflush(NULL);
    _exit((int)code);
}

// a reader's buffer (a file's, a directory's, a process's output), of cap bytes or grown to twice
// its cap: out of memory panics, as an allocation does (a NULL kept as the buffer had the next
// read write at the buffer's offset from address 0)
static char *buf_new(size_t cap) {
    char *b = malloc(cap);
    if (!b) zs_panic_c("out of memory");
    return b;
}

static char *buf_grow(char *b, size_t *cap) {
    char *nb = *cap > SIZE_MAX / 2 ? NULL : realloc(b, *cap * 2);
    if (!nb) zs_panic_c("out of memory");
    *cap *= 2;
    return nb;
}

zs_str *zs_file_read(zs_str *path) {
    clear_error();
    FILE *f = os_name(path) ? fopen(path->data, "rb") : NULL;
    if (!f) {
        set_error("cannot open", path);
        return str_of("", 0);
    }
    size_t cap = 4096, len = 0;
    char *buf = buf_new(cap);
    size_t n;
    while ((n = fread(buf + len, 1, cap - len, f)) > 0) {
        len += n;
        if (len == cap) buf = buf_grow(buf, &cap);
    }
    if (ferror(f)) set_error("cannot read", path);
    fclose(f);
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}

static void file_put(zs_str *path, zs_str *text, const char *mode) {
    clear_error();
    FILE *f = os_name(path) ? fopen(path->data, mode) : NULL;
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
    return os_name(path) && stat(path->data, &st) == 0 && S_ISREG(st.st_mode);
}

bool zs_dir_exists(zs_str *path) {
    struct stat st;
    return os_name(path) && stat(path->data, &st) == 0 && S_ISDIR(st.st_mode);
}

void zs_file_delete(zs_str *path) {
    clear_error();
    if (!os_name(path) || remove(path->data) != 0) set_error("cannot delete", path);
}

void zs_dir_create(zs_str *path) {
    clear_error();
    if (!os_name(path) || (mkdir(path->data, 0777) != 0 && errno != EEXIST)) set_error("cannot create", path);
}

// entry names (without . and ..), NUL-separated, in directory order
zs_str *zs_dir_list(zs_str *path) {
    clear_error();
    DIR *d = os_name(path) ? opendir(path->data) : NULL;
    if (!d) {
        set_error("cannot open", path);
        return str_of("", 0);
    }
    size_t cap = 256, len = 0;
    char *buf = buf_new(cap);
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        size_t n = strlen(e->d_name) + 1;
        while (len + n > cap) buf = buf_grow(buf, &cap);
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
    if (!os_name(path)) {
        set_error("cannot open", path);
        return -1;
    }
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
    if (!os_name(path) || stat(path->data, &st) != 0) {
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
    if (!os_name(path) || stat(path->data, &st) != 0) {
        set_error("cannot read", path);
        return 0;
    }
    return (int64_t)st.st_size;
}

// the file's modification time set to now (a cache's "used lately")
void zs_file_touch(zs_str *path) {
    clear_error();
#ifdef _WIN32
    if (!os_name(path) || _utime(path->data, NULL) != 0) set_error("cannot touch", path);
#else
    if (!os_name(path) || utimensat(AT_FDCWD, path->data, NULL, 0) != 0) set_error("cannot touch", path);
#endif
}

// whether snprintf's n bytes fitted in size (a path cut short names another file)
static bool fits(int n, size_t size) { return n >= 0 && (size_t)n < size; }

// what failed, with its own words: "<what> <path>: <why>"
static void set_error_why(const char *what, zs_str *path, const char *why) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s %s: %s", what, path ? path->data : "", why);
    if (io_error) zs_free(io_error);
    io_error = zs_str_from_c(buf);
}

// whether descriptors a and b are one file (two names for it, or one spelt two ways): its device
// and inode, or on Windows (whose stat has no inode) its volume and index
static bool same_file(int a, int b) {
#ifdef _WIN32
    BY_HANDLE_FILE_INFORMATION x, y;
    return GetFileInformationByHandle((HANDLE)_get_osfhandle(a), &x) && GetFileInformationByHandle((HANDLE)_get_osfhandle(b), &y) &&
           x.dwVolumeSerialNumber == y.dwVolumeSerialNumber && x.nFileIndexHigh == y.nFileIndexHigh && x.nFileIndexLow == y.nFileIndexLow;
#else
    struct stat x, y;
    return fstat(a, &x) == 0 && fstat(b, &y) == 0 && x.st_dev == y.st_dev && x.st_ino == y.st_ino;
#endif
}

// in's bytes to its end, written to out: false with errno set
static bool copy_bytes(int in, int out) {
    char buf[65536];
    for (;;) {
        ssize_t n = read(in, buf, sizeof buf);
        if (n == 0) return true;
        if (n < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        for (ssize_t done = 0; done < n;) {
            ssize_t w = write(out, buf + done, (size_t)(n - done));
            if (w < 0 && errno != EINTR) return false;
            if (w > 0) done += w;
        }
    }
}

// File.copy: from's bytes into to, replacing what's there. A new file gets from's permission
// bits (less the umask, as cp gives them), so a file only its owner may read isn't copied to one
// anyone may. to is emptied only once it's known not to be from (a link to it, or its path spelt
// another way), which opening it emptied before a byte was read.
static bool copy_file(zs_str *from, zs_str *to) {
    struct stat st;
    int in = os_name(from) ? open(from->data, O_RDONLY | O_CLOEXEC) : -1;
    if (in < 0 || fstat(in, &st) != 0) {
        set_error("cannot open", from);
        if (in >= 0) close(in);
        return false;
    }
#ifdef _WIN32
    int mode = 0666; // the directory's ACL decides
#else
    int mode = st.st_mode & 0777;
#endif
    int out = os_name(to) ? open(to->data, O_WRONLY | O_CREAT | O_CLOEXEC, mode) : -1;
    if (out < 0) {
        set_error("cannot create", to);
        close(in);
        return false;
    }
    bool ok = false;
    if (same_file(in, out)) set_error_why("cannot copy to", to, "it's the file copied");
#ifdef _WIN32
    else if (_chsize(out, 0) != 0 || !copy_bytes(in, out)) set_error("cannot copy to", to);
#else
    else if (ftruncate(out, 0) != 0 || !copy_bytes(in, out)) set_error("cannot copy to", to);
#endif
    else ok = true;
    close(in);
    if (close(out) != 0 && ok) {
        set_error("cannot copy to", to);
        ok = false;
    }
    return ok;
}

void zs_file_copy(zs_str *from, zs_str *to) {
    clear_error();
    copy_file(from, to);
}

#ifndef _WIN32
// File.move across file systems: from copied into a new file beside to (made 0600, then given
// from's owner where that's allowed and its permission bits, as mv gives them: the set-user and
// set-group bits only with the owner), which is renamed over to, so a failure (a full disk)
// leaves to as it was and no one reads it half written; then from deleted. A file moved onto
// itself (rename gives EXDEV across two mounts of one file system) stays as it is, as rename has it.
static void move_across(zs_str *from, zs_str *to) {
    struct stat st, at;
    if (lstat(from->data, &st) != 0) {
        set_error("cannot move", from);
        return;
    }
    if (!S_ISREG(st.st_mode)) { // a directory or a link moves by rename alone
        errno = EXDEV;
        set_error("cannot move", from);
        return;
    }
    if (stat(to->data, &at) == 0 && at.st_dev == st.st_dev && at.st_ino == st.st_ino) return;
    const char *slash = strrchr(to->data, '/');
    char tmp[4096];
    if (!fits(snprintf(tmp, sizeof tmp, "%.*s.zs-move-XXXXXX", slash ? (int)(slash - to->data + 1) : 0, to->data), sizeof tmp)) {
        errno = ENAMETOOLONG;
        set_error("cannot move", from);
        return;
    }
    int in = open(from->data, O_RDONLY | O_CLOEXEC | O_NOFOLLOW); // what lstat saw, not a link
    if (in < 0) {
        set_error("cannot open", from);
        return;
    }
    int out = mkostemp(tmp, O_CLOEXEC);
    if (out < 0) {
        set_error("cannot move to", to);
        close(in);
        return;
    }
    mode_t bits = fchown(out, st.st_uid, st.st_gid) == 0 ? 07777 : 0777;
    bool ok = copy_bytes(in, out) && fchmod(out, st.st_mode & bits) == 0 && fsync(out) == 0;
    if (!ok) set_error("cannot move to", to);
    close(in);
    if (close(out) != 0 && ok) {
        set_error("cannot move to", to);
        ok = false;
    }
    if (ok && rename(tmp, to->data) != 0) {
        set_error("cannot move to", to);
        ok = false;
    }
    if (!ok) unlink(tmp);
    else if (remove(from->data) != 0) set_error("cannot delete", from);
}
#endif

// a rename, or across file systems a copy and a delete
void zs_file_move(zs_str *from, zs_str *to) {
    clear_error();
    if (!os_name(from) || !os_name(to)) {
        set_error("cannot move", from);
        return;
    }
#ifdef _WIN32
    // rename doesn't replace an existing file on Windows
    if (!MoveFileExA(from->data, to->data, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED)) {
        errno = EACCES;
        set_error("cannot move", from);
    }
#else
    if (rename(from->data, to->data) == 0) return;
    if (errno != EXDEV) {
        set_error("cannot move", from);
        return;
    }
    move_across(from, to);
#endif
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
    if (!os_name(path) || rmdir(path->data) != 0) set_error("cannot delete", path);
}

// ---- Directory.deleteRecursive: path and everything under it, no symbolic link followed: a link
// (path itself, or one in the tree) is deleted as itself, never what it points to.

// the error of a step of the walk, at where's entry name (or where itself)
static void tree_failed(const char *what, const char *where, const char *name) {
    int e = errno;
    char buf[4096];
    snprintf(buf, sizeof buf, "%s%s%s", where, name ? "/" : "", name ? name : "");
    zs_str *p = zs_str_from_c(buf);
    errno = e;
    set_error(what, p);
    zs_free(p);
}

#ifndef _WIN32
// The walk goes by descriptors: each directory opened from its parent's with O_NOFOLLOW, each
// entry deleted by its name in its directory's (unlinkat), so a directory swapped for a link
// meanwhile can't lead the walk, or its deletes, out of the tree (CVE-2022-21658's fix, Rust's).
// A directory is read again after a pass that deleted something, as a file system may skip an
// entry when the one before it is deleted.
typedef struct {
    DIR *d;
    char *name;     // its name in the directory below it (NULL for path's)
    size_t at;      // where's length without it (path's: with it)
    bool removed;   // something in it was deleted this pass
} tree_dir;

void zs_dir_delete_tree(zs_str *path) {
    clear_error();
    if (!os_name(path)) {
        set_error("cannot delete", path);
        return;
    }
    size_t n = 1, cap = 16, wcap = (size_t)path->len + 256;
    tree_dir *st = malloc(cap * sizeof(tree_dir));
    char *where = malloc(wcap); // the path of the directory on top, for an error's message
    if (!st || !where) zs_panic_c("out of memory");
    // without a trailing slash, which would have a link followed
    size_t len = (size_t)path->len;
    while (len > 1 && path->data[len - 1] == '/') len--;
    memcpy(where, path->data, len);
    where[len] = 0;
    int fd = open(where, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    DIR *root = fd < 0 ? NULL : fdopendir(fd);
    if (!root) {
        struct stat s;
        // a link (O_NOFOLLOW's ELOOP; EMLINK on the BSDs): deleted as itself
        if (fd < 0 && (errno == ELOOP || errno == EMLINK || errno == ENOTDIR) && lstat(where, &s) == 0 && S_ISLNK(s.st_mode)) {
            if (unlink(where) != 0) set_error("cannot delete", path);
        } else {
            set_error("cannot delete", path);
            if (fd >= 0) close(fd);
        }
        free(st);
        free(where);
        return;
    }
    st[0] = (tree_dir){root, NULL, len, false};
    bool ok = true;
    while (ok && n > 0) {
        tree_dir *top = &st[n - 1];
        errno = 0;
        struct dirent *e = readdir(top->d);
        if (!e) {
            if (errno != 0) {
                ok = false;
                tree_failed("cannot read", where, NULL);
            } else if (top->removed) {
                top->removed = false;
                rewinddir(top->d);
            } else {
                // empty: deleted from its parent's descriptor (path's by its path)
                closedir(top->d);
                char *name = top->name;
                where[top->at] = 0;
                n--;
                if (n > 0 && unlinkat(dirfd(st[n - 1].d), name, AT_REMOVEDIR) != 0) ok = false, tree_failed("cannot delete", where, name);
                else if (n > 0) st[n - 1].removed = true;
                else if (rmdir(where) != 0) ok = false, set_error("cannot delete", path);
                free(name);
            }
            continue;
        }
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        int dfd = dirfd(top->d);
        bool isdir = e->d_type == DT_DIR;
        if (e->d_type == DT_UNKNOWN) {
            struct stat s;
            isdir = fstatat(dfd, e->d_name, &s, AT_SYMLINK_NOFOLLOW) == 0 && S_ISDIR(s.st_mode);
        }
        if (isdir) {
            int cfd = openat(dfd, e->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            DIR *c = cfd < 0 ? NULL : fdopendir(cfd);
            if (c) {
                size_t at = strlen(where), len = strlen(e->d_name);
                if (n == cap && !(st = realloc(st, (cap *= 2) * sizeof(tree_dir)))) zs_panic_c("out of memory");
                if (at + len + 2 > wcap && !(where = realloc(where, wcap = 2 * (at + len + 2)))) zs_panic_c("out of memory");
                where[at] = '/';
                memcpy(where + at + 1, e->d_name, len + 1);
                st[n++] = (tree_dir){c, strdup(e->d_name), at, false};
                if (!st[n - 1].name) zs_panic_c("out of memory");
                continue;
            }
            if (cfd >= 0) close(cfd);
            // swapped for a link or a file since it was read: deleted as itself, below
            if (errno != ELOOP && errno != EMLINK && errno != ENOTDIR) {
                ok = false;
                tree_failed("cannot delete", where, e->d_name);
                continue;
            }
        }
        if (unlinkat(dfd, e->d_name, 0) != 0) ok = false, tree_failed("cannot delete", where, e->d_name);
        else top->removed = true;
    }
    for (; n > 0; n--) { // what's left open after a failure
        closedir(st[n - 1].d);
        free(st[n - 1].name);
    }
    free(st);
    free(where);
}
#else
// Windows has no calls relative to a directory's handle here, so the walk goes by paths; a
// reparse point (a symbolic link, a junction) is deleted as itself (RemoveDirectory takes a
// directory's, DeleteFile a file's) and never walked into.
// ponytail: a directory swapped for a junction between its listing and its walk is walked;
// handle-relative deletes (NtCreateFile, FILE_FLAG_OPEN_REPARSE_POINT) if that matters
typedef struct {
    HANDLE find; // INVALID_HANDLE_VALUE until it's read
    char *dir;
} tree_dir;

static int win_errno(void) {
    switch (GetLastError()) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
        return ENOENT;
    case ERROR_DIR_NOT_EMPTY:
        return ENOTEMPTY;
    case ERROR_DIRECTORY:
        return ENOTDIR;
    default:
        return EACCES;
    }
}

// dir's entry name, as a path
static char *tree_path(const char *dir, const char *name) {
    size_t a = strlen(dir), b = strlen(name);
    char *p = malloc(a + b + 2);
    if (!p) zs_panic_c("out of memory");
    memcpy(p, dir, a);
    p[a] = '\\';
    memcpy(p + a + 1, name, b + 1);
    return p;
}

void zs_dir_delete_tree(zs_str *path) {
    clear_error();
    if (!os_name(path)) {
        set_error("cannot delete", path);
        return;
    }
    DWORD a = GetFileAttributesA(path->data);
    if (a == INVALID_FILE_ATTRIBUTES || (a & FILE_ATTRIBUTE_REPARSE_POINT)) {
        if (a == INVALID_FILE_ATTRIBUTES || !((a & FILE_ATTRIBUTE_DIRECTORY) ? RemoveDirectoryA(path->data) : DeleteFileA(path->data))) {
            errno = win_errno();
            set_error("cannot delete", path);
        }
        return;
    }
    if (!(a & FILE_ATTRIBUTE_DIRECTORY)) {
        errno = ENOTDIR;
        set_error("cannot delete", path);
        return;
    }
    size_t n = 1, cap = 16;
    tree_dir *st = malloc(cap * sizeof(tree_dir));
    char *root = strdup(path->data);
    if (!st || !root) zs_panic_c("out of memory");
    st[0] = (tree_dir){INVALID_HANDLE_VALUE, root};
    bool ok = true;
    while (ok && n > 0) {
        tree_dir *top = &st[n - 1];
        WIN32_FIND_DATAA f;
        bool got;
        if (top->find == INVALID_HANDLE_VALUE) {
            char *pattern = tree_path(top->dir, "*");
            top->find = FindFirstFileA(pattern, &f);
            free(pattern);
            got = top->find != INVALID_HANDLE_VALUE;
        } else {
            got = FindNextFileA(top->find, &f);
        }
        if (!got) {
            DWORD why = GetLastError();
            if (why != ERROR_NO_MORE_FILES && why != ERROR_FILE_NOT_FOUND) {
                errno = win_errno();
                tree_failed("cannot read", top->dir, NULL);
                ok = false;
                continue;
            }
            // empty: deleted
            if (top->find != INVALID_HANDLE_VALUE) FindClose(top->find);
            char *dir = top->dir;
            n--;
            if (!RemoveDirectoryA(dir)) {
                errno = win_errno();
                tree_failed("cannot delete", dir, NULL);
                ok = false;
            }
            free(dir);
            continue;
        }
        if (strcmp(f.cFileName, ".") == 0 || strcmp(f.cFileName, "..") == 0) continue;
        char *p = tree_path(top->dir, f.cFileName);
        DWORD fa = f.dwFileAttributes;
        if ((fa & FILE_ATTRIBUTE_DIRECTORY) && !(fa & FILE_ATTRIBUTE_REPARSE_POINT)) {
            if (n == cap && !(st = realloc(st, (cap *= 2) * sizeof(tree_dir)))) zs_panic_c("out of memory");
            st[n++] = (tree_dir){INVALID_HANDLE_VALUE, p};
            continue;
        }
        if (!((fa & FILE_ATTRIBUTE_DIRECTORY) ? RemoveDirectoryA(p) : DeleteFileA(p))) {
            errno = win_errno();
            tree_failed("cannot delete", p, NULL);
            ok = false;
        }
        free(p);
    }
    for (; n > 0; n--) { // what's left open after a failure
        if (st[n - 1].find != INVALID_HANDLE_VALUE) FindClose(st[n - 1].find);
        free(st[n - 1].dir);
    }
    free(st);
}
#endif

bool zs_is_symlink(zs_str *path) {
    if (!os_name(path)) return false;
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

// Runs prog with args (each NUL-ended, no shell), stdout captured, stderr passed through.
static _Thread_local int64_t process_code;

zs_int zs_process_code(void) { return process_code; }

// ---- the processes Process.start started, by the number it gives each (1, 2, ...), which is
// never another process's, as a process id may be once its process has been waited for (and a
// Windows handle's value at once): each one's id and, once it has been waited for, its exit
// code, which a later wait gives again (a kill then leaves it alone). A wait frees the id under
// procs_mu, which a kill takes, so a kill never reaches a process that has taken the id since.
// ponytail: an entry a process, kept to the end; freed by Process's dispose if a program starts
// millions
enum { PROC_RUNNING, PROC_WAITING, PROC_DONE }; // PROC_WAITING: a thread waits for its end

typedef struct {
    zs_int pid;
#ifdef _WIN32
    HANDLE h; // open until the process has been waited for
#endif
    zs_int code;
    int state;
} proc;

static proc *procs;
static size_t nprocs, procs_cap;
static pthread_mutex_t procs_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t procs_cv = PTHREAD_COND_INITIALIZER; // a wait has ended

// the table freed at exit (valgrind counts what's still allocated then), unless a thread still
// waits for a process in it; a number is no process's after
static void procs_free(void) {
    pthread_mutex_lock(&procs_mu);
    bool waiting = false;
    for (size_t i = 0; i < nprocs; i++) waiting = waiting || procs[i].state == PROC_WAITING;
    if (!waiting) {
        free(procs);
        procs = NULL;
        nprocs = procs_cap = 0;
    }
    pthread_mutex_unlock(&procs_mu);
}

static pthread_once_t procs_once = PTHREAD_ONCE_INIT;
static void procs_at_exit(void) { atexit(procs_free); }

// a process started (h: its handle on Windows): its number
static zs_int proc_add(zs_int pid, void *h) {
    pthread_once(&procs_once, procs_at_exit);
    pthread_mutex_lock(&procs_mu);
    if (nprocs == procs_cap) {
        size_t cap = procs_cap ? 2 * procs_cap : 16;
        proc *p = realloc(procs, cap * sizeof(proc));
        if (!p) zs_panic_c("out of memory");
        procs = p;
        procs_cap = cap;
    }
    procs[nprocs] = (proc){.pid = pid, .code = -1, .state = PROC_RUNNING};
#ifdef _WIN32
    procs[nprocs].h = h;
#else
    (void)h;
#endif
    zs_int n = (zs_int)++nprocs;
    pthread_mutex_unlock(&procs_mu);
    return n;
}

// the entry of a number Process.start gave, NULL for any other (under procs_mu; procs moves
// when it grows, so not kept past an unlock)
static proc *proc_of(zs_int n) { return n >= 1 && (size_t)n <= nprocs ? &procs[n - 1] : NULL; }

// waits for the process to end, unless it has been waited for: its exit code, -1 if that can't
// be had. One thread waits at a time; another waits for that one.
static zs_int proc_wait(zs_int n) {
    pthread_mutex_lock(&procs_mu);
    proc *p = proc_of(n);
    while (p && p->state == PROC_WAITING) {
        pthread_cond_wait(&procs_cv, &procs_mu);
        p = proc_of(n); // NULL once the table is freed, at exit
    }
    if (!p) {
        pthread_mutex_unlock(&procs_mu);
        return -1;
    }
    if (p->state == PROC_RUNNING) {
        p->state = PROC_WAITING;
        zs_int got = -1;
#ifdef _WIN32
        HANDLE h = p->h;
        pthread_mutex_unlock(&procs_mu);
        DWORD c = 0;
        if (WaitForSingleObject(h, INFINITE) == WAIT_OBJECT_0 && GetExitCodeProcess(h, &c)) got = (zs_int)c;
        pthread_mutex_lock(&procs_mu);
        CloseHandle(h); // under the lock, which zs_process_kill takes to use it
        p = proc_of(n);
        p->h = NULL;
#else
        pid_t pid = (pid_t)p->pid;
        pthread_mutex_unlock(&procs_mu);
        int status = 0;
        pid_t w = -1;
#ifdef __linux__
        // waited for without reaping it, then reaped under the lock: a kill, which takes it too,
        // reaches the process or its zombie, never an id that's free for another
        siginfo_t si;
        int r;
        while ((r = waitid(P_PID, (id_t)pid, &si, WEXITED | WNOWAIT)) < 0 && errno == EINTR) {}
        pthread_mutex_lock(&procs_mu);
        if (r == 0) {
            while ((w = waitpid(pid, &status, 0)) < 0 && errno == EINTR) {}
        }
#else
        // ponytail: reaped before the lock is taken (macOS's waitid returns for a stopped process
        // too, so it can't wait without reaping), so a kill in between may signal a free id
        while ((w = waitpid(pid, &status, 0)) < 0 && errno == EINTR) {}
        pthread_mutex_lock(&procs_mu);
#endif
        if (w > 0) got = WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
        p = proc_of(n);
#endif
        p->code = got;
        p->state = PROC_DONE;
        pthread_cond_broadcast(&procs_cv);
    }
    zs_int code = p->code;
    pthread_mutex_unlock(&procs_mu);
    return code;
}

#ifdef _WIN32
// prog as an executable path: as given when it has a separator, else the first match on PATH
// (';'-separated); either way with ".exe" added when the name alone isn't a file. Then made full
// (GetFullPathName, against this program's working directory, where it was found), so the file
// run is the file found, whatever directory the child starts in.
static bool is_file(const char *p) {
    DWORD a = GetFileAttributesA(p);
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

static bool find_program(const char *prog, char *out, size_t size) {
    char found[4096];
    bool ok = false;
    if (strchr(prog, '/') || strchr(prog, '\\')) {
        ok = fits(snprintf(found, sizeof found, "%s", prog), sizeof found) && is_file(found);
        if (!ok) ok = fits(snprintf(found, sizeof found, "%s.exe", prog), sizeof found) && is_file(found);
    } else {
        for (const char *path = getenv("PATH"); path && *path && !ok;) {
            const char *end = strchr(path, ';');
            size_t len = end ? (size_t)(end - path) : strlen(path);
            if (len) {
                ok = fits(snprintf(found, sizeof found, "%.*s\\%s", (int)len, path, prog), sizeof found) && is_file(found);
                if (!ok) ok = fits(snprintf(found, sizeof found, "%.*s\\%s.exe", (int)len, path, prog), sizeof found) && is_file(found);
            }
            path += len + (end ? 1 : 0);
        }
    }
    if (!ok) return false;
    DWORD n = GetFullPathNameA(found, (DWORD)size, out, NULL);
    return n > 0 && n < size;
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

// A batch file (.bat, .cmd) runs in cmd.exe, which reads its command line by rules of its own:
// & | < > ^ ( ) are live outside quotes, %NAME% is expanded inside them too, and a backslash
// escapes nothing (BatBadBut, CVE-2024-24576). So its line is built as Rust's has been since:
// cmd.exe named outright, /e:ON /v:OFF /d /c ""<script>" <args>", an argument quoted unless it's
// letters, digits and #$*+-./:?@\_ alone, a " in one doubled, a % turned into %%cd:~,% (an empty
// slice of %cd%, so what follows names no variable), and a CR or LF, which ends the command
// whatever quotes it's in, refused.

// whether exe is a batch file, its name's trailing dots and spaces (which Windows drops) dropped
static bool is_batch(const char *exe) {
    size_t n = strlen(exe);
    while (n && (exe[n - 1] == '.' || exe[n - 1] == ' ')) n--;
    return n >= 4 && (_strnicmp(exe + n - 4, ".bat", 4) == 0 || _strnicmp(exe + n - 4, ".cmd", 4) == 0);
}

// appends arg to a batch file's command line; false for one that can't be passed
static bool bat_arg(char **buf, size_t *len, size_t *cap, const char *arg) {
    size_t n = strlen(arg);
    // empty, or ending in a backslash (which a script's "%~1" would read as escaping its quote)
    bool quote = n == 0 || arg[n - 1] == '\\';
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)arg[i];
        if (c == '\r' || c == '\n') return false;
        bool plain = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || strchr("#$*+-./:?@\\_", c);
        // any other ASCII character, or a C1 control (U+0080 to U+009F: C2 80 to C2 9F)
        if ((c < 0x80 && !plain) || (c == 0xC2 && i + 1 < n && (unsigned char)arg[i + 1] < 0xA0)) quote = true;
    }
    if (*len + 8 * n + 4 > *cap) { // a % takes 8 bytes, a " or \ at most 2
        *cap = 2 * (*len + 8 * n + 4);
        *buf = realloc(*buf, *cap);
        if (!*buf) zs_panic_c("out of memory");
    }
    char *b = *buf;
    b[(*len)++] = ' ';
    if (quote) b[(*len)++] = '"';
    size_t slashes = 0;
    for (size_t i = 0; i < n; i++) {
        if (arg[i] == '\\') {
            slashes++;
        } else {
            if (arg[i] == '"') { // the backslashes before it doubled, and the quote too
                for (size_t k = 0; k < slashes; k++) b[(*len)++] = '\\';
                b[(*len)++] = '"';
            } else if (arg[i] == '%') {
                memcpy(b + *len, "%%cd:~,", 7);
                *len += 7;
            }
            slashes = 0;
        }
        b[(*len)++] = arg[i];
    }
    if (quote) {
        for (size_t k = 0; k < slashes; k++) b[(*len)++] = '\\'; // doubled before the closing quote
        b[(*len)++] = '"';
    }
    b[*len] = 0;
    return true;
}

// the command line running the batch file script with args (each NUL-ended) in cmd.exe, or NULL
// when one can't be passed (a file's name has no " and doesn't end in a backslash)
static char *bat_line(const char *script, zs_str *args) {
    size_t n = strlen(script);
    if (strchr(script, '"') || (n && script[n - 1] == '\\')) return NULL;
    size_t cap = n + 64, len;
    char *b = malloc(cap);
    if (!b) zs_panic_c("out of memory");
    len = (size_t)snprintf(b, cap, "cmd.exe /e:ON /v:OFF /d /c \"\"%s\"", script);
    for (int64_t i = 0; i < args->len; i += (int64_t)strlen(args->data + i) + 1)
        if (!bat_arg(&b, &len, &cap, args->data + i)) {
            free(b);
            return NULL;
        }
    if (len + 2 > cap) {
        cap = len + 2;
        b = realloc(b, cap);
        if (!b) zs_panic_c("out of memory");
    }
    b[len++] = '"';
    b[len] = 0;
    return b;
}

static _Thread_local zs_int started[4]; // the last start's number and pipes, for Native.processPipe

zs_int zs_process_pipe(zs_int k) { return k >= 0 && k < 3 ? started[k + 1] : -1; }

// starts prog with args (each NUL-ended), as zs_process_start's POSIX version: 0 and the
// process's handle, or -errno. Each piped stream's end here is a CRT descriptor, in started.
// ponytail: the child's ends are inheritable while CreateProcess runs, so a process another
// thread starts at that moment inherits them too; PROC_THREAD_ATTRIBUTE_HANDLE_LIST if it matters
static zs_int win_start(zs_str *prog, zs_str *args, zs_str *env, bool hasEnv, zs_str *dir, zs_int in, zs_int outm, zs_int errm, HANDLE *process) {
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) return -ENOENT;
    size_t len = 0, cap = 0;
    char *cmd = NULL;
    char shell[MAX_PATH + 16];
    const char *run = exe;
    if (is_batch(exe)) {
        UINT k = GetSystemDirectoryA(shell, MAX_PATH);
        if (k == 0 || k >= MAX_PATH) return -ENOENT;
        strcat(shell, "\\cmd.exe");
        run = shell;
        if (!(cmd = bat_line(exe, args))) return -EINVAL;
    } else {
        quote_arg(&cmd, &len, &cap, prog->data);
        for (int64_t i = 0; i < args->len; i += (int64_t)strlen(args->data + i) + 1) quote_arg(&cmd, &len, &cap, args->data + i);
    }
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
            // a megabyte, where the default is a page or so: a caller reading one pipe to its end
            // before the other (a program's output, then its errors) blocks the program only past
            // that. ponytail: a stream read on a thread of its own if one writes more
            if (!CreatePipe(&r, &w, &sa, 1 << 20)) continue;
            HANDLE mine = k == 0 ? w : r;
            theirs[k] = k == 0 ? r : w;
            SetHandleInformation(mine, HANDLE_FLAG_INHERIT, 0);
            started[k + 1] = _open_osfhandle((intptr_t)mine, _O_BINARY | (k == 0 ? _O_WRONLY : _O_RDONLY));
            *std[k] = theirs[k];
        } else if (modes[k] == 2) {
            theirs[k] = CreateFileA("NUL", k == 0 ? GENERIC_READ : GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
            *std[k] = theirs[k];
        } else if (modes[k] == 3 && k == 2) {
            // standard error where standard output goes (2>&1): the same handle, closed with it
            *std[k] = si.hStdOutput;
        } else {
            *std[k] = GetStdHandle(which[k]);
        }
    }
    // the environment block: NAME=value strings, each NUL-ended, and one NUL more
    char *block = NULL;
    if (hasEnv) {
        block = calloc((size_t)env->len + 2, 1);
        if (!block) zs_panic_c("out of memory");
        memcpy(block, env->data, (size_t)env->len);
    }
    console_flush();
    PROCESS_INFORMATION pi;
    BOOL ok = CreateProcessA(run, cmd, NULL, NULL, TRUE, 0, block, dir->len ? dir->data : NULL, &si, &pi);
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
    *process = pi.hProcess;
    return 0;
}

// starts prog (Process.start): its number in procs, or -errno
zs_int zs_process_start(zs_str *prog, zs_str *args, zs_str *env, bool hasEnv, zs_str *dir, zs_int in, zs_int outm, zs_int errm) {
    HANDLE h;
    zs_int e = win_start(prog, args, env, hasEnv, dir, in, outm, errm, &h);
    if (e < 0) return e;
    started[0] = proc_add((zs_int)GetProcessId(h), h);
    return started[0];
}

// Runs prog with args (each NUL-ended, no shell), stdout captured, stderr passed through
zs_str *zs_process_run(zs_str *prog, zs_str *args) {
    clear_error();
    zs_str none = {0};
    HANDLE h;
    zs_int e = win_start(prog, args, &none, false, &none, 0, 1, 0, &h);
    if (e < 0) {
        errno = (int)-e;
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    int fd = (int)started[2];
    size_t cap = 4096, len = 0;
    char *buf = buf_new(cap);
    int n;
    while ((n = _read(fd, buf + len, (unsigned)(cap - len))) > 0) {
        len += (size_t)n;
        if (len == cap) buf = buf_grow(buf, &cap);
    }
    if (n < 0) set_error("cannot read the output of", prog);
    _close(fd);
    DWORD code = 0;
    if (WaitForSingleObject(h, INFINITE) == WAIT_OBJECT_0 && GetExitCodeProcess(h, &code)) {
        process_code = (zs_int)code;
    } else {
        errno = ECHILD;
        set_error("cannot wait for", prog);
        process_code = -1;
    }
    CloseHandle(h);
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}
#else
#ifdef __linux__
#include <sys/syscall.h>
#endif

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

// prog as an executable path: as given when it has a '/', else the first match on PATH (looked
// up here so a missing program is the same error on every libc, and under valgrind). Then made
// absolute, against this program's working directory (where it was found), so the file run is
// the file found, whatever directory the child starts in. false with errno set.
static bool find_program(const char *prog, char *out, size_t size) {
    char found[4096];
    bool ok = false;
    if (strchr(prog, '/')) {
        ok = fits(snprintf(found, sizeof found, "%s", prog), sizeof found) && access(found, X_OK) == 0;
    } else {
        const char *path = getenv("PATH");
        if (!path) path = "/usr/bin:/bin";
        while (*path && !ok) {
            const char *end = strchr(path, ':');
            size_t len = end ? (size_t)(end - path) : strlen(path);
            // an empty entry is the working directory
            ok = fits(snprintf(found, sizeof found, "%.*s/%s", (int)(len ? len : 1), len ? path : ".", prog), sizeof found) && access(found, X_OK) == 0;
            path += len + (end ? 1 : 0);
        }
    }
    if (!ok) {
        errno = ENOENT;
        return false;
    }
    char cwd[4096];
    if (found[0] != '/' && !getcwd(cwd, sizeof cwd)) return false;
    if (!fits(found[0] == '/' ? snprintf(out, size, "%s", found) : snprintf(out, size, "%s/%s", cwd, found), size)) {
        errno = ENAMETOOLONG;
        return false;
    }
    return true;
}

// the strings of s as an argv-style array (with first in front, NULL after): one starts at each
// byte that begins s or follows a NUL, so Process's arguments "a\0\0" (each NUL-ended) are "a"
// and "", "\0" is one "", and an environment "A=1\0B=2" two
static char **split_nul(zs_str *s, char *first) {
    int64_t count = 0;
    for (int64_t i = 0; i < s->len; i++) count += i == 0 || s->data[i - 1] == 0;
    char **v = malloc(sizeof(char *) * (size_t)(count + 2));
    if (!v) zs_panic_c("out of memory");
    int64_t k = 0;
    if (first) v[k++] = first;
    for (int64_t i = 0; i < s->len; i++)
        if (i == 0 || s->data[i - 1] == 0) v[k++] = s->data + i;
    v[k] = NULL;
    return v;
}

// what a child starts with: SIGPIPE and SIGCHLD as the system has them, not as this program
// keeps them (zs_set_args), so a pipeline's writer ends at SIGPIPE once its reader has
static void spawn_attr(posix_spawnattr_t *at) {
    sigset_t def;
    sigemptyset(&def);
    sigaddset(&def, SIGPIPE);
    sigaddset(&def, SIGCHLD);
    posix_spawnattr_init(at);
    posix_spawnattr_setsigdefault(at, &def);
    posix_spawnattr_setflags(at, POSIX_SPAWN_SETSIGDEF);
}

zs_str *zs_process_run(zs_str *prog, zs_str *args) {
    clear_error();
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) {
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    char **argv = split_nul(args, prog->data);
    int fds[2];
    // close-on-exec, as every descriptor here is: a process another thread starts meanwhile
    // would hold the write end open, and the read below wait for that one's end too. The
    // child's standard output, dup2's copy, isn't.
    if (pipe_cloexec(fds, false) != 0) {
        free(argv);
        set_error("cannot run", prog);
        return str_of("", 0);
    }
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], 1);
    posix_spawnattr_t at;
    spawn_attr(&at);
    console_flush();
    pid_t pid;
    int rc = posix_spawn(&pid, exe, &fa, &at, argv, environ);
    posix_spawnattr_destroy(&at);
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
    char *buf = buf_new(cap);
    for (ssize_t n; (n = read(fds[0], buf + len, cap - len)) != 0;) {
        if (n < 0) {
            if (errno == EINTR) continue;
            set_error("cannot read the output of", prog);
            break;
        }
        len += (size_t)n;
        if (len == cap) buf = buf_grow(buf, &cap);
    }
    close(fds[0]);
    // a failed wait is an Error, not a code: status as it was (0) would read as success
    int status = 0;
    pid_t w;
    while ((w = waitpid(pid, &status, 0)) < 0 && errno == EINTR) {}
    if (w < 0) set_error("cannot wait for", prog);
    process_code = w < 0 ? -1 : WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
    zs_str *s = str_of(buf, (int64_t)len);
    free(buf);
    return s;
}

// ---- Process.start (0024): posix_spawn with each stream inherited, piped or /dev/null

// starts prog with args (each NUL-ended); env: NUL-separated NAME=value pairs, used when hasEnv;
// dir: its working directory ("" for this one's); modes per stream (0 inherit, 1 piped, 2
// /dev/null). Its number in procs, or -errno; zs_process_pipe(k) gives this end of stream k's
// pipe (-1 when it isn't piped).
static _Thread_local zs_int started[4]; // the last start's number and pipes, for Native.processPipe

zs_int zs_process_pipe(zs_int k) { return k >= 0 && k < 3 ? started[k + 1] : -1; }

zs_int zs_process_start(zs_str *prog, zs_str *args, zs_str *env, bool hasEnv, zs_str *dir, zs_int in, zs_int outm, zs_int errm) {
    zs_int *out = started;
    char exe[4096];
    if (!find_program(prog->data, exe, sizeof exe)) return -(zs_int)errno;
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
        } else if (modes[k] == 3 && k == 2) {
            // standard error where standard output goes (2>&1), after standard output's own action
            posix_spawn_file_actions_adddup2(&fa, 1, 2);
        }
    }
    if (rc == 0 && dir->len > 0) rc = posix_spawn_file_actions_addchdir_np(&fa, dir->data);
    pid_t pid = 0;
    if (rc == 0) {
        char **argv = split_nul(args, prog->data);
        char **envp = hasEnv ? split_nul(env, NULL) : environ;
        posix_spawnattr_t at;
        spawn_attr(&at);
        console_flush();
        rc = posix_spawn(&pid, exe, &fa, &at, argv, envp);
        posix_spawnattr_destroy(&at);
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
    out[0] = proc_add(pid, NULL);
    return out[0];
}
#endif

// waits for the process Process.start numbered n (Process.wait, once zs_process_waiter's
// descriptor is readable, or on a thread): its exit code, or 128 plus the signal that ended it
// (on Windows an NTSTATUS such as 0xC0000005 when it crashed); -1 when that can't be had
zs_int zs_process_wait(zs_int n) { return proc_wait(n); }

// ends the process at once (SIGKILL, TerminateProcess), or -errno; one that has been waited for
// has ended already, and is left alone
zs_int zs_process_kill(zs_int n) {
    pthread_mutex_lock(&procs_mu);
    proc *p = proc_of(n);
    zs_int r = 0;
    if (!p) r = -ESRCH;
#ifdef _WIN32
    // ended and not yet waited for, it can't be terminated: left alone too
    else if (p->state != PROC_DONE && !TerminateProcess(p->h, 137) && WaitForSingleObject(p->h, 0) != WAIT_OBJECT_0) r = -EPERM;
#else
    else if (p->state != PROC_DONE && kill((pid_t)p->pid, SIGKILL) != 0) r = -(zs_int)errno;
#endif
    pthread_mutex_unlock(&procs_mu);
    return r;
}

// the system's id of the process (Process.pid), -1 for a number Process.start didn't give
zs_int zs_process_id(zs_int n) {
    pthread_mutex_lock(&procs_mu);
    proc *p = proc_of(n);
    zs_int pid = p ? p->pid : -1;
    pthread_mutex_unlock(&procs_mu);
    return pid;
}

static int wake_pair(int w[2]);
static void wake_close(int fd);

// a thread of zs_process_waiter's: waits for the process w[0], then closes w[1] (w freed first:
// once it's closed, the program may end before this thread does)
static void *proc_waiter(void *arg) {
    zs_int *w = arg, n = w[0], fd = w[1];
    free(w);
    proc_wait(n);
    wake_close((int)fd);
    return NULL;
}

// A descriptor the event loop waits for in Process.wait, so a wait holds no thread of the loop's
// (Task.blocking has one) and a cancelled one is over at once: readable once the process has
// ended, zs_process_wait then giving its code without waiting; zs_fd_close closes it. -1 when
// the process has been waited for (its code is at hand), another -errno when none could be made
// (the caller waits on Task.blocking's thread). Linux's pidfd, made under the lock, so the
// process can't have been reaped and its id taken; elsewhere one end of a wake pair (sockets on
// Windows, all the loop waits for there), whose other end a thread closes once the process has
// been waited for.
zs_int zs_process_waiter(zs_int n) {
    pthread_mutex_lock(&procs_mu);
    proc *p = proc_of(n);
    bool done = !p || p->state == PROC_DONE;
#if defined(__linux__) && defined(SYS_pidfd_open)
    int fd = done ? -1 : (int)syscall(SYS_pidfd_open, (pid_t)p->pid, 0);
#endif
    pthread_mutex_unlock(&procs_mu);
    if (done) return -1;
#if defined(__linux__) && defined(SYS_pidfd_open)
    if (fd >= 0) return fd;
#endif
    int w[2];
    if (wake_pair(w) != 0) return -EMFILE;
    zs_int *arg = malloc(2 * sizeof(zs_int));
    if (!arg) zs_panic_c("out of memory");
    arg[0] = n;
    arg[1] = w[1];
    pthread_attr_t at;
    pthread_t t;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&at, 256 << 10);
    int rc = pthread_create(&t, &at, proc_waiter, arg);
    pthread_attr_destroy(&at);
    if (rc == 0) return w[0];
    free(arg);
    wake_close(w[0]);
    wake_close(w[1]);
    return -EAGAIN;
}

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
// The table is in chunks that never move or go, so a lookup on any thread (a helper's wake of
// a loop, a loop thread's read) takes no lock while another thread adds a socket.
#ifdef _WIN32
#define SOCK_BASE 0x40000000
#define SOCK_CHUNK 1024
#define SOCK_CHUNKS 4096 // 4M sockets
static SOCKET *_Atomic sock_chunks[SOCK_CHUNKS];
static atomic_size_t nsocks; // slots handed out, each in a chunk already published
static size_t freesock = (size_t)-1; // the free slots, a list through their entries
static pthread_mutex_t socks_mu = PTHREAD_MUTEX_INITIALIZER;

static SOCKET *sk_slot(size_t i) { return &atomic_load_explicit(&sock_chunks[i / SOCK_CHUNK], memory_order_acquire)[i % SOCK_CHUNK]; }
static bool is_sock(zs_int fd) { return fd >= SOCK_BASE && (size_t)(fd - SOCK_BASE) < atomic_load_explicit(&nsocks, memory_order_acquire); }
// a number that isn't a socket's (a TcpStream or UdpSocket built with one of the program's own)
// is no socket: Winsock refuses it, where its slot would be read from outside the table
static SOCKET sk_of(zs_int fd) { return is_sock(fd) ? *sk_slot((size_t)(fd - SOCK_BASE)) : INVALID_SOCKET; }

static int sk_add(SOCKET s) {
    if (s == INVALID_SOCKET) return -1;
    pthread_mutex_lock(&socks_mu);
    size_t i = freesock;
    if (i != (size_t)-1) {
        freesock = (size_t)*sk_slot(i);
    } else {
        i = atomic_load_explicit(&nsocks, memory_order_relaxed);
        if (i == (size_t)SOCK_CHUNKS * SOCK_CHUNK) {
            pthread_mutex_unlock(&socks_mu);
            closesocket(s);
            WSASetLastError(WSAEMFILE);
            return -1;
        }
        if (i % SOCK_CHUNK == 0) {
            SOCKET *c = malloc(SOCK_CHUNK * sizeof(SOCKET));
            if (!c) zs_panic_c("out of memory");
            atomic_store_explicit(&sock_chunks[i / SOCK_CHUNK], c, memory_order_release);
        }
        atomic_store_explicit(&nsocks, i + 1, memory_order_release);
    }
    *sk_slot(i) = s;
    pthread_mutex_unlock(&socks_mu);
    return SOCK_BASE + (int)i;
}

static void sk_close(zs_int fd) {
    pthread_mutex_lock(&socks_mu);
    SOCKET *slot = sk_slot((size_t)(fd - SOCK_BASE));
    closesocket(*slot);
    *slot = (SOCKET)freesock;
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
    if ((w[0] = sk_add(a)) < 0) {
        closesocket(c);
        return -1;
    }
    if ((w[1] = sk_add(c)) < 0) {
        sk_close(w[0]);
        return -1;
    }
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
    uintptr_t next_timer; // the last id given: unsigned, as a 32-bit word's wraps
    size_t ran;    // callbacks run since the kernel's queue was last looked at
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
#ifndef _WIN32
        // Task.waitFor takes any number, and the table is sized by it: only an open descriptor's,
        // which the system's limit bounds (a negative one would double the size without end, a
        // large one overflow it and put the callback outside the table)
        if (fd < 0 || fd > INT_MAX || fcntl((int)fd, F_GETFD) < 0) zs_panic_c("waiting for a descriptor that isn't open");
#endif
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
    // a deadline past the clock's range is one that never comes: the range's end
    int64_t now = now_ns();
    int64_t at = ms <= 0 ? now : (int64_t)ms > (INT64_MAX - now) / 1000000 ? INT64_MAX : now + (int64_t)ms * 1000000;
    // ids wrap on a 32-bit word: one still in use, or 0 (the table's empty key), is skipped
    do L.next_timer++;
    while (L.next_timer == 0 || tab_get(&L.timers, (void *)L.next_timer));
    *t = (zs_timer){at, (zs_int)L.next_timer, cb, 0};
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
        if (spawn(&b->helper, helper_main, b) != 0) zs_panic_c("pthread_create failed");
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

// the loop threads and the thread pool, once started, stop at exit in one handler (the first of
// them to start registers it), the loop threads first whichever started first: one may be running
// a task that forks, and one that forked gives its deque back into the pool's arrays as it ends
static atomic_bool loopsUp, poolUp;
static void threads_stop(void);
static void stop_at_exit(void) {
    static atomic_flag registered = ATOMIC_FLAG_INIT;
    if (!atomic_flag_test_and_set(&registered)) atexit(threads_stop);
}

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
        if (spawn(&T.threads[k], loop_main, (void *)(intptr_t)k) != 0) zs_panic_c("pthread_create failed");
    pthread_mutex_lock(&T.mu);
    while (T.ready < T.n) pthread_cond_wait(&T.cv, &T.mu);
    pthread_mutex_unlock(&T.mu);
    atomic_store(&loopsUp, true);
    stop_at_exit();
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

// a microcontroller's waits (rt-embedded.c, 0016): a computer's program has no interrupt lines
// to wait for, nor handlers to set a Signal
void zs_loop_irq_wait(zs_int n, void *cb) {
    (void)n;
    zs_clo_drop(cb);
    zs_panic_c("Irq.wait needs a microcontroller's interrupt controller: build with --target cortex-m4");
}

void zs_loop_irq_unwait(zs_int n) { (void)n; }

// Irq.enable, disable and pend's lines (lib/core/Irq.zs): none, rather than a store to an NVIC
// a computer doesn't have
zs_int zs_irq_lines(void) { zs_panic_c("Irq needs a microcontroller's interrupt controller: build with --target cortex-m4"); }

zs_int zs_signal_new(void) { zs_panic_c("a Signal needs a microcontroller's interrupt handlers: build with --target cortex-m4"); }

void zs_signal_set(zs_int s) { (void)s; }

bool zs_signal_take(zs_int s) { return (void)s, false; }

void zs_signal_wait(zs_int s, void *cb) {
    (void)s;
    zs_clo_drop(cb);
}

void zs_signal_unwait(zs_int s) { (void)s; }

bool zs_loop_step(void) {
    if (L.stepping) zs_panic_c("Task.run inside a task: use let! there instead");
    L.stepping = true;
    for (size_t n = L.qlen; n > 0 && L.qlen; n--) {
        zs_clo_run(queue_pop());
        L.ran++;
    }
    L.stepping = false;
    int64_t now = now_ns();
    while (L.ntimers && L.heap[0]->at <= now) {
        zs_timer *t = L.heap[0];
        heap_remove(t);
        tab_remove(&L.timers, (void *)(uintptr_t)t->id);
        zs_loop_post(t->cb);
        free(t);
    }
    int timeout = -1;
    if (L.qlen) {
        // callbacks ready still (a task that keeps yielding, a run of awaits that complete at
        // once): every 64 the kernel's queue is looked at without waiting, so what descriptors
        // and other threads (the inbox) have for this loop isn't held back for good
        if (L.ran < 64 || (!L.waits && !L.box)) return true;
        timeout = 0;
    } else if (!L.waits && !L.ntimers && !L.jobs) {
        return false;
    } else if (L.ntimers) {
        // in whole milliseconds, rounded up, and at most what the call takes: the loop wakes then
        // and looks again
        int64_t d = L.heap[0]->at - now;
        int64_t ms = d / 1000000 + (d % 1000000 != 0);
        timeout = d <= 0 ? 0 : ms > INT_MAX ? INT_MAX : (int)ms;
    }
    L.ran = 0;
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

static int resolve_as(zs_str *host, zs_int port, bool passive, int socktype, struct addrinfo **res);
static int resolve(zs_str *host, zs_int port, bool passive, struct addrinfo **res) { return resolve_as(host, port, passive, SOCK_STREAM, res); }

#ifndef AI_NUMERICSERV
#define AI_NUMERICSERV 0
#endif

static int resolve_as(zs_str *host, zs_int port, bool passive, int socktype, struct addrinfo **res) {
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = socktype, .ai_flags = (passive ? AI_PASSIVE : 0) | AI_NUMERICSERV};
    char p[24];
    snprintf(p, sizeof p, "%lld", (long long)port);
    // a port past 16 bits isn't one (glibc would take its low 16 bits: 65561 as 25)
    if (!os_name(host) || port < 0 || port > 65535) {
        sk_seterr(EINVAL);
        return EAI_NONAME;
    }
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

// whether accept's failure is the connection's own (reset before it was taken, or a network
// error Linux passes on from it), not the listener's: the next connection is taken instead
static bool accept_again(void) {
#ifdef _WIN32
    int e = WSAGetLastError();
    return e == WSAECONNRESET || e == WSAEINTR;
#else
    int e = errno;
    return e == ECONNABORTED || e == EINTR || e == EPROTO
#ifdef __linux__
           || e == ENETDOWN || e == ENOPROTOOPT || e == EHOSTDOWN || e == ENONET || e == EHOSTUNREACH || e == EOPNOTSUPP || e == ENETUNREACH
#endif
        ;
#endif
}

// a connection, or would-block; a failure (out of descriptors, say) is the listener's, and
// Tcp.accept waits a moment before it gives it, as a loop going on after it would spin
zs_int zs_tcp_accept(zs_int fd) {
    int c;
    // many such failures in a row: would-block, so the next try waits a turn of the loop
    for (int tries = 0; (c = sk_accept((int)fd)) < 0 && accept_again(); tries++)
        if (tries == 64) return -1000;
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

// ---- UDP (0024, track S item 8): a socket bound to a host and port, datagrams to a host and
// port and from whoever sent them; the loop waits on the socket as on a TCP one
#ifdef _WIN32 // mswsock.h's and mstcpip.h's, which mingw-w64 may lack
#ifndef SIO_UDP_CONNRESET
#define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12)
#endif
#ifndef SIO_UDP_NETRESET
#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)
#endif
#endif

// a UDP socket bound to the host ("" for every interface) and port (0: one the system picks)
zs_int zs_udp_bind(zs_str *host, zs_int port) {
    struct addrinfo *res;
    if (resolve_as(host, port, true, SOCK_DGRAM, &res) != 0) return failed();
    int fd = sk_new(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0 || bind(S(fd), res->ai_addr, (int)res->ai_addrlen) != 0) {
        int e = sk_err();
        if (fd >= 0) sk_drop(fd);
        freeaddrinfo(res);
        sk_seterr(e);
        return failed();
    }
    freeaddrinfo(res);
#ifdef _WIN32
    // a port unreachable answering an earlier send isn't this socket's failure, which Winsock
    // makes it on the next receive unless told not to (NETRESET's is a newer Windows's)
    BOOL off = FALSE;
    DWORD n = 0;
    WSAIoctl(S(fd), SIO_UDP_CONNRESET, &off, sizeof off, NULL, 0, &n, NULL, NULL);
    WSAIoctl(S(fd), SIO_UDP_NETRESET, &off, sizeof off, NULL, 0, &n, NULL, NULL);
#endif
    return fd;
}

// the port a socket is bound to (after zs_udp_bind with port 0)
zs_int zs_socket_port(zs_int fd) {
    struct sockaddr_storage a;
    socklen_t n = sizeof a;
    if (getsockname(S(fd), (struct sockaddr *)&a, &n) != 0) return failed();
    if (a.ss_family == AF_INET6) return ntohs(((struct sockaddr_in6 *)&a)->sin6_port);
    return ntohs(((struct sockaddr_in *)&a)->sin_port);
}

// the buffer's first n bytes as one datagram to the host and port: the bytes sent
zs_int zs_udp_send(zs_int fd, zs_str *host, zs_int port, const uint8_t *data, zs_int len, zs_int n) {
    if (n < 0 || n > len) zs_panic_c("Udp.send: count out of the buffer");
    struct addrinfo *res;
    if (resolve_as(host, port, false, SOCK_DGRAM, &res) != 0) return failed();
    zs_int r = (zs_int)sendto(S(fd), (const char *)data, (size_t)n, 0, res->ai_addr, (int)res->ai_addrlen);
    freeaddrinfo(res);
    return r < 0 ? failed() : r;
}

// the sender of the last datagram this thread received: read right after zs_udp_receive
static _Thread_local struct sockaddr_storage udp_from;
static _Thread_local socklen_t udp_from_len;

// a datagram into the buffer (cut to its length): the bytes received, or would-block
zs_int zs_udp_receive(zs_int fd, uint8_t *data, zs_int len) {
    udp_from_len = sizeof udp_from;
    zs_int r = (zs_int)recvfrom(S(fd), (char *)data, (size_t)len, 0, (struct sockaddr *)&udp_from, &udp_from_len);
#ifdef _WIN32
    if (r < 0) {
        int e = WSAGetLastError();
        // a datagram longer than the buffer fails, with its start in the buffer: cut, as elsewhere
        if (e == WSAEMSGSIZE) return len;
        // a port unreachable for an earlier send, where the ioctls of zs_udp_bind are unknown
        if (e == WSAECONNRESET || e == WSAENETRESET) return -1000;
    }
#endif
    return r < 0 ? failed() : r;
}

// the last datagram's sender, as text
zs_str *zs_udp_from(void) {
    char h[NI_MAXHOST];
    if (udp_from_len == 0 || getnameinfo((struct sockaddr *)&udp_from, udp_from_len, h, sizeof h, NULL, 0, NI_NUMERICHOST) != 0) return str_of("", 0);
    return zs_str_from_c(h);
}

zs_int zs_udp_from_port(void) {
    if (udp_from_len == 0) return 0;
    if (udp_from.ss_family == AF_INET6) return ntohs(((struct sockaddr_in6 *)&udp_from)->sin6_port);
    return ntohs(((struct sockaddr_in *)&udp_from)->sin_port);
}

// the addresses getaddrinfo found, as text into out (cap bytes), one per line, in its order:
// the bytes written
static size_t addresses_text(struct addrinfo *res, char *out, size_t cap) {
    size_t used = 0;
    // each node is read through a copy: Wine packs a list's nodes one after another, the later
    // ones at addresses a struct addrinfo's fields can't be read at (tests/task/connect.zs, under Wine)
    struct addrinfo node;
    for (struct addrinfo *next = res; next; next = node.ai_next) {
        memcpy(&node, (const unsigned char *)(uintptr_t)next, sizeof node);
        const struct addrinfo *a = &node;
        char h[NI_MAXHOST];
        if (getnameinfo(a->ai_addr, (socklen_t)a->ai_addrlen, h, sizeof h, NULL, 0, NI_NUMERICHOST) != 0) continue;
        size_t n = strlen(h);
        if (used + n + 1 > cap) break;
        // each address once: getaddrinfo lists one per socket type
        bool seen = false;
        for (size_t i = 0, start = 0; i < used; i++)
            if (out[i] == '\n') { if (i - start == n && memcmp(out + start, h, n) == 0) seen = true; start = i + 1; }
        if (seen) continue;
        memcpy(out + used, h, n);
        used += n;
        out[used++] = '\n';
    }
    return used;
}

// the addresses of a host as text, one per line (Dns.lookup, run off the loop's thread since it
// blocks); "" when it has none
zs_str *zs_dns_lookup(zs_str *host) {
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM}, *res;
    if (!os_name(host) || host->len == 0 || getaddrinfo(host->data, NULL, &hints, &res) != 0) return str_of("", 0);
    char out[1024];
    size_t used = addresses_text(res, out, sizeof out);
    freeaddrinfo(res);
    return str_of(out, (zs_int)used);
}

// ---- name lookup for Tcp.connect and Udp.send, off the loop's thread: a thread of its own
// for each, so a resolver that doesn't answer holds up no other task, nor another lookup. Its
// answer comes back on a descriptor the task waits for (a socket pair; on Windows, where only
// sockets are waited for, a loopback connection, as the inbox's wake is): the addresses, one per
// line, or "!" and why there are none. A task cancelled meanwhile closes its end, and the
// thread's write fails. The threads that have answered are joined at the next lookup and at exit.
typedef struct lookup {
    char *host;
    int out;          // the descriptor the answer goes to, closed after it
    atomic_bool done; // answered: what's left of the thread is its return
    pthread_t thread;
    struct lookup *next;
} lookup;
static lookup *lookups; // started and not yet joined
static pthread_mutex_t lookups_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t lookups_once = PTHREAD_ONCE_INIT;

// joins the lookups' threads that have answered
static void lookups_reap(void) {
    pthread_mutex_lock(&lookups_mu);
    for (lookup **p = &lookups; *p;) {
        lookup *l = *p;
        if (atomic_load_explicit(&l->done, memory_order_acquire)) {
            *p = l->next;
            pthread_join(l->thread, NULL);
            free(l);
        } else {
            p = &l->next;
        }
    }
    pthread_mutex_unlock(&lookups_mu);
}

static void lookups_start(void) { atexit(lookups_reap); }

// the answer's descriptors: [0] the task reads, non-blocking; [1] the thread writes, blocking
static int lookup_pair(int p[2]) {
#ifdef _WIN32
    if (wake_pair(p) != 0) return -1;
    u_long zero = 0;
    ioctlsocket(sk_of(p[1]), FIONBIO, &zero);
#else
#ifdef SOCK_CLOEXEC
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, p) != 0) return -1;
#else
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, p) != 0) return -1;
    fcntl(p[0], F_SETFD, FD_CLOEXEC);
    fcntl(p[1], F_SETFD, FD_CLOEXEC);
#endif
    fcntl(p[0], F_SETFL, O_NONBLOCK);
#ifdef __APPLE__
    int one = 1;
    setsockopt(p[1], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
#endif
    return 0;
}

static void *lookup_main(void *arg) {
    lookup *l = arg;
    char text[1024];
    size_t n;
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM}, *res;
    int rc = getaddrinfo(l->host, NULL, &hints, &res);
    if (rc == 0) {
        n = addresses_text(res, text, sizeof text);
        freeaddrinfo(res);
        if (n == 0) n = (size_t)snprintf(text, sizeof text, "!the host has no address");
    } else {
#ifdef _WIN32
        DWORD k = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD)rc, 0, text + 1, sizeof text - 1, NULL);
        while (k && (text[k] == '\n' || text[k] == '\r' || text[k] == '.')) k--;
        text[0] = '!';
        n = k ? k + 1 : (size_t)snprintf(text, sizeof text, "!no such host");
#else
        n = (size_t)snprintf(text, sizeof text, "!%s", rc == EAI_SYSTEM ? strerror(errno) : gai_strerror(rc));
#endif
    }
    if (n >= sizeof text) n = sizeof text - 1; // snprintf's length, cut
    free(l->host);
    int out = l->out;
    for (size_t at = 0; at < n;) {
#ifdef _WIN32
        int w = send(sk_of(out), text + at, (int)(n - at), 0);
#else
        ssize_t w = send(out, text + at, n - at, MSG_NOSIGNAL);
#endif
        if (w <= 0) break; // the task was cancelled, and closed its end
        at += (size_t)w;
    }
    atomic_store_explicit(&l->done, true, memory_order_release);
#ifdef _WIN32
    sk_close(out);
#else
    close(out);
#endif
    return NULL;
}

// starts looking the host up: the descriptor its answer comes on; -1001 when the host needs no
// lookup (an address, or "": this machine's)
zs_int zs_dns_start(zs_str *host) {
    if (!os_name(host)) {
        sk_seterr(EINVAL);
        return failed();
    }
    if (host->len == 0) return -1001;
    struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM, .ai_flags = AI_NUMERICHOST}, *res;
    if (getaddrinfo(host->data, NULL, &hints, &res) == 0) {
        freeaddrinfo(res);
        return -1001;
    }
    pthread_once(&lookups_once, lookups_start);
    lookups_reap();
    lookup *l = calloc(1, sizeof *l);
    char *h = malloc((size_t)host->len + 1);
    if (!l || !h) zs_panic_c("out of memory");
    memcpy(h, host->data, (size_t)host->len);
    h[host->len] = 0;
    int p[2];
    if (lookup_pair(p) != 0) {
        free(h);
        free(l);
        return failed();
    }
    l->host = h;
    l->out = p[1];
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, (size_t)1 << 20);
    pthread_mutex_lock(&lookups_mu);
    int r = pthread_create(&l->thread, &attr, lookup_main, l);
    if (r == 0) {
        l->next = lookups;
        lookups = l;
    }
    pthread_mutex_unlock(&lookups_mu);
    pthread_attr_destroy(&attr);
    if (r != 0) {
        for (int k = 0; k < 2; k++) sk_drop(p[k]);
        free(h);
        free(l);
        return -(zs_int)r;
    }
    return p[0];
}

#ifndef _WIN32
#include <sys/un.h>
#endif

// a Unix socket's address: the path, which must fit sun_path
static int unix_address(zs_str *path, struct sockaddr_un *a) {
    zs_int n = path->len;
    if (n == 0 || n >= (zs_int)sizeof a->sun_path) { errno = ENAMETOOLONG; return -1; }
    if (!os_name(path)) return -1; // a NUL: a shorter path, or first, Linux's abstract names (no permissions)
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    memcpy(a->sun_path, path->data, (size_t)n);
    return 0;
}

#if defined(_WIN32) && !defined(IO_REPARSE_TAG_AF_UNIX)
#define IO_REPARSE_TAG_AF_UNIX 0x80000023L
#endif

#ifdef _WIN32
// Under Wine a Unix socket's file is the host's own socket, with no reparse tag: what tells it
// from a file there is that it can't be opened (no such device), where a file can. Only asked
// under Wine, so on Windows a file that can't be opened for another reason is still a file.
static bool wine_socket(const char *path) {
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    if (!ntdll || !GetProcAddress(ntdll, "wine_get_version")) return false;
    HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (h != INVALID_HANDLE_VALUE) { CloseHandle(h); return false; }
    return GetLastError() == ERROR_NO_SUCH_DEVICE;
}
#endif

// what's at a Unix socket's path before a socket listens there: 0 when it's nothing, or a socket
// no one listens on (an earlier run's, removed now); else the error, EEXIST for what isn't a
// socket (a file is never removed) and EADDRINUSE for one a server listens on
static int unix_clear(const struct sockaddr_un *a) {
#ifdef _WIN32
    // a socket's file is a reparse point with a tag of its own
    WIN32_FIND_DATAA d;
    HANDLE h = FindFirstFileA(a->sun_path, &d);
    if (h == INVALID_HANDLE_VALUE) return 0; // nothing there, or bind says what's wrong
    FindClose(h);
    bool tagged = (d.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && d.dwReserved0 == IO_REPARSE_TAG_AF_UNIX;
    if (!tagged && !wine_socket(a->sun_path)) return EEXIST;
    // a blocking socket, so the answer is the connect's own
    SOCKET s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s == INVALID_SOCKET) return WSAGetLastError();
    bool stale = connect(s, (const struct sockaddr *)a, sizeof *a) != 0 && WSAGetLastError() == WSAECONNREFUSED;
    closesocket(s);
    if (!stale) return WSAEADDRINUSE;
#else
    struct stat st;
    if (lstat(a->sun_path, &st) != 0) return 0; // nothing there, or bind says what's wrong
    if (!S_ISSOCK(st.st_mode)) return EEXIST;
    // a Unix socket's connect is answered at once: refused when no one listens
    int s = sk_new(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0) return errno;
    bool stale = connect(s, (const struct sockaddr *)a, sizeof *a) != 0 && (errno == ECONNREFUSED || errno == ENOENT);
    close(s);
    if (!stale) return EADDRINUSE;
#endif
    unlink(a->sun_path);
    return 0;
}

// a socket listening at the path; a socket an earlier run left there is removed first
zs_int zs_unix_listen(zs_str *path) {
    struct sockaddr_un a;
    if (unix_address(path, &a) != 0) return failed();
    int there = unix_clear(&a);
    if (there != 0) {
        sk_seterr(there);
        return failed();
    }
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
#ifdef _WIN32
        // Windows' AF_UNIX says a path with nothing there is a network that's down: POSIX's
        // error when that's so (no file, or no directory on the way to it); failed() then reads
        // errno
        if (e == WSAENETDOWN && GetFileAttributesA(a.sun_path) == INVALID_FILE_ATTRIBUTES) {
            DWORD why = GetLastError();
            if (why == ERROR_FILE_NOT_FOUND || why == ERROR_PATH_NOT_FOUND) {
                e = 0;
                errno = ENOENT;
            }
        }
#endif
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

// writes from a Buffer<u8> or a string's bytes; a closed connection or pipe is an error, not
// SIGPIPE (zs_set_args ignores it), but standard output or error gone ends the program as print's
// does (console_failed)
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
    if (r < 0 && errno == ENOTSOCK) {
        r = write((int)fd, data + off, (size_t)n);
        if (r < 0 && (fd == 1 || fd == 2)) console_failed();
    }
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
// to do while enough others can sleeps until it's needed again. Spares are at most twice the
// cores: past that, a job waits without one.

typedef struct {
    void (*run)(void *clo, void *out);
    void *clo;
    atomic_int done;
    _Alignas(64) char result[]; // what run stores (a SIMD vector, say)
} par_job;

// a deque's ring of jobs, with its capacity in it: a thief loads the ring once and indexes it by
// that ring's own capacity, so a resize between its loads can't pair one ring with another's
// (Lê et al. keep the size in the array for this)
typedef struct {
    long long cap; // a power of two, written before the ring is published and never after
    _Atomic(par_job *) slot[];
} par_ring;

typedef struct {
    atomic_llong top, bottom;
    _Atomic(par_ring *) ring;
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
    void **old; // rings replaced by bigger ones (a thief may still read one), freed at exit
    size_t nold;
    pthread_mutex_t oldmu;
} P;

static pthread_once_t pool_once = PTHREAD_ONCE_INIT;
static _Thread_local int me = -1;         // this thread's deque, -1 for a thread without one
static _Thread_local bool runsJobs;      // a worker or a spare: what the pool counts on
static pthread_key_t slotKey;            // gives a forking thread's deque back when it ends

static par_ring *ring_new(long long cap) {
    par_ring *r = calloc(1, sizeof(par_ring) + (size_t)cap * sizeof(_Atomic(par_job *)));
    if (!r) zs_panic_c("out of memory");
    r->cap = cap;
    return r;
}

static void dq_init(par_deque *q) {
    atomic_init(&q->top, 0);
    atomic_init(&q->bottom, 0);
    atomic_init(&q->ring, ring_new(64));
}

static void dq_push(par_deque *q, par_job *j) {
    long long b = atomic_load_explicit(&q->bottom, memory_order_relaxed);
    long long t = atomic_load_explicit(&q->top, memory_order_acquire);
    par_ring *a = atomic_load_explicit(&q->ring, memory_order_relaxed);
    if (b - t >= a->cap - 1) { // full: twice as big, the old one kept for thieves still reading it
        par_ring *n = ring_new(a->cap * 2);
        for (long long i = t; i < b; i++)
            atomic_store_explicit(&n->slot[i & (n->cap - 1)], atomic_load_explicit(&a->slot[i & (a->cap - 1)], memory_order_relaxed), memory_order_relaxed);
        pthread_mutex_lock(&P.oldmu);
        void **o = realloc(P.old, (P.nold + 1) * sizeof(void *));
        if (!o) zs_panic_c("out of memory");
        P.old = o;
        P.old[P.nold++] = a;
        pthread_mutex_unlock(&P.oldmu);
        // one store publishes the jobs copied and the capacity with them
        atomic_store_explicit(&q->ring, n, memory_order_release);
        a = n;
    }
    atomic_store_explicit(&a->slot[b & (a->cap - 1)], j, memory_order_relaxed);
    // publishes the job; seq_cst, as is zs_par_fork's look for sleepers after it (see run_jobs)
    atomic_store_explicit(&q->bottom, b + 1, memory_order_seq_cst);
}

static par_job *dq_pop(par_deque *q) {
    long long b = atomic_load_explicit(&q->bottom, memory_order_relaxed) - 1;
    par_ring *a = atomic_load_explicit(&q->ring, memory_order_relaxed);
    atomic_store_explicit(&q->bottom, b, memory_order_seq_cst);
    long long t = atomic_load_explicit(&q->top, memory_order_seq_cst);
    par_job *x = NULL;
    if (t <= b) {
        x = atomic_load_explicit(&a->slot[b & (a->cap - 1)], memory_order_relaxed);
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
    // the ring current when job t was pushed, or a later one it was copied into
    par_ring *a = atomic_load_explicit(&q->ring, memory_order_acquire);
    par_job *x = atomic_load_explicit(&a->slot[t & (a->cap - 1)], memory_order_relaxed);
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

// a thread that forked ends: its deque (empty: it joined what it forked) is handed out again,
// unless the pool has stopped (a thread ending after exit has freed the pool's arrays)
static void slot_give(void *arg) {
    (void)arg;
    if (me < 0) return;
    pthread_mutex_lock(&P.mu);
    if (!atomic_load(&P.stop)) P.freed[P.nfreed++] = me;
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
        // at most twice the cores: it waits without one. That's no deadlock to end the program
        // for: what it waits for may be a thread outside the pool (the main thread holding the
        // lock, a task's loop thread receiving), which no count here tells from a job that no
        // thread is left to run
        pthread_mutex_unlock(&P.mu);
        return;
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
        if (spawn(&P.spareThreads[P.nspare], spare_main, NULL) != 0) zs_panic_c("pthread_create failed");
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
    for (int k = 0; k < used; k++) free(atomic_load(&P.deques[k].ring));
    for (size_t k = 0; k < P.nold; k++) free(P.old[k]);
    free(P.old);
    free(P.deques);
    free(P.freed);
    free(P.threads);
    free(P.spareThreads);
}

static void threads_stop(void) {
    if (atomic_load(&loopsUp)) loops_stop();
    if (atomic_load(&poolUp)) pool_stop();
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
        if (spawn(&P.threads[k], worker_main, (void *)(intptr_t)k) != 0) zs_panic_c("pthread_create failed");
    atomic_store(&poolUp, true);
    stop_at_exit();
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
    // the slots, past what can be allocated a panic (wrapped, a small block sends would overrun)
    size_t bytes;
    if (__builtin_mul_overflow((size_t)(cap == 0 ? 1 : cap), (size_t)(size ? size : 1), &bytes)) zs_panic_c("out of memory");
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
    c->slots = malloc(bytes);
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
    zs_free_checked(c);
}

// ---- Spsc (0012): a ring between a producer and a consumer, an interrupt handler and the program,
// or two threads, neither waiting or locking. Spsc is Share, so safe code can push or pop from
// more threads than one a side, and that stays safe: each slot has a sequence number (Vyukov's
// bounded queue). A push or a pop claims its position with a CAS on the tail or the head, copies
// the value, then moves the slot's number on, which hands the slot to the other side. A pop finds
// nothing while the value at the head is still being pushed, and a push finds the queue full
// while the slot it needs is still being popped: neither ever waits for the other. The slots are
// a power of two (positions wrap with the word), the capacity or more: past the capacity, a push
// finds the queue full. A Z# object: the drop function it was made with drops what's still in it
// when it's freed.
typedef struct {
    ZS_HEADER;
    zs_int cap, size; // the values it holds at most; a value's bytes
    uintptr_t mask;   // the slots, less one
    void (*drop)(void *slot);
    // positions: the next to pop, the next to push, each on a cache line of its own (the two
    // sides write them, and read the fields above)
    char apart[64];
    uintptr_t head;
    char apart2[64 - sizeof(uintptr_t)];
    uintptr_t tail;
    char apart3[64 - sizeof(uintptr_t)];
    // a slot's number: its position while it waits for that position's push, the position + 1
    // once it holds its value. The values' bytes come after.
    uintptr_t seq[];
} zs_spsc;

static char *spsc_value(zs_spsc *q, uintptr_t pos) { return (char *)(q->seq + q->mask + 1) + (pos & q->mask) * (size_t)q->size; }

void *zs_spsc_new(zs_int cap, zs_int size, void (*drop)(void *)) {
    if (cap < 1) zs_panic_c("an Spsc holds at least one value");
    zs_int n = 2, slot, bytes; // past what can be allocated a panic
    while (n < cap)
        if (__builtin_mul_overflow(n, 2, &n)) zs_panic_c("out of memory");
    if (__builtin_add_overflow(size, (zs_int)sizeof(uintptr_t), &slot) || __builtin_mul_overflow(n, slot, &bytes) || __builtin_add_overflow(bytes, (zs_int)sizeof(zs_spsc), &bytes)) zs_panic_c("out of memory");
    zs_spsc *q = zs_alloc(bytes);
    q->rc = 1;
    q->cap = cap;
    q->size = size;
    q->mask = (uintptr_t)n - 1;
    q->head = q->tail = 0;
    q->drop = drop;
    for (zs_int i = 0; i < n; i++) q->seq[i] = (uintptr_t)i;
    return q;
}

bool zs_spsc_push(zs_spsc *q, const void *v) {
    uintptr_t t = __atomic_load_n(&q->tail, __ATOMIC_RELAXED);
    for (;;) {
        uintptr_t *s = &q->seq[t & q->mask];
        intptr_t d = (intptr_t)(__atomic_load_n(s, __ATOMIC_ACQUIRE) - t);
        if (d < 0) return false; // full: the value a lap before isn't popped yet
        if (d > 0) {             // another push took t
            t = __atomic_load_n(&q->tail, __ATOMIC_RELAXED);
            continue;
        }
        // full at the capacity, when the slots are more (a head read late finds it full sooner,
        // never later)
        if ((uintptr_t)q->cap <= q->mask && (intptr_t)(t - __atomic_load_n(&q->head, __ATOMIC_RELAXED)) >= q->cap) return false;
        if (__atomic_compare_exchange_n(&q->tail, &t, t + 1, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            memcpy(spsc_value(q, t), v, (size_t)q->size);
            __atomic_store_n(s, t + 1, __ATOMIC_RELEASE); // the value, to a pop
            return true;
        }
    }
}

bool zs_spsc_pop(zs_spsc *q, void *out) {
    uintptr_t h = __atomic_load_n(&q->head, __ATOMIC_RELAXED);
    for (;;) {
        uintptr_t *s = &q->seq[h & q->mask];
        intptr_t d = (intptr_t)(__atomic_load_n(s, __ATOMIC_ACQUIRE) - (h + 1));
        if (d < 0) return false; // empty, or its value is still being pushed
        if (d > 0) {             // another pop took h
            h = __atomic_load_n(&q->head, __ATOMIC_RELAXED);
            continue;
        }
        if (__atomic_compare_exchange_n(&q->head, &h, h + 1, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            memcpy(out, spsc_value(q, h), (size_t)q->size);
            __atomic_store_n(s, h + q->mask + 1, __ATOMIC_RELEASE); // the slot, to the push a lap on
            return true;
        }
    }
}

void zs_spsc_free(zs_spsc *q) {
    // what's between the head and the tail (no push or pop is under way: each holds a reference)
    if (q->drop)
        for (uintptr_t p = q->head; p != q->tail; p++) q->drop(spsc_value(q, p));
    zs_free_checked(q);
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
