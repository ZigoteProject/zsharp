// F#: async { }; Z# has task { } and Task.run
let main () =
  let work = async { return 1 }
  Async.RunSynchronously work
