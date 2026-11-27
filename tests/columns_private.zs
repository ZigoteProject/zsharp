// A private row's columns and ColumnBuffer used whole outside its module (0037): their fields are
// the module's, but they are passed, measured, converted and assigned whole
module Vault =
  [<Derive(Columns)>]
  type private Secret = { code: int; note: string }

  let make () = ColumnBuffer.create 2 { code = 1; note = "a" }

  let makeColumns () = Columns.create 3 { code = 2; note = "b" }

  let total (c: columns<Secret>) = Array.sum c.code

let main () =
  let b = Vault.make ()
  let mutable c = Vault.makeColumns ()
  c <- Vault.makeColumns ()
  let again = ColumnBuffer.ofColumns c
  println $"{ColumnBuffer.length b} {Columns.length c} {ColumnBuffer.length again} {Vault.total c}"
