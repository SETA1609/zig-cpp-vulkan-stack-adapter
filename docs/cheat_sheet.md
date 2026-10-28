# C / C++ / Zig cross-language cheat sheet

A short field guide to the traps you fall into when you mix Zig with C and C++ in the same project. Written for someone who already knows C/C++ and is picking up Zig.

Sections:

1. [Zig syntax that looks like C but isn't](#1-zig-syntax-that-looks-like-c-but-isnt)
2. [Slices, arrays, and string literals](#2-slices-arrays-and-string-literals)
3. [Error unions vs optionals](#3-error-unions-vs-optionals)
4. [Zig 0.16 and 0.17 changes (Io, ArrayList, main, translate-c)](#4-zig-016-and-017-changes-io-arraylist-main-translate-c)
5. [The FFI boundary: linking C and C++ from Zig](#5-the-ffi-boundary-linking-c-and-c-from-zig)
6. [Stdio buffering across languages (output)](#6-stdio-buffering-across-languages-output)
7. [Stdin across languages (input)](#7-stdin-across-languages-input)
8. [Build script (`build.zig`) traps](#8-build-script-buildzig-traps)
9. [Quick reference table](#9-quick-reference-table)

---

## 1. Zig syntax that looks like C but isn't

Zig deliberately renamed several operators that look identical to C's but have different semantics, to force you to think about it. The big ones:

| You typed (C-style) | Zig wants | Notes |
|---|---|---|
| `&&` | `and` | Logical AND. `&&` doesn't exist. |
| `\|\|` | `or` | Logical OR. `\|\|` doesn't exist. |
| `+` for arrays | `++` | Compile-time array/slice concatenation. `+` is arithmetic only. |
| `*` for "string of bytes" | (no `*`) | Strings are slices: `[]const u8`, NOT `[]const *u8`. The `*` would mean "pointer to single u8". |
| `if (x in list)` | for-loop or helper | Zig has no `in` operator. Loop and `break :blk true`, or write a helper like `containsSuffix`. |
| `for (T x : items)` | `for (items) \|x\|` | Capture is name-only — **no type annotation** on the capture. Zig infers it. |
| Statement without `;` | `;` always | Zig has no automatic semicolon insertion. The last line of a block needs `;` too. |
| `func` (bare reference) | `func()` | A bare identifier `list.toOwnedSlice` is a method reference, not a call. You need the parentheses. |

The one that bites hardest: **`[_]T` is not a type annotation.** It's a length-inference shorthand inside a literal:

```zig
const flags = [_][]const u8{ "-Wall", "-Wextra" };          // OK — inferred length 2
const flags: [_][]const u8 = .{ "-Wall", "-Wextra" };        // ERROR — [_] needs a literal
const flags: [2][]const u8 = .{ "-Wall", "-Wextra" };        // OK — explicit length
```

---

## 2. Slices, arrays, and string literals

Three different things, all related, all trip people up.

| Form | Type | What it is |
|---|---|---|
| `"hello"` | `*const [5:0]u8` | Pointer to a null-terminated array literal. |
| `"hello"[0..]` or annotated | `[]const u8` | Slice — pointer + length, no null terminator guarantee. |
| `[_]u8{1, 2, 3}` | `[3]u8` | Sized array. |
| `&[_]u8{1, 2, 3}` | `*const [3]u8` → coerces to `[]const u8` | The idiomatic way to pass an inline array as a slice. |
| `.{1, 2, 3}` | anonymous tuple/struct | Coerces to whatever the target wants — usually `[N]T`, **not** a slice. |
| `&.{1, 2, 3}` | `*const [N]T` → coerces to `[]const T` | The way to pass an anonymous array literal where a slice is expected. |

**The trap:** when an API wants `[]const T` and you write `.{x, y}`, you'll get a coercion error. Add the `&`:

```zig
addCSourceFiles(.{ .files = .{ "foo.c" } });    // ERROR — files wants []const []const u8
addCSourceFiles(.{ .files = &.{ "foo.c" } });   // OK
```

---

## 3. Error unions vs optionals

Zig splits into two distinct concepts what other languages often blur:

- **Error union** `!T` — "this returns `T` or an error".
- **Optional** `?T` — "this returns `T` or nothing".

A function can return both stacked: `!?T` means "may error; if it doesn't, the value may still be absent."

Two completely different unwrap mechanisms, in a fixed order:

```zig
// Returns !?Entry — error first, then optional.
while (try walker.next()) |entry| {
    //   ^^^                ^^^^^^^
    //   handles the error  handles the optional
    ...
}
```

**Trap:** writing `while (walker.next()) |entry|` without `try` won't compile, because `|entry|` only unwraps an optional, not an error union. You need both.

Cheat:
- `try x` — propagate any error from `x` up the stack.
- `x catch |err| { ... }` — handle an error from `x` inline.
- `x catch unreachable` — assert `x` cannot fail (panics if it does).
- `if (x) |val| { ... }` / `if (x) |val| {...} else {...}` — unwrap an optional.
- `while (x) |val| { ... }` — keep going as long as `x` returns non-null.

---

## 4. Zig 0.16 and 0.17 changes (Io, ArrayList, main, translate-c)

### 0.16 → 0.17 (what this repo had to port)

| 0.16 | 0.17 |
|---|---|
| `@cImport({ @cInclude("shaderc/shaderc.h"); })` | Removed, even in a branch that is never compiled. Put the include in a `.h` file and translate it in `build.zig`: `b.addTranslateC(...)`, then `module.addImport("shaderc_c", translate_c.createModule())` |
| `if (b.args) \|args\| run.addArgs(args);` | `run.addPassthruArgs();` |
| `@typeInfo(E).@"enum".fields` (`field.name`, `field.value`) | `.field_names` and `.field_values`, parallel slices |
| `@intFromEnum(e)` / `@enumFromInt(i)` | `@backingInt(e)` / `@fromBackingInt(i)`. `zig fmt` on 0.17 rewrites these for you |
| `std.Uri.getHostAlloc` | Removed (`std.Io.net.HostName.fromUri`). tiawl's `toolbox` 2.1.3 still calls it, which is why `-Dshaderc` now links the system library |

vulkan-zig `master` (the 0.17 version) also changed the generated bindings:

| Before | vulkan-zig `master` |
|---|---|
| `vk.SurfaceKHR = .null_handle` | `.null` (non-dispatchable handles are `enum(u64) { null = 0, _ }`) |
| `vk.Instance`, `PhysicalDevice`, `Device` as `enum(usize)` | `*opaque {}`: no null value; use `?vk.Instance` and `null`, and `@intFromPtr` / `@ptrCast` instead of int conversions |
| `.{ .transfer_src_bit = true }` | `.{ .transfer_src = true }`; `.@"1_bit"` → `.@"1"` (the `_bit` suffix is gone) |

### ≤ 0.15 → 0.16

If you have an older `build.zig` lying around, several things broke between 0.13 and 0.16. The big ones:

### The Io interface

Every blocking filesystem and stdio call now takes an explicit `io: Io` parameter so different runtimes (sync, threaded, async) can be swapped in.

| Old (≤ 0.15) | New (0.16) |
|---|---|
| `std.fs.cwd()` | `std.Io.Dir.cwd()` |
| `dir.openDir(path, opts)` | `dir.openDir(io, path, opts)` |
| `dir.close()` | `dir.close(io)` |
| `walker.next()` | `walker.next(io)` |
| `std.io.getStdOut().writer()` | `std.Io.File.stdout().writer(io, &buffer)` |

In a build script the value comes from `b.graph.io`. In `main`, it comes from the new entry point signature:

```zig
pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(init.io, "hello\n");
}
```

### ArrayList unmanaged-by-default

`ArrayList(T).init(allocator)` is gone. Initialize with `.empty` and pass the allocator to every mutating method:

```zig
var list: std.ArrayList([]const u8) = .empty;
errdefer list.deinit(allocator);
try list.append(allocator, value);
return list.toOwnedSlice(allocator);
```

### `addExecutable` takes a Module

`root_source_file`/`target`/`optimize` no longer go on the executable directly. Build a Module first and pass `root_module`:

```zig
const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
    .link_libcpp = true,
});
exe_mod.addCSourceFiles(.{ .files = c_sources, .flags = &c_flags });

const exe = b.addExecutable(.{ .name = "demo", .root_module = exe_mod });
```

`linkLibC()` / `linkLibCpp()` on the compile step are gone — set `link_libc` / `link_libcpp` on the Module instead.

---

## 5. The FFI boundary: linking C and C++ from Zig

Calls between Zig, C, and C++ all go through the **C ABI**. That works for free in C, but C++ name-mangles symbols by default, so:

- **C function called from Zig:** declare in Zig with `extern fn name(...) ReturnType;`. Done.
- **C++ function called from Zig:** wrap the *definition* in `extern "C"`:

  ```cpp
  extern "C" void greetFromCpp() {
      std::cout << "..." << std::flush;
  }
  ```

  Without `extern "C"`, the linker sees `_Z11greetFromCppv` (or similar) and Zig's `extern fn greetFromCpp` doesn't find it.

- **Calling Zig from C/C++:** mark the Zig function `export fn`. That gives it a stable C-ABI symbol.

- **Passing types across:** stick to types that exist in C. `i32`/`int32_t`, `u8`/`uint8_t`, `*T`/`T*`, `[*]T` ↔ `T*` (multi-item pointer), `[*c]T` ↔ `T*` (C-pointer that admits null). Slices (`[]T`) are **not** ABI-compatible with anything in C — pass pointer + length as separate arguments instead.

- **Linking the runtimes:** if your program uses `printf` you need libc; if it uses `std::cout` you need libc++. In `build.zig`:

  ```zig
  .link_libc = true,
  .link_libcpp = true,
  ```

---

## 6. Stdio buffering across languages (output)

The most common surprise. When Zig, C, and C++ share `stdout`, output appears out of order because each runtime has its own buffer over the same file descriptor.

| Runtime | Behavior |
|---|---|
| Zig `writeStreamingAll` | **Unbuffered** — goes straight to the fd. |
| C `printf` | Line-buffered on a TTY, **fully buffered** on a pipe/file. Flushes at exit. |
| C++ `std::cout` | Buffered, tied to libc's stdout. Flushes at exit. |
| C `fprintf(stderr, ...)` | **Unbuffered.** No flush needed. |
| C++ `std::cerr` | **Unbuffered.** No flush needed. |
| C++ `std::clog` | Buffered (despite going to stderr). Easy to forget. |

**Symptom:** Zig prints land in the right place; C/C++ prints all bunch up at the end of the program.

**Fix in C:** call `fflush(stdout);` after the print.
**Fix in C++:** end the chain with `<< std::flush` or `<< std::endl`.
**Or:** disable buffering at startup with `setbuf(stdout, NULL);` once, in main or a constructor.

Things this does **not** affect: function calls, return values, structs, memory, threads, signals. Only the buffered streams.

---

## 7. Stdin across languages (input)

The symmetric trap. If two languages each call `read`-style functions on `stdin`, each runtime keeps its own buffer over the descriptor:

- C's `fgets` / `scanf` may read 4 KB from the fd into libc's stdin buffer when you only asked for one line. The leftover bytes sit in libc's buffer, **invisible to Zig** if it tries to read the same fd next.
- Same in reverse: a buffered Zig reader will hide bytes from libc.

**Rule:** pick **one language to own stdin** for the whole program. Read everything from there, then pass parsed values across the FFI boundary as plain function arguments. Don't alternate reads on the same descriptor.

---

## 8. Build script (`build.zig`) traps

Beyond the stdlib renames already covered:

- **`entry.path` from `dir.walk()` is relative to the walked dir,** not to your build root. If you call `walk("src/c")`, you get back `"foo.c"`, not `"src/c/foo.c"`. The compiler will then look for `foo.c` in cwd and fail. Always join with the original `dir_path` before using the result.
- **Headers must NOT be passed to `addCSourceFiles`.** It compiles each file as a translation unit; `.h` files aren't translation units. Filter them out by extension.
- **Subdirectories are walked recursively by `Dir.walk`.** That's usually what you want, but if you have generated/cached files inside a source dir you'll pick those up too. Either ignore them by extension or use `walkSelectively`.
- **Build script panics on error.** It can't recover meaningfully from "I couldn't read the source dir," so `catch |err| std.debug.panic(...)` is the idiomatic way to fail. Don't try to "handle" build-time IO errors gracefully.
- **The script uses `b.allocator`.** It's an arena that lives for the entire build — you don't free anything you allocate from it. Don't rig up a separate allocator unless you have a real reason.
- **API churn is real.** Zig is pre-1.0. Pin a Zig version per project, document it in the README, and expect to do a small migration when you upgrade.

---

## 9. Quick reference table

| Symptom | Likely cause |
|---|---|
| `error: no field named 'X' in struct 'Y'` | API rename across Zig versions. Check stdlib source. |
| `expected []const T, found struct{...}` | Anonymous literal `.{...}` where a slice was needed. Add `&`. |
| `error: '&&' is invalid` | Use `and`. |
| `error: invalid token: '+'` (between arrays) | Use `++`. |
| `for (xs) \|x: T\|` parse error | Drop the type annotation on the capture. |
| `walker.next() \|entry\|` doesn't typecheck | Add `try`: `(try walker.next()) \|entry\|`. |
| `printf` output appears at end of program | Stdio buffering. Add `fflush(stdout)`. |
| `std::cout` output appears at end of program | Same. Add `<< std::flush`. |
| C++ symbol "not found" at link time | Missing `extern "C"` on the C++ definition. |
| C++ link error mentioning `__gxx_personality` or `std::__1::*` | Forgot `linkLibCpp` / `link_libcpp = true`. |
| C function "not found" at link time | Forgot `linkLibC` / `link_libc = true`, or the file wasn't in `addCSourceFiles`. |
| `unable to open file` for source files | `entry.path` was used without joining `dir_path`. |
| Build runs but exe is "Zig only" / segfaults calling extern | C/C++ source list is empty (e.g. wrong `path_to_c`, or your filter rejected everything). |
| `error: missing return statement` | Zig requires `return`; falling off the end is not allowed. |
| `error: expected ';' after statement` | No ASI in Zig — every statement, including the last, needs `;`. |
