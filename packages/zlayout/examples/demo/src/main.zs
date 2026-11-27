open Zlayout

type Vec3 =
  { x: f32
    y: f32
    z: f32 }

[<Derive(Inspect)>]
type Particle =
  { enabled: bool
    lastSeen: i64
    team: u8
    age: f32
    position: Vec3
    velocity: Vec3
    label: string }

let main () =
  let particle =
    { enabled = true
      team = u8 2
      age = 1.5
      position = { x = 1.0; y = 2.0; z = 3.0 }
      velocity = { x = 0.0; y = 0.1; z = 0.0 }
      lastSeen = 123456
      label = "particle" }
  let report = Inspect.inspect "Particle" particle
  printReport 64 true report

  let particles = [| particle; particle; particle; particle |]
  Heap.printEstimate "array<Particle>" (Heap.estimateArray particles)
  println $"payload only: {Heap.arrayPayloadBytes particles} bytes"
  println $"nominal 64-byte cache lines: {Cache.arrayLines particles 64}"

  let mutable observedAge = Width.emptySigned
  for age in [ i64 18; i64 23; i64 31; i64 27; i64 42 ] do
    observedAge <- Width.observeSigned age observedAge
  let width = Width.recommendSigned observedAge
  println $"sampled age range: {observedAge.minimum}..{observedAge.maximum} ({observedAge.samples} samples)"
  println $"smallest signed width covering samples: {Width.signedWidthBytes width} bytes"
  0
