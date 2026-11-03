// An interpreter: a small imperative language is tokenized, parsed by recursive descent into a
// syntax tree (variables resolved to slots), and run by walking the tree.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *source =
    "count = 0;\n"
    "i = 2;\n"
    "while i < n {\n"
    "  prime = 1;\n"
    "  j = 2;\n"
    "  while j * j <= i {\n"
    "    if i % j == 0 { prime = 0; j = i; }\n"
    "    j = j + 1;\n"
    "  }\n"
    "  count = count + prime;\n"
    "  i = i + 1;\n"
    "}\n"
    "steps = 0;\n"
    "k = 1;\n"
    "while k < n / 4 {\n"
    "  x = k;\n"
    "  while x > 1 {\n"
    "    if x % 2 == 0 { x = x / 2; } else { x = 3 * x + 1; }\n"
    "    steps = steps + 1;\n"
    "  }\n"
    "  k = k + 1;\n"
    "}\n";

typedef enum { TNUM, TNAME, TSYM, TEND } TokenKind;
typedef struct { TokenKind kind; int64_t num; char text[16]; } Token;

static Token *tokens;
static size_t ntokens, pos;

static void tokenize(const char *s) {
  size_t cap = 64;
  tokens = malloc(cap * sizeof(Token));
  while (*s) {
    if (ntokens + 1 >= cap) tokens = realloc(tokens, (cap *= 2) * sizeof(Token));
    Token *t = &tokens[ntokens];
    memset(t, 0, sizeof *t);
    const char *start = s;
    if (*s == ' ' || *s == '\n' || *s == '\t' || *s == '\r') { s++; continue; }
    if (*s >= '0' && *s <= '9') {
      t->kind = TNUM;
      while (*s >= '0' && *s <= '9') t->num = t->num * 10 + (*s++ - '0');
    } else if (*s >= 'a' && *s <= 'z') {
      t->kind = TNAME;
      while (*s >= 'a' && *s <= 'z') s++;
      memcpy(t->text, start, (size_t)(s - start));
    } else {
      t->kind = TSYM;
      int two = (s[0] == '<' || s[0] == '>' || s[0] == '=' || s[0] == '!') && s[1] == '=';
      s += two ? 2 : 1;
      memcpy(t->text, start, (size_t)(s - start));
    }
    ntokens++;
  }
  tokens[ntokens].kind = TEND;
}

typedef enum { ADD, SUB, MUL, DIV, MOD, LT, LE, GT, GE, EQ, NE } Op;
typedef enum { NUM, VAR, BIN } ExprKind;
typedef struct Expr Expr;
struct Expr { ExprKind kind; Op op; int64_t value; Expr *a, *b; }; // value: NUM's, or VAR's slot

typedef enum { ASSIGN, WHILE, IF } StmtKind;
typedef struct Stmt Stmt;
struct Stmt { StmtKind kind; int slot; Expr *e; Stmt *body, *orelse, *next; };

static char names[64][16];
static int nnames;

static int slot(const char *name) {
  for (int i = 0; i < nnames; i++)
    if (strcmp(names[i], name) == 0) return i;
  strcpy(names[nnames], name);
  return nnames++;
}

static Token *peek(void) { return &tokens[pos]; }
static int isSym(const char *s) { return peek()->kind == TSYM && strcmp(peek()->text, s) == 0; }
static int isName(const char *s) { return peek()->kind == TNAME && strcmp(peek()->text, s) == 0; }
static void expect(const char *s) {
  if (!isSym(s)) { fprintf(stderr, "expected %s\n", s); exit(1); }
  pos++;
}

static Expr *node(ExprKind kind) {
  Expr *e = calloc(1, sizeof *e);
  e->kind = kind;
  return e;
}

static Expr *comparison(void);

