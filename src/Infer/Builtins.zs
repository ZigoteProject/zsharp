/// The functions built into the compiler, by full name: what each is in Core (its primitive),
/// its type scheme (the kinds of its TGen variables, its type) and how many arguments it takes.
open Types.Ty

/// A function built into the compiler.
type Builtin = { prim: string; kinds: list<Kind>; ty: Ty; arity: int }

// one entry
let private b (name: string) (prim: string) (kinds: list<Kind>) (ty: Ty) (arity: int) : string * Builtin =
  (name, { prim = prim; kinds = kinds; ty = ty; arity = arity })

let private f (x: Ty) (y: Ty) : Ty = tfun x y

// the functions on SIMD vectors and masks (DESIGN §8), a module per type (F32x4.splat,
// Mask8.any)
let private simdBuiltins () : list<string * Builtin> =
  let entries = Buffer.empty
  let add (e: string * Builtin) = Buffer.push e entries
  for (n, e, k) in vectorTypes do
    let v = tcon n
    let et = tcon e
    let m = simdModule n
    let mask = tcon $"mask{k}"
    let arr = TCon("array", [ et ])
    add (b (m + ".splat") "vec.splat" [] (f et v) 1)
    add (b (m + ".load") "vec.load" [] (f (TCon("span", [ et ])) (f tInt v)) 2)
    add (b (m + ".store") "vec.store" [] (f arr (f tInt (f v arr))) 3)
    add (b (m + ".get") "vec.get" [] (f v (f tInt et)) 2)
    add (b (m + ".set") "vec.set" [] (f v (f tInt (f et v))) 3)
    add (b (m + ".init") "vec.init" [] (f (f tInt et) v) 1)
    add (b (m + ".sum") "vec.sum" [] (f v et) 1)
    add (b (m + ".min") "vec.min" [] (f v (f v v)) 2)
    add (b (m + ".max") "vec.max" [] (f v (f v v)) 2)
    add (b (m + ".reduceMin") "vec.reduceMin" [] (f v et) 1)
    add (b (m + ".reduceMax") "vec.reduceMax" [] (f v et) 1)
    add (b (m + ".abs") "vec.abs" [] (f v v) 1)
    for c in [ "equal"; "notEqual"; "lessThan"; "lessOrEqual"; "greaterThan"; "greaterOrEqual" ] do
      add (b (m + "." + c) ("vec." + c) [] (f v (f v mask)) 2)
    add (b (m + ".select") "vec.select" [] (f mask (f v (f v v))) 3)
    add (b (m + ".shuffle") "vec.shuffle" [] (f v (f v (f (TCon("array", [ tInt ])) v))) 3)
    if Set.contains e floats then
      for g in [ "sqrt"; "floor"; "ceil"; "round" ] do
        add (b (m + "." + g) ("vec." + g) [] (f v v) 1)
      add (b (m + ".mulAdd") "vec.mulAdd" [] (f v (f v (f v v))) 3)
    // from the other vectors with as many lanes, lane by lane
    for (n2, _, k2) in vectorTypes do
      if k2 = k && n2 <> n then
        add (b (m + ".of" + simdModule n2) "vec.convert" [] (f (tcon n2) v) 1)
  for (name, intr, ps, r, _) in simdIntrinsics do
    add (b name ("llvm:" + intr) [] (List.fold (fun acc p -> f (tcon p) acc) (tcon r) (List.rev ps)) (List.length ps))
  for (mn, _) in maskTypes do
    let mt = tcon mn
    let mm = simdModule mn
    add (b (mm + ".any") "mask.any" [] (f mt tBool) 1)
    add (b (mm + ".all") "mask.all" [] (f mt tBool) 1)
    add (b (mm + ".count") "mask.count" [] (f mt tInt) 1)
    add (b (mm + ".not") "mask.not" [] (f mt mt) 1)
    add (b (mm + ".get") "mask.get" [] (f mt (f tInt tBool)) 2)
  Array.toList (Buffer.toArray entries)

let private a : Ty = TGen 0

let private atomic : Ty = TCon("Atomic", [ a ])

let private mutex : Ty = TCon("Mutex", [ a ])

let private channel : Ty = TCon("Channel", [ a ])

let private kAtomic : Kind = { kAny with allowed = Some(Set.union nums (Set.ofList [ "bool"; "char" ])) }

let private kShare : Kind = kTrait "Share"

