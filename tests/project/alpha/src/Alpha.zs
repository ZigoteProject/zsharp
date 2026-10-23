// A package with a Util.zs, as beta has: from outside they're Alpha.Util and Beta.Util.

/// What alpha says, from its own Util and its Shapes/Square.zs.
let describe () = $"alpha: {Util.name} {Shapes.Square.area 3}"
