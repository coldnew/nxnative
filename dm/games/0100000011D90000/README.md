# Pokemon Brilliant Diamond

Experimental native port of the base game, version 1.0.0 / v0. No update NSP was
provided. Unity 2019.4.27f1 IL2CPP, Nintendo SDK 11.4.3, NVN, FMOD and Wwise.
No iPhone or LiveContainer gameplay test has been performed.

The SDK and movie builds are shared with Metroid Dread and 13 Sentinels. With
virtual address memory enabled, StandardAllocator initialization aborted before
nnMain at sdk+0x145038 (main caller +0x2aa900). The established node-area reduction
from approximately 1 GiB to 62 MiB makes startup fit the 5 GiB guest layout.
`nso_fnmap.py` mapped the constructor from SDK 14; disassembly checked both movs
at sdk+0x34e0c8 and +0x34e164, gated on SDK build
`2d369d9999e3e10e665106f840ffff9b` in `dm/tools/sdk_patches.py`.

The built-in ComputeShader objects have type hash
`1a95529ac2eb1a97cd9d2a4356bd722f`. Unlike Unity 2020's variant maps and 2022's
variant arrays, this 2019 layout stores each kernel's name, resources and code
directly. `unityfs.py` reads that layout and `shader_split.py` accepts the direct
kernels. This adds 19 kernels, for 20 compute shaders in the full inventory.
The schema was checked against generated field-layout evidence in TypeTreeDumps
commit `20ba06e00e0625de0e49a502c6868d6cc86d0f0b`,
`StructsDump/release/2019.4.27f1.dump:2780` (class 72). That repository lists no
license file; no executable implementation was adapted from it.

FMOD stops its initial AudioOut and joins its worker when changing scenes
(main+0x1334a60). The worker waits on the buffer-release event at main+0x1334ba8;
stopping playback without returning its queued buffers leaves that wait blocked.
`hle_audio.c` now releases the partial and queued buffers in order after stopping
the backend, and signals the release event. Stopping an already-stopped output
preserves buffers queued before the first Start. The audio test covers both real
and silent backends, the event wake-up, and repeated stops. Reference behavior:
Ryujinx commit `f556c80d0230056335632b60c71f1567e177239e`,
`Ryujinx.Audio/Common/AudioDeviceSession.cs:281-305,364-376`
(LGPL-3.0-or-later in that file; behavior inspected, implementation independent).

Shader inventory: 14,385 keys; 14,384 compile for Mac and iOS. The remaining
geometry shader `2c7d63f41f497354` is Unity's built-in
`Hidden/VR/BlitFromTex2DToTexArraySlice#var19.2`, unused on the tested opening route.
Do not claim all shaders compile or full-game compatibility.

Mac bring-up reaches character and rival naming, the opening TV dialogue, and
bedroom controls. Audio PCM is nonzero and the host regression suite passes.
Physical memory measured approximately 2 GiB in the bedroom; this is not an
iPhone measurement.

Known rendering blocker: the bedroom TV produces excessive HDR brightness that
bloom spreads over the room. Draw isolation identifies `Delphis/Map/LineUVScroll`
(vertex `b8b1925cc16f8247`, fragment `bf70b833d622277c`). Captured inline uniforms
give its vertex animation period as zero, producing non-finite color arithmetic;
safe Metal math for this pair did not resolve the bloom. No shader skip or
unverified color clamp is included in the release. This remains an experimental
build, not a verified playable port.
