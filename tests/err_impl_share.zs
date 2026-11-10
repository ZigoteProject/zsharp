// An impl's requirements on its type arguments are found from its methods, so a use of the impl
// by them, at other arguments, is checked once they're known: run needs Share of 'a (its jobs
// capture the box), and its use inside itself gives a ref, of a known type or of the impl's own
// variable (a ref is never Share, whatever it holds).
trait Run<'t> =
  abstract run : 't -> int

type Box<'a> = { n: int; v: 'a }

type Pair<'a> = { m: int; w: 'a }

impl Run<Box<'a>> =
  let run b =
    if b.n > 0 then
      Parallel.both (fun () -> b.v) (fun () -> b.v) |> ignore
      0
    else
      run { n = 1; v = ref "" }

impl Run<Pair<'a>> =
  let run p =
    if p.m > 0 then
      Parallel.both (fun () -> p.w) (fun () -> p.w) |> ignore
      0
    else
      run { m = 1; w = ref p.w }

let main () = run { n = 1; v = 2 }
