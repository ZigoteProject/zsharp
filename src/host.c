// What the compiler asks of the machine it runs on, by the C preprocessor and each OS's own call
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#else
#include <unistd.h>
#endif

// the architecture as a target triple's first part
const char *zs_host_arch(void) {
#if defined(__x86_64__)
    return "x86_64";
#elif defined(__aarch64__)
    return "aarch64";
#else
    return "unknown";
#endif
}

// the operating system, as a target triple names it
const char *zs_host_os(void) {
#if defined(_WIN32)
    return "windows";
#elif defined(__APPLE__)
    return "macos";
#else
    return "linux";
#endif
}

// this program's executable, its symbolic links followed ("" when it can't be found)
const char *zs_host_exe(void) {
    static char path[4096];
    if (path[0]) return path;
    char raw[4096] = "";
#ifdef _WIN32
    GetModuleFileNameA(NULL, raw, sizeof raw);
    if (!_fullpath(path, raw, sizeof path)) path[0] = 0;
#else
#ifdef __APPLE__
    uint32_t n = sizeof raw;
    if (_NSGetExecutablePath(raw, &n) != 0) raw[0] = 0;
#else
    strcpy(raw, "/proc/self/exe");
#endif
    if (!realpath(raw, path)) path[0] = 0;
#endif
    return path;
}

#ifndef _WIN32
#include <sys/resource.h>
// The compiler recurses as deep as the program it reads nests (a long list literal, a long run of
// lets, a chain of calls inlined): 256 MB of stack where the hard limit allows, not the usual
// 8 MB. Set before main, so the pool's threads have it too (the runtime sizes its threads by this
// limit); Linux grows the main thread's stack up to it as well, within the room the kernel left
// below the stack at exec (128 MB at least), where macOS keeps the main thread's 8 MB. The
// processes the compiler runs inherit the limit: their threads reserve more address space, not
// more memory.
__attribute__((constructor(101))) static void zs_host_stack(void) {
    struct rlimit rl;
    rlim_t want = (rlim_t)256 << 20;
    if (getrlimit(RLIMIT_STACK, &rl) != 0 || rl.rlim_cur == RLIM_INFINITY || rl.rlim_cur >= want) return;
    rl.rlim_cur = rl.rlim_max == RLIM_INFINITY || rl.rlim_max >= want ? want : rl.rlim_max;
    setrlimit(RLIMIT_STACK, &rl);
}
#endif

#include <stdint.h>
// this process's environment, NAME=value each, for a child given it with a variable more (zs
// test's runs, git's): how many, and the i-th
#ifdef _WIN32
#define host_environ _environ
#else
extern char **environ;
#define host_environ environ
#endif
int64_t zs_host_env_count(void) {
    int64_t n = 0;
    while (host_environ && host_environ[n]) n++;
    return n;
}
const char *zs_host_env_at(int64_t i) { return host_environ[i]; }
