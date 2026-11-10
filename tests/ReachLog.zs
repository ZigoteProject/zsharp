// a second module with a record of ReachDb.Line's field names (tests/err_record_reach.zs)
module ReachLog

type Entry = { id: int; text: string }

let entries () : list<Entry> = [ { id = 7; text = "log" } ]
