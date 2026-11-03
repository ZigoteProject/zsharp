// JSON, as a web service handles it: a generated document of n user records is parsed into a
// tree, decoded into structs, summarised, and the active users encoded back to JSON.
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int64_t next(int64_t seed) { return (seed * 1103515245 + 12345) % 2147483648; }

typedef struct { char *data; size_t len, cap; } Buf;

static void reserve(Buf *b, size_t n) {
  if (b->len + n <= b->cap) return;
  while (b->len + n > b->cap) b->cap = b->cap ? b->cap * 2 : 4096;
  b->data = realloc(b->data, b->cap);
}
static void put(Buf *b, const char *s, size_t n) {
  reserve(b, n);
  memcpy(b->data + b->len, s, n);
  b->len += n;
}
static void putStr(Buf *b, const char *s) { put(b, s, strlen(s)); }
__attribute__((format(printf, 2, 3)))
static void putf(Buf *b, const char *fmt, ...) {
  va_list a;
  va_start(a, fmt);
  int n = vsnprintf(NULL, 0, fmt, a);
  va_end(a);
  reserve(b, (size_t)n + 1);
  va_start(a, fmt);
  vsnprintf(b->data + b->len, (size_t)n + 1, fmt, a);
  va_end(a);
  b->len += (size_t)n;
}
static void putJsonString(Buf *b, const char *s) {
  put(b, "\"", 1);
  for (; *s; s++) {
    switch (*s) {
    case '"': put(b, "\\\"", 2); break;
    case '\\': put(b, "\\\\", 2); break;
    case '\n': put(b, "\\n", 2); break;
    default: put(b, s, 1);
    }
  }
  put(b, "\"", 1);
}

static const char *notes[4] = {"ok", "said \"hi\"", "line one\nline two", ""};

static Buf generate(int n) {
  Buf b = {0};
  putStr(&b, "[\n");
  int64_t seed = 7;
  for (int i = 0; i < n; i++) {
    seed = next(seed);
    int64_t r = seed;
    double score = (double)(r % 4000) + 0.25 * (double)(1 + r % 3);
    putf(&b, "  {\"id\": %d, \"name\": \"user%d\", \"email\": \"user%d@example.com\", ", i, i, i);
    putf(&b, "\"age\": %d, \"score\": %g, \"active\": %s, ", (int)(18 + r % 60), score, r % 3 != 0 ? "true" : "false");
    putStr(&b, "\"tags\": [");
    for (int t = 0; t <= r % 4; t++) putf(&b, "%s\"t%d\"", t ? ", " : "", (int)((r / 7 + t * 3) % 10));
    putf(&b, "], \"address\": {\"city\": \"city%d\", \"zip\": \"%d\"}, \"note\": ", (int)(r % 100), (int)(10000 + r % 90000));
    putJsonString(&b, notes[r % 4]);
    putStr(&b, i < n - 1 ? "},\n" : "}\n");
  }
  putStr(&b, "]\n");
  put(&b, "", 1); // the terminating 0 the parser stops at
  b.len--;
  return b;
}

// the document tree
typedef enum { JNULL, JBOOL, JINT, JNUMBER, JSTRING, JARRAY, JOBJECT } Kind;
typedef struct Json Json;
struct Json {
  Kind kind;
  union {
    int b;
    int64_t i;
    double x;
    char *s;
    struct { Json *items; char **keys; size_t len; } list; // keys: an object's
  };
};

static const char *p;

static void skip(void) {
  while (*p == ' ' || *p == '\n' || *p == '\t' || *p == '\r') p++;
}

// a string's text, its escapes decoded: never longer than the quoted text, so one allocation
static char *text(void) {
  const char *end = ++p; // past the opening "
  while (*end != '"') end += *end == '\\' ? 2 : 1;
  char *s = malloc((size_t)(end - p) + 1), *o = s;
  while (p < end) {
    if (*p != '\\') { *o++ = *p++; continue; }
    p++;
    char c = *p++;
    switch (c) {
    case 'n': *o++ = '\n'; break;
    case 't': *o++ = '\t'; break;
    case 'r': *o++ = '\r'; break;
    default: *o++ = c; // \" \\ \/ (\u is not in these documents)
    }
  }
  *o = 0;
  p = end + 1;
  return s;
}

static Json value(void);

