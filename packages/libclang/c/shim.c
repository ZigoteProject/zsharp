// What libclang's API needs to suit Z#: a visitor whose user data comes first and which takes the
// cursor by pointer (a Z# callback's form), strings that are never NULL, and arguments for a
// parse in one NUL-separated buffer. And libclang itself, opened when first used rather than
// linked, so a program built with this package starts where libclang isn't installed (an
// editor's sandbox): zs_clang_load says whether it's there.
#define _GNU_SOURCE // dladdr
#include <dirent.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "clang.h"

// what only this file calls
typedef enum CXChildVisitResult (*CXCursorVisitor)(CXCursor cursor, CXCursor parent, void *client_data);
const char *clang_getCString(CXString string);
unsigned clang_visitChildren(CXCursor parent, CXCursorVisitor visitor, void *client_data);
CXTranslationUnit clang_parseTranslationUnit(CXIndex index, const char *source_filename,
                                             const char *const *command_line_args, int num_command_line_args,
                                             void *unsaved_files, unsigned num_unsaved_files, unsigned options);

static void *lib;
static int tried;

static void *open_at(const char *path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }

// $ZS_LIBCLANG; else the libclang of the first clang on PATH (its ../lib); else the system's, by
// its name and then its versioned names, newest first
static void *open_libclang(void) {
  const char *env = getenv("ZS_LIBCLANG");
  if (env && *env) return open_at(env);
  char path[4096], real[4096];
  for (const char *p = getenv("PATH"); p && *p;) {
    const char *end = strchr(p, ':');
    int n = end ? (int)(end - p) : (int)strlen(p);
    snprintf(path, sizeof path, "%.*s/clang", n, p);
    if (n > 0 && access(path, X_OK) == 0) {
      void *h = NULL;
      if (realpath(path, real)) {
        *strrchr(real, '/') = 0;
        snprintf(path, sizeof path, "%s/../lib/libclang.so", real);
        h = open_at(path);
      }
      if (h) return h;
      break;
    }
    p = end ? end + 1 : NULL;
  }
  void *h = open_at("libclang.so");
  for (int v = 40; !h && v >= 13; v--) {
    snprintf(path, sizeof path, "libclang.so.%d.1", v);
    h = open_at(path);
    snprintf(path, sizeof path, "libclang.so.%d", v);
    if (!h) h = open_at(path);
    snprintf(path, sizeof path, "libclang-%d.so", v);
    if (!h) h = open_at(path);
  }
  return h;
}

int zs_clang_load(void) {
  if (!tried) {
    lib = open_libclang();
    tried = 1;
  }
  return lib != NULL;
}

// clang's resource directory beside the libclang opened (its own headers: stdbool.h, stddef.h…),
// which an LLVM release's libclang doesn't find by itself: <its directory>/clang/<the newest
// version there>; "" when there's none (a system's libclang finds its own)
const char *zs_clang_resource_dir(void) {
  static char found[4096];
  static int looked;
  if (looked || !zs_clang_load()) return found;
  looked = 1;
  Dl_info info;
  char real[4096], base[4200];
  void *f = dlsym(lib, "clang_createIndex");
  if (!f || !dladdr(f, &info) || !info.dli_fname || !realpath(info.dli_fname, real)) return found;
  *strrchr(real, '/') = 0;
  snprintf(base, sizeof base, "%s/clang", real);
  DIR *d = opendir(base);
  if (!d) return found;
  long best = -1;
  for (struct dirent *e; (e = readdir(d));) {
    long v = strtol(e->d_name, NULL, 10);
    if (e->d_name[0] != '.' && v > best) {
      best = v;
      snprintf(found, sizeof found, "%s/%s", base, e->d_name);
    }
  }
  closedir(d);
  return found;
}

static void *sym(const char *name) {
  void *f = zs_clang_load() ? dlsym(lib, name) : NULL;
  if (!f) {
    fprintf(stderr, "libclang: %s isn't here (check Libclang.available first)\n", name);
    abort();
  }
  return f;
}

