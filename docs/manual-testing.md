# Manual / e2e testing — zig-cpp-vulkan-stack-adapter

> The companion to the automated [`src/tests/tdd/`](../src/tests/tdd) suite.
> The only function family that can be proven in-process is **shaderc**
> (pure-CPU GLSL→SPIR-V — fully covered there; run `zig build test-tdd`).
> Everything else on this library returns an **opaque Vulkan handle** or mutates
> **GPU state**, and is only meaningful against a **live Vulkan instance,
> device, and (for surfaces) a real OS window**. Those functions are specified
> here as e2e procedures.
>
> Each entry lists: the API, what to do, and the **pass criterion**. These
> require a machine with a working Vulkan ICD (a real or software GPU —
> `lavapipe`/`llvmpipe` is fine for most). Validation Layers **on** for every
> procedure (`VK_LAYER_KHRONOS_validation`): a procedure only passes with **zero
> validation errors**.

## Coverage status — as of `aad92b9`

What is **proven today**. The `vk` re-export is real from v0.1.0; every other
function (shaderc, volk, surfaces, VMA) is still a `@panic("not implemented")`
stub at this commit. Re-tick each box as its backend lands and the matching TDD
test / e2e procedure passes; bump the commit hash in this heading when you do.

**Automated — `zig build test`** (contract/data, must stay green):

- [x] `vk` re-export exposes the typed Vulkan API + dispatch wrappers
- [x] Wrapper enum values + option defaults (`shaderc`/`vma`) (`src/tests/api_test.zig`)

**Automated — `zig build test-tdd`** (red→green; all RED now):

- [ ] `shaderc.compile` — GLSL→SPIR-V for vertex/fragment/compute, optimize levels, debug info, invalid-source error
- [ ] `shaderc.lastErrorMessage` — diagnostic present & stable after a failed compile

**Manual / e2e** (this document; all UNPROVEN now):

- [ ] §1 volk: `loadBase` / `loadInstance` / `loadDevice`
- [ ] §2 Surface creators: `createX11Surface` / `createWaylandSurface` / `createWin32Surface` / `createAndroidSurface`
- [ ] §3 VMA: `createAllocator`/`destroyAllocator`, `createBuffer`/`destroyBuffer`, `createImage`/`destroyImage`, `mapMemory`/`unmapMemory` (incl. `gpu_only` map fails, leak gate)
- [ ] §4 shaderc device-validity (SPIR-V → `vkCreateShaderModule` → pipeline draw)
- [ ] §5 Cross-library integration (Vulkan clear-color: window → surface → swapchain → present + resize)
- [ ] `nm` headless-Vulkan decoupling check (zero `SDL_`/`x11`/`wayland` symbols)

## Why these can't be unit tests

- **No result a headless assertion can check.** `createBuffer` returns a
  `vk.Buffer` + opaque `*Allocation`; the only proof they are correct is that a
  real device accepts them, the memory is mappable/usable, and validation stays
  silent. There is no pure-data invariant to assert without a device.
- **They need resources a CI box doesn't have.** A `VkInstance` with the right
  extensions, a `VkPhysicalDevice`/`VkDevice`, and a presentable window handle
  are prerequisites — standing them up *is* the integration test.

Where an instance/device is needed, build the minimal bootstrap once and reuse
it across the rows in a section. The companion **platform adapter** supplies the
window handles for the surface section (that pairing is the whole point of the
two libraries).

## How to run these

Drive them from the examples-repo ladder apps (headless rungs for VMA/shaderc,
windowed rungs for surfaces) and short throwaway snippets. Suggested order —
each section unblocks the next: **volk → surfaces → VMA**.

---

## 1. volk — loader / function-pointer tables (v0.2.0)

`loadBase`/`loadInstance`/`loadDevice` populate dispatch tables; "did it work"
means *the function pointers resolve and the calls they enable succeed*.

| API | Procedure | Pass criterion |
| --- | --- | --- |
| `loadBase` | Call `loadBase()` at startup (it `dlopen`s libvulkan), then `vkEnumerateInstanceVersion` / `vkCreateInstance` via the base table. | Base entry points are non-null; `vkCreateInstance` succeeds. `error.VulkanLibraryNotFound` means no loader is installed. |
| `loadInstance` | After `vkCreateInstance`, call `loadInstance(instance)`, then an instance-level call (e.g. `vkEnumeratePhysicalDevices`). | Instance entry points resolve; enumeration returns ≥1 physical device. |
| `loadDevice` | After `vkCreateDevice`, call `loadDevice(device)`, then a device-level call (e.g. `vkGetDeviceQueue`, `vkCreateFence`). | Device entry points resolve and bypass the instance dispatch indirection; the device call succeeds. |

**Cross-check:** if vulkan-zig's own `vk.BaseWrapper`/`InstanceWrapper`/
`DeviceWrapper` are used instead, confirm a frame can be rendered without volk —
volk may be dropped (see `docs/ROADMAP.md`).

## 2. Surface creators (v0.2.0 X11/Win32 · v0.5.0 Wayland/Android)

