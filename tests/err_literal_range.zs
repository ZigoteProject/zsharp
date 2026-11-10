// An integer literal outside its type's range is an error at the literal (track G, defect 1): a
// decimal one is a value of its type; one written in a radix may fill its type's bits instead
let a: u8 = 256
let b: i8 = -129
let c: i8 = 128
let d: u16 = 0x1_0000
let e: i32 = 4294967296

let name (x: u8) =
  match x with
  | 300 -> "big"
  | _ -> "small"

let low (x: i16) =
  match x with
  | -32769 -> "low"
  | _ -> "high"

let limit = 300
let f: u8 = limit

// in range, or a radix literal's bits
let g: u8 = 255
let h: i8 = -128
let i: i8 = 0xFF
let j: i64 = -0x8000_0000_0000_0000
let k: u64 = 0xFFFF_FFFF_FFFF_FFFF
let l: int = 0xcbf2_9ce4_8422_2325

// a literal in a generic function: the function is of the types that hold it
let add300 x = x + 300
let big: u16 = add300 1
let small: u8 = add300 1

// a constant's literal at each use: decimal is a value, a radix literal its bits
let two = 200
let mask = 0xF0
let n: i8 = two
let o: i8 = mask
let p: u8 = two

let main () = ()
