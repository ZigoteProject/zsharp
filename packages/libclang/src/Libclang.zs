// libclang's C API (clang-c/Index.h and the headers it includes): its names as libclang has
// them, and the few functions below that make it suit Z#.
import c "clang-c/CXErrorCode.h"
import c "clang-c/CXString.h"
import c "clang-c/CXFile.h"
import c "clang-c/CXSourceLocation.h"
import c "clang-c/CXDiagnostic.h"
import c "clang-c/Index.h"

extern zs_clang_visit_children : CXCursor -> callback<ptr<CXCursor> -> i32> -> u32
extern zs_clang_text : CXString -> cstr
extern zs_clang_parse : cptr -> cstr -> span<u8> -> i32 -> u32 -> cptr

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

/// The cursors of the declarations in a file, by the spelling of each, in order (what a header
/// declares, without what it includes).
let declarations (tu: cptr) : list<string> =
  let names = ref []
  visitChildren (clang_getTranslationUnitCursor tu) (fun c ->
    if clang_Location_isFromMainFile (clang_getCursorLocation c) <> 0 then
      names.Value <- text (clang_getCursorSpelling c) :: names.Value
    CXChildVisit_Continue)
  List.rev names.Value

[<Test>]
let readsAHeader () =
  let dir = Directory.createTemp "libclang"
  match dir with
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
    Directory.deleteRecursive dir |> ignore
