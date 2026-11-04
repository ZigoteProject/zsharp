/// Integer literals as the optimizer may take them: a pattern's literal that isn't a value of its
/// type (`| 256` at u8) is compared by the code at the type's width, where it's another value,
/// so no pass may decide a match holding one at compile time; Simplify and Decide leave it as
/// written.
open Types.Ty
open Core.Ir
open Core.Program

/// Whether an integer is a value of the type: `int` and `usize` taken as 32 bits (a chip's word),
/// a char a scalar value, any bits an i64's or a u64's (one at or above 2^63 is held negative).
let fits (t: Ty) (n: i64) : bool =
  match t with
  | TCon("i8", []) -> n >= i64 -128 && n <= i64 127
  | TCon("i16", []) -> n >= i64 -32768 && n <= i64 32767
  | TCon("i32", [])
  | TCon("int", []) -> n >= i64 -2147483648 && n <= i64 2147483647
  | TCon("u8", []) -> n >= i64 0 && n <= i64 255
  | TCon("u16", []) -> n >= i64 0 && n <= i64 65535
  | TCon("u32", [])
  | TCon("usize", []) -> n >= i64 0 && n <= i64 4294967295
  | TCon("char", []) -> n >= i64 0 && n <= i64 0x10FFFF
  | _ -> true

/// Whether every integer literal in the pattern, at any depth, is a value of its type (t: the
/// value matched; a case's or a record's fields typed from its definition).
let patternFits (types: Map<string, TypeInfo>) (t: Ty) (p: CPat) : bool =
  let v = Types.Vars.make ()
  let rec go (t: Ty) (p: CPat) : bool =
    let all (ts: list<Ty>) (ps: list<CPat>) =
      List.length ts <> List.length ps || List.forall (fun (x, q) -> go x q) (List.zip ts ps)
    match p with
    | CPInt n -> fits t n
    | CPTuple ps ->
      match t with
      | TTuple ts -> all ts ps
      | _ -> true
    | CPCtor(_, tag, ps) ->
      match t with
      | TCon(u, args) ->
        match Map.tryFind u types with
        | Some { def = UnionDef cs } when tag >= 0 && tag < List.length cs -> all (List.map (Types.Norm.substGen v args) (snd (List.item tag cs))) ps
        | _ -> true
      | _ -> true
    | CPRecord(_, fs) ->
      match t with
      | TCon(r, args) ->
        match Map.tryFind r types with
        | Some { def = RecordDef rfs } ->
          let one (fq: string * CPat) =
            let (f, q) = fq
            match List.tryFind (fun (n, _) -> n = f) rfs with
            | Some(_, ft) -> go (Types.Norm.substGen v args ft) q
            | None -> true
          List.forall one fs
        | _ -> true
      | _ -> true
    | CPOr(a, b) -> go t a && go t b
    | CPAs(a, _, _) -> go t a
    | _ -> true
  go t p
