# 2. Program structure

## 2.1 Compilation units

A **program** is a set of source files compiled together into one executable, library or
firmware image. It is either

- a **single file**, given to the compiler by name, with the files it reaches beside it; or
- a **package**: a directory with a `zs.toml` manifest naming its main file, together with the
  packages it depends on ([§2.7](#27-packages)).

Every file is a **module**. There is no list of files and no order among them: a file is part
of the program when a module that is part of it names it, and modules are checked in
dependency order.

- Two modules must not depend on each other; a cycle of modules is an error.
- A file's declarations are in order: a declaration may name those above it in the file, itself
  where it is recursive ([§4.1](04-declarations.md#41-let)), and the public declarations of
  other modules.

```text
file        = [ module-header NEWLINE ] { declaration NEWLINE } ;
module-header = 'module' ID | 'namespace' ID ;
```

## 2.2 Modules

**A file's module name** is its path under the directory of the program's main file, each
part capitalized and joined by dots, without the extension: `geometry.zs` is `Geometry`, and
`Shapes/Square.zs` is `Shapes.Square`.

- `module Name` as the file's first declaration names the module `Name` instead.
- `namespace Name` as the first declaration puts the file's types and nested modules in the
  namespace `Name`: they are `Name.T` and `Name.M`. Several files may share one namespace.
  A namespace holds types, modules, traits, effects and derives; the library uses it to put
  `type Map` and `module Map` side by side in `Collections`.

**Nested modules:**

```text
nested-module = 'module' ID '=' INDENT { declaration NEWLINE } DEDENT
              | 'module' ID '=' import ;
```

- Names declared in `module Inner =` inside `Outer` are `Outer.Inner.x`.
- The block sees the names of its enclosing modules without qualification.
- `module Name = import …` makes a module of provided declarations
  ([§4.9](04-declarations.md#49-imports-and-providers)).

## 2.3 Visibility

A declaration is **public** unless marked `private`.

- `let private x`, `type private T`, and `private` on any member of a `let rec … and` or
  `type … and` group make the name visible in its module and in the modules nested in it.
- The fields of a private record type are private too, also where a public value holds one.
- A public declaration may use a private one: a public constant may be defined by a private
  one, and a public function's body may call private functions.
- Using a private name from elsewhere is an error (`'Vault.secret' is private to module Vault`).
- **Package-internal modules:** a file under a package's `internal/` directory is visible to
  that package's files only ([§2.7](#27-packages)).

## 2.4 Name resolution

A name is **qualified** (`List.map`, `Geometry.Shape`) or **unqualified** (`map`).

**An unqualified name** is looked up, nearest first, in:

1. the local scopes of the enclosing expression, innermost first: `let` bindings, parameters,
   pattern variables. A later binding of a name **shadows** an earlier one, in the same block
   too; the two are different variables;
2. the current module, then the modules it is nested in, outward;
3. the modules opened with `open`, the latest first;
4. the prelude ([§12.1](12-builtins.md#121-the-prelude));
5. the library's auto-opened namespaces: `Collections`, `Text`, `IO`, `Diagnostics`,
   `Threading`, `Net`, `Time`, `Numerics`.

**A qualified name** `M.x` resolves `M` by the same steps, as a module, a type (for a static
member or a union case) or an effect (for an operation), then finds `x` in it. Because the
auto-opened namespaces come last, `List.map` means `Collections.List.map` unless the program
defines a `List` module of its own with a `map`, and the full name always works.

```text
open = 'open' ID ;
```

- `open M` makes `M`'s public names available unqualified from that point to the end of the
  enclosing module block (the file, or the nested module).
- An `open` naming no module is an error.

**What belongs to a module.** Values, functions, types, union cases, record fields, traits and
their methods, effects, derives and active patterns all belong to the module that declares
them and follow the rules above. Three lookups use the scopes in a particular way:

- **Record fields.** A record expression, a record pattern, or `.f` on a value whose type is
  not yet known, selects among the record types in scope
  ([§5.4](05-expressions.md#54-records)).
- **Trait methods** are called by their bare name where the trait's module is in scope, and as
  `Module.method` elsewhere ([§7.1](07-traits.md#71-traits)).
- **C functions** declared by `extern` or `import c` are global: one C name is one function,
  reachable bare as well as through the module that declares it
  ([§11.1](11-low-level.md#111-c-interop)).

**Dependencies.** A dependency's modules are named behind its package name: the package
`json`'s main module is `Json` and its `Parser.zs` is `Json.Parser`. Inside the package its
files name each other without the prefix. A package sees its own dependencies only.

## 2.5 Top-level values and startup

A top-level `let` without parameters declares a **top-level value**
([§4.2](04-declarations.md#42-top-level-values)). It is one of:

- a **constant**, which has no run-time initialization: it is as if written out at each use;
- a **static table**, an object in the program's image;
- a **startup value**, computed once when the program starts.

**Startup order.** Before `main` runs, the startup values and the top-level `assert`s that are
not constant are evaluated, module by module in dependency order (a module after those it
depends on), and within a module in declaration order. So no declaration can observe a value
that has not been initialized. Startup values are released when the program exits.

- An initializer must perform no unhandled effect ([§8.5](08-effects.md#85-where-the-row-must-be-empty)).
- A **library** (`--lib`) has no startup: a startup value in one is an error; its top-level
  values must be constants or static tables.

## 2.6 The entry point

A program that is not a library must define, in its main module, a function

```fsharp
let main () = …
```

- `main` takes one `unit` parameter (`'main' must take one unit parameter: let main () = ...`).
- Its result is `int`, `i32` (`c_int`) or `unit`. A number is the process's exit status, as
  the platform truncates it; `unit` exits with 0.
- `main` must perform no unhandled effect.
- The command line is read with `Environment.args ()`; `Environment.exit n` ends the process
  at once.

The program runs the startup of §2.5, then `main`; when `main` returns, the process exits
with its status. On a bare-metal target, returning from `main` stops the core as the runtime
defines (a debugger exit, or sleep).

A file's top-level `[<Tests>]` values make its **test entry**, which `zs test` builds in
place of `main` ([§12.3](12-builtins.md#123-attributes)).

## 2.7 Packages

A package is a directory with a `zs.toml`. The manifest is outside the language proper; what
the language depends on is:

| Manifest | Effect on the program |
|---|---|
| `[package] name`, `main` | the package's name (the prefix of its modules for dependents) and its main file, whose directory is the module root |
| `[package] target` | the default compilation target |
| `[dependencies]` | the packages whose modules are in scope, by path, by git revision or by version |
| `[c]`, `[c.<target>]` | C sources, include paths and libraries linked with the program |
| `[target.<name>]` | per-target settings (a chip's heap size) |
| `[provider]` | the package is a type provider ([§4.9](04-declarations.md#49-imports-and-providers)) |
| `[workspace]` | several packages resolved together |

- **The orphan rule** ([§7.3](07-traits.md#73-coherence)) and **internal modules**
  ([§2.3](#23-visibility)) are the two language rules that depend on package boundaries.
- A second major version of a package is a different package with a name of its own.
- Resolution of versions (minimal version selection), the lock file and vendoring are
  specified in [DESIGN.md §12](../../DESIGN.md#12-tooling).

## 2.8 Library tiers and targets

The library is in two tiers:

- **Core** is available on every target, bare metal included: the prelude, the collections,
  `Text`, `Numerics`, `Time.DateTime`, `Task`, `Atomic`, `Spsc`, `Signal`, the effects,
  `Testing`, and the hardware modules (`Mmio`, `Irq`, `Cpu`, `Bits`, `Ptr`, `Simd`).
- **Std** needs an operating system: `Console`, `Environment`, `IO`, `Diagnostics`, `Net`,
  `Time.Clock`, `Numerics.Entropy`, and the parts of `Threading` that need threads (`Mutex`,
  `Channel`, `Alt`, `Parallel`, `Array.Parallel`).

On a target without an operating system (a microcontroller, freestanding WebAssembly), Std is
not loaded: naming it is an error that says so, and so is depending on a package that uses it.

The target fixes the **machine word**: `int` and `usize` are 64 bits wide on a 64-bit target
and 32 bits on a 32-bit one ([§3.2](03-types.md#32-numbers)). A program whose meaning depends
on the width of `int` is target-dependent; the sized types are not.
