// Signals around processes: a write to a pipe whose reader has ended is an Error, not SIGPIPE
// ending the program; standard output's reader ending still ends it (quietly, by SIGPIPE: 141), as
// `| head` expects; children start with SIGPIPE's default (`yes | head` says nothing); and a
// SIGCHLD the program was started with ignored, which has the kernel reap children unasked,
// doesn't make a failed program's code 0. And a relative program is from this program's working
// directory, whatever directory the child starts in.
let shell (name: string) (script: string) (args: list<string>) =
  match Process.run name (List.append [ "-c"; script; name ] args) with
  | Ok r -> String.trim r.output
  | Error e -> e

// prints until standard output's reader has gone, which ends it
let forever () =
  while true do
    println "y"
  1

// started with SIGCHLD ignored
let child () =
  match Process.run "sh" [ "-c"; "exit 3" ] with
  | Ok r -> println $"with SIGCHLD ignored: code {r.code}"
  | Error e -> println e
  0

// started in a directory with bin/tool, and sub/bin/tool in it
let relative () =
  match Process.start { program = "./bin/tool"; directory = Some "sub"; stdout = Piped } with
  | Ok p ->
    use proc = p
    let out = match proc.stdout with | Some r -> Reader.readToEnd r | None -> Ok ""
    println $"{Result.map String.trim out} {Task.run (Process.wait proc)}"
  | Error e -> println e
  0

let tool (path: string) (says: string) =
  File.writeAllText path $"#!/bin/sh\necho {says}\n" |> ignore
  Process.run "chmod" [ "+x"; path ] |> ignore

let main () =
  let me = Environment.programName ()
  let args = Environment.args ()
  if args = [ "--forever" ] then forever ()
  else if args = [ "--child" ] then child ()
  else if args = [ "--relative" ] then relative ()
  else
    match Process.start { program = "sh"; args = [ "-c"; "exit 0" ]; stdin = Piped } with
    | Ok p ->
      use proc = p
      let code = Task.run (Process.wait proc)
      match proc.stdin with
      | Some w ->
        // more than the writer's buffer holds, so it's written now, to no reader
        let wrote = Writer.write w (Buffer.create 100000 (u8 120))
        println $"a write with no reader: {Result.isError wrote} (it exited {code})"
      | None -> ()
    | Error e -> println e
    println $"yes | head: {shell "sh" "yes | head -n 1" []}"
    let status = File.createTemp "zs-sigpipe" |> Result.defaultValue "status"
    let script = "{ timeout 60 \"$1\" --forever; echo $? > \"$2\"; } | head -n 2 | wc -l"
    let lines = shell "sh" script [ me; status ]
    let ended = File.readAllText status |> Result.map String.trim
    println $"forever | head: {lines} lines, then {ended}"
    File.delete status |> ignore
    // bash, which hands an ignored SIGCHLD on to what it execs (dash, Debian's sh, doesn't)
    println (shell "bash" "trap '' CHLD; exec \"$1\" --child" [ me ])
    match Directory.createTemp "zs-relative" with
    | Ok dir ->
      Directory.create (Path.combine dir "bin") |> ignore
      Directory.create (Path.combine dir "sub") |> ignore
      Directory.create (Path.combine dir "sub/bin") |> ignore
      tool (Path.combine dir "bin/tool") "the tool beside the program"
      tool (Path.combine dir "sub/bin/tool") "the tool in its directory"
      match Process.start { program = me
        args = [ "--relative" ]
        directory = Some dir
        stdout = Piped } with
      | Ok p ->
        use proc = p
        let out = match proc.stdout with | Some r -> Reader.readToEnd r | None -> Ok ""
        print (Result.defaultValue "" out)
        Task.run (Process.wait proc) |> ignore
      | Error e -> println e
      Directory.deleteRecursive dir |> ignore
    | Error e -> println e
    0
