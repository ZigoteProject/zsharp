// External scanner for Z#: the offside rule. At the start of a line it compares the line's
// indentation with the enclosing block's and produces zero-width _indent, _dedent or _newline
// tokens, but only those the grammar accepts there (so none appear inside brackets, except
// newlines where lists and records take them as separators). Modelled on tree-sitter-python.
#include "tree_sitter/parser.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum TokenType { NEWLINE, INDENT, DEDENT, ERROR_SENTINEL };

#define MAX_DEPTH 255

typedef struct {
    uint16_t indents[MAX_DEPTH];
    uint8_t count;
} Scanner;

void *tree_sitter_zsharp_external_scanner_create(void) {
    Scanner *s = calloc(1, sizeof(Scanner));
    s->indents[0] = 0;
    s->count = 1;
    return s;
}

void tree_sitter_zsharp_external_scanner_destroy(void *payload) { free(payload); }

unsigned tree_sitter_zsharp_external_scanner_serialize(void *payload, char *buffer) {
    Scanner *s = payload;
    unsigned size = 1 + s->count * sizeof(uint16_t);
    if (size > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) return 0;
    buffer[0] = (char)s->count;
    memcpy(buffer + 1, s->indents, s->count * sizeof(uint16_t));
    return size;
}

void tree_sitter_zsharp_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
    Scanner *s = payload;
    s->indents[0] = 0;
    s->count = 1;
    if (length > 0) {
        s->count = (uint8_t)buffer[0];
        if (s->count == 0) s->count = 1;
        memcpy(s->indents, buffer + 1, s->count * sizeof(uint16_t));
    }
}

static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

bool tree_sitter_zsharp_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid) {
    Scanner *s = payload;
    bool recovering = valid[ERROR_SENTINEL];

    lexer->mark_end(lexer); // every token here is zero-width
    bool at_line_start = false;
    uint32_t indent = 0;

    for (;;) {
        if (lexer->lookahead == '\n') {
            at_line_start = true;
            indent = 0;
            skip(lexer);
        } else if (lexer->lookahead == ' ') {
            indent++;
            skip(lexer);
        } else if (lexer->lookahead == '\r' || lexer->lookahead == '\f') {
            indent = 0;
            skip(lexer);
        } else if (lexer->lookahead == '\t') {
            indent += 8;
            skip(lexer);
        } else if (lexer->lookahead == '/' && at_line_start) {
            // a line holding only a comment doesn't count as code
            skip(lexer);
            if (lexer->lookahead != '/') break;
            while (lexer->lookahead && lexer->lookahead != '\n' && !lexer->eof(lexer)) skip(lexer);
        } else if (lexer->eof(lexer)) {
            indent = 0;
            at_line_start = true;
            break;
        } else {
            break;
        }
    }

    if (!at_line_start || recovering) return false;

    // a line starting with |> continues the previous one
    if (lexer->lookahead == '|') {
        skip(lexer);
        if (lexer->lookahead == '>') return false;
    }

    uint16_t current = s->indents[s->count - 1];

    if (valid[INDENT] && indent > current && s->count < MAX_DEPTH) {
        s->indents[s->count++] = (uint16_t)indent;
        lexer->result_symbol = INDENT;
        return true;
    }

    if (valid[DEDENT] && indent < current && s->count > 1) {
        s->count--;
        lexer->result_symbol = DEDENT;
        return true;
    }

    // a deeper line where no block can start is a continuation: inside { } and [ ] it
    // separates fields and items, as in the compiler
    if (valid[NEWLINE] && (indent <= current || !valid[INDENT])) {
        lexer->result_symbol = NEWLINE;
        return true;
    }

    return false;
}
