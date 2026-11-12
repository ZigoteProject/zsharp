// What packages/http asks of llhttp (c/llhttp, Node's parser): llhttp calls back as it finds
// each part of a message, and this collects the parts so the Z# side reads a whole head at
// once. One zs_http parses the messages of one connection, requests or responses.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "llhttp.h"

enum { ZS_HTTP_MORE = 0, ZS_HTTP_COMPLETE = 1, ZS_HTTP_ERROR = -1 };
enum { ZS_HTTP_MAX_HEADERS = 128 };

typedef struct { size_t at, len; } zs_span;

typedef struct zs_http {
    llhttp_t parser;
    llhttp_settings_t settings;
    char *text; // the URL, then each header's name and value, back to back
    size_t text_len, text_cap, max_head;
    zs_span url, names[ZS_HTTP_MAX_HEADERS], values[ZS_HTTP_MAX_HEADERS];
    size_t headers;   // complete ones
    uint8_t *body;    // the body's bytes not taken yet
    size_t body_len, body_cap;
    size_t consumed;  // of the last feed
    size_t head_fed;  // bytes fed since the message began, until its head is complete
    int head_done, no_body;
    const char *why;  // an error of this file's, else llhttp's
} zs_http;

static int fail(zs_http *h, const char *why) {
    h->why = why;
    return HPE_USER;
}

// appends to the text, within the head's limit
static int keep(zs_http *h, zs_span *part, const char *at, size_t n) {
    if (n > h->max_head || h->text_len > h->max_head - n) return fail(h, "the head is too large");
    if (h->text_len + n > h->text_cap) {
        size_t want = h->text_cap ? h->text_cap : 1024;
        while (want < h->text_len + n) want *= 2;
        char *p = realloc(h->text, want);
        if (!p) return fail(h, "out of memory");
        h->text = p;
        h->text_cap = want;
    }
    if (part->len == 0) part->at = h->text_len;
    memcpy(h->text + h->text_len, at, n);
    h->text_len += n;
    part->len += n;
    return 0;
}

static zs_http *of(llhttp_t *p) { return (zs_http *)p->data; }

static int on_url(llhttp_t *p, const char *at, size_t n) { return keep(of(p), &of(p)->url, at, n); }

static int on_header_field(llhttp_t *p, const char *at, size_t n) {
    zs_http *h = of(p);
    if (h->headers >= ZS_HTTP_MAX_HEADERS) return fail(h, "too many headers");
    return keep(h, &h->names[h->headers], at, n);
}

static int on_header_value(llhttp_t *p, const char *at, size_t n) {
    zs_http *h = of(p);
    return keep(h, &h->values[h->headers], at, n);
}

static int on_header_value_complete(llhttp_t *p) {
    of(p)->headers++;
    return 0;
}

// 1 tells llhttp the message has no body whatever its headers say (the answer to a HEAD)
static int on_headers_complete(llhttp_t *p) {
    of(p)->head_done = 1;
    return of(p)->no_body ? 1 : 0;
}

static int on_body(llhttp_t *p, const char *at, size_t n) {
    zs_http *h = of(p);
    if (n > SIZE_MAX - h->body_len) return fail(h, "out of memory");
    if (h->body_len + n > h->body_cap) {
        size_t want = h->body_cap ? h->body_cap : 4096;
        while (want < h->body_len + n) {
            if (want > SIZE_MAX / 2) return fail(h, "out of memory");
            want *= 2;
        }
        uint8_t *b = realloc(h->body, want);
        if (!b) return fail(h, "out of memory");
        h->body = b;
        h->body_cap = want;
    }
    memcpy(h->body + h->body_len, at, n);
    h->body_len += n;
    return 0;
}

// the parser stops at a message's end, so the bytes after it wait for zs_http_next
static int on_message_complete(llhttp_t *p) {
    (void)p;
    return HPE_PAUSED;
}

// A parser of requests (or of responses), a head limited to max_head bytes of URL and headers.
// NULL when there's no memory.
zs_http *zs_http_new(int responses, size_t max_head) {
    zs_http *h = calloc(1, sizeof *h);
    if (!h) return NULL;
    llhttp_settings_init(&h->settings);
    h->settings.on_url = on_url;
    h->settings.on_header_field = on_header_field;
    h->settings.on_header_value = on_header_value;
    h->settings.on_header_value_complete = on_header_value_complete;
    h->settings.on_headers_complete = on_headers_complete;
    h->settings.on_body = on_body;
    h->settings.on_message_complete = on_message_complete;
    llhttp_init(&h->parser, responses ? HTTP_RESPONSE : HTTP_REQUEST, &h->settings);
    h->parser.data = h;
    h->max_head = max_head;
    return h;
}