// a libclang function: looked up at its first call
#define FORWARD(R, name, P, A)                                                                     \
  R name P {                                                                                       \
    static R(*real) P;                                                                             \
    if (!real) real = (R(*) P)sym(#name);                                                          \
    return real A;                                                                                 \
  }
#define FORWARD_VOID(name, P, A)                                                                   \
  void name P {                                                                                    \
    static void(*real) P;                                                                          \
    if (!real) real = (void(*) P)sym(#name);                                                       \
    real A;                                                                                        \
  }

FORWARD(CXIndex, clang_createIndex, (int a, int b), (a, b))
FORWARD_VOID(clang_disposeIndex, (CXIndex i), (i))
FORWARD(CXTranslationUnit, clang_parseTranslationUnit,
        (CXIndex i, const char *f, const char *const *a, int n, void *u, unsigned m, unsigned o), (i, f, a, n, u, m, o))
FORWARD_VOID(clang_disposeTranslationUnit, (CXTranslationUnit t), (t))
FORWARD(const char *, clang_getCString, (CXString s), (s))
FORWARD_VOID(clang_disposeString, (CXString s), (s))
FORWARD(unsigned, clang_visitChildren, (CXCursor c, CXCursorVisitor v, void *d), (c, v, d))
FORWARD(CXCursor, clang_getTranslationUnitCursor, (CXTranslationUnit t), (t))
FORWARD(enum CXCursorKind, clang_getCursorKind, (CXCursor c), (c))
FORWARD(CXString, clang_getCursorSpelling, (CXCursor c), (c))
FORWARD(CXSourceLocation, clang_getCursorLocation, (CXCursor c), (c))
FORWARD(CXSourceRange, clang_getCursorExtent, (CXCursor c), (c))
FORWARD(CXType, clang_getCursorType, (CXCursor c), (c))
FORWARD(CXType, clang_getTypedefDeclUnderlyingType, (CXCursor c), (c))
FORWARD(long long, clang_getEnumConstantDeclValue, (CXCursor c), (c))
FORWARD(int, clang_Cursor_getNumArguments, (CXCursor c), (c))
FORWARD(CXCursor, clang_Cursor_getArgument, (CXCursor c, unsigned i), (c, i))
FORWARD(enum CX_StorageClass, clang_Cursor_getStorageClass, (CXCursor c), (c))
FORWARD(unsigned, clang_Cursor_isMacroFunctionLike, (CXCursor c), (c))
FORWARD(CXString, clang_getTypeSpelling, (CXType t), (t))
FORWARD(CXType, clang_getResultType, (CXType t), (t))
FORWARD(unsigned, clang_isFunctionTypeVariadic, (CXType t), (t))
FORWARD(int, clang_Location_isFromMainFile, (CXSourceLocation l), (l))
FORWARD(CXSourceLocation, clang_getRangeStart, (CXSourceRange r), (r))
FORWARD(CXSourceLocation, clang_getRangeEnd, (CXSourceRange r), (r))
FORWARD_VOID(clang_getExpansionLocation, (CXSourceLocation l, CXFile *f, unsigned *a, unsigned *b, unsigned *c),
             (l, f, a, b, c))
FORWARD(CXString, clang_getFileName, (CXFile f), (f))
FORWARD_VOID(clang_tokenize, (CXTranslationUnit t, CXSourceRange r, CXToken **o, unsigned *n), (t, r, o, n))
FORWARD(CXString, clang_getTokenSpelling, (CXTranslationUnit t, CXToken k), (t, k))
FORWARD(CXSourceRange, clang_getTokenExtent, (CXTranslationUnit t, CXToken k), (t, k))
FORWARD_VOID(clang_disposeTokens, (CXTranslationUnit t, CXToken *k, unsigned n), (t, k, n))
FORWARD(unsigned, clang_getNumDiagnostics, (CXTranslationUnit t), (t))
FORWARD(CXDiagnostic, clang_getDiagnostic, (CXTranslationUnit t, unsigned i), (t, i))
FORWARD(enum CXDiagnosticSeverity, clang_getDiagnosticSeverity, (CXDiagnostic d), (d))
FORWARD(CXString, clang_formatDiagnostic, (CXDiagnostic d, unsigned o), (d, o))
FORWARD_VOID(clang_disposeDiagnostic, (CXDiagnostic d), (d))

typedef int (*zs_visitor)(void *user, const CXCursor *cursor);

struct zs_visit {
  zs_visitor f;
  void *user;
};

static enum CXChildVisitResult zs_trampoline(CXCursor cursor, CXCursor parent, void *data) {
  (void)parent;
  struct zs_visit *v = data;
  return (enum CXChildVisitResult)v->f(v->user, &cursor);
}

unsigned zs_clang_visit_children(CXCursor parent, zs_visitor f, void *user) {
  struct zs_visit v = {f, user};
  return clang_visitChildren(parent, zs_trampoline, &v);
}

const char *zs_clang_text(CXString s) {
  const char *c = clang_getCString(s);
  return c ? c : "";
}

// args: n strings, each ending in a NUL, len bytes in all
CXTranslationUnit zs_clang_parse(CXIndex index, const char *file, const char *args, size_t len, int n,
                                 unsigned options) {
  const char **argv = calloc(n ? n : 1, sizeof *argv);
  for (int i = 0; i < n && len > 0; i++) {
    argv[i] = args;
    while (*args++) len--;
    len--;
  }
  CXTranslationUnit tu = clang_parseTranslationUnit(index, file, argv, n, NULL, 0, options);
  free(argv);
  return tu;
}
