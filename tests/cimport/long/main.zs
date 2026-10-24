// C's long by the target's data model: 64 bits on Linux and macOS, 32 on Windows (LLP64), its
// header read with the target's system headers (stdio.h: mingw-w64's for Windows)
import c "lib.h"

let main () = println $"{twice 21} {width ()}"