void zs_http_free(zs_http *h) {
    free(h->text);
    free(h->body);
    free(h);
}

// The next message's head has no body after it (a response to HEAD).
void zs_http_no_body(zs_http *h, int yes) { h->no_body = yes; }

static int result(zs_http *h, llhttp_errno_t e, const char *data, size_t n) {
    if (e == HPE_OK) {
        h->consumed = n;
        // a head that never ends is cut off here; the limit on its parts alone would let the
        // request line's method and spaces grow without end
        if (!h->head_done && (h->head_fed += n) > h->max_head + 1024) {
            h->why = "the head is too large";
            return ZS_HTTP_ERROR;
        }
        return ZS_HTTP_MORE;
    }
    if (e == HPE_PAUSED) {
        h->consumed = data ? (size_t)(llhttp_get_error_pos(&h->parser) - data) : 0;
        return ZS_HTTP_COMPLETE;
    }
    if (e == HPE_PAUSED_UPGRADE) h->why = "an upgrade to another protocol isn't supported";
    return ZS_HTTP_ERROR;
}

// Parses n bytes at data: ZS_HTTP_MORE when the message isn't whole yet, ZS_HTTP_COMPLETE when
// it is (zs_http_consumed says how many of the bytes were its), ZS_HTTP_ERROR (zs_http_error).
int zs_http_feed(zs_http *h, const uint8_t *data, size_t n) {
    return result(h, llhttp_execute(&h->parser, n ? (const char *)data : "", n), (const char *)data, n);
}

// The connection ended: ZS_HTTP_COMPLETE when that ends a message whose body runs to the
// end, ZS_HTTP_MORE when no message had begun, ZS_HTTP_ERROR when one was cut short.
int zs_http_finish(zs_http *h) {
    llhttp_errno_t e = llhttp_finish(&h->parser);
    if (e == HPE_PAUSED) return ZS_HTTP_COMPLETE;
    if (e != HPE_OK) return ZS_HTTP_ERROR;
    return h->head_done ? ZS_HTTP_COMPLETE : ZS_HTTP_MORE;
}

// After ZS_HTTP_COMPLETE: forgets the message, for the next one on the connection.
void zs_http_next(zs_http *h) {
    h->text_len = h->body_len = h->headers = h->head_fed = 0;
    h->head_done = h->no_body = 0;
    h->url.len = 0;
    memset(h->names, 0, sizeof h->names);
    memset(h->values, 0, sizeof h->values);
    llhttp_resume(&h->parser);
}

size_t zs_http_consumed(zs_http *h) { return h->consumed; }
int zs_http_head_done(zs_http *h) { return h->head_done; }
const char *zs_http_error(zs_http *h) {
    if (h->why) return h->why;
    const char *reason = llhttp_get_error_reason(&h->parser);
    return reason && *reason ? reason : llhttp_errno_name(llhttp_get_errno(&h->parser));
}

// The head, once zs_http_head_done: a request's method and URL, a response's status, whether
// the connection may carry another message, and the headers in order.
const char *zs_http_method(zs_http *h) { return llhttp_method_name((llhttp_method_t)llhttp_get_method(&h->parser)); }
int zs_http_status(zs_http *h) { return llhttp_get_status_code(&h->parser); }
int zs_http_keep_alive(zs_http *h) { return llhttp_should_keep_alive(&h->parser); }
// 0 for a message of HTTP/1.0, which knows no chunks: a streamed answer to it ends with the connection
int zs_http_minor(zs_http *h) { return llhttp_get_http_minor(&h->parser); }
const uint8_t *zs_http_url(zs_http *h) { return (const uint8_t *)h->text + h->url.at; }
size_t zs_http_url_length(zs_http *h) { return h->url.len; }
size_t zs_http_headers(zs_http *h) { return h->headers; }
const uint8_t *zs_http_name(zs_http *h, size_t i) { return (const uint8_t *)h->text + h->names[i].at; }
size_t zs_http_name_length(zs_http *h, size_t i) { return i < h->headers ? h->names[i].len : 0; }
const uint8_t *zs_http_value(zs_http *h, size_t i) { return (const uint8_t *)h->text + h->values[i].at; }
size_t zs_http_value_length(zs_http *h, size_t i) { return i < h->headers ? h->values[i].len : 0; }

// The body's bytes parsed and not taken yet, until zs_http_body_taken.
const uint8_t *zs_http_body(zs_http *h) { return h->body; }
size_t zs_http_body_length(zs_http *h) { return h->body_len; }
void zs_http_body_taken(zs_http *h) { h->body_len = 0; }
