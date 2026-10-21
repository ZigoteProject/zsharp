module Vault =
  let private secret = 42
  let reveal () = secret

let main () = Vault.secret
