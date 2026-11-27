/// Contained jobs: a function run with memory of its own, whose panic ends it and not the
/// program. Its caller gets `Error` with the panic's message, and goes on: a server answers
/// that one request with a failure, a tool over many inputs loses that one.
///
/// Nothing unwinds. A job's function is a `share<…>`, so the cells it can change (a `ref`, a
/// `Buffer`) are ones it made, and what it shares with the rest of the program is immutable, or
/// an `Atomic`, a `Mutex` or a `Channel`: a panic leaves nothing half changed that anything else
/// can reach. The job's memory goes at once, the mutexes it held are unlocked (with the value
/// they had), and the files, sockets and timers the runtime opened for it are closed.
///
/// A panic is still a bug, and still says so (its message and backtrace are printed): a
/// contained job is for a supervisor, not a way to handle errors, which are `result` values.
/// Its result is copied out of the job's memory, as is what it sends on a channel or puts in a
/// mutex, so a large result costs its size.
///
/// Not contained: a stack overflow and running out of memory (they stop the program), what the
/// job did outside itself before it failed (bytes written, a message sent), what a C library
/// holds for it, and work it started on other threads (`Parallel`, `Task.spawn`), whose own
/// panic stops the program.
namespace Threading

/// What a contained job's panic left: its message.
type Panic =
  { /// The panic's message.
    message: string }

/// Functions that run contained jobs.
module Contained =
  // how a job ended, read once (the runtime's record of it goes with the reading)
  let private outcome (job: cptr) : result<'a, Panic> =
    if Native.containedFailed job then
      Error { message = Native.containedMessage job }
    else
      Ok(Native.containedTake job)

  /// Runs `f` as a contained job: `Ok` with its result, or `Error` with the message of the
  /// panic that ended it. `f` crosses into the job, so what it captures must be Share, as its
  /// result must.
  let run (f: share<unit -> 'a>) : result<'a, Panic> = outcome (Native.containedRun f)

  // what a task's job runs first, in the job: f's task started, with a cancellation of its own
  // (which the runtime calls on, in the job, when what waits for the job is cancelled), its
  // result the job's
  let private starting (f: share<unit -> Task<'a>>) : share<unit -> unit> =
    fun () ->
      let c = newCancel ()
      Native.containedOnCancel (fun () -> cancelNow c)
      Task.handOff (f ()) c (fun x -> Native.containedFinish x)

  /// Runs the task `f` makes, and the tasks it waits for on this thread's event loop, as one
  /// contained job: `Ok` with its result, or `Error` with the message of a panic in any of
  /// them. Cancelling this task cancels the job's (its `use` values are disposed).
  let task (f: share<unit -> Task<'a>>) : Task<result<'a, Panic>> =
    task {
      let job = Native.containedOpen ()
      // ended runs here, outside the job, once its task has given its result or panicked
      let start (ended: unit -> unit) = Native.containedStart job (starting f) ended
      do! Task.fromCallback start (fun () -> Native.containedCancel job)
      return outcome job
    }
