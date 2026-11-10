# 6. Patterns

A pattern is matched against a value: it either matches, binding its variables to parts of
the value, or does not. Matching has no side effects, except that an active pattern calls its
function.

## 6.1 Syntax

```text
pattern      = or-pattern { 'as' ID } ;
or-pattern   = tuple-pattern { '|' tuple-pattern } ;
tuple-pattern = cons-pattern { ',' cons-pattern } ;
cons-pattern = app-pattern [ '::' cons-pattern ] ;
app-pattern  = case-name atom-pattern { atom-pattern }
             | atom-pattern ;
atom-pattern = '_' | ID
             | INT | '-' INT | CHAR | STR | 'true' | 'false' | '(' ')'
             | '(' pattern ')'
             | '(' ID '=' pattern { ( ',' | ';' ) ID '=' pattern } ')'
             | '[' [ pattern { ';' pattern } ] ']'
             | '{' ID '=' pattern { ';' ID '=' pattern } [ ';' ] '}' ;
```

`as` binds loosest, then `|`, then `,`, then `::`; a tuple pattern needs no parentheses. A
`case-name` is an identifier that starts with an upper-case ASCII letter or is qualified
([§1.3](01-lexical.md#13-identifiers)).

## 6.2 Forms

| Pattern | Matches | Binds |
|---|---|---|
| `_` | any value | nothing |
| `x` | any value, unless `x` names a case or an active pattern's case in scope | `x` |
| `42`, `-1`, `'a'`, `"s"`, `true`, `()` | the value equal to the literal | nothing |
| `p1, p2, …` | a tuple whose parts match | the parts' variables |
| `C` | the case `C` without fields | nothing |
| `C p` | the case `C`, its fields matching `p`: one field as itself, several as a tuple `C (p1, p2)` | `p`'s |
| `C(f = p, …)` | the case `C`, its named fields matching; fields left out match anything | the patterns' |
| `{ f = p; … }` | a record whose named fields match; fields left out match anything | the patterns' |
| `[]` | the empty list | nothing |
| `p :: ps` | a non-empty list, head and tail matching | both |
| `[p1; …; pn]` | a list of exactly `n` elements | the elements' |
| `p \| q` | what `p` or `q` matches, `p` tried first | see below |
| `p as x` | what `p` matches | `p`'s, and `x` the whole value |
| `A p`, `A` for an active pattern | [§6.5](#65-active-patterns) | |

- **Literals.** An integer literal has the type of what it is matched against; a negative
  literal needs a signed type. There are no float literal patterns and no byte-string
  patterns; compare those with a guard.
- **Variables.** A pattern must not bind one variable twice.
- **Or-patterns.** Both sides must bind the same variables, each at the same type on both
  sides.
- **Record patterns** name at least one field, and select their record type as a record
  expression does ([§5.4](05-expressions.md#54-records)).
- **Types.** A pattern is checked against the type of the value; parameters alone may carry
  an annotation, as `(x: T)` ([§4.1](04-declarations.md#41-let)).
- Arrays, spans, maps, strings (by character) and `ref`s have no patterns.
- A `[<CLayout>]` union cannot be matched ([§11.3](11-low-level.md#113-layout)).

## 6.3 Where patterns appear

```text
match    = 'match' scrutinee 'with' clauses ;
scrutinee = expression { ',' expression } ;                 several: a tuple
clauses  = [ '|' ] clause { '|' clause } ;                  on one line, or one per line
clause   = pattern [ 'when' expression ] '->' block ;
```

**`match e with clauses`** evaluates `e`, then tries the clauses in order. The first clause
whose pattern matches and whose guard, if any, is `true` is taken: its body is evaluated with
the pattern's variables bound, and is the value of the `match`. All bodies have one type.

- A **guard** `when c` is a `bool` expression over the pattern's variables. It is evaluated
  only when the pattern matches. A guard must not perform an effect.
- `function clauses` is `fun x -> match x with clauses` for a fresh `x`.
- Clauses may be on one line (`match o with Some x -> x | None -> 0`) or one per line; the
  first `|` is optional.

**Irrefutable positions.** In a `let`, a parameter of a function or a lambda, and a `for`
loop, the pattern must match every value of its type; otherwise it is an error naming a value
it misses (`a let's pattern must match every value, and this one misses None`). There is no
`let … else`.

```fsharp
let (x, y) = point                        // a tuple
let norm { x = x; y = y } = x * x + y * y // a record
let next (UserId n) = UserId (n + 1)      // a one-case union
for (key, value) in table do …            // each element
```

**Handler clauses** take atomic patterns for an operation's arguments
([§8.4](08-effects.md#84-handlers)), which must be irrefutable too.

## 6.4 Exhaustiveness and redundancy

Both are **errors**, not warnings.

- **A `match` must be exhaustive:** for every value of the scrutinee's type some clause
  without a guard matches. The error gives an example of a value not matched
  (`match is not exhaustive; missing case: (true, None)`).
- **Every clause must be reachable:** a clause whose pattern matches only values that earlier
  unguarded clauses already match is an error (`this match case is never reached`).

For this analysis:

- a clause with a guard matches nothing (it never makes a match exhaustive, and never makes a
  later clause unreachable);
- the integer types, `char` and `string` have more values than literals can list, so a match
  on literals needs a clause for the rest (`missing case: _`);
- a total active pattern's cases are a complete set; a partial active pattern is a guard
  ([§6.5](#65-active-patterns)).

## 6.5 Active patterns

An active pattern is a function whose result decides which pattern matched.

```text
active-pattern-name = '(' '|' ID { '|' ID } '|' ')'           total
                    | '(' '|' ID '|' '_' '|' ')' ;            partial
```

**Total:** `let (|Even|Odd|) n = if n % 2 = 0 then Even else Odd`.

- The body's result is one of the named cases, each optionally applied to a value
  (`Positive n`).
- In a pattern, `Even`, or `Positive p`, matches when the function, applied to the value
  being matched, gives that case, and `p` is matched against the case's value.
- The cases are a closed set: they count for exhaustiveness as a union's do, and a `match`
  over them needs all of them.
- A single-case total pattern, `(|Name|)`, converts a value as it is matched.

**Partial:** `let (|Int|_|) (s: string) = String.parseInt s`.

- The function returns an `option`. `Int n` matches when the result is `Some v`, with `n`
  matched against `v`.
- A partial pattern may fail to match, so it counts as a guard does.

**Parameterized:** an active pattern function may take parameters before the value matched:
`let (|DivBy|_|) d n = if n % d = 0 then Some (n / d) else None`. In a pattern, the atoms
after the name are the arguments, then the pattern for the result: `DivBy 3 q`. The arguments
are literals or names in scope.

Active patterns are declared at the top level or in a module, obey the scope rules of other
names, and may be used wherever a refutable pattern is allowed. A function may be called
once per clause that uses it; a program must not depend on how many times.
