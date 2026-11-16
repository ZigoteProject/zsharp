open Testing
open Zlayout

type Vec3 = { x: f32; y: f32; z: f32 }

[<Derive(Inspect)>]
type Particle =
  { enabled: bool
    team: u8
    age: f32
    position: Vec3
    lastSeen: i64
    label: string }

[<Derive(Inspect)>]
type Loose = { a: u8; b: i64; c: u8; d: i32; e: u8 }

// Loose's fields in the order the report suggests
type Tight = { b: i64; d: i32; a: u8; c: u8; e: u8 }

[<CLayout; Derive(Inspect)>]
type Packet = { kind: u8; length: u32; data: fixed<u8, 6>; flags: u16 }

[<Derive(Inspect)>]
type Shape =
  | Dot
  | Circle of f64
  | Rect of f64 * f64

let private offsets (r: Report) = List.map (fun (f: FieldLayout) -> (f.name, f.offset)) r.fields

let private est (allocations: int) (requested: int) (poolClass: option<int>) : Heap.Estimate =
  { allocations = allocations; requestedBytes = requested; poolClassBytes = poolClass }

let private signed (xs: list<int>) =
  Width.recommendSigned (List.fold (fun r x -> Width.observeSigned (i64 x) r) Width.emptySigned xs)

let private unsigned (xs: list<int>) =
  Width.recommendUnsigned (List.fold (fun r x -> Width.observeUnsigned (u64 x) r) Width.emptyUnsigned xs)

let private word = sizeof<int>