static Expr *primary(void) {
  Token *t = peek();
  pos++;
  if (t->kind == TNUM) { Expr *e = node(NUM); e->value = t->num; return e; }
  if (t->kind == TNAME) { Expr *e = node(VAR); e->value = slot(t->text); return e; }
  if (t->kind == TSYM && strcmp(t->text, "(") == 0) {
    Expr *e = comparison();
    expect(")");
    return e;
  }
  fprintf(stderr, "unexpected %s\n", t->text);
  exit(1);
}

// a left-associative level: operands from `operand`, operators from the table
static Expr *binary(Expr *(*operand)(void), const char *const *syms, const Op *ops, int n) {
  Expr *left = operand();
  for (;;) {
    int k = -1;
    for (int i = 0; i < n && k < 0; i++)
      if (isSym(syms[i])) k = i;
    if (k < 0) return left;
    pos++;
    Expr *e = node(BIN);
    e->op = ops[k];
    e->a = left;
    e->b = operand();
    left = e;
  }
}

static Expr *product(void) {
  static const char *const syms[] = {"*", "/", "%"};
  static const Op ops[] = {MUL, DIV, MOD};
  return binary(primary, syms, ops, 3);
}
static Expr *sum(void) {
  static const char *const syms[] = {"+", "-"};
  static const Op ops[] = {ADD, SUB};
  return binary(product, syms, ops, 2);
}
static Expr *comparison(void) {
  static const char *const syms[] = {"<", "<=", ">", ">=", "==", "!="};
  static const Op ops[] = {LT, LE, GT, GE, EQ, NE};
  return binary(sum, syms, ops, 6);
}

static Stmt *statements(void);

static Stmt *block(void) {
  expect("{");
  Stmt *body = statements();
  expect("}");
  return body;
}

static Stmt *statement(void) {
  Stmt *s = calloc(1, sizeof *s);
  if (isName("while")) {
    pos++;
    s->kind = WHILE;
    s->e = comparison();
    s->body = block();
  } else if (isName("if")) {
    pos++;
    s->kind = IF;
    s->e = comparison();
    s->body = block();
    if (isName("else")) { pos++; s->orelse = block(); }
  } else if (peek()->kind == TNAME) {
    s->kind = ASSIGN;
    s->slot = slot(peek()->text);
    pos++;
    expect("=");
    s->e = comparison();
    expect(";");
  } else {
    fprintf(stderr, "unexpected %s\n", peek()->text);
    exit(1);
  }
  return s;
}

static Stmt *statements(void) {
  Stmt *first = NULL, **last = &first;
  while (peek()->kind != TEND && !isSym("}")) {
    *last = statement();
    last = &(*last)->next;
  }
  return first;
}

static int64_t env[64];

static int64_t eval(const Expr *e) {
  switch (e->kind) {
  case NUM: return e->value;
  case VAR: return env[e->value];
  case BIN: break;
  }
  int64_t x = eval(e->a), y = eval(e->b);
  switch (e->op) {
  case ADD: return x + y;
  case SUB: return x - y;
  case MUL: return x * y;
  case DIV: return x / y;
  case MOD: return x % y;
  case LT: return x < y;
  case LE: return x <= y;
  case GT: return x > y;
  case GE: return x >= y;
  case EQ: return x == y;
  case NE: return x != y;
  }
  return 0;
}

static void exec(const Stmt *s) {
  for (; s; s = s->next) {
    switch (s->kind) {
    case ASSIGN: env[s->slot] = eval(s->e); break;
    case WHILE: while (eval(s->e)) exec(s->body); break;
    case IF: if (eval(s->e)) exec(s->body); else exec(s->orelse); break;
    }
  }
}

int main(int argc, char **argv) {
  int64_t n = argc > 1 ? atoll(argv[1]) : 300000;
  tokenize(source);
  slot("n");
  Stmt *program = statements();
  env[0] = n;
  exec(program);
  for (int i = 0; i < nnames; i++) printf("%s = %lld\n", names[i], (long long)env[i]);
  return 0; // the tree lives as long as the program
}
