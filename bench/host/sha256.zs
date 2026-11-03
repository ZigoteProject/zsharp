// Hashing, as a backup tool or a content-addressed store does it: m MiB of data, made of 4 KiB
// chunks that often repeat, is hashed whole with SHA-256 (Core's Sha256); each chunk is hashed
// on its own and named by its hex digest, as git names objects; the distinct names are counted in
// a hash set, and the chunk digests hashed into a root.
// 32-bit arithmetic, byte arrays and spans.
let chunk = 4096

let next (seed: int) = (seed * 1103515245 + 12345) % 2147483648

let main () =
  let mib =
    match Environment.args () with
    | a :: _ -> Option.defaultValue 64 (String.parseInt a)
    | [] -> 64
  let size = mib * 1048576
  let mutable data = Array.create size (u8 0)
  for c in 0 .. size / chunk - 1 do
    let mutable seed = 1 + c * c % 251 // so chunks repeat, as blocks of real files do
    for i in c * chunk .. (c + 1) * chunk - 1 do
      seed <- next seed
      data.[i] <- u8 (seed >>> 16 &&& 255)
  println $"whole: {Hex.encode (Sha256.hash data)}"
  let mutable seen = HashSet.empty
  let mutable digests = Buffer.empty
  for c in 0 .. size / chunk - 1 do
    let d = Sha256.hash data.[c * chunk .. (c + 1) * chunk - 1]
    seen <- HashSet.add (Hex.encode d) seen
    for b in d do
      Buffer.push b digests
  println $"{size / chunk} chunks, {HashSet.count seen} distinct"
  println $"root: {Hex.encode (Sha256.hash digests)}"
  0
