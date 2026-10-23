# Self-hosting: the Z# compiler's front end against the F# compiler's

**Question:** 0020's second criterion, phase 11's gate: is a program of the compiler's shape,
written in Z#, within 1.5× of the F# compiler? It's measured on code the compiler keeps:
`compiler/src/Syntax/Lexer.zs` and `Parser.zs`, on 0019's tree, against the F# compiler's
lexer and parser over the same files; and the checker, `compiler/src/Infer/`, against `Typer` on
the same programs.

**Answer:** yes. The Z# lexer and parser, the AST included, take 0.6–0.9× the F# compiler's
time on the compiler's own sources and 1.0× over every `.zs` file in the repository. They make
the same tokens, the same tree and the same AST for all 303 files (`compiler/tests/lexer.sh`,
`parser.sh`, `ast.sh`), and the same first error for the files that have one.
- **First run:** 1.5× and 2.6×. The parser showed the F# compiler three inefficiencies, all
  fixed there (below), and with them the parser's state, a record of 22 fields passed to every
  function, stopped being copied field by field on each call.
- **The checker:** the whole of it (`Infer`, `Typer` ported, not a subset), checking a program
  and the library it uses, takes 0.8× the F# compiler's time (below). It gives the F# compiler's
  errors on 90 of the 93 `.err` tests (the other three are errors of passes after checking, and
  of `import c`) and checks 100 of the 105 programs with an `.out` cleanly (the other five import
  C): `compiler/tests/errors.sh`.

## Setup

| | |
|---|---|
| Machine | AMD Ryzen 7 PRO 8840U, 16 threads, Fedora 44 in the dev container (`./dev`) |
| Z# | `compiler/` built by the F# compiler (`zs build`: default optimization, ThinLTO with the runtime) |
| F# | the F# compiler's `Release` build on .NET 10, after one run for the JIT |
| What's timed | lexing and parsing, in process, after the files are read: the best of ten runs (`zs parse-time <files>` in both) |
| Files | `compiler/src` (20 files, 6,601 lines), and every `.zs` file under `tests`, `lib`, `examples`, `packages` and `compiler` that the F# parser takes (303 files, 17,289 lines; it stops at a file's first error) |

**What each makes:** the F# compiler's lexer and parser make tokens with their trivia, the AST,
the lossless tree (0019's F2) and the positions table. The Z# ones make tokens (a kind, an offset
and a length), the same lossless tree as a few arrays indexed by node ids, and the AST in the F#
compiler's shapes, its places token indices into the tree. Both parse each interpolated string's
holes, for their errors.

## Results

| Files | F# | Z# | Z# / F# |
|---|---|---|---|
| `compiler/src`, 6,601 lines | 47–69 ms | 42–43 ms | 0.6–0.9 |
| the repository, 17,289 lines | 115–121 ms | 117–121 ms | 1.0 |
| first run (the tree only), `compiler/src` | | | 1.5 |
| first run (the tree only), the repository | | | 2.6 |

With the tree only (the parser before it made the AST), the figures were 0.55–0.65 and 1.03.

## The checker

| Program (with the library, 6,600 lines) | F# | Z# | Z# / F# |
|---|---|---|---|
| `examples/simple.zs` | 107 ms | 84 ms | 0.79 |
| `tests/json.zs` | 105 ms | 87 ms | 0.83 |
| `examples/complex.zs` | 105 ms | 85 ms | 0.81 |
| `tests/modules/main.zs` | 97 ms | 83 ms | 0.85 |

`zs check-time file` in both: parsing and checking the library and the program, the best of ten
runs in process (the F# one after one for the JIT, with `ZS_NO_CACHE=1`).

The first build took 225–240 ms, 2.0–2.3×. Four changes brought it under the F# compiler's:
- **The built-in impls' sets were made at each use.** `hasBuiltinImpl`, which unification asks
  for every literal and trait, built the union of the number and vector types each time; the
  sets are values now.
- **The context was copied into closures.** A record of 74 fields captured by a lambda is 74
  words copied and as many counts incremented: the context is one heap cell now (a union of one
  case, with a property per field, so its uses read as before).
- **A field read through the cell copied the whole record.** `match c with Cx d -> d.globals`
  copies `d` out of the cell before reading the field; `Cx { globals = g } -> g` reads the one
  field. This was most of what was left (callgrind: 12% of instructions in the copy). The Z#
  code generator should read a field through the cell either way; until then, the pattern says
  which field.
- **Names were resolved again at each use.** `resolveName`, a dozen candidates tried against nine
  tables, runs several times per name; it's remembered for the declaration now.

## What the first run found

All three were in the F# compiler, which builds the first generation of `compiler/`; the Z#
compiler's passes take the same rules.
- **`Mono.reaching` was exponential on a large recursive group.** A walk that met a function it
  was inside of kept no answer for the functions it went through, so every walk went through the
  whole group again: the parser's expressions, one group of about 50 functions, didn't finish building in ten
  minutes. A walk now goes through a function once, and when it finds nothing, nothing is the
  answer for every function it went through. The build takes 5 seconds.
- **No copy propagation.** Inlining a call binds its parameters (`let p' = p`), and Simplify
  kept the alias, so a record parameter looked consumed and each caller dup'ed every field of
  the record to pass it. `let x = y` is now `y`.
- **Borrowing stopped at records and join points.** A record parameter whose uses are field
  reads is borrowed now (a read dups the field it reads), and so is a `ref` read and written
  through. A join point's parameter that every jump to it passes the same borrowed parameter of
  the function in is that parameter: Simplify and Decide give a join point all its body uses,
  the function's parameters too, and passing one there consumed it.

And one in the parser itself: its entry point is pure (`/ <>`). With an open row, its functions
were instances under the caller's `Report`, with a check after each call for an operation in
progress, though none performs one.

After the fixes, only the two functions that make a parser state own one; every other function
borrows it.
