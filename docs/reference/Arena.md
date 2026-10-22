# Arena

Arenas: bulk allocation freed at once. What a function given to `Arena.with` allocates comes
from the arena's large blocks, a malloc each, instead of a malloc per object; the blocks are
freed together when the last of those objects goes. Nothing can outlive its memory: an object
that lives on keeps its arena's blocks. Its functions are built into the compiler.

## Functions

### `Arena.with`

```zsharp
Arena.with : (unit -> 'a) -> 'a
```

Runs the function with an arena: what it allocates comes from the arena's blocks, freed at once when the last of those objects goes (when the function returns, unless something it made lives on).

