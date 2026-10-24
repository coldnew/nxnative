# FINAL FANTASY RESONANCE DEMO 1.0.0

This profile is for the separate demo title `0100517027E86000`, not the retail
`0100606026F12000` profile. The input identifies itself as FINAL FANTASY RESONANCE
DEMO, version 1.0.0, Unreal Engine 5.6.1, Nintendo SDK 20.5.17, with NVN and CRIWARE.
Bring-up is in progress; this note does not claim target-phone validation.

## Executable identities

- `main`: `dd0dc94da6f6e6d7270119601bb06d86`.
- `subsdk0`: `ab62fe8edd07a6a293f885d54359e559` (NintendoSDK_movie).
- `sdk`: `0023a1b06130cd795f7bc4613772af0a`.

The SDK and movie builds match retail, so the existing build-checked SDK node-area
patch applies. The demo main was independently disassembled before adding its
allocator registration; retail addresses were not applied to it.

## Allocator evidence

`nninitStartup` exports a branch at `main+0x352f8d0` to `+0x13370`. It reads
`-SwitchVirtualAddressSpaceSize=` and reserves the engine region at `+0x137d0`.
At `+0x137e4..+0x137f0` it passes object `+0x77f9210` to constructor `+0xaee70`.
The call bytes are `a06d0294`, checked by `patches.py` before replacing the call
with a nop. The constructor writes the 32-slot FMallocBinned3 vtable `+0x680f810`.
`BaseAllocator` at `+0x13c64` returns that same object. The TLS callbacks at
`+0x13830` and `+0x13870` call vtable offsets `+0x30` (Malloc) and `+0x50` (Free).

The vtable was checked directly: slots 7/9 forward to Malloc/Realloc, slots 11/12
share the zeroed-allocation wrapper that calls Malloc then clears the result,
and the remaining slots fit the existing host `UE5_6` layout. The host reuses
that general allocator implementation, gated by the demo main's build ID.

The engine region is capped at 4064 MB inside a 5 GiB guest layout. The profile
retains the game's 30 fps pacing during bring-up and uses the full 3D controller
layout. Runtime validation is recorded below.

## Packaging

The deliverable is one unsigned IPA containing the executable, Metal libraries
and all selected game data. Signing and device installation are external steps.
No separate game-data installation is required by this deliverable.

## Bring-up validation

A 30-second windowless Mac bootstrap reached `nnMain`, installed the build-gated
host allocator, initialized NVN and audio, committed save transactions and submitted
600 frames with 33.33 ms median frame time. The engine argument was 4064 MB and
the alias mapping stayed within the 4.375 GiB region. This used incomplete shader
libraries while the first compile was running: expected missing-library errors
mean it does not establish correct rendering or gameplay. It exited cleanly on
the planned SIGTERM.

The complete Mac and iOS shader build subsequently finished. The single unsigned
IPA is 4,749,319,664 bytes and passed ZIP CRC validation, bundle identity and ARM64
executable checks. All 14 extracted game-data files and 33,928 Metal libraries are
present inside the app; no separate data import is needed.

A subsequent 120-second Mac run with the full libraries and scripted A-button
input reached the title and difficulty-selection menus. Screenshots of both were
visually reviewed. The log contains no `[RED]` or crash lines, and the frame-3000
window reports 33.36 ms median frame time (30 fps). The planned SIGTERM exited
cleanly with status 0. Audio callbacks ran, but stream 0 reported periodic short
underruns; audible correctness has not been verified. These checks establish menu
bring-up, not field or battle gameplay, or stability on an iPhone.

Generated assets, logs, screenshots and the IPA stay in the game's NSP folder.
The delivered IPA SHA-256 is
`6c6bd1e217ef615f189cdae48e50404fb7884a8b7764128905a438ebf734c632`.
Target-phone installation, memory use and gameplay remain unverified.
