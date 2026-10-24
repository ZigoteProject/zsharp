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
