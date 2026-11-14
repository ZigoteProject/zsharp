// what doesn't compile (tests/packages/http.sh checks this file and expects the error): a
// session's connections taken from it, which could be put back after its close with their
// parsers freed
open Http

let kept (s: Client.Session) : int = List.length s.idle.waiting.Value
