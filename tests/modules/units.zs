module Units

let label () = "area:"

// a pattern's names are values of the module, private ones too; a constant using a private one
// is inlined into other modules as its expression
let private (scale, offset) = (10, 1)
let (lo, hi) = (offset, scale * 4)
