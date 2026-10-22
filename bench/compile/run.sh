#!/usr/bin/env bash
# Compile time: a generated program of modules (records, unions, matches, pipelines, strings),
# built once from nothing, then again after a change: a function's body in the main file and in
# one of its modules, and a module's interface. Each timed build follows a change of its own,
# so nothing of it is in the caches. Run in the dev container:
#   ./dev bench/compile/run.sh [modules] [zs binary]   (KEEP=dir keeps the generated program)
set -u
cd "$(dirname "$0")/../.."
n=${1:-10}
zs=${2:-bin/zs}
t=${KEEP:-$(mktemp -d)}; [ -z "${KEEP:-}" ] && trap 'rm -rf "$t"' EXIT; mkdir -p "$t"
export XDG_CACHE_HOME=$t/cache # a cache of its own, empty at first

module() { # module <k> <variant>: about 120 lines
  local k=$1 v=$2
  cat <<EOF
module M$k

type Shape =
  | Circle of r: f64
  | Rect of w: f64 * h: f64
  | Named of string * f64

type Item = { name: string; qty: int; price: f64; tags: list<string> }

type Event =
  | Added of Item
  | Removed of string
  | Renamed of string * string

let area s =
  match s with
  | Circle r -> 3.14159 * r * r
  | Rect (w, h) -> w * h
  | Named (_, a) -> a

let total (items: list<Item>) = items |> List.sumBy (fun i -> float i.qty * i.price)

let describe (i: Item) = \$"{i.name} x{i.qty} at {i.price} [{String.join ", " i.tags}]"

let cheap (items: list<Item>) = items |> List.filter (fun i -> i.price < 10.0 + float $v) |> List.map (fun i -> i.name)

let apply (items: list<Item>) (e: Event) =
  match e with
  | Added i -> i :: items
  | Removed n -> items |> List.filter (fun i -> i.name <> n)
  | Renamed (a, b) -> items |> List.map (fun i -> if i.name = a then { i with name = b } else i)

let replay (events: list<Event>) = List.fold apply [] events

let tagged (tag: string) (items: list<Item>) = items |> List.filter (fun i -> List.contains tag i.tags)

let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let classify n =
  match n % 4 with
  | 0 -> "zero"
  | 1 -> "one"
  | 2 -> "two"
  | _ -> "three"

let parse (s: string) =
  match String.parseInt s with
  | Some n when n > 0 -> Ok n
  | Some _ -> Error \$"not positive: {s}"
  | None -> Error \$"not a number: {s}"

let sumParsed (xs: list<string>) =
  xs |> List.fold (fun acc s -> match parse s with
                                | Ok n -> acc + n
                                | Error _ -> acc) 0

let byPrice (items: list<Item>) = items |> List.sortBy (fun i -> i.price)

let index (items: list<Item>) =
  items |> List.fold (fun (m: Map<string, Item>) i -> Map.add i.name i m) Map.empty

let lookup (name: string) (items: list<Item>) =
  match Map.tryFind name (index items) with
  | Some i -> describe i
  | None -> \$"no {name}"

let shapes () = [ Circle 1.0; Rect (2.0, 3.0); Named ("hex", 4.5); Circle (float $k) ]

let report () =
  let items =
    [ { name = "a$k"; qty = 2; price = 3.5; tags = [ "x"; "y" ] }
      { name = "b$k"; qty = 1; price = 12.0; tags = [ "y" ] }
      { name = "c$k"; qty = 5; price = 0.5; tags = [] } ]
  let events = [ Added (List.item 0 items); Added (List.item 1 items); Renamed ("a$k", "z$k"); Removed "b$k" ]
  let lines =
    [ \$"total {total items}"
      \$"cheap {cheap items}"
      \$"replayed {replay events |> List.map describe}"
      \$"tagged {tagged "y" items |> List.length}"
      \$"fib {fib 10} {classify $k}"
      \$"parsed {sumParsed [ "1"; "x"; "3"; "-2" ]}"
      \$"sorted {byPrice items |> List.map (fun i -> i.name)}"
      \$"lookup {lookup "c$k" items}"
      \$"areas {shapes () |> List.map area |> List.sum}" ]
  String.join "\n" lines
EOF
}

main() { # main <variant>
  echo "// a generated program for bench/compile/run.sh"
  for k in $(seq 1 "$n"); do echo "open M$k"; done
  echo
  echo "let banner () = \"variant $1\""
  echo
  echo "let main () ="
  echo "  println (banner ())"
  for k in $(seq 1 "$n"); do echo "  println (M$k.report ())"; done
  echo "  0"
}

for k in $(seq 1 "$n"); do module "$k" 0 > "$t/m$k.zs"; done
main 0 > "$t/main.zs"
lines=$(cat "$t"/*.zs | wc -l)

# build <label> [change]: seconds of the best of 3 builds, each after `change <i>` (a change of
# its own) when given, with the time parse and check took and the modules checked again
build() {
  local label=$1; shift
  local best="" check="" again=""
  for i in 1 2 3; do
    [ $# -gt 0 ] && "$@" "$i"
    local s; s=$( { TIMEFORMAT=%R; time "$zs" build "$t/main.zs" -o "$t/exe" --time 2>"$t/time.log" >/dev/null; } 2>&1 )
    if [ -z "$best" ] || awk -v s="$s" -v b="$best" 'BEGIN { exit !(s < b) }'; then
      best=$s
      check=$(grep '^parse + check' "$t/time.log" | awk '{print $(NF-1)}')
      again=$(grep -o 'program: [^)]*' "$t/time.log" | sed 's/program: //')
    fi
  done
  echo "| $label | $best | $check | $again |"
}
body_main() { main "$((100 + $1))" > "$t/main.zs"; }
body_module() { module 3 "$((100 + $1))" > "$t/m3.zs"; }
interface_module() { { module 3 0; printf '\nlet extra%d () = %d\n' "$1" "$1"; } > "$t/m3.zs"; }

echo "**$n modules + main, $lines lines** ($zs)"
echo
echo "| build | seconds | parse + check, ms | checked again |"
echo "|---|---:|---:|---|"
s=$( { TIMEFORMAT=%R; time "$zs" build "$t/main.zs" -o "$t/exe" >/dev/null 2>&1; } 2>&1 )
echo "| first (nothing cached) | $s | | |"
build "again, unchanged"
build "a function's body changed in the main file" body_main
build "a function's body changed in a module" body_module
build "a module's interface changed (a function added)" interface_module
ZS_NO_CACHE=1 build "without the cache"
"$t/exe" >/dev/null || echo "the program doesn't run"
