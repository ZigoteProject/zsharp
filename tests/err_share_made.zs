// A function a call returns, or a field holds, may capture what can't be shared (a ref the call
// made): it crosses threads only as a share<…>. A top-level function given some of its arguments
// holds them, so they must be Share.
type Handlers = { onItem: int -> unit }

let collector () =
  let seen = ref ""
  fun (i: int) -> seen.Value <- seen.Value + "x"

let bump (r: ref<string>) (i: int) = r.Value <- r.Value + "x"

let fromCall () =
  Parallel.``for`` 0 1000 (collector ())

let throughLocal () =
  let add = collector ()
  Parallel.both (fun () -> add 1) (fun () -> add 2) |> ignore

let localFactory () =
  let make () =
    let r = ref 0
    fun (i: int) -> r.Value <- r.Value + i
  Parallel.``for`` 0 1000 (make ())

let partial () =
  Parallel.``for`` 0 1000 (bump (ref ""))

let field (h: Handlers) =
  Parallel.``for`` 0 1000 h.onItem

let main () = ()
