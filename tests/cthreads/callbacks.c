#include <pthread.h>
#include <stdint.h>
#include "callbacks.h"

struct call {
    void (*f)(void *, int64_t);
    void *user;
    int64_t x;
};

static void *run(void *arg) {
    struct call *c = arg;
    c->f(c->user, c->x);
    return NULL;
}

void on_thread(void (*f)(void *, int64_t), void *user, int64_t x) {
    struct call c = {f, user, x};
    pthread_t t;
    pthread_create(&t, NULL, run, &c);
    pthread_join(t, NULL);
}

// the same, declared callback<share<…>> in Z#: C may call it on any thread
void on_thread_shared(void (*f)(void *, int64_t), void *user, int64_t x) { on_thread(f, user, x); }

// declared callback<…> in Z#: called on another thread, it panics
void on_thread_checked(void (*f)(void *, int64_t), void *user, int64_t x) { on_thread(f, user, x); }
