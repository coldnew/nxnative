# Rune Factory 3 Special

Experimental Mac bring-up for the Asian release, update 1.0.3 / v196608.
Unity 2020.3.40f1 IL2CPP, Nintendo SDK 14.3.0, NVN, CRI movies/audio.
No iPhone or LiveContainer gameplay test has been performed.

The native game plugin is `Plugins/SanDLL.nro` (build
`7deb00afb04e5dec365e15bf741a78be`). `nro_modules` sends it through the same
rewriter and executable embedding as the static modules. The host matches its
build ID when Unity calls `nn::ro::LoadModule`, runs its constructors then,
and looks up exports through the SDK's copyable Module handle. This is prepared
plugin support; arbitrary runtime-generated code is not loaded.

SDK build `2aef2cffb104ee7c9e212fd2f4c731e9` needs the established node-area
reduction to 62 MiB (`patch_nso.py`, sdk+0x12d8b0 and +0x12d94c). Without it,
StandardAllocator initialization aborts before nnMain at sdk+0x11f308.
The 1 GiB application-pool setting also matters: nninitStartup reserves
pool minus used in StandardAllocator, while Unity separately reserves resource
regions. The default pool exhausts the 5 GiB guest address layout, first failing
the plugin BSS allocation and then corrupting asset loads when allocation errors
are ignored. An 8 GiB diagnostic reservation avoided those early crashes;
the smaller pool fits the tested route in 5 GiB. This is address-space sizing,
not a claim that the whole process uses only 1 GiB of physical memory.

Unity's built-in compute shaders use type hash
`d0171b849bb064b2424893e7d4809be5`: kernel variants are a map, before Unity
2022's deduplicated array. The reader extracts 56 kernels, including skinning
and blend shapes. Leaving those out distorts the 3D models into long triangles.

Shader inventory: 4,023 keys, of which 4,022 compile for Mac and iOS. The remaining
key `fba3c62500b434b6` is the built-in geometry shader
`Hidden/VR/BlitFromTex2DToTexArraySlice`; it has not been requested on the tested
route. Geometry shaders outside the existing slice-folding pattern remain
unsupported. Do not report all shaders as compiled or full-game compatibility.

Validation includes startup logos and movie, title/new-game input, Traditional
Chinese story dialogue, skinned 3D characters and scenery, PCM output, and the
host regression suite (including copied NRO handles). A 90-second story run had
no RED lines or crashes and a 1,750–1,751 MiB footprint over its final 30 seconds.
These are Mac measurements, not phone memory or performance guarantees.

Binary disassembly and local source inspection supplied the implementation
checks. Relevant external format evidence:

- Atmosphere `6b0c077b4c608a3a2ee712b8dc35fee87ceb62e8`,
  `stratosphere/ro/source/impl/ro_nro_utils.cpp:55–65`: segment permission/layout
  behavior (GPL-2.0; inspected for behavior, no source copied).
- TypeTreeDumps `20ba06e00e0625de0e49a502c6868d6cc86d0f0b`,
  `StructsDump/release/2020.3.40f1.dump:3513–3662`: generated field-layout
  evidence, checked against the game's serialized objects. The repository lists
  no license file; no executable implementation was adapted from it.
- SDK disassembly: `GetBufferSize` at +0x135130 reads BSS size from NRO+0x38;
  `LoadModule` at +0x135620 stores state 1 at Module+8 and image/BSS at +0x10;
  Unity main+0x5baa30 copies that Module by value. Host tests cover that copy.

A subsequent 180-second route ended cleanly with no RED or crash lines, advanced
the story through the town scene to name entry, and measured 1,762–1,764 MiB
footprint over seconds 150–180. Input used automatic button presses; free
movement was not established by that particular route.

Name entry checks the SDK's dictionary version before calling the word filter
(main+0x213f4a0, with the zero branch at +0x213f4a4). The offline host already
reports successful filter initialization and an empty dictionary; it now reports
revision 1 for that dictionary. Revision 0 means missing content to this wrapper
and rejects every name without a word check. The confirmation dialog defaults
to Cancel, so automated routes must select Left before A to accept the name.
The corrected route accepts `Micah` and continues the story (frame 6,600).
The dictionary policy regression checks both a nonzero content version and zero
word-result masks through the registered SDK symbol names.
The final route reaches the playable town with its HUD and minimap. Screenshots
at frames 10,000, 10,200 and 10,600 verify left-stick right turns the character
and left-stick up walks up the tree's stairs (the minimap position and camera
change). This verifies initial free movement on Mac, not full-game or iOS
compatibility.