[<Tests>]
let tests =
  testList "zlayout" [
    // a field's offset in the report is the compiler's offsetof for it
    test "offsets match offsetof" (fun () ->
      let p =
        { enabled = true
          team = u8 1
          age = 1.0
          position = { x = 1.0; y = 2.0; z = 3.0 }
          lastSeen = 5
          label = "x" }
      let r = Inspect.inspect "Particle" p
      assert (r.size = sizeof<Particle> && r.alignment = alignof<Particle>)
      assert (offsets r = [ ("enabled", offsetof<Particle> "enabled")
          ("team", offsetof<Particle> "team")
          ("age", offsetof<Particle> "age")
          ("position", offsetof<Particle> "position")
          ("lastSeen", offsetof<Particle> "lastSeen")
          ("label", offsetof<Particle> "label") ])
      assert (r.payloadBytes + r.internalPaddingBytes + r.trailingPaddingBytes = r.size))
    test "CLayout offsets match offsetof" (fun () ->
      let r =
        Inspect.inspect "Packet" ({ kind = u8 1
            length = u32 2
            data = Fixed.create (u8 0)
            flags = u16 3 } : Packet)
      assert (r.size = 16 && r.internalPaddingBytes = 3 && r.trailingPaddingBytes = 0)
      assert (offsets r = [ ("kind", 0)
          ("length", offsetof<Packet> "length")
          ("data", offsetof<Packet> "data")
          ("flags", offsetof<Packet> "flags") ]))
    test "a report from fields given by hand" (fun () ->
      let r = recordReport "Hand" 24 8 [ ("a", 0, 1, 1); ("b", 8, 8, 8); ("c", 16, 2, 2) ]
      assert (r.payloadBytes = 11 && r.internalPaddingBytes = 7 && r.trailingPaddingBytes = 6)
      assert (r.compactCandidateSize = 16 && r.compactCandidateOrder = [ "b"; "c"; "a" ]))
    test "padding and candidate order" (fun () ->
      let r = Inspect.inspect "Loose" ({ a = u8 1; b = i64 2; c = u8 3; d = 4; e = u8 5 } : Loose)
      assert (r.size = 32 && r.payloadBytes = 15)
      assert (r.internalPaddingBytes = 10 && r.trailingPaddingBytes = 7)
      assert (r.compactCandidateOrder = [ "b"; "d"; "a"; "c"; "e" ])
      // the predicted size is what the compiler gives the reordered record
      assert (r.compactCandidateSize = sizeof<Tight> && sizeof<Tight> = 16))
    test "union" (fun () ->
      let r = Inspect.inspect "Shape" (Rect (1.0, 2.0))
      assert (r.kind = UnionKind && r.activeCase = Some "Rect")
      assert (r.size = sizeof<Shape> && r.alignment = alignof<Shape> && List.isEmpty r.fields))
    test "printReport" (fun () ->
      printReport 64 true (Inspect.inspect "Loose" ({ a = u8 1
            b = i64 2
            c = u8 3
            d = 4
            e = u8 5 } : Loose))
      printReport 16 false (Inspect.inspect "Loose" ({ a = u8 1
            b = i64 2
            c = u8 3
            d = 4
            e = u8 5 } : Loose))
      printReport 0 true (Inspect.inspect "Shape" Dot))
    test "heap arrays" (fun () ->
      assert (Heap.estimateArray [| i64 1; i64 2; i64 3; i64 4 |] = est 1 (2 * word + 32) (Some (2 * word + 32)))
      assert (Heap.estimateArray [| u8 1 |] = est 1 (2 * word + 1) (Some (2 * word + 8)))
      assert (Heap.estimateArray (Array.init 40 (fun i -> i64 i)) = est 1 (2 * word + 320) None)
      assert (Heap.estimateArray ([||] : array<i64>) = est 0 0 None)
      assert (Heap.arrayPayloadBytes [| u16 1; u16 2 |] = 4))
    test "heap strings" (fun () ->
      // header + length + 8 bytes + NUL
      assert (Heap.estimateString "particle" = est 1 (2 * word + 9) (Some (2 * word + 16)))
      assert (Heap.estimateString "é" = est 1 (2 * word + 3) (Some (2 * word + 8))))
    test "heap list cells" (fun () ->
      assert (Heap.listCellRequestedBytes 0 = 3 * word)
      assert (Heap.listCellRequestedBytes (u8 0) = 3 * word)
      assert (Heap.listCellRequestedBytes (i64 0, i64 0) = 16 + 2 * word)
      // 20 cells are 20 pooled objects, not one 480-byte one
      assert (Heap.estimateListCells 20 0 = est 20 (60 * word) (Some (3 * word)))
      assert (Heap.estimateListCells 0 0 = est 0 0 None)
      assert (Heap.estimateListCells (-3) 0 = est 0 0 None))
    test "buffer payload" (fun () ->
      assert (Heap.bufferPayloadLowerBound (Buffer.ofArray [| i32 1; i32 2; i32 3 |]) = 12))
    test "cache" (fun () ->
      assert (Cache.elementsPerLine 64 16 = 4 && Cache.elementsPerLine 64 48 = 1)
      assert (Cache.elementsPerLine 64 0 = 0 && Cache.elementsPerLine 0 8 = 0)
      assert (Cache.linesForArray 4 48 64 = 3 && Cache.linesForArray 4 16 64 = 1)
      assert (Cache.linesForArray 0 16 64 = 0 && Cache.linesForArray 4 16 0 = 0)
      assert (Cache.arrayLines [| i64 1; i64 2; i64 3 |] 16 = 2))
    test "signed widths" (fun () ->
      assert (signed [] = Width.NoSamples)
      assert (signed [ -128; 127 ] = Width.I8 && signed [ 128 ] = Width.I16 && signed [ -129 ] = Width.I16)
      assert (signed [ -32768; 32767 ] = Width.I16 && signed [ 32768 ] = Width.I32)
      assert (signed [ -2147483648; 2147483647 ] = Width.I32)
      assert (signed [ 2147483648 ] = Width.I64 && signed [ -2147483649 ] = Width.I64)
      assert (List.map Width.signedWidthBytes [ Width.NoSamples
          Width.I8
          Width.I16
          Width.I32
          Width.I64 ] = [ 0; 1; 2; 4; 8 ]))
    test "unsigned widths" (fun () ->
      assert (unsigned [] = Width.NoUnsignedSamples)
      assert (unsigned [ 0; 255 ] = Width.U8 && unsigned [ 256 ] = Width.U16)
      assert (unsigned [ 65535 ] = Width.U16 && unsigned [ 65536 ] = Width.U32)
      assert (unsigned [ 4294967295 ] = Width.U32 && unsigned [ 4294967296 ] = Width.U64)
      assert (List.map Width.unsignedWidthBytes [ Width.NoUnsignedSamples
          Width.U8
          Width.U16
          Width.U32
          Width.U64 ] = [ 0; 1; 2; 4; 8 ]))
    test "range keeps min, max and count" (fun () ->
      let r = List.fold (fun r x -> Width.observeSigned (i64 x) r) Width.emptySigned [ 5; -2; 9 ]
      assert (r.minimum = i64 (-2) && r.maximum = i64 9 && r.samples = 3))
  ]
