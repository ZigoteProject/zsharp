// The command line, parsed with Throw: the first mistake stops with a message for the user.

type Options = { top: int; timeoutMs: int; verbose: bool; inputs: list<string> }

let usage = "usage: logstat [--top N] [--timeout MS] [-v] <file.log | dir>..."

let private positive (flag: string) (s: string) =
  match String.parseInt s with
  | Some n when n > 0 -> n
  | _ -> Throw.throw $"{flag} needs a positive number, got '{s}'"

let rec private go (o: Options) args =
  match args with
  | [] -> o
  | "--top" :: n :: rest -> go { o with top = positive "--top" n } rest
  | "--timeout" :: n :: rest -> go { o with timeoutMs = positive "--timeout" n } rest
  | "-v" :: rest -> go { o with verbose = true } rest
  | flag :: _ when String.startsWith "-" flag -> Throw.throw $"unknown option {flag}"
  | input :: rest -> go { o with inputs = input :: o.inputs } rest

let parse args =
  let o = go { top = 3; timeoutMs = 2000; verbose = false; inputs = [] } args
  if o.inputs = [] then Throw.throw "no input files" else { o with inputs = List.rev o.inputs }
