# Enum numeric values — `vulkan_stack`

> Stable name → integer-value maps for this library's **own** wrapper enums,
> for **serialization**: build manifests, asset pipelines, or any text/binary
> boundary that records a stage or memory usage by number. Inside Zig code
> always use the named field (`.vertex`, `.gpu_only`) — reach for these
> numbers only when crossing a boundary.
>
> This covers only the enums *this adapter defines*. The re-exported `vk`
> enums (`vk.Format`, `vk.Result`, …) are generated from `vk.xml` by
> vulkan-zig and carry the official Vulkan values — consult the Vulkan
> registry for those, not this file.
>
> Generated from `src/`. Values are assigned in declaration order from `0`;
> **append new fields at the end** to keep existing numbers stable. All three
> are closed enums backed by `u8`.

## Backing widths

| Enum | Source | Tag type |
| --- | --- | --- |
| `shaderc.Stage` | `src/shaderc.zig` | `u8` |
| `shaderc.OptimizeLevel` | `src/shaderc.zig` | `u8` |
| `vma.Usage` | `src/vma.zig` | `u8` |

## Values

```json
{
  "shaderc.Stage": {
    "vertex": 0,
    "fragment": 1,
    "compute": 2,
    "geometry": 3,
    "tess_control": 4,
    "tess_eval": 5
  },
  "shaderc.OptimizeLevel": {
    "none": 0,
    "size": 1,
    "performance": 2
  },
  "vma.Usage": {
    "auto": 0,
    "gpu_only": 1,
    "cpu_to_gpu": 2,
    "gpu_to_cpu": 3
  }
}
```

## Regenerating

These maps are derived, not hand-maintained. To regenerate after editing the
enums, dump `@intFromEnum` over `@typeInfo(T).@"enum".fields` for each enum in
`src/`, and paste the result above.