Each takes **raw OS primitives** (no windowing type) and returns a
`vk.SurfaceKHR`. Proof = the surface is non-null, validation-clean, and a
swapchain built on it **presents frames**. Handles come from the platform
adapter's `get*Handle` getters — this is the **cross-library decoupling test**.

Bootstrap: instance with `VK_KHR_surface` + the platform-specific surface
extension (from `platform.requiredVulkanInstanceExtensions()`), a physical
device whose queue family reports `vkGetPhysicalDeviceSurfaceSupportKHR == true`.

| API | Target | Procedure | Pass criterion |
| --- | --- | --- | --- |
| `createX11Surface` | Linux/X11 | Feed `getX11Handle(win)` → `(display, window)` into it. | Non-null `VkSurfaceKHR`; `vkGetPhysicalDeviceSurfaceSupportKHR` true; swapchain created and **presents** (e.g. clear-color shows on screen). |
| `createWaylandSurface` | Linux/Wayland | Feed `getWaylandHandle(win)` → `(display, surface)`. | As above, on a Wayland session. |
| `createWin32Surface` | Windows | Feed `getWin32Handle(win)` → `(hinstance, hwnd)`. | As above, on `x86_64-windows-gnu`. |
| `createAndroidSurface` | Android | Feed an `ANativeWindow*`. | As above, on device/emulator (deferred target). |
| *(negative)* | any | Pass a bogus/null handle (or mismatched OS getter). | Returns a Vulkan error (not a silent bad handle); no UB, no validation crash. |

**Decoupling invariant (from the examples repo):** a headless-Vulkan binary
(no window) must show **zero `SDL_`/`x11`/`wayland`** symbols — `nm` it. The
surface creators are the *only* place OS primitives enter, and they import no
windowing library.

## 3. VMA — GPU memory allocator (v0.3.0)

All of VMA needs a **real `VkDevice`** (from §1/§2 bootstrap). The allocations
are opaque; proof is round-tripping data through mapped memory and a clean
validation log.

| API | Procedure | Pass criterion |
| --- | --- | --- |
| `createAllocator` | Call with a valid `{physical_device, device, instance}` (api_version default = 1.3). | Returns a non-null `*Allocator`; no validation error. |
| `destroyAllocator` | Destroy at the end, after all buffers/images freed. | No crash; no "object leaked"/"in use" validation error. |
| `createBuffer` | `createBuffer(alloc, &info, .cpu_to_gpu)` for a small `TRANSFER_SRC` buffer. | Returns a valid `vk.Buffer` + non-null `*Allocation`; buffer usable as a copy source. |
| `mapMemory` + write/read | `mapMemory` the `.cpu_to_gpu` buffer, write a known byte pattern, `unmapMemory`, map again, read it back. | The bytes read back **equal** what was written (host-visible round-trip). |
| `mapMemory` on `gpu_only` | Create a `.gpu_only` buffer and try to `mapMemory` it. | **Fails with an error** (not a crash) — `gpu_only` memory is not host-visible, per the doc contract. |
| `unmapMemory` | Unmap a previously mapped allocation. | No crash; a subsequent map still works. |
| `destroyBuffer` | Destroy the buffer+allocation pair from `createBuffer`. | No crash; no leak reported at `destroyAllocator`. |
| `createImage` | `createImage(alloc, &info, .gpu_only)` for a small 2D `SAMPLED`/`TRANSFER_DST` image. | Returns a valid `vk.Image` + non-null `*Allocation`; image usable as a transfer/sample target. |
| `destroyImage` | Destroy the image+allocation pair. | No crash; no leak reported at `destroyAllocator`. |

**Leak gate:** with validation on, a full create→use→destroy cycle followed by
`destroyAllocator` must report **no leaked allocations**. That clean shutdown is
the pass condition for the whole section.

## 4. shaderc — already automated

`compile` and `lastErrorMessage` are pure-CPU and fully covered by
[`src/tests/tdd/`](../src/tests/tdd) suite (`zig build test-tdd`). The
only manual touch worth doing once the bridge lands:

| Check | Procedure | Pass criterion |
| --- | --- | --- |
| End-to-end shader use | Compile a real vertex+fragment pair, feed the SPIR-V to `vkCreateShaderModule`, build a pipeline, draw. | The pipeline links and renders — proves the emitted SPIR-V is **device-valid**, not just magic-word-valid. |
| `#include` / resource limits | If `compile` later grows include resolution, compile a shader with an `#include`. | Resolves and compiles; missing include reports via `lastErrorMessage`. |

## 5. Cross-library integration (the real target)

The reason both libraries exist is to be consumed **together**. The end-to-end
proof lives in the examples repo's **Vulkan clear-color** rung:

1. `platform` opens a `.renderer = .vulkan` window and yields native handles +
   required instance extensions — **no Vulkan type crosses out**.
2. `vulkan_stack` builds the instance, picks a device, and turns those raw
   handles into a `VkSurfaceKHR` — **no windowing type crosses in**.
3. A swapchain clears to a color and presents; resizing recreates the swapchain
   on the platform `.resize` event.

**Pass:** a colored window that survives resize, with validation layers silent,
built against a single shared build of each library.
