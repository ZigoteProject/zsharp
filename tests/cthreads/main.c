// Uses a Z# library's handles on 16 threads (tests/cthreads/lib.zs): a list's, which may be
// used on any thread, retained, read, extended and released on all of them at once. With
// "other-thread", then a ref's, which panics when another thread than the one that made it
// releases it (test.sh runs that, and this under Helgrind).
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include "lib.h"

static zs_handle shared_list;
static int64_t sums[16];

static void *use_list(void *arg) {
    int k = (int)(intptr_t)arg;
    int64_t total = 0;
    for (int i = 0; i < 200; i++) {
        zs_retain(shared_list);
        total += numbers_sum(shared_list);
        zs_handle longer = numbers_more(k, shared_list); // shares the list's cells
        total += numbers_sum(longer) - numbers_sum(shared_list);
        zs_release(longer);
        zs_release(shared_list);
    }
    sums[k] = total;
    return NULL;
}

static zs_handle a_counter;

static void *release_counter(void *arg) {
    (void)arg;
    zs_release(a_counter); // made on the main thread: panics
    return NULL;
}

int main(int argc, char **argv) {
    shared_list = numbers(100);
    pthread_t threads[16];
    for (int k = 0; k < 16; k++) pthread_create(&threads[k], NULL, use_list, (void *)(intptr_t)k);
    for (int k = 0; k < 16; k++) pthread_join(threads[k], NULL);
    int ok = 1;
    for (int k = 0; k < 16; k++) ok = ok && sums[k] == 200 * (5050 + k);
    printf("16 threads using a list's handle: %s\n", ok ? "every sum right" : "a sum wrong");
    zs_release(shared_list);
    if (argc < 2 || strcmp(argv[1], "other-thread") != 0) return 0;

    a_counter = counter();
    printf("the counter on its own thread: %lld\n", (long long)counter_add(a_counter, 5));
    fflush(stdout);
    pthread_t other;
    pthread_create(&other, NULL, release_counter, NULL);
    pthread_join(other, NULL);
    printf("not reached\n");
    return 0;
}
