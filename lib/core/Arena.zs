/// Arenas: bulk allocation freed at once. What a function given to `Arena.with` allocates comes
/// from the arena's large blocks, a malloc each, instead of a malloc per object; the blocks are
/// freed together when the last of those objects goes. Nothing can outlive its memory: an object
/// that lives on keeps its arena's blocks. Its functions are built into the compiler.
module Arena
