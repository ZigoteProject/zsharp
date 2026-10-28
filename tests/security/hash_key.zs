// A string's hash is keyed per process, so whoever picks a HashMap's keys can't make them all
// collide (HashDoS): test.sh runs this twice and expects two hashes of the same string, each
// run hashing it the same way throughout
let main () =
  let a = hash "zsharp"
  let b = hash ("z" + "sharp")
  println $"{a = b} {a}"
  0
