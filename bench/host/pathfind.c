// Shortest paths: Dijkstra's algorithm over a w x w grid whose cells cost 1 to 9 to enter, from
// the top-left corner to every cell, with a binary heap.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int64_t next(int64_t seed) { return (seed * 1103515245 + 12345) % 2147483648; }

typedef struct { int64_t dist; int64_t cell; } Item;
typedef struct { Item *items; size_t len, cap; } Heap;

static void push(Heap *h, Item x) {
  if (h->len == h->cap) {
    h->cap = h->cap ? h->cap * 2 : 1024;
    h->items = realloc(h->items, h->cap * sizeof(Item));
  }
  size_t i = h->len++;
  while (i > 0) {
    size_t parent = (i - 1) / 2;
    if (h->items[parent].dist <= x.dist) break;
    h->items[i] = h->items[parent];
    i = parent;
  }
  h->items[i] = x;
}

static Item pop(Heap *h) {
  Item top = h->items[0], last = h->items[--h->len];
  size_t i = 0;
  for (;;) {
    size_t c = 2 * i + 1;
    if (c >= h->len) break;
    if (c + 1 < h->len && h->items[c + 1].dist < h->items[c].dist) c++;
    if (last.dist <= h->items[c].dist) break;
    h->items[i] = h->items[c];
    i = c;
  }
  if (h->len > 0) h->items[i] = last;
  return top;
}

int main(int argc, char **argv) {
  int64_t w = argc > 1 ? atoll(argv[1]) : 1000;
  int64_t cells = w * w;
  int64_t *cost = malloc(cells * sizeof *cost), *dist = malloc(cells * sizeof *dist);
  int64_t seed = 3;
  for (int64_t i = 0; i < cells; i++) {
    seed = next(seed);
    cost[i] = 1 + seed / 65536 % 9;
    dist[i] = cells * 10;
  }
  dist[0] = 0;
  Heap heap = {0};
  push(&heap, (Item){0, 0});
  int64_t settled = 0;
  while (heap.len > 0) {
    Item it = pop(&heap);
    if (it.dist != dist[it.cell]) continue; // stale: the cell was reached cheaper since
    settled++;
    int64_t x = it.cell % w, y = it.cell / w;
    const int64_t nxs[4] = {x - 1, x + 1, x, x}, nys[4] = {y, y, y - 1, y + 1};
    for (int k = 0; k < 4; k++) {
      int64_t nx = nxs[k], ny = nys[k];
      if (nx < 0 || nx >= w || ny < 0 || ny >= w) continue;
      int64_t near = ny * w + nx, nd = it.dist + cost[near];
      if (nd < dist[near]) {
        dist[near] = nd;
        push(&heap, (Item){nd, near});
      }
    }
  }
  int64_t total = 0;
  for (int64_t i = 0; i < cells; i++) total += dist[i];
  printf("%lld cells settled\n", (long long)settled);
  printf("to the far corner: %lld\n", (long long)dist[cells - 1]);
  printf("all distances: %lld\n", (long long)total);
  free(cost);
  free(dist);
  free(heap.items);
  return 0;
}
