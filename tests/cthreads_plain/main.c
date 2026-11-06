// Calls a Z# library without handles (tests/cthreads_plain/lib.zs) on 8 threads at once, 2,000
// times each, and checks every result against C's own count of the digits.
#include <pthread.h>
#include <stdio.h>
#include "lib.h"

static int right[8];

static intptr_t digits(intptr_t n) {
    intptr_t total = 0;
    for (intptr_t i = 0; i < n; i++) total += snprintf(NULL, 0, "%lld", (long long)(i * 7919));
    return total;
}

static void *calls(void *arg) {
    int k = (int)(intptr_t)arg;
    int good = 1;
    for (int i = 0; i < 2000; i++) {
        intptr_t n = 10 + (i + k) % 30;
        if (digits_total(n) != digits(n)) good = 0;
    }
    right[k] = good;
    return NULL;
}

int main(void) {
    pthread_t threads[8];
    for (int k = 0; k < 8; k++) pthread_create(&threads[k], NULL, calls, (void *)(intptr_t)k);
    for (int k = 0; k < 8; k++) pthread_join(threads[k], NULL);
    int all = 1;
    for (int k = 0; k < 8; k++) all = all && right[k];
    printf("8 threads calling a library without handles: %s\n", all ? "every result right" : "a result wrong");
    return 0;
}
