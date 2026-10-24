// The program's dependencies on the outside world, as effects: dependency injection without
// interfaces or constructor parameters. Code performs Terminal and Files; whoever runs it
// decides what they mean: Io.Real is the terminal and the disk, Io.Memory is for tests.

effect Terminal =
  abstract out : string -> unit
  abstract err : string -> unit

effect Files =
  abstract isDirectory : string -> bool
  abstract listRecursive : string -> result<list<string>, string>     // full paths
  abstract readAll : int * list<string> -> list<result<string * string, string>>
