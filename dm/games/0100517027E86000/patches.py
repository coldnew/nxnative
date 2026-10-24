# FINAL FANTASY RESONANCE DEMO 1.0.0: build-checked patches of the demo executable.
# The SDK build is shared with retail and is handled by dm/tools/sdk_patches.py.
CUTS = {
    # nninitStartup (+0x13370) reserves the argument-capped region at +0x137d0.
    # The following call constructs FMallocBinned3 at +0x77f9210, reserving 38 GB.
    # Its constructor at +0xaee70 writes vtable +0x680f810 (32 slots); the TLS
    # callbacks at +0x13830 / +0x13870 use Malloc +0x30 and Free +0x50.
    # hle_uemalloc.c installs the UE5_6 host vtable before guest startup.
    'dd0dc94da6f6e6d7270119601bb06d86': [
        (0x137f0, 'a06d0294', '1f2003d5',
         'nninitStartup: skip verified FMallocBinned3 constructor; host allocator installed before startup'),
    ],
}
