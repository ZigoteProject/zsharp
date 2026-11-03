// The sql provider by import (0001): a record per CREATE TABLE, a column an option unless NOT
// NULL or in the primary key, and the table's name and columns in a module of the record's name
module Db = import sql "schema.sql"

let main () =
  let ada: Db.Users = { id = 1; name = "Ada"; ``signed-up`` = "2026-11-03"; active = true }
  println $"{ada.name} {ada.email} {ada.score} {ada.active} {Db.Users.table} {Db.Users.columns}"
  let order: Db.Orders = { id = 7; user_id = ada.id; total = 12.5; note = Some "gift" }
  println $"{order.id} {order.total} {order.note} {Option.isSome order.payload} {Db.Orders.columns}"
  0
