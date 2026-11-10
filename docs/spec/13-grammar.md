# 13. Grammar

The collected grammar, in the notation of [the introduction](README.md#notation). It is
written over the tokens of [chapter 1](01-lexical.md), layout tokens included, and describes
the language the reference parser (`src/Syntax/Parser.zs`) accepts. Where a rule depends on
context that BNF cannot state (adjacency, the case of an identifier, a contextual word), the
note at its right says so and the chapter cited is normative.

`block` means: one form on the same line, or `INDENT` forms separated by `NEWLINE` `DEDENT`.

## 13.1 Files and declarations

```text
file          = { declaration NEWLINE } ;
declaration   = [ attributes [ NEWLINE ] ] plain-decl ;
plain-decl    = 'module' ID                                         first line only
              | 'namespace' ID                                      first line only
              | 'module' ID '=' INDENT { declaration NEWLINE } DEDENT
              | 'module' ID '=' import
              | 'open' ID
              | let-decl | type-decl | trait-decl | impl-decl | derive-decl
              | effect-decl | extern-decl | import | assert-decl ;

attributes    = '[<' attribute { ';' attribute } '>]' ;
attribute     = ID [ STR | INT | '(' attr-arg { ',' attr-arg } ')' ] ;
attr-arg      = ID | STR ;

let-decl      = 'let' [ 'rec' ] [ 'private' ] binder { parameter } [ ':' type ] '=' block
                { NEWLINE 'and' [ 'private' ] ID parameter { parameter } [ ':' type ] '=' block }
              | 'let' [ 'private' ] pattern [ ':' type ] '=' block ;
binder        = ID | '(' OP ')' | '(' '|' ID { '|' ID } '|' ')' | '(' '|' ID '|' '_' '|' ')' ;
parameter     = '(' ID ':' type { ',' ID ':' type } ')' | atom-pattern ;

type-decl     = 'type' type-def { NEWLINE 'and' type-def } ;
type-def      = [ 'private' ] ID [ type-params ] [ type-body ] ;
type-params   = '<' TYVAR { ',' TYVAR } '>' ;
type-body     = '=' type                                            an alias: §4.3
              | '=' ( record-body | union-body ) [ members ]        same line or indented
              | '=' members                                         members only
              | 'with' members ;                                    an extension
record-body   = '{' field { ';' field } [ ';' ] '}' ;
field         = [ attributes ] ID ':' type [ '=' expression ] ;
union-body    = [ '|' ] case { '|' case } ;                         one per line allowed
case          = ID [ 'of' case-field { '*' case-field } ] ;
case-field    = [ ID ':' ] atom-type ;
members       = [ 'with' ] { member } ;                             one per line
member        = [ 'static' ] 'member' member-name [ member-params ] [ ':' type ] '=' block ;
member-name   = ID '.' ID | ID ;                                    the second form when static
member-params = '(' [ member-param { ',' member-param } ] ')' ;
member-param  = [ '?' ] ID [ ':' type ] [ '=' expression ] ;

trait-decl    = 'trait' ID type-params '=' INDENT { 'abstract' ID ':' type NEWLINE } DEDENT ;
impl-decl     = 'impl' ID '<' type { ',' type } '>' '=' INDENT { definition NEWLINE } DEDENT ;
derive-decl   = 'derive' ID '=' INDENT { definition NEWLINE } DEDENT
              | 'derive' ID '=' ID { ',' ID } ;
definition    = 'let' ID { parameter } [ ':' type ] '=' block ;
effect-decl   = 'effect' ID [ type-params ] '=' block( 'abstract' ID ':' type ) ;

extern-decl   = 'extern' ID ':' extern-type { '->' extern-type } ;
extern-type   = tuple-type | '...' ;
import        = 'import' ID STR
              | 'import' ID '(' STR { ',' ID '=' import-const } ')' ;
import-const  = STR | INT | FLOAT | 'true' | 'false' ;
assert-decl   = 'assert' expression ;
```

## 13.2 Types

```text
type          = tuple-type [ '->' type | '/' row ] ;
tuple-type    = atom-type { '*' atom-type } ;
atom-type     = ( TYVAR
                | INT                                               fixed's length only
                | 'dyn' ID
                | ID '<' measure '>'                                ID a number type
                | ID [ '<' type { ',' type } '>' ]
                | '(' type ')' )
                { ID } ;                                            postfix: int list
row           = '<>' | TYVAR | label
              | '<' label { ',' label } [ '|' TYVAR ] '>' ;
label         = ID [ '<' type { ',' type } '>' ] ;
measure       = unit-term { [ '*' | '/' ] unit-term } ;
unit-term     = ( ID | TYVAR | '1' | '(' measure ')' ) [ '^' [ '-' ] INT ] ;
```

## 13.3 Patterns

```text
pattern       = or-pattern { 'as' ID } ;
or-pattern    = tuple-pattern { '|' tuple-pattern } ;
tuple-pattern = cons-pattern { ',' cons-pattern } ;
cons-pattern  = app-pattern [ '::' cons-pattern ] ;
app-pattern   = ID atom-pattern { atom-pattern }                    ID a case name: §1.3
              | atom-pattern ;
atom-pattern  = ID                                                  `_` is the wildcard
              | INT | '-' INT | CHAR | STR | 'true' | 'false'
              | '(' ')' | '(' pattern ')'
              | '(' ID '=' pattern { ( ',' | ';' ) ID '=' pattern } ')'
              | '[' [ pattern { ';' pattern } ] ']'
              | '{' ID '=' pattern { ';' ID '=' pattern } [ ';' ] '}' ;
```

## 13.4 Expressions

```text
statements    = statement { NEWLINE statement } ;
statement     = 'let' pattern [ ':' type ] '=' block
              | 'let' [ 'rec' ] local-binder { parameter } [ ':' type ] '=' block
                { NEWLINE 'and' ID parameter { parameter } [ ':' type ] '=' block }
              | 'let' 'mutable' ID [ ':' type ] '=' block
              | 'use' ID '=' block
              | 'let' '!' pattern '=' block                         in a task or builder
              | 'do' '!' block                                      in a task or builder
              | 'return' [ '!' ] block                              in a task or builder
              | expression [ '<-' expression | assign-op expression ] ;
local-binder  = ID | '(' OP ')' ;
assign-op     = '+=' | '-=' | '*=' | '/=' | '%=' | '&&&=' | '|||=' | '^^^=' ;

expression    = 'let' … 'in' expression                             a binding within a line
              | 'if' expression 'then' block [ 'else' block ]
              | 'match' scrutinee 'with' clauses
              | 'function' clauses
              | 'fun' parameter { parameter } '->' block
              | 'while' expression 'do' block
              | 'for' ID 'in' op-expr '..' op-expr [ '..' op-expr ] 'do' block
              | 'for' pattern 'in' op-expr 'do' block
              | 'break' | 'continue'                                leaving a loop: §5.9
              | 'return' [ expression ]                             not in a computation expression
              | 'handle' block 'with' handler-clauses               `handle`: §8.4
              | 'unsafe' block
              | 'yield' [ '!' ] expression                          in seq or a list expression
              | op-expr ;
scrutinee     = expression { ',' expression } ;
clauses       = [ '|' ] clause { '|' clause } ;                     one per line allowed
clause        = pattern [ 'when' expression ] '->' block ;
handler-clauses = { '|' ( ID { atom-pattern } ',' ID | 'return' pattern ) '->' block } ;

op-expr       = or-expr ;
or-expr       = and-expr [ '||' or-expr ] ;
and-expr      = cmp-expr [ '&&' and-expr ] ;
cmp-expr      = bor-expr { ( '=' | '<>' | '<' | '>' | '<=' | '>=' | '|>' | '>>' | OP ) bor-expr } ;
bor-expr      = xor-expr { '|||' xor-expr } ;
xor-expr      = band-expr { '^^^' band-expr } ;
band-expr     = shift-expr { '&&&' shift-expr } ;
shift-expr    = cons-expr { ( '<<<' | '>>>' ) cons-expr } ;
cons-expr     = add-expr [ ( '::' | '@' | OP ) cons-expr ] ;
add-expr      = mul-expr { ( '+' | '-' | OP ) mul-expr } ;
mul-expr      = pow-expr { ( '*' | '/' | '%' | OP ) pow-expr } ;
pow-expr      = unary [ OP pow-expr ] ;
unary         = ( '-' | '~~~' | 'not' ) unary | application ;
application   = postfix { postfix } [ '?' ] ;
postfix       = primary { '.' ID | '.' '[' index ']' | '(' … ')' } ;   '(' adjacent: §5.5
index         = expression | [ expression ] '..' [ expression ] ;
```

An `OP` at each level is a custom operator whose first character puts it there
([§5.7](05-expressions.md#57-custom-operators)). The right operand of a binary operator may
be a `fun` or `function` expression.

```text
primary       = INT [ '<' measure '>' ] | FLOAT [ '<' measure '>' ]   '<' adjacent
              | CHAR | STR | INTERP | 'true' | 'false'
              | ID
              | OP postfix                                          a prefix operator
              | '(' ')'
              | '(' expression ')'
              | '(' expression ',' expression { ',' expression } ')'
              | '(' expression ':' type ')'
              | '(' operator ')'                                    an operator as a function
              | '{' field-init { ';' field-init } [ ';' ] '}'
              | '{' expression 'with' field-init { ';' field-init } [ ';' ] '}'
              | '[' list-body ']' | '[|' list-body '|]'
              | ID '{' ce-body '}'                                  a computation: §9
              | ( 'sizeof' | 'alignof' ) '<' type '>'               '<' adjacent
              | 'offsetof' '<' type '>' STR ;
field-init    = ID '=' expression ;
list-body     = [ expression { ';' expression } [ ';' ] ]
              | expression '..' expression [ '..' expression ]
              | comprehension ;                                     starts with for or yield
comprehension = comp-stmt { ( ';' | NEWLINE ) comp-stmt } ;
comp-stmt     = 'for' pattern 'in' op-expr ( '->' block | 'do' comp-block )
              | 'for' ID 'in' op-expr '..' op-expr [ '..' op-expr ] ( '->' block | 'do' comp-block )
              | 'if' expression 'then' comp-block [ 'else' comp-block ]
              | 'match' scrutinee 'with' clauses                    bodies are comp-blocks
              | 'let' pattern [ ':' type ] '=' block
              | 'yield' [ '!' ] expression
              | expression [ '<-' expression | assign-op expression ] ;
comp-block    = block( comp-stmt ) ;
ce-body       = block( statement ) ;                                with the builder forms
```

## 13.5 Ambiguities and their resolution

| Text | Resolution |
|---|---|
| `f -x` / `f - x` / `f-x` | negation of an argument / subtraction / subtraction ([§1.5](01-lexical.md#15-symbols-and-operators)) |
| `f x` / `f(x)` | application; the second binds like `.` ([§5.5](05-expressions.md#55-postfix-forms)) |
| `1.0<m>` / `a < m > b` | a measured literal only when `<` is adjacent to the number and a measure and `>` follow |
| `x.y` / `X.y` | member access / one qualified name ([§1.3](01-lexical.md#13-identifiers)) |
| `'a'` / `'a` | a character / a type variable ([§1.7](01-lexical.md#17-character-literals)) |
| `w { … }` | a computation expression when the brace's contents begin as one ([chapter 9](09-computations.md)); else an application to a record |
| `{ a = b }` | a record expression when it starts `ID =`; `{ e with … }` otherwise |
| `[ for …` , `[ yield …` | a list expression; any other content is a literal or a range |
| `name = e` in a method's argument list | a named argument when `name` is a parameter of the method; else equality |
| `x = e` as a statement | equality (and an error advising `<-`), never assignment |
| `let F p = …` with `F` upper-case | a pattern binding of the case `F`, not a function ([§1.3](01-lexical.md#13-identifiers)) |
| `type T = A` / `type T = \| A` | an alias of `A` / a union with the case `A` |
| `handle` | a handler when a block, or an expression and `with`, follows on the line; else a name |
| `>>` in `list<list<int>>` | two closers ([§1.5](01-lexical.md#15-symbols-and-operators)) |
| `a / b` in a type | a row after a result type; division is not a type operator |
