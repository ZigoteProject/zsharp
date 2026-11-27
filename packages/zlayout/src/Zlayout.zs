// ZLayout: compile-time type layout inspection and CPU-locality estimates for Z#.
//
// The Inspect derive is expanded per concrete type. It emits ordinary code and
// constants; it does not add runtime type metadata to the application.

type FieldLayout =
  { name: string
    index: int
    offset: int
    size: int
    alignment: int }

type Report =
  { typeName: string
    kind: ShapeKind
    size: int
    alignment: int
    fields: list<FieldLayout>
    activeCase: option<string>
    payloadBytes: int
    internalPaddingBytes: int
    trailingPaddingBytes: int
    compactCandidateSize: int
    compactCandidateOrder: list<string> }

let private alignUp (value: int) (alignment: int) : int =
  if alignment <= 1 then value
  else ((value + alignment - 1) / alignment) * alignment

/// Shallow representation size. For heap-backed values this is the handle size,
/// not the allocation reachable through that handle.
let representationBytes (value: 'a) : int = sizeof<'a>

/// Alignment of the value's shallow representation.
let representationAlignment (value: 'a) : int = alignof<'a>

/// The report for a record of the given size and alignment whose fields are
/// (name, offset, size, alignment) in declaration order: what the Inspect derive
/// gives it, each fact the compiler's own for the target the build is for.
let recordReport (typeName: string) (size: int) (alignment: int) (declared: list<string * int * int * int>) : Report =
  let fields =
    List.mapi (fun i (name, offset, fieldSize, fieldAlignment) ->
      { name = name; index = i; offset = offset; size = fieldSize; alignment = fieldAlignment }) declared
  let payloadBytes = List.sumBy (fun f -> f.size) fields
  // where the last field ends: fields are laid out in declaration order
  let used = List.fold (fun m f -> max m (f.offset + f.size)) 0 fields

  // Descending alignment, then size, is a good candidate for ordinary ABI
  // alignments (which are powers of two). This is advisory, not a source rewrite.
  let candidate = List.sortBy (fun f -> (-f.alignment, -f.size, f.index)) fields
  let mutable candidateCursor = 0
  for f in candidate do
    candidateCursor <- alignUp candidateCursor f.alignment + f.size
  { typeName = typeName
    kind = RecordKind
    size = size
    alignment = alignment
    fields = fields
    activeCase = None
    payloadBytes = payloadBytes
    internalPaddingBytes = used - payloadBytes
    trailingPaddingBytes = size - used
    compactCandidateSize = alignUp candidateCursor alignment
    compactCandidateOrder = List.map (fun f -> f.name) candidate }

/// A per-type layout inspector. Apply [<Derive(Inspect)>] to each record or union
/// ([<CLayout; Derive(Inspect)>] for a C-layout record). A [<Bits>] record is one
/// integer whose fields are bits, with no offsets in bytes: deriving it is an error.
trait Inspect<'a> =
  abstract inspect : string -> 'a -> Report

derive Inspect =
  let inspect (typeName: string) (value: 'self) : Report =
    match Shape.of value with
    | Record record ->
      let mutable declared = []
      for f in record.fields do
        declared <- (f.name, f.offset, representationBytes f.value, representationAlignment f.value) :: declared
      recordReport typeName sizeof<'self> alignof<'self> (List.rev declared)
    | Union c ->
      // A value only exposes its active case. sizeof/alignof still describe the
      // complete union representation, so we intentionally do not invent a
      // complete per-variant field map here.
      { typeName = typeName
        kind = UnionKind
        size = sizeof<'self>
        alignment = alignof<'self>
        fields = []
        activeCase = Some c.name
        payloadBytes = 0
        internalPaddingBytes = 0
        trailingPaddingBytes = 0
        compactCandidateSize = sizeof<'self>
        compactCandidateOrder = [] }

/// Print a readable layout report.
///
/// cacheLineBytes should match the target you are measuring (for example, 64 on
/// many desktop CPUs). Set allowReorder=false for [<CLayout>], [<Bits>] or any
/// type whose field order is part of an external ABI or serialized format.
let printReport (cacheLineBytes: int) (allowReorder: bool) (r: Report) : unit =
  let kind =
    match r.kind with
    | RecordKind -> "record"
    | UnionKind -> "union"
  println $"{r.typeName} ({kind})"
  println $"  size: {r.size} bytes; alignment: {r.alignment} bytes"

  match r.kind with
  | RecordKind ->
    println $"  field payload: {r.payloadBytes} bytes"
    println $"  internal padding: {r.internalPaddingBytes} bytes"
    println $"  trailing padding: {r.trailingPaddingBytes} bytes"
    println $"  total padding: {r.size - r.payloadBytes} bytes"
    for f in r.fields do
      println $"  +{f.offset}: {f.name} ({f.size} bytes, align {f.alignment})"
    if allowReorder && r.compactCandidateSize < r.size then
      println $"  candidate: {r.compactCandidateSize} bytes (save {r.size - r.compactCandidateSize})"
      println $"  candidate field order: {String.join ", " r.compactCandidateOrder}"
    else if not allowReorder && r.compactCandidateSize < r.size then
      println $"  possible layout saving: {r.size - r.compactCandidateSize} bytes; reorder disabled by caller"
  | UnionKind ->
    match r.activeCase with
    | Some name -> println $"  active case: {name}"
    | None -> ()
    println "  per-variant offsets are not inferred from one active value"

  if cacheLineBytes > 0 && r.size > 0 then
    if r.size <= cacheLineBytes then
      let perLine = cacheLineBytes / r.size
      println $"  cache-line model ({cacheLineBytes} B): {perLine} values/line, {cacheLineBytes - perLine * r.size} unused bytes"
    else
      let lines = (r.size + cacheLineBytes - 1) / cacheLineBytes
      println $"  cache-line model ({cacheLineBytes} B): {lines} lines/value"

module Heap =
  /// requestedBytes is the total over all allocations; poolClassBytes is the
  /// pool class of each one, or None when there is none or it is over 256 bytes.
  type Estimate =
    { allocations: int
      requestedBytes: int
      poolClassBytes: option<int> }

  let private wordBytes = sizeof<int>

  /// Z# pools objects up to 256 bytes in 8-byte size classes. Larger objects
  /// use the general allocator; its allocator-specific overhead is not guessed.
  let private estimate (allocations: int) (bytesEach: int) : Estimate =
    { allocations = allocations
      requestedBytes = allocations * bytesEach
      poolClassBytes = (if allocations > 0 && bytesEach <= 256 then
        Some (alignUp bytesEach 8)
      else
        None) }

  /// Payload only, excluding the array object header and length word.
  let arrayPayloadBytes (items: array<'a>) : int =
    Array.length items * sizeof<'a>

  /// Requested bytes for an array object: one object-header word, one length
  /// word, and the contiguous inline element payload. The empty array is a
  /// static object and allocates nothing.
  let estimateArray (items: array<'a>) : Estimate =
    if Array.length items = 0 then estimate 0 0
    else estimate 1 (2 * wordBytes + arrayPayloadBytes items)

  /// One list cons cell: object header, inline head, tail handle, laid out as a
  /// struct (so a u8 head still makes a 24-byte cell on a 64-bit target).
  let listCellRequestedBytes (headSample: 'a) : int =
    let headEnd = alignUp wordBytes alignof<'a> + sizeof<'a>
    alignUp (alignUp headEnd wordBytes + wordBytes) alignof<'a>

  /// count separately allocated list cells. The empty-list terminator is static.
  let estimateListCells (count: int) (headSample: 'a) : Estimate =
    estimate (max 0 count) (listCellRequestedBytes headSample)

  /// A string built at run time: object header, length word, the UTF-8 bytes
  /// (not Unicode scalar count) and a terminating NUL. A string literal is a
  /// static object and allocates nothing.
  let estimateString (value: string) : Estimate =
    estimate 1 (2 * wordBytes + Span.length (String.bytes value) + 1)

  /// Logical live payload only. Buffer capacity may be larger after growth,
  /// and its backing allocation is deliberately not guessed.
  let bufferPayloadLowerBound (buffer: Buffer<'a>) : int =
    Buffer.length buffer * sizeof<'a>

  let printEstimate (label: string) (e: Estimate) : unit =
    println $"{label}: {e.requestedBytes} requested bytes in {e.allocations} allocation(s)"
    match e.poolClassBytes with
    | Some bytes -> println $"  runtime pool class: {bytes} bytes each"
    | None ->
      if e.allocations > 0 then
        println "  larger than 256 bytes: general allocator; allocator overhead not included"

module Cache =
  /// Nominal number of whole values fitting in one cache line.
  let elementsPerLine (cacheLineBytes: int) (elementBytes: int) : int =
    if cacheLineBytes <= 0 || elementBytes <= 0 then 0
    else cacheLineBytes / elementBytes

  /// Number of cache lines needed for a tightly packed array payload.
  /// This is a capacity estimate; base-address alignment and access pattern matter.
  let linesForArray (count: int) (elementBytes: int) (cacheLineBytes: int) : int =
    if count <= 0 || elementBytes <= 0 || cacheLineBytes <= 0 then 0
    else
      let bytes = count * elementBytes
      (bytes + cacheLineBytes - 1) / cacheLineBytes

  let arrayLines (items: array<'a>) (cacheLineBytes: int) : int =
    linesForArray (Array.length items) (sizeof<'a>) cacheLineBytes

module Width =
  /// Observed range for a signed integer field. Feed it values from realistic
  /// workloads, then compare the result with the domain's actual invariants.
  type SignedRange =
    { minimum: i64
      maximum: i64
      samples: int }

  type SignedWidth =
    | NoSamples
    | I8
    | I16
    | I32
    | I64

  type UnsignedRange =
    { minimum: u64
      maximum: u64
      samples: int }

  type UnsignedWidth =
    | NoUnsignedSamples
    | U8
    | U16
    | U32
    | U64

  let emptySigned : SignedRange =
    { minimum = i64 0; maximum = i64 0; samples = 0 }

  let observeSigned (value: i64) (range: SignedRange) : SignedRange =
    if range.samples = 0 then
      { minimum = value; maximum = value; samples = 1 }
    else
      { minimum = min range.minimum value
        maximum = max range.maximum value
        samples = range.samples + 1 }

  let recommendSigned (range: SignedRange) : SignedWidth =
    if range.samples = 0 then NoSamples
    else if range.minimum >= -128 && range.maximum <= 127 then I8
    else if range.minimum >= -32768 && range.maximum <= 32767 then I16
    else if range.minimum >= -2147483648 && range.maximum <= 2147483647 then I32
    else I64

  let signedWidthBytes (width: SignedWidth) : int =
    match width with
    | NoSamples -> 0
    | I8 -> 1
    | I16 -> 2
    | I32 -> 4
    | I64 -> 8

  let emptyUnsigned : UnsignedRange =
    { minimum = u64 0; maximum = u64 0; samples = 0 }

  let observeUnsigned (value: u64) (range: UnsignedRange) : UnsignedRange =
    if range.samples = 0 then
      { minimum = value; maximum = value; samples = 1 }
    else
      { minimum = min range.minimum value
        maximum = max range.maximum value
        samples = range.samples + 1 }

  let recommendUnsigned (range: UnsignedRange) : UnsignedWidth =
    if range.samples = 0 then NoUnsignedSamples
    else if range.maximum <= 255 then U8
    else if range.maximum <= 65535 then U16
    else if range.maximum <= 4294967295 then U32
    else U64

  let unsignedWidthBytes (width: UnsignedWidth) : int =
    match width with
    | NoUnsignedSamples -> 0
    | U8 -> 1
    | U16 -> 2
    | U32 -> 4
    | U64 -> 8
