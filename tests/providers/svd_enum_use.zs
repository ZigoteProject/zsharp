// The svd provider's enumerated values (0001): a field whose values are 0 to n-1 is a union of
// cases, named after the list (ModeValue here, as the register's record is Mode), shared by the
// fields with the same values; sparse values stay a number; the reset value picks the default
import svd "enum.svd"

let main () =
  let r: Port.Mode = { mode0 = Port.Output }
  println $"{Bits.toU32 r:x} {r.mode0} {r.mode1} {r.speed} {r.en}"
  let all: Port.Mode = { mode0 = Port.Input; mode1 = Port.Analog; speed = u8 4; en = true }
  println $"{Bits.toU32 all:x} {sizeof<Port.Stat>}"
  0
