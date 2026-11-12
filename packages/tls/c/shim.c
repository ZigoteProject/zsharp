// What packages/tls asks of Mbed TLS, as a few calls over two handles. A connection does no
// socket I/O here: Mbed TLS reads from and writes to buffers in the handle, and the Z# side
// moves their bytes with Net.Tcp, so the same code serves every OS's sockets and the event
// loop decides when to wait.
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/ecp.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#endif

// what a step of a connection came to, when it isn't a count of bytes
enum { ZS_TLS_WANT_READ = -1, ZS_TLS_AGAIN = -2, ZS_TLS_CLOSED = -3, ZS_TLS_ERROR = -4 };

typedef struct zs_tls_config {
    mbedtls_ssl_config conf;
    mbedtls_x509_crt chain; // a client's roots, or a server's certificate and the chain above it
    mbedtls_pk_context key; // a server's key
    int refs;               // the Z# handle and each connection made from it (under g_lock)
} zs_tls_config;

typedef struct zs_tls_conn {
    mbedtls_ssl_context ssl;
    zs_tls_config *config;
    uint8_t *in;    // bytes from the peer Mbed TLS hasn't taken: in[in_at .. in_len)
    size_t in_at, in_len, in_cap;
    uint8_t *out;   // bytes for the peer the Z# side hasn't sent: out[0 .. out_len)
    size_t out_len, out_cap;
    uint8_t *plain; // what the last read decrypted
    size_t plain_cap;
    int error;      // the Mbed TLS code of the last ZS_TLS_ERROR
} zs_tls_conn;

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static mbedtls_entropy_context g_entropy;
static mbedtls_ctr_drbg_context g_rng; // locked by Mbed TLS itself (MBEDTLS_THREADING_C)
static int g_init;                     // the code that starting the generator gave
static _Thread_local int t_error;      // why the last call that gave NULL failed
static _Thread_local char t_text[400];

static void init_once(void) {
    mbedtls_entropy_init(&g_entropy);
    mbedtls_ctr_drbg_init(&g_rng);
    g_init = mbedtls_ctr_drbg_seed(&g_rng, mbedtls_entropy_func, &g_entropy, (const unsigned char *)"zsharp/tls", 10);
    if (g_init == 0 && psa_crypto_init() != PSA_SUCCESS) g_init = MBEDTLS_ERR_SSL_HW_ACCEL_FAILED;
}

static int ready(void) {
    pthread_once(&g_once, init_once);
    return g_init;
}

// The text of an Mbed TLS error code, in a buffer of this thread's.
const char *zs_tls_error_text(int code) {
    mbedtls_strerror(code, t_text, sizeof t_text);
    return t_text;
}

// Why the last call on this thread that returned NULL did.
int zs_tls_last_error(void) { return t_error; }

// PEM text must end in a NUL that its length counts: a copy that does.
static unsigned char *with_nul(const uint8_t *p, size_t n) {
    unsigned char *copy = malloc(n + 1);
    if (!copy) return NULL;
    if (n) memcpy(copy, p, n);
    copy[n] = 0;
    return copy;
}

static int parse_chain(mbedtls_x509_crt *chain, const uint8_t *pem, size_t n) {
    unsigned char *text = with_nul(pem, n);
    if (!text) return MBEDTLS_ERR_X509_ALLOC_FAILED;
    int rc = mbedtls_x509_crt_parse(chain, text, n + 1);
    free(text);
    return rc;
}

// The certificates this system trusts, added to chain: 0 when some were found.
static int system_roots(mbedtls_x509_crt *chain) {
#ifdef _WIN32
    HCERTSTORE store = CertOpenSystemStoreA(0, "ROOT");
    if (!store) return MBEDTLS_ERR_X509_FILE_IO_ERROR;
    int found = 0;
    for (PCCERT_CONTEXT c = NULL; (c = CertEnumCertificatesInStore(store, c)) != NULL;)
        if (mbedtls_x509_crt_parse_der(chain, c->pbCertEncoded, c->cbCertEncoded) == 0) found++;
    CertCloseStore(store, 0);
    return found ? 0 : MBEDTLS_ERR_X509_FILE_IO_ERROR;
#else
    // SSL_CERT_FILE as OpenSSL reads it, then where the distributions and macOS keep the bundle
    static const char *const files[] = {
        "/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem",
        "/etc/ssl/ca-bundle.pem", "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
    };
    const char *named = getenv("SSL_CERT_FILE");
    // a positive result counts the certificates of the file that didn't parse: the rest are in
    if (named && *named) return mbedtls_x509_crt_parse_file(chain, named) >= 0 ? 0 : MBEDTLS_ERR_X509_FILE_IO_ERROR;
    for (size_t i = 0; i < sizeof files / sizeof *files; i++)
        if (mbedtls_x509_crt_parse_file(chain, files[i]) >= 0) return 0;
    return MBEDTLS_ERR_X509_FILE_IO_ERROR;
#endif
}

