// Word frequencies: a generated text of n words, split into lowercase words, counted in an
// open-addressing hash table (FNV-1a) and sorted by count, then word.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VOCABULARY 50000

static const char *syllables[16] = {"ka", "lo", "mi", "ne", "ru", "sa", "to", "vi",
                                    "an", "el", "or", "us", "be", "di", "fu", "go"};

static int64_t next(int64_t seed) { return (seed * 1103515245 + 12345) % 2147483648; }

typedef struct { char *data; size_t len, cap; } Text;

static void append(Text *t, const char *s, size_t n) {
  if (t->len + n > t->cap) {
    while (t->len + n > t->cap) t->cap = t->cap ? t->cap * 2 : 1024;
    t->data = realloc(t->data, t->cap);
  }
  memcpy(t->data + t->len, s, n);
  t->len += n;
}

static char *word(int v) {
  char buf[64];
  size_t n = 0;
  int rest = v;
  do {
    memcpy(buf + n, syllables[rest % 16], 2);
    n += 2;
    rest /= 16;
  } while (rest > 0);
  char *w = malloc(n + 1);
  memcpy(w, buf, n);
  w[n] = 0;
  return w;
}

static Text generate(int n) {
  char **words = malloc(VOCABULARY * sizeof *words);
  for (int i = 0; i < VOCABULARY; i++) words[i] = word(i);
  Text t = {0};
  int64_t seed = 42;
  int capital = 1;
  for (int i = 0; i < n; i++) {
    seed = next(seed);
    int64_t x = seed % VOCABULARY;
    const char *w = words[x * x / VOCABULARY];
    size_t len = strlen(w);
    if (capital) {
      char c = (char)(w[0] - 32);
      append(&t, &c, 1);
      append(&t, w + 1, len - 1);
    } else append(&t, w, len);
    seed = next(seed);
    capital = seed % 20 == 0;
    switch (seed % 20) {
    case 0: append(&t, ". ", 2); break;
    case 1: append(&t, ", ", 2); break;
    case 2: append(&t, "\n", 1); break;
    default: append(&t, " ", 1);
    }
  }
  for (int i = 0; i < VOCABULARY; i++) free(words[i]);
  free(words);
  return t;
}

typedef struct { char *word; size_t len; uint64_t hash; long count; } Entry;
typedef struct { Entry *slots; size_t cap, size; } Table;

static uint64_t fnv1a(const char *s, size_t n) {
  uint64_t h = 14695981039346656037ull;
  for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)s[i]) * 1099511628211ull;
  return h;
}

static void grow(Table *t) {
  size_t cap = t->cap ? t->cap * 2 : 1024;
  Entry *slots = calloc(cap, sizeof *slots);
  for (size_t i = 0; i < t->cap; i++) {
    Entry e = t->slots[i];
    if (!e.word) continue;
    size_t j = e.hash & (cap - 1);
    while (slots[j].word) j = (j + 1) & (cap - 1);
    slots[j] = e;
  }
  free(t->slots);
  t->slots = slots;
  t->cap = cap;
}

static void add(Table *t, const char *w, size_t n) {
  if (2 * (t->size + 1) > t->cap) grow(t);
  uint64_t h = fnv1a(w, n);
  size_t j = h & (t->cap - 1);
  for (;; j = (j + 1) & (t->cap - 1)) {
    Entry *e = &t->slots[j];
    if (!e->word) {
      e->word = malloc(n + 1);
      memcpy(e->word, w, n);
      e->word[n] = 0;
      e->len = n;
      e->hash = h;
      e->count = 1;
      t->size++;
      return;
    }
    if (e->hash == h && e->len == n && memcmp(e->word, w, n) == 0) {
      e->count++;
      return;
    }
  }
}

static int isLetter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }

static int byCount(const void *a, const void *b) {
  const Entry *x = a, *y = b;
  if (x->count != y->count) return x->count < y->count ? 1 : -1;
  return strcmp(x->word, y->word);
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1000000;
  Text text = generate(n);
  Table t = {0};
  long total = 0;
  char w[64];
  size_t i = 0;
  while (i < text.len) {
    if (isLetter(text.data[i])) {
      size_t len = 0;
      while (i < text.len && isLetter(text.data[i])) {
        char c = text.data[i++];
        w[len++] = c >= 'A' && c <= 'Z' ? (char)(c + 32) : c;
      }
      add(&t, w, len);
      total++;
    } else i++;
  }
  Entry *all = malloc(t.size * sizeof *all);
  size_t k = 0;
  for (size_t j = 0; j < t.cap; j++)
    if (t.slots[j].word) all[k++] = t.slots[j];
  qsort(all, k, sizeof *all, byCount);
  printf("%ld words, %zu distinct\n", total, t.size);
  for (size_t j = 0; j < k && j < 10; j++) printf("%s %ld\n", all[j].word, all[j].count);
  for (size_t j = 0; j < t.cap; j++) free(t.slots[j].word);
  free(t.slots);
  free(all);
  free(text.data);
  return 0;
}
