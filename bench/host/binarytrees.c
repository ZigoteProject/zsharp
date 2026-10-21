// Binary trees (the Benchmarks Game): allocating and walking many small trees, with malloc.
#include <stdio.h>
#include <stdlib.h>

typedef struct Node { struct Node *l, *r; } Node;

static Node *make(int d) {
    Node *n = malloc(sizeof *n);
    if (d == 0) n->l = n->r = NULL;
    else { n->l = make(d - 1); n->r = make(d - 1); }
    return n;
}

static long check(const Node *n) { return n->l ? 1 + check(n->l) + check(n->r) : 1; }

static void drop(Node *n) {
    if (n->l) { drop(n->l); drop(n->r); }
    free(n);
}

int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 16;
    int maxDepth = n > 6 ? n : 6, stretch = maxDepth + 1;
    Node *s = make(stretch);
    printf("stretch tree of depth %d\t check: %ld\n", stretch, check(s));
    drop(s);
    Node *longLived = make(maxDepth);
    for (int d = 4; d <= maxDepth; d += 2) {
        long iterations = 1L << (maxDepth - d + 4), total = 0;
        for (long i = 0; i < iterations; i++) {
            Node *t = make(d);
            total += check(t);
            drop(t);
        }
        printf("%ld\t trees of depth %d\t check: %ld\n", iterations, d, total);
    }
    printf("long lived tree of depth %d\t check: %ld\n", maxDepth, check(longLived));
    drop(longLived);
    return 0;
}
