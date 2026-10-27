// Results that C leaves undefined, or that a check of the text could be fooled by, are defined:
// a float converted past an integer's range, malformed UTF-8, and names the OS reads only up to a
// NUL.
let codes (s: string) =
  let mutable out = ""
  for c in s do
    out <- out + $" {int c}"
  out

let failed (r: result<'a, string>) = if Result.isOk r then "ok" else "error"

let main () =
  // saturating, NaN as 0 (LLVM's plain fptosi was poison: x86's answer here, another on Arm)
  let floats =
    [ ("NaN", 0.0 / 0.0)
      ("1e30", 1.0e30)
      ("-1e30", -1.0e30)
      ("inf", 1.0 / 0.0)
      ("300", 300.0)
      ("-1", -1.0)
      ("2.9", 2.9)
      ("-2.9", -2.9) ]
  for (name, x) in floats do
    println $"{name}: {int x} {i32 x} {u8 x} {u64 x} {i8 x} {int (f32 x)}"
  // String.isFloat and String.toFloat read as Float.parse does (strtod took leading spaces and hex)
  println $"{String.isFloat " 1.5"} {String.isFloat "0x1p3"} {String.isFloat "1.5"} {String.toFloat " 2.5"} {String.toFloat "2.5"}"
  // malformed is U+FFFD, overlong forms, surrogates and values past U+10FFFF too, from bytes
  // (String.ofBytes) or in a string as they are (for c in s): C0 AE C0 AF decoded as "./" would
  // get past a check of the bytes for "../"
  let malformed =
    [ [| u8 0xC0; u8 0xAF |]
      [| u8 0xE0; u8 0x80; u8 0xAF |]
      [| u8 0xED; u8 0xA0; u8 0x80 |]
      [| u8 0xF4; u8 0x90; u8 0x80; u8 0x80 |]
      [| u8 0xF8; u8 0x88; u8 0x80; u8 0x80; u8 0x80 |] ]
  for b in malformed do
    let raw = Array.fold (fun (s: string) (x: u8) -> s + String.ofByte x) "" b
    println $"{Utf8.validate b}:{codes (String.ofBytes b)} /{codes raw}"
  let dots = String.ofBytes [| u8 0x2E; u8 0xC0; u8 0xAE; u8 0xC0; u8 0xAF |]
  println $"{String.contains "../" (String.ofChars (String.chars dots))} {String.length dots}"
  // the edges of each length still decode: U+0080, U+07FF, U+0800, U+D7FF, U+E000, U+FFFF,
  // U+10000, U+10FFFF
  let edges = String.bytes "\u{80}\u{7FF}\u{800}\u{D7FF}\u{E000}\u{FFFF}\u{10000}\u{10FFFF}"
  println $"{Utf8.validate edges}:{codes (String.ofBytes edges)} {Array.length edges}"
  // a NUL ends the name the OS reads: a path, a variable's name, a host or a socket's path holding
  // one fails instead of naming a shorter one ("secret\0.txt" opened secret)
  let nul = String.ofByte (u8 0)
  match Directory.createTemp "zs-security-" with
  | Error e -> println e
  | Ok dir ->
    let secret = Path.combine dir "secret"
    File.writeAllText secret "SECRET" |> ignore
    println $"read {failed (File.readAllText (secret + nul + ".txt"))}"
    File.writeAllText (secret + nul + ".txt") "x" |> ignore
    println $"write {File.readAllText secret} {File.exists (secret + nul + ".txt")} {Directory.exists (dir + nul + "x")}"
    println $"delete {failed (File.delete (secret + nul + ".txt"))} {File.exists secret}"
    println $"variable {Environment.getVariable ("PATH" + nul + "X")}"
    match Tcp.listen ("127.0.0.1" + nul + ".example") 0 with
    | Ok l ->
      Dispose.dispose l
      println "listen ok"
    | Error _ -> println "listen error"
    match Unix.listen (Path.combine dir "socket" + nul + "x") with
    | Ok l ->
      Dispose.dispose l
      println "unix ok"
    | Error _ -> println "unix error"
    match Directory.list dir with
    | Ok names ->
      for f in names do
        File.delete (Path.combine dir f) |> ignore
    | Error _ -> ()
    Directory.delete dir |> ignore
  0
