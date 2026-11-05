# Ten Advent of Code puzzles

Each solved with only the prelude, Core and Std, on the puzzle's example input (track S's exit
test: the library is enough for a day's puzzle without reaching for anything else). Lists, sets,
maps, folds and scans, string splitting and parsing, records with `with`, and tuples do the work.

| Program | Puzzle | What it reaches for |
|---|---|---|
| [day01_lisp.zs](day01_lisp.zs) | Not Quite Lisp (2015, 1) | `List.scan`, `List.tryFindIndex` |
| [day02_wrapping.zs](day02_wrapping.zs) | I Was Told There Would Be No Math (2015, 2) | `String.split`, `Int.parse`, `List.sort`, `List.sumBy` |
| [day03_houses.zs](day03_houses.zs) | Perfectly Spherical Houses in a Vacuum (2015, 3) | `Set` of tuples, `List.partition`, `List.indexed` |
| [day04_nice.zs](day04_nice.zs) | Doesn't He Have Intern-Elves For This? (2015, 5) | `String.chars`, `String.sub`, `String.contains`, `List.zip` |
| [day05_taxicab.zs](day05_taxicab.zs) | No Time for a Taxicab (2016, 1) | a record with `with`, `List.fold`, `Set` |
| [day06_captcha.zs](day06_captcha.zs) | Inverse Captcha (2017, 1) | `Array.ofList`, `List.init`, `int c - int '0'` |
| [day07_checksum.zs](day07_checksum.zs) | Corruption Checksum (2017, 2) | `List.collect`, `List.max`, `List.min` |
| [day08_calibration.zs](day08_calibration.zs) | Chronal Calibration (2018, 1) | `HashSet`, `String.replace`, a tail-recursive loop |
| [day09_expenses.zs](day09_expenses.zs) | Report Repair (2020, 1) | `List.choose` over pairs and triples |
| [day10_sonar.zs](day10_sonar.zs) | Sonar Sweep (2021, 1) | `List.zip` with `List.tail`, windows over an array |

```sh
zs run examples/aoc/day01_lisp.zs
```

`tests/examples_aoc.sh` builds and runs them all and checks the answers.
