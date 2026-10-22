# Ptr

Raw C pointers: `ptr<T>` points at C data (a number, a `bool`, a `[<CLayout>]` record or
another pointer), for C libraries that hand out or take memory. Reading, writing, pointer
arithmetic and casts are unsafe: they compile only inside `unsafe`, as calls through a C
function pointer (`fnptr<A -> R>`) do. Its functions are built into the compiler.

## Functions

### `Ptr.add`

```zsharp
Ptr.add : ptr<'a> -> int -> ptr<'a>
```

The pointer moved by a number of elements (pointer arithmetic). Unsafe.

### `Ptr.alloc`

```zsharp
Ptr.alloc : int -> ptr<'a>
```

C memory for a number of elements, zeroed (C's `calloc`); give it back with `Ptr.free`. Unsafe.

### `Ptr.cast`

```zsharp
Ptr.cast : ptr<'a> -> ptr<'b>
```

The same address as a pointer to another type. Unsafe.

### `Ptr.free`

```zsharp
Ptr.free : ptr<'a> -> unit
```

Frees memory from `Ptr.alloc` (C's `free`). Unsafe.

### `Ptr.isNull`

```zsharp
Ptr.isNull : ptr<'a> -> bool
```

Whether the pointer is null.

### `Ptr.null`

```zsharp
Ptr.null : unit -> ptr<'a>
```

The null pointer.

### `Ptr.ofCPtr`

```zsharp
Ptr.ofCPtr : cptr -> ptr<'a>
```

A C pointer (`cptr`, as `import c` gives one) as a typed pointer. Unsafe.

### `Ptr.read`

```zsharp
Ptr.read : ptr<'a> -> 'a
```

The value the pointer points to. Unsafe: only inside `unsafe`.

### `Ptr.toCPtr`

```zsharp
Ptr.toCPtr : ptr<'a> -> cptr
```

The pointer as a `cptr`, to pass to a C function that takes one.

### `Ptr.write`

```zsharp
Ptr.write : ptr<'a> -> 'a -> unit
```

Writes the value where the pointer points. Unsafe.

