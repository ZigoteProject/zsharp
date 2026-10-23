// A package with a Util.zs and a dependency of its own (text), which its files see.

/// What beta says, counting words with text.
let describe () = $"beta: {Util.name}, {Text.wordCount Util.name} words"