static Json value(void) {
  skip();
  Json j = {0};
  switch (*p) {
  case '{':
  case '[': {
    int object = *p == '{';
    j.kind = object ? JOBJECT : JARRAY;
    p++;
    size_t cap = 0;
    skip();
    if (*p == (object ? '}' : ']')) { p++; return j; }
    for (;;) {
      if (j.list.len == cap) {
        cap = cap ? cap * 2 : 4;
        j.list.items = realloc(j.list.items, cap * sizeof(Json));
        if (object) j.list.keys = realloc(j.list.keys, cap * sizeof(char *));
      }
      if (object) {
        skip();
        j.list.keys[j.list.len] = text();
        skip();
        p++; // :
      }
      j.list.items[j.list.len++] = value();
      skip();
      if (*p++ != ',') break;
    }
    return j;
  }
  case '"': j.kind = JSTRING; j.s = text(); return j;
  case 't': j.kind = JBOOL; j.b = 1; p += 4; return j;
  case 'f': j.kind = JBOOL; j.b = 0; p += 5; return j;
  case 'n': j.kind = JNULL; p += 4; return j;
  default: {
    const char *start = p;
    if (*p == '-') p++;
    while (*p >= '0' && *p <= '9') p++;
    if (*p == '.' || *p == 'e' || *p == 'E') {
      char *end;
      j.kind = JNUMBER;
      j.x = strtod(start, &end);
      p = end;
    } else {
      j.kind = JINT;
      j.i = strtoll(start, NULL, 10);
    }
    return j;
  }
  }
}

static void freeJson(Json *j) {
  if (j->kind == JSTRING) free(j->s);
  if (j->kind == JARRAY || j->kind == JOBJECT) {
    for (size_t i = 0; i < j->list.len; i++) {
      freeJson(&j->list.items[i]);
      if (j->kind == JOBJECT) free(j->list.keys[i]);
    }
    free(j->list.items);
    free(j->list.keys);
  }
}

static Json *field(Json *o, const char *key) {
  for (size_t i = 0; i < o->list.len; i++)
    if (strcmp(o->list.keys[i], key) == 0) return &o->list.items[i];
  fprintf(stderr, "no field %s\n", key);
  exit(1);
}

typedef struct {
  int64_t id, age;
  char *name, *email, *city, *zip, *note;
  double score;
  int active;
  char **tags;
  size_t ntags;
} User;

static char *dup(Json *j) { return strdup(j->s); }

static User decode(Json *o) {
  User u;
  u.id = field(o, "id")->i;
  u.name = dup(field(o, "name"));
  u.email = dup(field(o, "email"));
  u.age = field(o, "age")->i;
  Json *s = field(o, "score");
  u.score = s->kind == JINT ? (double)s->i : s->x;
  u.active = field(o, "active")->b;
  Json *tags = field(o, "tags");
  u.ntags = tags->list.len;
  u.tags = malloc(u.ntags * sizeof(char *));
  for (size_t i = 0; i < u.ntags; i++) u.tags[i] = dup(&tags->list.items[i]);
  Json *a = field(o, "address");
  u.city = dup(field(a, "city"));
  u.zip = dup(field(a, "zip"));
  u.note = dup(field(o, "note"));
  return u;
}

static void encode(Buf *b, const User *u) {
  putf(b, "{\"id\":%lld,\"name\":", (long long)u->id);
  putJsonString(b, u->name);
  putStr(b, ",\"email\":");
  putJsonString(b, u->email);
  putf(b, ",\"age\":%lld,\"score\":%g,\"active\":%s,\"tags\":[", (long long)u->age, u->score, u->active ? "true" : "false");
  for (size_t i = 0; i < u->ntags; i++) {
    if (i) putStr(b, ",");
    putJsonString(b, u->tags[i]);
  }
  putStr(b, "],\"address\":{\"city\":");
  putJsonString(b, u->city);
  putStr(b, ",\"zip\":");
  putJsonString(b, u->zip);
  putStr(b, "},\"note\":");
  putJsonString(b, u->note);
  putStr(b, "}");
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 200000;
  Buf in = generate(n);
  p = in.data;
  Json doc = value();
  size_t count = doc.list.len;
  User *users = malloc(count * sizeof(User));
  for (size_t i = 0; i < count; i++) users[i] = decode(&doc.list.items[i]);
  freeJson(&doc);

  long active = 0, ages = 0, tagged = 0;
  double score = 0;
  for (size_t i = 0; i < count; i++) {
    if (users[i].active) { active++; ages += users[i].age; }
    score += users[i].score;
    for (size_t t = 0; t < users[i].ntags; t++)
      if (strcmp(users[i].tags[t], "t3") == 0) { tagged++; break; }
  }
  Buf out = {0};
  putStr(&out, "[");
  int first = 1;
  for (size_t i = 0; i < count; i++) {
    if (!users[i].active) continue;
    if (!first) putStr(&out, ",");
    first = 0;
    encode(&out, &users[i]);
  }
  putStr(&out, "]");
  printf("%zu bytes in, %zu users, %ld active\n", in.len, count, active);
  printf("ages %ld, score %.2f, tagged t3 %ld\n", ages, score, tagged);
  printf("%zu bytes out\n", out.len);

  for (size_t i = 0; i < count; i++) {
    User *u = &users[i];
    free(u->name); free(u->email); free(u->city); free(u->zip); free(u->note);
    for (size_t t = 0; t < u->ntags; t++) free(u->tags[t]);
    free(u->tags);
  }
  free(users);
  free(in.data);
  free(out.data);
  return 0;
}
