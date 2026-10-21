// The CLI stdlib: arguments, environment, files, directories, processes, exit codes.
let show (r: result<'a, string>) =
  match r with
  | Ok _ -> "ok"
  | Error e -> "error: " + e

let main () =
  if Env.args () = [ "--exit" ] then Process.exit 7
  println $"args {List.length (Env.args ())}"
  println $"HOME set {Option.isSome (Env.var "HOME")}, unset {Env.var "ZS_SURELY_UNSET"}"
  let dir = "/tmp/zs-cli-test"
  println $"mkdir {show (Dir.create dir)} exists {Dir.exists dir}"
  let path = dir + "/a.txt"
  println $"write {show (File.write path "one\ntwo\n")}"
  println $"append {show (File.append path "three")}"
  println $"lines {File.lines path}"
  println $"read {File.read path |> Result.map String.length}"
  println $"exists {File.exists path} {File.exists (dir + "/nope")}"
  println $"list {Dir.list dir}"
  println $"missing: {show (File.read (dir + "/nope"))}"
  println $"delete {show (File.delete path)} {File.exists path}"
  match Process.run "echo" [ "hi there"; "a;b" ] with
  | Ok r -> println $"echo -> code {r.code} output {String.trim r.output}"
  | Error e -> println e
  match Process.run "sh" [ "-c"; "exit 3" ] with
  | Ok r -> println $"sh -> code {r.code}"
  | Error e -> println e
  println $"no such program: {show (Process.run "zs-no-such-program" [])}"
  // the program itself, started again with an argument that makes it exit with 7
  match Process.run (Env.programName ()) [ "--exit" ] with
  | Ok r -> println $"Process.exit -> code {r.code}"
  | Error e -> println e
  0