// the conversions: a number type's name converts to it (float and c_int too), and `char`
let private conversions () : list<string * Builtin> =
  let names = List.append (Set.toList nums) [ "float"; "c_int" ]
  let target (t: string) =
    match typeAlias t with
    | Some c -> c
    | None -> t
  List.append (List.map (fun (t: string) -> b t "conv" [ kConvertible ] (f a (tcon (target t))) 1) names) [ b "char" "conv" [ kIntOrChar ] (f a tChar) 1 ]

/// Every built-in function, by full name.
let builtins : Map<string, Builtin> =
  let table =
    [ b "ignore" "ignore" [ kAny ] (f a tUnit) 1
      b "panic" "panic" [ kAny ] (f tStr a) 1
      b "failwith" "panic" [ kAny ] (f tStr a) 1
      b "assert" "assert" [] (f tBool tUnit) 1
      b "print" "print" [] (f tStr tUnit) 1
      b "println" "println" [] (f tStr tUnit) 1
      b "Text.String.length" "String.length" [] (f tStr tInt) 1
      b "Text.String.ofCStr" "String.ofCStr" [] (f tCStr tStr) 1
      b "Text.String.sub" "String.sub" [] (f tStr (f tInt (f tInt tStr))) 3
      b "Text.String.byte" "String.byte" [] (f tStr (f tInt (tcon "u8"))) 2
      b "Text.String.ofByte" "String.ofByte" [] (f (tcon "u8") tStr) 1
      b "Text.String.indexOfFrom" "String.indexOfFrom" [] (f tStr (f tStr (f tInt tInt))) 3
      b "Text.String.trim" "String.trim" [] (f tStr tStr) 1
      b "Text.String.toUpper" "String.toUpper" [] (f tStr tStr) 1
      b "Text.String.toLower" "String.toLower" [] (f tStr tStr) 1
      b "Text.String.replace" "String.replace" [] (f tStr (f tStr (f tStr tStr))) 3
      b "Text.String.isFloat" "String.isFloat" [] (f tStr tBool) 1
      b "Native.parseInt" "int.parse" [ kInt ] (f tInt (f tStr (TTuple [ tBool; a ]))) 2
      b "Native.parseFloat" "float.parse" [ kFloat ] (f tStr (TTuple [ tBool; a ])) 1
      b "Float.toBits" "float.toBits" [] (f (tcon "f64") (tcon "u64")) 1
      b "Float.ofBits" "float.ofBits" [] (f (tcon "u64") (tcon "f64")) 1
      b "Native.clockRealtime" "Clock.realtime" [] (f tUnit (tcon "i64")) 1
      b "Native.fileOpen" "File.open" [] (f tStr (f tInt tInt)) 2
      b "Native.fileModified" "File.mtime" [] (f tStr (tcon "i64")) 1
      b "Native.fileSize" "File.size" [] (f tStr (tcon "i64")) 1
      b "Native.fileTouch" "File.touch" [] (f tStr tUnit) 1
      b "Native.fileCopy" "File.copy" [] (f tStr (f tStr tUnit)) 2
      b "Native.fileMove" "File.move" [] (f tStr (f tStr tUnit)) 2
      b "Native.tempFile" "File.temp" [] (f tStr tStr) 1
      b "Native.tempDirectory" "Dir.temp" [] (f tStr tStr) 1
      b "Native.deleteDirectory" "Dir.delete" [] (f tStr tUnit) 1
      b "Native.isSymlink" "File.isSymlink" [] (f tStr tBool) 1
      b "Native.currentDirectory" "Env.cwd" [] (f tUnit tStr) 1
      b "Native.isWindows" "Env.windows" [] (f tUnit tBool) 1
      b "Native.processStart" "Process.start" [] (f tStr (f tStr (f tStr (f tBool (f tStr (f tInt (f tInt (f tInt tInt)))))))) 8
      b "Native.processPipe" "Process.pipe" [] (f tInt tInt) 1
      b "Native.processWait" "Process.wait" [] (f tInt tInt) 1
      b "Native.processKill" "Process.kill" [] (f tInt tInt) 1
      b "Native.unixListen" "Unix.listen" [] (f tStr tInt) 1
      b "Native.unixConnect" "Unix.connect" [] (f tStr tInt) 1
      b "Text.String.toFloat" "String.toFloat" [] (f tStr (tcon "f64")) 1
      b "Native.readLine" "Console.readLineRaw" [] (f tUnit tStr) 1
      b "Native.eof" "Console.eof" [] (f tUnit tBool) 1
      b "eprintln" "eprintln" [] (f tStr tUnit) 1
      b "ref" "ref" [ kAny ] (f a (TCon("ref", [ a ]))) 1
      b "Collections.Array.create" "Array.create" [ kAny ] (f tInt (f a (TCon("array", [ a ])))) 2
      b "Collections.Array.set" "array.update" [ kAny ] (f (TCon("array", [ a ])) (f tInt (f a (TCon("array", [ a ]))))) 3
      b "Collections.Buffer.create" "Array.create" [ kAny ] (f tInt (f a (TCon("Buffer", [ a ])))) 2
      b "Collections.Buffer.length" "Array.length" [ kAny ] (f (TCon("Buffer", [ a ])) tInt) 1
      b "Collections.Buffer.push" "buffer.push" [ kAny ] (f a (f (TCon("Buffer", [ a ])) tUnit)) 2
      b "Collections.Buffer.removeLast" "buffer.removeLast" [ kAny ] (f (TCon("Buffer", [ a ])) a) 1
      b "Collections.Buffer.truncate" "buffer.truncate" [ kAny ] (f tInt (f (TCon("Buffer", [ a ])) tUnit)) 2
      b "Collections.Buffer.blit" "buffer.blit" [ kAny ] (f (TCon("span", [ a ])) (f tInt (f (TCon("Buffer", [ a ])) (f tInt (f tInt tUnit))))) 5
      b "Collections.Array.copy" "array.copy" [ kAny ] (f (TCon("array", [ a ])) (TCon("array", [ a ]))) 1
      b "Collections.Buffer.ofArray" "array.copy" [ kAny ] (f (TCon("array", [ a ])) (TCon("Buffer", [ a ]))) 1
      b "Collections.Buffer.toArray" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("array", [ a ]))) 1
      b "Collections.Buffer.ofSpan" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("Buffer", [ a ]))) 1
      b "Collections.Array.ofSpan" "array.copy" [ kAny ] (f (TCon("span", [ a ])) (TCon("array", [ a ]))) 1
      b "Collections.Span.length" "Array.length" [ kAny ] (f (TCon("span", [ a ])) tInt) 1
      b "Collections.Fixed.length" "fixed.length" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) tInt) 1
      b "Collections.Fixed.get" "fixed.get" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) (f tInt a)) 2
      b "Collections.Fixed.set" "fixed.set" [ kAny; kAny ] (f (TCon("fixed", [ a; TGen 1 ])) (f tInt (f a (TCon("fixed", [ a; TGen 1 ]))))) 3
      b "Collections.Fixed.create" "fixed.create" [ kAny; kAny ] (f a (TCon("fixed", [ a; TGen 1 ]))) 1
      b "Collections.Fixed.ofArray" "fixed.ofArray" [ kAny; kAny ] (f (TCon("span", [ a ])) (TCon("fixed", [ a; TGen 1 ]))) 1
      b "Collections.Span.ofPtr" "span.ofPtr" [ kAny ] (f (TCon("ptr", [ a ])) (f tInt (TCon("span", [ a ])))) 2
      b "Text.String.bytes" "span.ofString" [] (f tStr (TCon("span", [ tcon "u8" ]))) 1
      b "Text.String.ofBytes" "String.ofBytes" [] (f (TCon("span", [ tcon "u8" ])) tStr) 1
      b "Int.wrappingAdd" "wrap+" [ kInt ] (f a (f a a)) 2
      b "Int.wrappingSub" "wrap-" [ kInt ] (f a (f a a)) 2
      b "Int.wrappingMul" "wrap*" [ kInt ] (f a (f a a)) 2
      b "Runtime.allocations" "Runtime.allocations" [] (f tUnit tInt) 1
      b "Environment.exit" "Process.exit" [ kAny ] (f tInt a) 1
      b "Mmio.read32" "mmio.read.u32" [] (f (tcon "usize") (tcon "u32")) 1
      b "Mmio.write32" "mmio.write.u32" [] (f (tcon "usize") (f (tcon "u32") tUnit)) 2
      b "Mmio.read8" "mmio.read.u8" [] (f (tcon "usize") (tcon "u8")) 1
      b "Mmio.write8" "mmio.write.u8" [] (f (tcon "usize") (f (tcon "u8") tUnit)) 2
      b "Runtime.ticks" "Runtime.ticks" [] (f tUnit (tcon "u64")) 1
      b "Math.sqrt" "Math.sqrt" [ kFloat ] (f a a) 1
      b "Ptr.read" "ptr.read" [ kAny ] (f (TCon("ptr", [ a ])) a) 1
      b "Ptr.write" "ptr.write" [ kAny ] (f (TCon("ptr", [ a ])) (f a tUnit)) 2
      b "Ptr.add" "ptr.add" [ kAny ] (f (TCon("ptr", [ a ])) (f tInt (TCon("ptr", [ a ])))) 2
      b "Ptr.null" "ptr.null" [ kAny ] (f tUnit (TCon("ptr", [ a ]))) 1
      b "Ptr.isNull" "ptr.isNull" [ kAny ] (f (TCon("ptr", [ a ])) tBool) 1
      b "Ptr.alloc" "ptr.alloc" [ kAny ] (f tInt (TCon("ptr", [ a ]))) 1
      b "Ptr.free" "ptr.free" [ kAny ] (f (TCon("ptr", [ a ])) tUnit) 1
      b "Ptr.ofCPtr" "ptr.cast" [ kAny ] (f (tcon "cptr") (TCon("ptr", [ a ]))) 1
      b "Ptr.toCPtr" "ptr.cast" [ kAny ] (f (TCon("ptr", [ a ])) (tcon "cptr")) 1
      b "Ptr.cast" "ptr.cast" [ kAny; kAny ] (f (TCon("ptr", [ a ])) (TCon("ptr", [ TGen 1 ]))) 1
      b "Weak.create" "weak.new" [ kAny ] (f a (TCon("weak", [ a ]))) 1
      b "Weak.get" "weak.get" [ kAny ] (f (TCon("weak", [ a ])) (TCon("option", [ a ]))) 1
      b "Arena.with" "arena.with" [ kAny ] (f (f tUnit a) a) 1
      b "Runtime.mallocs" "Runtime.mallocs" [] (f tUnit tInt) 1
      b "Runtime.marks" "Runtime.marks" [] (f tUnit tInt) 1
      // the thread pool (runtime/rt.c), which Std's Parallel wraps: a job runs a function
      // that crossed threads, and its result comes back to the thread that joins it
      b "Native.parFork" "par.fork" [ kAny ] (f (TCon("share", [ f tUnit a ])) tCPtr) 1
      b "Native.parJoin" "par.join" [ kAny ] (f tCPtr a) 1
      b "Native.parWorkers" "par.workers" [] (f tUnit tInt) 1
      // what threads share (Std's Threading): an Atomic holds a number, bool or char, a Mutex
      // and a Channel any value that can be shared
      b "Threading.Atomic.make" "atomic.make" [ kAtomic ] (f a atomic) 1
      b "Threading.Atomic.get" "atomic.get" [ kAtomic ] (f atomic a) 1
      b "Threading.Atomic.set" "atomic.set" [ kAtomic ] (f atomic (f a tUnit)) 2
      b "Threading.Atomic.exchange" "atomic.exchange" [ kAtomic ] (f atomic (f a a)) 2
      b "Threading.Atomic.compareExchange" "atomic.cas" [ kAtomic ] (f atomic (f a (f a a))) 3
      b "Threading.Atomic.add" "atomic.add" [ kNumeric ] (f atomic (f a a)) 2
      b "Threading.Mutex.make" "mutex.make" [ kShare ] (f a mutex) 1
      b "Threading.Mutex.get" "mutex.get" [ kShare ] (f mutex a) 1
      b "Threading.Mutex.set" "mutex.set" [ kShare ] (f mutex (f a tUnit)) 2
      b "Threading.Mutex.update" "mutex.update" [ kShare ] (f mutex (f (f a a) a)) 2
      b "Threading.Channel.make" "chan.make" [ kShare ] (f tInt channel) 1
      b "Threading.Channel.send" "chan.send" [ kShare ] (f channel (f a tUnit)) 2
      b "Threading.Channel.receive" "chan.receive" [ kShare ] (f channel (TCon("option", [ a ]))) 1
      b "Threading.Channel.close" "chan.close" [ kShare ] (f channel tUnit) 1
      // the event loop and sockets (runtime/rt.c), which Std's Task and Tcp wrap
      b "Native.loopPost" "Loop.post" [] (f (f tUnit tUnit) tUnit) 1
      b "Native.loopWait" "Loop.wait" [] (f tInt (f tBool (f (f tUnit tUnit) tUnit))) 3
      b "Native.loopUnwait" "Loop.unwait" [] (f tInt (f tBool tUnit)) 2
      b "Native.loopTimer" "Loop.timer" [] (f tInt (f (f tUnit tUnit) tInt)) 2
      b "Native.loopUntimer" "Loop.untimer" [] (f tInt tUnit) 1
      b "Native.loopStep" "Loop.step" [] (f tUnit tBool) 1
      b "Native.loopJobs" "Loop.jobs" [] (f tUnit tInt) 1
      b "Native.loopClose" "Loop.close" [] (f tUnit tUnit) 1
      b "Native.loopEnter" "Loop.enter" [] (f tUnit tBool) 1
      b "Native.loopLeave" "Loop.leave" [] (f tUnit tUnit) 1
      b "Native.loopBlocking" "Loop.blocking" [] (f (TCon("share", [ f tUnit tUnit ])) (f (f tUnit tUnit) tUnit)) 2
      // tasks on other threads' loops (Task.spawn): the token says which loop gets a result
      b "Native.loopSpawn" "Loop.spawn" [] (f (TCon("share", [ f tUnit tUnit ])) tUnit) 1
      b "Native.loopExpect" "Loop.expect" [] (f (f tUnit tUnit) tInt) 1
      b "Native.loopFulfill" "Loop.fulfill" [] (f tInt tUnit) 1
      b "Native.tcpListen" "Tcp.listen" [] (f tStr (f tInt tInt)) 2
      b "Native.tcpAccept" "Tcp.accept" [] (f tInt tInt) 1
      b "Native.tcpConnect" "Tcp.connect" [] (f tStr (f tInt tInt)) 2
      b "Native.socketError" "Tcp.error" [] (f tInt tInt) 1
      b "Native.fdRead" "Fd.read" [] (f tInt (f (TCon("Buffer", [ tcon "u8" ])) (f tInt (f tInt tInt)))) 4
      b "Native.fdWrite" "Fd.write" [] (f tInt (f (TCon("Buffer", [ tcon "u8" ])) (f tInt (f tInt tInt)))) 4
      b "Native.fdWriteText" "Fd.write" [] (f tInt (f tStr (f tInt (f tInt tInt)))) 4
      b "Native.fdClose" "Fd.close" [] (f tInt tUnit) 1
      b "Native.errorText" "Errno.text" [] (f tInt tStr) 1
      b "Native.argc" "Env.argc" [] (f tUnit tInt) 1
      b "Native.arg" "Env.arg" [] (f tInt tStr) 1
      b "Native.hasVariable" "Env.has" [] (f tStr tBool) 1
      b "Native.getVariable" "Env.get" [] (f tStr tStr) 1
      b "Native.ioOk" "Io.ok" [] (f tUnit tBool) 1
      b "Native.ioError" "Io.error" [] (f tUnit tStr) 1
      b "Native.readFile" "File.readRaw" [] (f tStr tStr) 1
      b "Native.writeFile" "File.writeRaw" [] (f tStr (f tStr tUnit)) 2
      b "Native.appendFile" "File.appendRaw" [] (f tStr (f tStr tUnit)) 2
      b "IO.File.exists" "File.exists" [] (f tStr tBool) 1
      b "Native.deleteFile" "File.deleteRaw" [] (f tStr tUnit) 1
      b "IO.Directory.exists" "Dir.exists" [] (f tStr tBool) 1
      b "Native.createDirectory" "Dir.createRaw" [] (f tStr tUnit) 1
      b "Native.listDirectory" "Dir.listRaw" [] (f tStr tStr) 1
      b "Native.runProcess" "Process.runRaw" [] (f tStr (f tStr tStr)) 2
      b "Native.exitCode" "Process.code" [] (f tUnit tInt) 1
      b "Collections.Array.length" "Array.length" [ kAny ] (f (TCon("span", [ a ])) tInt) 1      ]
  Map.ofList (List.concat [ table; conversions (); simdBuiltins () ])

/// The built-in functions only `unsafe` code may call: raw memory through ptr<T>.
let unsafeBuiltins : Set<string> =
  Set.ofList [ "Ptr.read"; "Ptr.write"; "Ptr.add"; "Ptr.alloc"; "Ptr.free"; "Ptr.ofCPtr"; "Ptr.cast"; "Collections.Span.ofPtr" ]

/// Builtins over arrays that take a span and read an array, a Buffer or a span alike: an argument
/// converted to a span for them is passed as it is (Codegen reads all three).
let overWindows : Set<string> = Set.ofList [ "Array.length"; "array.copy"; "vec.load"; "fixed.ofArray" ]

/// The type of a function built into the compiler, by full name (for `zs doc`).
let builtinType (name: string) : option<Ty> =
  match Map.tryFind name builtins with
  | Some x -> Some x.ty
  | None -> None
