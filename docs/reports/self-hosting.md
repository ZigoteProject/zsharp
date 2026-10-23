# Self-hosting: the Z# compiler's lexer and parser against the F# compiler's

**Question:** 0020's second criterion, phase 11's gate: is a program of the compiler's shape,
written in Z#, within 1.5× of the F# compiler? It's measured on code the compiler keeps:
`compiler/src/Syntax/Lexer.zs` and `Parser.zs`, on 0019's tree, against the F# compiler's
lexer and parser over the same files.

**Answer:** yes. The Z# lexer and parser, the AST included, take 0.6–0.9× the F# compiler's
time on the compiler's own sources and 1.0× over every `.zs` file in the repository. They make
the same tokens, the same tree and the same AST for all 303 files (`compiler/tests/lexer.sh`,
`parser.sh`, `ast.sh`), and the same first error for the files that have one.
- **First run:** 1.5× and 2.6×. The parser showed the F# compiler three inefficiencies, all
  fixed there (below), and with them the parser's state, a record of 22 fields passed to every
  function, stopped being copied field by field on each call.
- **Still to measure:** the subset checker's figure comes with `Infer`, against `Typer` on the
  same programs.

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
