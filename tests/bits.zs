// [<Bits>] records (0013): one unsigned integer, its fields ranges of its bits: a construction
// is the OR of the fields, a field read a shift and a mask, `with` a masked write that keeps the
// gaps; compared and ordered as the integer, printed as a record
type Parity =
  | Even
  | Odd

/// USART control register 1, an STM32's (bit 14 reserved)
[<Bits 32>]
type Cr1 =
  { sbk: bool = false
    rwu: bool = false
    re: bool = false
    te: bool = false
    idleie: bool = false
    rxneie: bool = false
    tcie: bool = false
    txeie: bool = false
    peie: bool = false
    ps: Parity = Even
    pce: bool = false
    wake: bool = false
    m: bool = false
    ue: bool = false
    [<Bit 15>] over8: bool = false }

/// An IPv4 header's first word: 16 bits, the smallest that holds its fields
[<Bits>]
type Head = { [<Width 4>] ihl: u8; [<Width 4>] version: u8; tos: u8 }

let main () =
  let on = { ue = true; te = true; re = true }
  println $"{Bits.toU32 on:x} {on.ue} {on.sbk} {on.ps} {sizeof<Cr1>}"
  let odd = { on with ps = Odd; over8 = true }
  println $"{Bits.toU32 odd:x} {odd.ps} {odd.over8}"
  // bit 14, a gap, kept through an update
  let raw: Cr1 = Bits.ofU32 (u32 0x4001)
  let kept = { raw with sbk = false }
  println $"{Bits.toU32 kept:x} {kept = raw} {kept < raw} {Bits.raw kept}"
  let h = { ihl = u8 5; version = u8 4; tos = u8 0 }
  println $"{Bits.toU16 h:x} {h.version} {h.ihl} {h} {sizeof<Head>}"
  match h with
  | { version = 4 } -> println "IPv4"
  | _ -> println "other"
  // 20 needs five bits, and ihl has four
  let wide = u8 20
  let bad = { h with ihl = wide }
  println $"{bad}"
  0
