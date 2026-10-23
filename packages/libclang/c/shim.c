// What libclang's API needs to suit Z#: a visitor whose user data comes first and which takes the
// cursor by pointer (a Z# callback's form), strings that are never NULL, and arguments for a
// parse in one NUL-separated buffer.
#include <stdlib.h>
#include <clang-c/Index.h>

typedef int (*zs_visitor)(void *user, const CXCursor *cursor);

struct zs_visit {
  zs_visitor f;
  void *user;
};

static enum CXChildVisitResult zs_trampoline(CXCursor cursor, CXCursor parent, CXClientData data) {
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
