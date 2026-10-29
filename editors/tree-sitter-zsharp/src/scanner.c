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

static bool is_op_char(int32_t c) { return c > 0 && c < 128 && strchr("!%&*+-./<=>?@^|~$", (int)c) != NULL; }

// the language's own symbols made of operator characters; another run of them is a custom
// operator (as in the compiler's lexer)
static const char *const SYMBOLS[] = {"&&&", "|||", "^^^", "<<<", ">>>", "~~~", "...", "..", "->", "<-", "|>",
                                      ">>",  "<>",  "<=",  ">=",  "&&",  "||",  "?",   "|",  ".",  "=",  "<",
                                      ">",   "+",   "-",   "*",   "/",   "%",   "@",   "^",  NULL};

static bool is_custom_operator(const char *run) {
    if (!*run) return false;
    for (int i = 0; SYMBOLS[i]; i++)
        if (strcmp(run, SYMBOLS[i]) == 0) return false;
    for (const char *c = run; *c; c++)
        if (*c != '.') return true;
    return false;
}

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

    if (recovering) return false;

    // the operator characters coming next (|] is a closer)
    char run[16];
    int n = 0;
    bool closer = lexer->lookahead == ')' || lexer->lookahead == ']' || lexer->lookahead == '}';
    while (!closer && n < 15 && is_op_char(lexer->lookahead)) {
        char c = (char)lexer->lookahead;
        skip(lexer);
        if ((c == '$' && lexer->lookahead == '"') || (c == '/' && lexer->lookahead == '/')) break; // $"…", //
        if (c == '|' && n == 0 && lexer->lookahead == ']') closer = true;
        run[n++] = c;
    }
    run[n] = 0;

    // a closing bracket ends the blocks opened inside it, as in the compiler: `(fun x ->`, the
    // body on deeper lines, then `)`
    if (closer) {
        if (valid[DEDENT] && s->count > 1) {
            s->count--;
            lexer->result_symbol = DEDENT;
            return true;
        }
        return false;
    }

    if (!at_line_start) return false;

    // a line starting with |>, || && ||| &&& ^^^, or an infix custom operator (>>=, <|>, .>>)
    // continues the previous one; a prefix operator (! but not !=, or ~) starts an expression
    bool prefix = (run[0] == '!' && run[1] != '=') || run[0] == '~';
    bool logic = strcmp(run, "||") == 0 || strcmp(run, "&&") == 0 || strcmp(run, "|||") == 0 ||
                 strcmp(run, "&&&") == 0 || strcmp(run, "^^^") == 0;
    if ((n >= 2 && run[0] == '|' && run[1] == '>') || logic || (is_custom_operator(run) && !prefix)) return false;

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
