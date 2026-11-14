// what doesn't compile (tests/packages/tls.sh checks this file and expects the errors): Mbed
// TLS's pointer taken from a stream or a configuration, which could be put back after its
// release, or a configuration's put where a connection's goes
open Tls

let kept (s: TlsStream) : option<cptr> = s.handle.connected.Value

let swapped (c: ClientConfig) (s: TlsStream) : unit =
  s.handle.connected.Value <- c.roots.configured.Value
