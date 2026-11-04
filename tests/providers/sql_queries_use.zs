// The sql provider's named queries (0001): each a module with its text (? for each parameter),
// its parameters typed from the columns they meet, and the row it gives, typed from the schema
module Db = import sql ("schema.sql", queries = "queries.sql")

let main () =
  println $"{Db.GetUser.sql} | {Db.GetUser.kind} | {Db.GetUser.parameters}"
  let p: Db.GetUser.Params = { id = 7 }
  let row: Db.GetUser.Row = { id = p.id; name = "Ada" }
  println $"{row.id} {row.name} {row.email}"
  // SELECT * is the table's columns
  let active: Db.ListActive.Row = { id = 1; name = "Bob"; ``signed-up`` = "2026"; active = true }
  println $"{active.active} {active.score} {Db.ListActive.parameters}"
  // a join: columns by alias, an expression named AS n
  let o: Db.OrdersFor.Row = { id = 1; total = 9.5; buyer = "Ada"; n = 2 }
  let q: Db.OrdersFor.Params = { user = 1; least = 5.0 }
  println $"{o.buyer} {o.n} {q.least} {Db.OrdersFor.sql}"
  // INSERT's values by position, UPDATE's ? by position
  let add: Db.AddUser.Params = { name = "Cy"; active = false }
  println $"{add.email} {Db.AddUser.sql} | {Db.Rename.parameters}"
  0
