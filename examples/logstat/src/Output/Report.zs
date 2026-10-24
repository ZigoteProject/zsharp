// The summary, written to Terminal.out: the real terminal, or a test's in-memory one.
open Domain.Entry
open Domain.Stats
open Io.Effects

let private pct a b = if b = 0 then 0 else a * 100 / b

let private heading (title: string) =
  Terminal.out ""
  Terminal.out title

let private levels (s: Stats) =
  for (level, n) in Map.toList s.levels do
    Terminal.out $"  {String.padRight 6 level}{String.padLeft 7 (show n)}  {pct n s.lines}%"

let private routes (top: int) (s: Stats) =
  heading $"top {top} routes by traffic:"
  for (name, r) in Map.toList s.routes |> List.sortBy (fun (_, r) -> -r.hits) |> List.take top do
    Terminal.out $"  {String.padRight 24 name}{r.hits} hits, avg {r.totalMs / r.hits} ms, {pct r.errors r.hits}% 5xx"

let private slowest (s: Stats) =
  heading "slowest requests:"
  for e in s.slowest do
    Terminal.out $"  {String.padLeft 6 (show e.ms)} ms  {e.meth} {e.path} ({e.status}) at {e.time}"

let private unreadable (s: Stats) =
  if s.bad <> [] then
    heading "unreadable lines:"
    for b in s.bad do
      Terminal.out $"  ! {b.file}:{b.line}: {b.why}"

let render (top: int) (s: Stats) =
  Terminal.out $"{s.lines} entries, {List.length s.bad} unreadable lines"
  levels s
  routes top s
  slowest s
  unreadable s
