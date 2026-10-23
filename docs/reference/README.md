# Library reference

One page per module, generated from the library's doc comments by `zs doc` (`tests/reference.sh` regenerates them). How the library is organized is in the guide: [The library](../guide/08-programs.md#the-library).

## Prelude

The names every program has without qualification: the operator traits and their derives, `option` and `result`, the effects `Yield` and `Throw`, and functions such as `print`, `ignore`, `fst` and `min`.

- [prelude](prelude.md)

## Core: every target, microcontrollers included

| Namespace | Modules |
|---|---|
| `Collections` | [List](Collections.List.md), [Array](Collections.Array.md), [Buffer](Collections.Buffer.md), [Span](Collections.Span.md), [Fixed](Collections.Fixed.md), [Map](Collections.Map.md), [Set](Collections.Set.md), [HashMap](Collections.HashMap.md), [HashSet](Collections.HashSet.md), [Seq](Collections.Seq.md) |
| `Text` | [String](Text.String.md), [Char](Text.Char.md), [Json](Text.Json.md) |
| `Time` | [DateTime](Time.DateTime.md) |
| none | [Iter](Iter.md), [Testing](Testing.md), [Binary](Binary.md), [Option](Option.md), [Result](Result.md), [Throw](Throw.md), [Math](Math.md), [Int](Int.md), [Float](Float.md), [Runtime](Runtime.md), [Mmio](Mmio.md), [Ptr](Ptr.md), [Weak](Weak.md), [Arena](Arena.md), [Simd](Simd.md), [Simd.X86](Simd.X86.md), [Simd.Arm](Simd.Arm.md) |

## Std: targets with an operating system

| Namespace | Modules |
|---|---|
| none | [Console](Console.md), [Environment](Environment.md) |
| `IO` | [File](IO.File.md), [Directory](IO.Directory.md), [Path](IO.Path.md), [Reader and Writer](IO.Stream.md) |
| `Diagnostics` | [Process](Diagnostics.Process.md), [Stopwatch](Diagnostics.Stopwatch.md) |
| `Threading` | [Task](Threading.Task.md), [Parallel](Threading.Parallel.md), [Atomic](Threading.Atomic.md), [Mutex](Threading.Mutex.md), [Channel](Threading.Channel.md) |
| `Collections` | [Array.Parallel](Collections.Array.Parallel.md) |
| `Net` | [Tcp](Net.Tcp.md), [Unix](Net.Unix.md) |
| `Time` | [DateTime.utcNow](Time.Clock.md) |
| `Testing` | [Runner](Testing.Runner.md) |
