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

// zs fmt's write: the file's text replaced by `len` bytes as a whole or not at all. They go to a
// new file beside it (the same file system, so the rename is atomic), flushed to the disk, with
// the file's permission bits (and owner, where we may), and only then does it take the file's
// place; a write that fails (a full disk, a quota) leaves the file as it was. A symbolic link
// stays one: the file it names is replaced. "" when done, else why not.
#ifdef _WIN32
#include <stdio.h>
#include <stdint.h>
const char *zs_host_replace(const char *path, const char *data, int64_t len) {
    DWORD attrs = GetFileAttributesA(path);
    if (attrs == INVALID_FILE_ATTRIBUTES) return "cannot read its attributes";
    char tmp[MAX_PATH + 32];
    HANDLE h = INVALID_HANDLE_VALUE;
    // a name no other file has: one a run that stopped left behind is skipped
    for (int k = 0; h == INVALID_HANDLE_VALUE && k < 100; k++) {
        if (snprintf(tmp, sizeof tmp, "%s.zsfmt-%lu-%d", path, (unsigned long)GetCurrentProcessId(), k) >= (int)sizeof tmp)
            return "its path is too long";
        h = CreateFileA(tmp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h == INVALID_HANDLE_VALUE && GetLastError() != ERROR_FILE_EXISTS) break;
    }
    if (h == INVALID_HANDLE_VALUE) return "cannot create a file beside it";
    BOOL ok = TRUE;
    for (int64_t at = 0; ok && at < len;) {
        DWORD chunk = len - at > (1 << 30) ? (DWORD)(1 << 30) : (DWORD)(len - at), wrote = 0;
        ok = WriteFile(h, data + at, chunk, &wrote, NULL) && wrote > 0;
        at += wrote;
    }
    ok = ok && FlushFileBuffers(h);
    if (!CloseHandle(h)) ok = FALSE;
    // its attributes (hidden, archive); a read-only one isn't replaced, as it isn't written
    ok = ok && SetFileAttributesA(tmp, attrs & ~(DWORD)FILE_ATTRIBUTE_READONLY);
    if (ok && MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return "";
    DeleteFileA(tmp);
    return "the write failed, and the file is as it was";
}
#else
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
const char *zs_host_replace(const char *path, const char *data, int64_t len) {
    char *real = realpath(path, NULL);
    const char *target = real ? real : path;
    size_t n = strlen(target);
    char *tmp = malloc(n + sizeof ".zsfmt-XXXXXX");
    struct stat st;
    int err = 0;
    if (!tmp) err = ENOMEM;
    else if (stat(target, &st) != 0) err = errno;
    int fd = -1;
    if (!err) {
        memcpy(tmp, target, n);
        memcpy(tmp + n, ".zsfmt-XXXXXX", sizeof ".zsfmt-XXXXXX");
        // mkstemp's file is 0600: no one else reads it before it has the file's own bits
        fd = mkstemp(tmp);
        if (fd < 0) err = errno;
    }
    for (int64_t at = 0; fd >= 0 && !err && at < len;) {
        ssize_t wrote = write(fd, data + at, (size_t)(len - at));
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) err = wrote < 0 ? errno : EIO;
        else at += wrote;
    }
    if (fd >= 0) {
        // the file's owner too, where we may (root formatting another's file); else ours
        if (!err && (st.st_uid != geteuid() || st.st_gid != getegid())) {
            int owned = fchown(fd, st.st_uid, st.st_gid);
            (void)owned;
        }
        if (!err && fchmod(fd, st.st_mode & 0777) != 0) err = errno;
        // a file system that can't sync (some FUSE ones) has nothing better to offer
        if (!err && fsync(fd) != 0 && errno != EINVAL && errno != ENOTSUP) err = errno;
        if (close(fd) != 0 && !err) err = errno;
        if (!err && rename(tmp, target) != 0) err = errno;
        if (err) unlink(tmp);
    }
    free(tmp);
    free(real);
    return err ? strerror(err) : "";
}
#endif

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
