/// A generator seeded from the operating system, which needs one.
namespace Numerics

type Random with
  /// A new generator seeded from the operating system's randomness, so each run's numbers
  /// differ: `Random.shared ()`. A function, since a value threads share can't hold a `Random`.
  static member shared () : Random = Random.create (Native.randomSeed ())
