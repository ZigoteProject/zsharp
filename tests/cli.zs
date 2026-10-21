// The CLI library (Std): arguments, environment, files, directories, processes, exit codes.
let show (r: result<'a, string>) =
  match r with
  | Ok _ -> "ok"
  | Error e -> "error: " + e

let main () =
  if Environment.args () = [ "--exit" ] then Environment.exit 7
  println $"args {List.length (Environment.args ())}"
  println $"HOME set {Option.isSome (Environment.getVariable "HOME")}, unset {Environment.getVariable "ZS_SURELY_UNSET"}"
  let dir = "/tmp/zs-cli-test"
  println $"mkdir {show (Directory.create dir)} exists {Directory.exists dir}"
  let path = dir + "/a.txt"
  println $"write {show (File.writeAllText path "one\ntwo\n")}"
  println $"append {show (File.appendAllText path "three")}"
  println $"lines {File.readAllLines path}"
  println $"read {File.readAllText path |> Result.map String.length}"
  println $"exists {File.exists path} {File.exists (dir + "/nope")}"
  println $"list {Directory.list dir}"
  println $"missing: {show (File.readAllText (dir + "/nope"))}"
  println $"delete {show (File.delete path)} {File.exists path}"
  let other = dir + "/b.txt"
  println $"writeAllLines {show (File.writeAllLines other [ "x"; "y" ])} {File.readAllLines other} {show (File.delete other)}"
  match Process.run "echo" [ "hi there"; "a;b" ] with
  | Ok r -> println $"echo -> code {r.code} output {String.trim r.output}"
  | Error e -> println e
  match Process.run "sh" [ "-c"; "exit 3" ] with
  | Ok r -> println $"sh -> code {r.code}"
  | Error e -> println e
  println $"no such program: {show (Process.run "zs-no-such-program" [])}"
  // the program itself, started again with an argument that makes it exit with 7
  match Process.run (Environment.programName ()) [ "--exit" ] with
  | Ok r -> println $"Environment.exit -> code {r.code}"
  | Error e -> println e
  0
