// F#: option.Value; Z# reads an option by matching, or with Option.defaultValue
let main () =
  let o = Some 3
  o.Value
