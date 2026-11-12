// Mbed TLS's configuration for this package: the release's own (c/mbedtls/include/mbedtls/
// mbedtls_config.h, unmodified: TLS 1.2 and 1.3, no older protocol) with its mutexes on, since
// a Z# program's connections run on any thread and TLS 1.3 keeps keys in state they share.
// This directory comes before the release's in zs.toml's include list, so
// "mbedtls/mbedtls_config.h" is this file.
#include "../../mbedtls/include/mbedtls/mbedtls_config.h"

#define MBEDTLS_THREADING_C
#define MBEDTLS_THREADING_PTHREAD
