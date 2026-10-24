// The whole program, from arguments to exit code. It reaches the outside world only through
// the Terminal and Files effects: main runs it with Io.Real, the tests with Io.Memory.
//
//   Cli.Args         parse the command line     Throw, handled here
//   Input.Discover   find the log files         Progress, shown on stderr with -v
//   Files.readAll    read them                  all at once, each with a timeout
//   Domain.Chunk     count 256 KB pieces        in parallel, pure, then summed
//   Output.Report    print the summary          Terminal.out
open Io.Effects

// big enough that a chunk's work dwarfs handing it to a thread, small enough that 50 MB makes
// ~200 jobs, so no worker idles long at the end
let private chunkBytes = 262144

let private complain (msg: string) = Terminal.err $"logstat: {msg}"

// the files to read; with -v, what discovery found goes to stderr
let private discover (opts: Cli.Args.Options) =
  handle Input.Discover.files opts.inputs with
  | Input.Discover.Progress.note msg, k ->
    if opts.verbose then complain msg
    k ()

// every file counted, chunk by chunk, on every core
let private count (files: list<string * string>) =
  files
  |> List.collect (Domain.Chunk.cut chunkBytes)
  |> Array.ofList
  |> Array.Parallel.map Domain.Chunk.count
  |> Array.sum

let run (args: list<string>) =
  match Throw.catch (fun () -> Cli.Args.parse args) with
  | Error e ->
    complain $"{e}\n{Cli.Args.usage}"
    2
  | Ok opts ->
    let read = Files.readAll (opts.timeoutMs, discover opts)
    let failed = read |> List.choose (fun r -> match r with Error e -> Some e | Ok _ -> None)
    for e in failed do complain e
    Output.Report.render opts.top (count (List.choose Result.toOption read))
    if failed = [] then 0 else 1
