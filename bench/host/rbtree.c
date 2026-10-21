// A red-black tree: inserting a million keys, then looking each one up. An in-place
// left-leaning red-black tree (Sedgewick), the usual way to write one in C.
#include <stdio.h>
#include <stdlib.h>

typedef struct Node { long key; struct Node *l, *r; int red; } Node;

static int isRed(const Node *n) { return n && n->red; }

static Node *rotateLeft(Node *h) {
    Node *x = h->r; h->r = x->l; x->l = h; x->red = h->red; h->red = 1;
    return x;
}

static Node *rotateRight(Node *h) {
    Node *x = h->l; h->l = x->r; x->r = h; x->red = h->red; h->red = 1;
    return x;
}

static void flip(Node *h) { h->red = !h->red; h->l->red = !h->l->red; h->r->red = !h->r->red; }

static Node *insert(Node *h, long k) {
    if (!h) {
        Node *n = malloc(sizeof *n);
        n->key = k; n->l = n->r = NULL; n->red = 1;
        return n;
    }
    if (k < h->key) h->l = insert(h->l, k);
    else if (k > h->key) h->r = insert(h->r, k);
    else return h;
    if (isRed(h->r) && !isRed(h->l)) h = rotateLeft(h);
    if (isRed(h->l) && isRed(h->l->l)) h = rotateRight(h);
    if (isRed(h->l) && isRed(h->r)) flip(h);
    return h;
}

static int contains(const Node *t, long k) {
    while (t) {
        if (k < t->key) t = t->l;
        else if (k > t->key) t = t->r;
        else return 1;
    }
    return 0;
}

static void drop(Node *t) {
    if (t) { drop(t->l); drop(t->r); free(t); }
}

int main(int argc, char **argv) {
    long n = argc > 1 ? atol(argv[1]) : 1000000;
    Node *t = NULL;
    long seed = 42;
    for (long i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        t = insert(t, seed % n);
        t->red = 0;
    }
    long found = 0;
    for (long i = 0; i < n; i++) found += contains(t, i);
    printf("%ld\n", found);
    drop(t);
    return 0;
}
