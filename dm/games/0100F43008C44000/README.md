# Pokémon Legends: Z-A 2.0.2

The iPhone 15 Pro failure log used shader chain `73182a4469b2`. The first GPU
hang is fence 2104, frame 2103. Subsequent submissions are ignored by Metal;
continuing to submit does not restore the picture. The preceding memory sample
has 1,425 MiB headroom, so the log does not establish a memory-limit failure.

Two invalid graphics paths were found during investigation:

- A depth/stencil texture was created without `PixelFormatView`, then read as an
  `X32_Stencil8` view. Metal API validation aborts this operation. Combined
  depth/stencil textures now request view usage at creation; a stencil bind
  retains the backing texture and the rendered values.
- Shader `2bd5037003980716` performs atomics on an R32Uint 2D array. The observed
  image is 480 by 270 by 3. MSL 2.3 emits a linear atomic pointer and a coordinate
  helper that drops the layer. The replay redirected this pointer to a 64 KiB
  dummy buffer, although even one plane contains 518,400 bytes. Normal shaders
  with 2D image-atomic pointers now use SPIRV-Cross's MSL 3.1 native atomics. The
  replay binds the real image with atomic usage. Legacy block-linear atomic
  pointer bindings stop with a rebuild diagnostic instead of risking a GPU write
  outside the dummy buffer. Buffer-only atomic shaders retain their existing path.

The A17 Pro also needs the integer-LOD min-filter fallback for Hi-Z shaders
`151607c7a92386cc` and `ec5ebd6d9902a9a1` at slot 17; native sampler reduction
requires Apple10. The established guest heap and RomFS are unchanged. The earlier
CPU-only pool-hashing experiment is not part of this branch's fix.

Regression coverage reads 388,800 atomic results across three layers, plus both
NVN depth/stencil formats and the preserved stencil bits under Metal validation.
Mac validation cannot confirm an iPhone driver failure is resolved: a fresh device
run and its log remain necessary. Do not describe this as full-game validation.

## References inspected

Local MIT source at `eab15b5a7e339d172ba7cd6b1a298ec3cf1e16b6`:
`dm/gfx/nvn/nvn_mtl.m:1294` (`tex_need_pfv`), `:1424` (`tex_desc`), and the
`NVN_RB_IMGA` branch in `encode_args_`. No peer implementation was copied.

SPIRV-Cross commit `300681bbcb8365a8d1eacdacdbdd0249bbf1d6b1`,
[spirv_msl.cpp:10826](https://github.com/KhronosGroup/SPIRV-Cross/blob/300681bbcb8365a8d1eacdacdbdd0249bbf1d6b1/spirv_msl.cpp#L10826)
selects native image atomics at MSL 3.1; lines 5896 and 9468 show the older linear
coordinate calculation. Its file is Apache-2.0 OR MIT; the build invokes its
existing compiler feature without adapting its implementation.
Apple documents the [stencil-plane view](https://developer.apple.com/documentation/metal/mtlpixelformat/x32_stencil8)
and [format-view usage](https://developer.apple.com/documentation/metal/mtltextureusage/pixelformatview).
