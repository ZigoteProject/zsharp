// a computation expression's forms need the builder's functions: here bind, for let!
module Counter =
  module Builder =
    let delay f = f ()
    let ret x = x

let main () =
  let n =
    counter {
      let! x = 1
      return x
    }
  println $"{n}"
  0
