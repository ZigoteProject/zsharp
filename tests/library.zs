// The library's organization: namespaces open everywhere at the lowest precedence, full names,
// a program's own modules named like the library's, and Path, Stopwatch, Map and Set.
module List =
  // a program's own List module: its names come first, and the library's List.map still works
  let top xs = List.head xs

module Text =
  let shout (s: string) = String.toUpper s + "!"

let main () =
  println $"{List.top [ 3; 4 ]} {List.map (fun x -> x * 2) [ 1; 2 ]} {Text.shout "hey"} {String.length "abc"}"
  println $"{Collections.List.sum [ 1; 2; 3 ]} {Text.String.toLower "ABC"} {Collections.Map.ofList [ (1, "a") ] |> Map.count}"
  println $"{Map.ofList [ (2, "b"); (1, "a") ]} {Set.ofList [ 3; 1; 2; 1 ]}"
  println $"{Path.combine "a/b" "c.txt"} {Path.combine "a/" "/abs"} {Path.getFileName "a/b/c.tar.gz"} {Path.getDirectoryName "a/b/c"}"
  println $"{Path.getExtension "a/b/c.tar.gz"} [{Path.getExtension ".gitignore"}] {Path.getFileNameWithoutExtension "x/main.zs"} {Path.changeExtension "a/main.zs" ".md"}"
  println $"{String.lastIndexOf "/" "a/b/c"} {String.lastIndexOf "x" "abc"} {Path.getDirectoryName "/etc"} [{Path.getDirectoryName "file"}]"
  let sw = Stopwatch.startNew ()
  println $"stopwatch {sw.ElapsedMilliseconds >= 0} {sw.ElapsedNanoseconds >= u64 0}"
  0
