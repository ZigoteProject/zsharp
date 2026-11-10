// a module tests/record_reach.zs and tests/err_record_reach.zs use by its qualified names
module ReachDb

type Line = { id: int; text: string; who: string }

type private Secret = { token: string }

let lines () : list<Line> =
  [ { id = 1; text = "hi"; who = "a" }; { id = 2; text = "yo"; who = "b" } ]