static zs_tls_config *config_new(int endpoint) {
    if ((t_error = ready()) != 0) return NULL;
    zs_tls_config *c = calloc(1, sizeof *c);
    if (!c) { t_error = MBEDTLS_ERR_SSL_ALLOC_FAILED; return NULL; }
    mbedtls_ssl_config_init(&c->conf);
    mbedtls_x509_crt_init(&c->chain);
    mbedtls_pk_init(&c->key);
    c->refs = 1;
    t_error = mbedtls_ssl_config_defaults(&c->conf, endpoint, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    mbedtls_ssl_conf_rng(&c->conf, mbedtls_ctr_drbg_random, &g_rng);
    return c;
}

// Gives up a reference to the configuration: freed with its last one.
void zs_tls_config_release(zs_tls_config *c) {
    pthread_mutex_lock(&g_lock);
    int left = --c->refs;
    pthread_mutex_unlock(&g_lock);
    if (left) return;
    mbedtls_ssl_config_free(&c->conf);
    mbedtls_x509_crt_free(&c->chain);
    mbedtls_pk_free(&c->key);
    free(c);
}

// A client's configuration: the peer's certificate is verified against the roots in pem (PEM
// text, n bytes), or against the system's when n is 0, and its name against the host asked for.
// NULL on a failure (zs_tls_last_error).
zs_tls_config *zs_tls_client_config(const uint8_t *pem, size_t n) {
    zs_tls_config *c = config_new(MBEDTLS_SSL_IS_CLIENT);
    if (!c) return NULL;
    if (t_error == 0) t_error = n ? parse_chain(&c->chain, pem, n) : system_roots(&c->chain);
    if (t_error > 0) t_error = MBEDTLS_ERR_X509_INVALID_FORMAT; // some of the roots given didn't parse
    if (t_error != 0) { zs_tls_config_release(c); return NULL; }
    mbedtls_ssl_conf_ca_chain(&c->conf, &c->chain, NULL);
    mbedtls_ssl_conf_authmode(&c->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    return c;
}

// A server's configuration: its certificate (and the chain above it) and its key, as PEM text.
zs_tls_config *zs_tls_server_config(const uint8_t *cert, size_t cert_n, const uint8_t *key, size_t key_n) {
    zs_tls_config *c = config_new(MBEDTLS_SSL_IS_SERVER);
    if (!c) return NULL;
    if (t_error == 0) t_error = parse_chain(&c->chain, cert, cert_n);
    if (t_error > 0) t_error = MBEDTLS_ERR_X509_INVALID_FORMAT;
    if (t_error == 0) {
        unsigned char *text = with_nul(key, key_n);
        t_error = text ? mbedtls_pk_parse_key(&c->key, text, key_n + 1, NULL, 0, mbedtls_ctr_drbg_random, &g_rng)
                       : MBEDTLS_ERR_PK_ALLOC_FAILED;
        if (text) { mbedtls_platform_zeroize(text, key_n + 1); free(text); }
    }
    if (t_error == 0) t_error = mbedtls_ssl_conf_own_cert(&c->conf, &c->chain, &c->key);
    if (t_error != 0) { zs_tls_config_release(c); return NULL; }
    return c;
}

// A new P-256 key and a certificate for host signed with it, valid from yesterday for a year:
// for a test or a development server, whose client trusts exactly this certificate. Each is PEM
// text in a buffer of size bytes. 0, or an Mbed TLS code.
int zs_tls_self_signed(const char *host, char *cert_pem, char *key_pem, size_t size) {
    int rc = ready();
    if (rc != 0) return rc;
    mbedtls_pk_context key;
    mbedtls_x509write_cert crt;
    char name[300], from[16], to[16];
    unsigned char serial[16];
    time_t now = time(NULL), start = now - 86400, end = now + 365 * 86400;
    struct tm tm;
    mbedtls_pk_init(&key);
    mbedtls_x509write_crt_init(&crt);
    if (snprintf(name, sizeof name, "CN=%s", host) >= (int)sizeof name) rc = MBEDTLS_ERR_X509_BAD_INPUT_DATA;
    if (rc == 0 && (!mbedtls_platform_gmtime_r(&start, &tm) || !strftime(from, sizeof from, "%Y%m%d%H%M%S", &tm)))
        rc = MBEDTLS_ERR_X509_BAD_INPUT_DATA;
    if (rc == 0 && (!mbedtls_platform_gmtime_r(&end, &tm) || !strftime(to, sizeof to, "%Y%m%d%H%M%S", &tm)))
        rc = MBEDTLS_ERR_X509_BAD_INPUT_DATA;
    if (rc == 0) rc = mbedtls_pk_setup(&key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    if (rc == 0) rc = mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(key), mbedtls_ctr_drbg_random, &g_rng);
    if (rc == 0) rc = mbedtls_ctr_drbg_random(&g_rng, serial, sizeof serial);
    serial[0] = (serial[0] & 0x7f) | 0x40; // positive, and no leading zero byte
    mbedtls_x509write_crt_set_version(&crt, MBEDTLS_X509_CRT_VERSION_3);
    mbedtls_x509write_crt_set_md_alg(&crt, MBEDTLS_MD_SHA256);
    mbedtls_x509write_crt_set_subject_key(&crt, &key);
    mbedtls_x509write_crt_set_issuer_key(&crt, &key);
    if (rc == 0) rc = mbedtls_x509write_crt_set_subject_name(&crt, name);
    if (rc == 0) rc = mbedtls_x509write_crt_set_issuer_name(&crt, name);
    if (rc == 0) rc = mbedtls_x509write_crt_set_serial_raw(&crt, serial, sizeof serial);
    if (rc == 0) rc = mbedtls_x509write_crt_set_validity(&crt, from, to);
    if (rc == 0) rc = mbedtls_x509write_crt_pem(&crt, (unsigned char *)cert_pem, size, mbedtls_ctr_drbg_random, &g_rng);
    if (rc == 0) rc = mbedtls_pk_write_key_pem(&key, (unsigned char *)key_pem, size);
    mbedtls_x509write_crt_free(&crt);
    mbedtls_pk_free(&key);
    return rc;
}

// Mbed TLS takes the peer's bytes from the connection's buffer, and waits when there are none
static int bio_recv(void *ctx, unsigned char *buf, size_t len) {
    zs_tls_conn *c = ctx;
    size_t have = c->in_len - c->in_at;
    if (have == 0) return MBEDTLS_ERR_SSL_WANT_READ;
    if (len > have) len = have;
    memcpy(buf, c->in + c->in_at, len);
    c->in_at += len;
    if (c->in_at == c->in_len) c->in_at = c->in_len = 0;
    return (int)len;
}

// room for n more bytes at *buf's end; false when there's no memory
static int grow(uint8_t **buf, size_t used, size_t *cap, size_t n) {
    if (n > SIZE_MAX - used) return 0;
    if (used + n <= *cap) return 1;
    size_t want = *cap ? *cap : 4096;
    while (want < used + n) {
        if (want > SIZE_MAX / 2) return 0;
        want *= 2;
    }
    uint8_t *p = realloc(*buf, want);
    if (!p) return 0;
    *buf = p;
    *cap = want;
    return 1;
}

// and puts what it has for the peer in the other, which the Z# side sends after each call
static int bio_send(void *ctx, const unsigned char *buf, size_t len) {
    zs_tls_conn *c = ctx;
    if (len > 0x7fffffff) len = 0x7fffffff;
    if (!grow(&c->out, c->out_len, &c->out_cap, len)) return MBEDTLS_ERR_SSL_ALLOC_FAILED;
    memcpy(c->out + c->out_len, buf, len);
    c->out_len += len;
    return (int)len;
}

// Frees the connection (the socket is the Z# side's).
void zs_tls_conn_free(zs_tls_conn *c) {
    mbedtls_ssl_free(&c->ssl);
    zs_tls_config_release(c->config);
    free(c->in);
    free(c->out);
    free(c->plain);
    free(c);
}

// A connection under the configuration; a client's verifies the peer's certificate for host
// (NUL-terminated; ignored for a server). NULL on a failure (zs_tls_last_error).
zs_tls_conn *zs_tls_conn_new(zs_tls_config *config, const char *host) {
    zs_tls_conn *c = calloc(1, sizeof *c);
    if (!c) { t_error = MBEDTLS_ERR_SSL_ALLOC_FAILED; return NULL; }
    mbedtls_ssl_init(&c->ssl);
    c->config = config;
    pthread_mutex_lock(&g_lock);
    config->refs++;
    pthread_mutex_unlock(&g_lock);
    t_error = mbedtls_ssl_setup(&c->ssl, &config->conf);
    if (t_error == 0 && config->conf.MBEDTLS_PRIVATE(endpoint) == MBEDTLS_SSL_IS_CLIENT)
        t_error = mbedtls_ssl_set_hostname(&c->ssl, host);
    if (t_error != 0) { zs_tls_conn_free(c); return NULL; }
    mbedtls_ssl_set_bio(&c->ssl, c, bio_send, bio_recv, NULL);
    return c;
}

// The peer's bytes, n of them at p, for the connection's next step.
int zs_tls_feed(zs_tls_conn *c, const uint8_t *p, size_t n) {
    if (!grow(&c->in, c->in_len, &c->in_cap, n)) return ZS_TLS_ERROR;
    if (n) memcpy(c->in + c->in_len, p, n);
    c->in_len += n;
    return 0;
}

// What the connection has for the peer: out_length bytes at out, until out_done.
const uint8_t *zs_tls_out(zs_tls_conn *c) { return c->out; }
size_t zs_tls_out_length(zs_tls_conn *c) { return c->out_len; }
void zs_tls_out_done(zs_tls_conn *c) { c->out_len = 0; }

// a step's Mbed TLS result as this file's: a count, or one of ZS_TLS_…
static int outcome(zs_tls_conn *c, int rc) {
    if (rc >= 0) return rc;
    if (rc == MBEDTLS_ERR_SSL_WANT_READ) return ZS_TLS_WANT_READ;
    // a write waits for nothing here (bio_send always takes it), and TLS 1.3's tickets and key
    // updates arrive as a read that has nothing yet: the same call again
    if (rc == MBEDTLS_ERR_SSL_WANT_WRITE || rc == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET ||
        rc == MBEDTLS_ERR_SSL_ASYNC_IN_PROGRESS || rc == MBEDTLS_ERR_SSL_CRYPTO_IN_PROGRESS)
        return ZS_TLS_AGAIN;
    if (rc == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return ZS_TLS_CLOSED;
    c->error = rc;
    return ZS_TLS_ERROR;
}

// The handshake's next step: 0 when it's done.
int zs_tls_handshake(zs_tls_conn *c) { return outcome(c, mbedtls_ssl_handshake(&c->ssl)); }

// Decrypts up to n bytes into the connection's own buffer (zs_tls_plain): how many.
int zs_tls_read(zs_tls_conn *c, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    if (n > c->plain_cap && !grow(&c->plain, 0, &c->plain_cap, n)) { c->error = MBEDTLS_ERR_SSL_ALLOC_FAILED; return ZS_TLS_ERROR; }
    return outcome(c, mbedtls_ssl_read(&c->ssl, c->plain, n));
}
const uint8_t *zs_tls_plain(zs_tls_conn *c) { return c->plain; }

// Encrypts up to n bytes at p for the peer: how many it took (a record's worth at most).
int zs_tls_write(zs_tls_conn *c, const uint8_t *p, size_t n) {
    if (n > 0x7fffffff) n = 0x7fffffff;
    return outcome(c, mbedtls_ssl_write(&c->ssl, n ? p : (const uint8_t *)"", n));
}

// Tells the peer no more is coming.
int zs_tls_close_notify(zs_tls_conn *c) { return outcome(c, mbedtls_ssl_close_notify(&c->ssl)); }

// Why the last step that gave ZS_TLS_ERROR failed: the code's text, and for a certificate that
// didn't verify, what was wrong with it.
const char *zs_tls_conn_error(zs_tls_conn *c) {
    mbedtls_strerror(c->error, t_text, sizeof t_text);
    uint32_t flags = mbedtls_ssl_get_verify_result(&c->ssl);
    if (c->error == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED && flags != 0 && flags != (uint32_t)-1) {
        size_t at = strlen(t_text);
        if (at + 3 < sizeof t_text) {
            memcpy(t_text + at, ": ", 3);
            mbedtls_x509_crt_verify_info(t_text + at + 2, sizeof t_text - at - 2, "", flags);
            for (char *p = t_text + at + 2; *p; p++)
                if (*p == '\n') *p = p[1] ? ';' : 0;
        }
    }
    return t_text;
}
int zs_tls_conn_error_code(zs_tls_conn *c) { return c->error; }
