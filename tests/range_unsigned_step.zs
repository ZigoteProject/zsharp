// A u64 step of 2^63 or more (its bits, held negative) counts up, as an unsigned step always
// does: in a loop that yields (a generator's) as in one that doesn't, so the two agree
let halves (lo: u64) (hi: u64) =
  seq { for i in lo .. (0x8000_0000_0000_0000 : u64) .. hi do yield i }

let main () =
  let top: u64 = 0xFFFF_FFFF_FFFF_FFFF
  let mutable counted = []
  for i in u64 1 .. (0x8000_0000_0000_0000 : u64) .. top do
    counted <- i :: counted
  println $"{Seq.toList (halves (u64 1) top)} {List.rev counted}"
  0
