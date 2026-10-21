// a tokenizer state machine over 2 KB of text: a union for the state, matched per byte
type State =
  | Idle
  | InNumber of value: int
  | InWord of length: int

let step (st: State) (b: u8) (numbers: int) (words: int) =
  let digit = b >= u8 48 && b <= u8 57
  let letter = b >= u8 97 && b <= u8 122
  match st with
  | InNumber v when digit -> (InNumber (v * 10 + int (b - u8 48)), numbers, words)
  | InWord n when letter -> (InWord (n + 1), numbers, words)
  | _ ->
    let numbers = match st with
                  | InNumber _ -> numbers + 1
                  | _ -> numbers
    let words = match st with
                | InWord _ -> words + 1
                | _ -> words
    if digit then (InNumber (int (b - u8 48)), numbers, words)
    else if letter then (InWord 1, numbers, words)
    else (Idle, numbers, words)

let main () =
  let text = "set 12 leds to 255 and wait 1000 ms then blink 3 times "
  let mutable data = Array.create 2048 (u8 32)
  for i in 0 .. 2047 do
    data.[i] <- String.byte text (i % String.length text)
  let t0 = Runtime.ticks ()
  let mutable st = Idle
  let mutable numbers = 0
  let mutable words = 0
  for i in 0 .. 2047 do
    let (s, n, w) = step st data.[i] numbers words
    st <- s
    numbers <- n
    words <- w
  let t1 = Runtime.ticks ()
  println $"tokens result={numbers * 1000 + words} ticks={t1 - t0}"
  0
