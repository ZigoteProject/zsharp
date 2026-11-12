# tls

TLS 1.2 and 1.3 for Z#, over a `Net.TcpStream`, through Mbed TLS
([proposal 0032](../../docs/proposals/0032-first-party-packages.md)).

```fsharp
let fetch (host: string) : Task<result<Tls.TlsStream, Tls.Error>> =
  task {
    match Tls.Config.client () with
    | Error e -> return Error e
    | Ok trust ->
      use config = trust
      let! connected = Tcp.connect host 443
      match connected with
      | Ok socket -> return! Tls.connect config host socket
      | Error e -> return Error (Tls.Io e)
  }
```

- **Use:** `tls = { path = "…/packages/tls" }` under `[dependencies]`. `src/Tls.zs`'s doc comments
  are the reference.
- **A client always verifies** the server's certificate and its name, against the system's
  authorities or the certificates given to `Tls.Config.clientTrusting`. There's no setting that
  doesn't.
- **Targets:** those with an operating system. Run on Linux, and on Windows x64 under Wine;
  built for macOS and not run there yet.
- **The library:** Mbed TLS 3.6.7's `library/` and `include/` in `c/mbedtls`, unmodified;
  `c/VERSION` says where it's from and how to update it. `c/config` turns its mutexes on.
- **License:** this package's code is the repository's (MIT). Mbed TLS is Apache-2.0
  (`c/mbedtls/LICENSE`): a program distributed with this package in it includes that license's
  text.
