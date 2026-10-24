// libclang's C API (c/clang.h: the part of clang-c/Index.h this package uses), its names as
// libclang has them, and the functions below that make it suit Z#. libclang is opened at the first
// call into it, so a program using this package starts where it isn't installed.
import c "clang.h"

extern zs_clang_load : unit -> i32
extern zs_clang_visit_children : CXCursor -> callback<ptr<CXCursor> -> i32> -> u32
extern zs_clang_text : CXString -> cstr
extern zs_clang_parse : cptr -> cstr -> span<u8> -> i32 -> u32 -> cptr
extern zs_clang_resource_dir : unit -> cstr

/// Whether libclang is here, opened from $ZS_LIBCLANG, else beside the first clang on PATH, else
/// from the system's libraries. A libclang function called where it isn't stops the program.
let available () : bool = zs_clang_load () <> 0

/// clang's resource directory beside the libclang opened (its own headers, stdbool.h and the
/// like), for `-resource-dir`: an LLVM release's libclang doesn't find it by itself. Empty when
/// there's none there.
let resourceDir () : string = String.ofCStr (zs_clang_resource_dir ())

/// A CXString's text, copied (empty for a null one); the CXString is disposed.
let text (s: CXString) : string =
  let t = String.ofCStr (zs_clang_text s)
  clang_disposeString s
  t

/// Calls f on each child of the cursor in order. f returns CXChildVisit_Continue for the next
/// sibling, CXChildVisit_Recurse to visit this child's children first, or CXChildVisit_Break to
/// stop.
let visitChildren (c: CXCursor) (f: CXCursor -> i32) : unit =
  zs_clang_visit_children c (fun p -> f (unsafe Ptr.read p)) |> ignore

/// A file's translation unit, parsed with clang's arguments (`-I dir`, `-D NAME`) and
/// clang_parseTranslationUnit's options; None when clang couldn't parse it at all (its
/// diagnostics say why when it could).
let parse (index: cptr) (file: string) (args: list<string>) (options: u32) : option<cptr> =
  let joined = String.concat (List.map (fun a -> a + "\0") args)
  let tu = zs_clang_parse index file (String.bytes joined) (i32 (List.length args)) options
  let p: ptr<u8> = unsafe Ptr.ofCPtr tu
  if Ptr.isNull p then None else Some tu

/// The cursor's children, in order.
let children (c: CXCursor) : list<CXCursor> =
  let found = ref []
  visitChildren c (fun x ->
    found.Value <- x :: found.Value
    CXChildVisit_Continue)
  List.rev found.Value

/// Where a location is expanded: its file (empty for a built-in), line and byte offset.
let place (l: CXSourceLocation) : string * int * int =
  let file: ptr<cptr> = unsafe Ptr.alloc 1
  let nums: ptr<u32> = unsafe Ptr.alloc 3
  clang_getExpansionLocation l (Ptr.toCPtr file) (Ptr.toCPtr nums) (Ptr.toCPtr (unsafe Ptr.add nums 1)) (Ptr.toCPtr (unsafe Ptr.add nums 2))
  let f = unsafe Ptr.read file
  let named: ptr<u8> = unsafe Ptr.ofCPtr f
  let name = if Ptr.isNull named then "" else text (clang_getFileName f)
  let line = int (unsafe Ptr.read nums)
  let offset = int (unsafe Ptr.read (unsafe Ptr.add nums 2))
  unsafe Ptr.free file
  unsafe Ptr.free nums
  (name, line, offset)

/// The tokens a cursor spans, in order: each one's spelling and the byte offsets where it starts
/// and ends in its file.
let tokens (tu: cptr) (c: CXCursor) : list<string * int * int> =
  let out: ptr<cptr> = unsafe Ptr.alloc 1
  let count: ptr<u32> = unsafe Ptr.alloc 1
  clang_tokenize tu (clang_getCursorExtent c) (Ptr.toCPtr out) (Ptr.toCPtr count)
  let first: ptr<CXToken> = unsafe Ptr.ofCPtr (unsafe Ptr.read out)
  let offset (l: CXSourceLocation) =
    let (_, _, o) = place l
    o
  let one (i: int) =
    let t = unsafe Ptr.read (unsafe Ptr.add first i)
    let r = clang_getTokenExtent tu t
    (text (clang_getTokenSpelling tu t),
      offset (clang_getRangeStart r),
      offset (clang_getRangeEnd r))
  let n = int (unsafe Ptr.read count)
  let ts = List.init n one
  clang_disposeTokens tu (unsafe Ptr.read out) (u32 n)
  unsafe Ptr.free out
  unsafe Ptr.free count
  ts

/// A translation unit's errors (fatal ones too), as clang prints them: `file:line:col: error: …`.
let errors (tu: cptr) : list<string> =
  let one (i: int) =
    let d = clang_getDiagnostic tu (u32 i)
    let shown =
      if clang_getDiagnosticSeverity d >= CXDiagnostic_Error then
        Some(text (clang_formatDiagnostic d (u32 (CXDiagnostic_DisplaySourceLocation ||| CXDiagnostic_DisplayColumn))))
      else
        None
    clang_disposeDiagnostic d
    shown
  List.choose one (List.init (int (clang_getNumDiagnostics tu)) (fun i -> i))

/// The cursors of the declarations in a file, by the spelling of each, in order (what a header
/// declares, without what it includes).
let declarations (tu: cptr) : list<string> =
  let names = ref []
  visitChildren (clang_getTranslationUnitCursor tu) (fun c ->
    if clang_Location_isFromMainFile (clang_getCursorLocation c) <> 0 then
      names.Value <- text (clang_getCursorSpelling c) :: names.Value
    CXChildVisit_Continue)
  List.rev names.Value

[<Tests>]
let tests =
  Testing.test "reads a header" (fun () ->
    match Directory.createTemp "libclang" with
    | Error e -> panic e
    | Ok dir ->
      let header = Path.combine dir "shapes.h"
      File.writeAllText header "#include <stddef.h>\nstruct point { int x; int y; };\nint area(struct point p, size_t n);\n"
      |> ignore
      let index = clang_createIndex 0 0
      match parse index header [ "-x"; "c"; "-DSIDES=4" ] (u32 0) with
      | None -> panic "clang couldn't parse shapes.h"
      | Some tu ->
        assert (declarations tu = [ "point"; "area" ])
        clang_disposeTranslationUnit tu
      clang_disposeIndex index
      Directory.deleteRecursive dir |> ignore)
