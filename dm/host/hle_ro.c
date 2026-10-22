// nn::ro: executable code is rewritten and embedded offline, including NROs named by
// the profile's nro_modules. LoadModule binds a matching prepared image and runs its
// constructors at the game's requested time; it never executes the raw RomFS bytes.
#include "hle.h"

#define RO_FAIL ((Result)(22 | (1 << 9)))
// nn::ro::Module is copied by value by Unity: preserve its cookie and state in the
// guest object, rather than using the address of a temporary stack object as its identity.
typedef struct { module_t *cookie; uint32_t state, pad; const void *image; void *bss; } ro_guest_module;
typedef struct { module_t *module; } ro_binding;
static ro_binding g_ro[MAX_MOD];

static uint32_t ro_u32(const void *p, size_t off) { uint32_t v; memcpy(&v, (const char *)p + off, sizeof v); return v; }
static int ro_header(const void *p) {
    if (!p || memcmp((const char *)p + 0x10, "NRO0", 4) || ro_u32(p, 0x14) != 0) return 0;
    uint32_t size = ro_u32(p, 0x18), end = 0;
    for (unsigned i = 0; i < 3; i++) {
        uint32_t off = ro_u32(p, 0x20 + i * 8), len = ro_u32(p, 0x24 + i * 8);
        if (off != end || off > size || len > size - off) return 0;
        end = off + len;
    }
    return size >= 0x80 && end == size;
}
static module_t *ro_prepared(const void *image) {
    if (!ro_header(image)) return NULL;
    char id[33]; const uint8_t *b = (const uint8_t *)image + 0x40;
    for (int i = 0; i < 16; i++) snprintf(id + i * 2, 3, "%02x", b[i]);
    for (int i = 0; i < g_nmod; i++) if (g_mod[i].nro && !strcmp(g_mod[i].build_id, id)) return &g_mod[i];
    return NULL;
}
static ro_binding *ro_bound(const void *object) {
    if (!object) return NULL;
    const ro_guest_module *m = object;
    for (int i = 0; i < MAX_MOD; i++) if (m->state == 1 && g_ro[i].module && g_ro[i].module == m->cookie) return &g_ro[i];
    return NULL;
}
HLE_FORCE("_ZN2nn2ro10InitializeEv", "NRO code is prepared offline; no ldr:ro session is needed", Result, h_ro_Initialize, void) { return 0; }

HLE_FORCE("_ZN2nn2ro12LookupSymbolEPmPKc", "look up a definition in the prepared modules", Result, h_ro_LookupSymbol, uintptr_t *out, const char *name) {
    void *p = name ? guest_sym(name) : NULL;
    static int n; if (n++ < 40) LOG("ro::LookupSymbol %s → %p", name ? name : "(null)", p);
    if (!p) return RO_FAIL;
    if (out) *out = (uintptr_t)p;
    return 0;
}
HLE_FORCE("_ZN2nn2ro18LookupModuleSymbolEPmPKNS0_6ModuleEPKc", "look up a definition only in the requested loaded NRO", Result, h_ro_LookupModuleSymbol, uintptr_t *out, const void *m, const char *name) {
    ro_binding *b = ro_bound(m);
    void *p = b && name ? module_sym(b->module, name) : NULL;
    static int n; if (n++ < 40) LOG("ro::LookupModuleSymbol %s → %p", name ? name : "(null)", p);
    if (!p) return RO_FAIL;   // optional Unity plugin entry points need not be exported
    if (out) *out = (uintptr_t)p;
    return 0;
}
HLE_FORCE("_ZN2nn2ro13GetBufferSizeEPmPKv", "report the NRO header's BSS size", Result, h_ro_GetBufferSize, size_t *out, const void *image) {
    if (!out || !ro_header(image)) { LOG("[RED] ro::GetBufferSize invalid NRO header"); return RO_FAIL; }
    *out = ro_u32(image, 0x38);
    return 0;
}
HLE_FORCE("_ZN2nn2ro10LoadModuleEPNS0_6ModuleEPKvPvmi", "bind a rewritten NRO embedded at build time, then run its constructors", Result, h_ro_LoadModule, void *m, const void *image, void *buf, size_t size, int flag) {
    (void)buf; (void)flag;
    module_t *module = ro_prepared(image);
    if (!m || !module || size < ro_u32(image, 0x38) || ro_bound(m)) {
        LOG("[RED] ro::LoadModule has no matching prepared NRO or invalid buffer (size %#zx)", size); return RO_FAIL;
    }
    ro_binding *slot = NULL;
    for (int i = 0; i < MAX_MOD; i++) {
        if (g_ro[i].module == module) return RO_FAIL;
        if (!g_ro[i].module) slot = &g_ro[i];
    }
    if (!slot) return RO_FAIL;
    *slot = (ro_binding){module};
    *(ro_guest_module *)m = (ro_guest_module){.cookie = module, .state = 1, .image = image, .bss = buf};
    LOG("ro::LoadModule %s build %s", module->name, module->build_id);
    if (module->init) ((void (*)(void))(module->base + module->init))();
    return 0;
}
// SDK 19 adds a bool after the binding flag.
HLE_FORCE("_ZN2nn2ro10LoadModuleEPNS0_6ModuleEPKvPvmib", "bind a prepared NRO (SDK 19 overload)", Result, h_ro_LoadModule2, void *m, const void *image, void *buf, size_t size, int flag, int b) {
    (void)b; return h_ro_LoadModule(m, image, buf, size, flag);
}
HLE_FORCE("_ZN2nn2ro12UnloadModuleEPNS0_6ModuleE", "finalize the NRO; its embedded code remains mapped", void, h_ro_UnloadModule, void *m) {
    ro_binding *b = ro_bound(m); if (!b) return;
    for (const Elf64_Dyn *d = b->module->dyn; d->d_tag; d++) if (d->d_tag == 13 && d->d_un.d_ptr) {
        ((void (*)(void))(b->module->base + d->d_un.d_ptr))(); break;
    }
    *b = (ro_binding){0};
    ((ro_guest_module *)m)->state = 0;
}
HLE_FORCE("_ZN2nn2ro8FinalizeEv", "close the prelinked module registry", void, h_ro_Finalize, void) {
    for (int i = 0; i < MAX_MOD; i++) if (g_ro[i].module) {
        ro_guest_module m = {.cookie = g_ro[i].module, .state = 1}; h_ro_UnloadModule(&m);
    }
}
HLE_FORCE("_ZN2nn2ro18RegisterModuleInfoEPNS0_16RegistrationInfoEPKv", "prepared NROs are trusted build inputs; no ldr:ro registration is required", Result, h_ro_RegisterModuleInfo, void *info, const void *nrr) {
    (void)info;
    if (!nrr || memcmp(nrr, "NRR0", 4)) return RO_FAIL;
    for (int i = 0; i < g_nmod; i++) if (g_mod[i].nro) { LOG("ro::RegisterModuleInfo (prelinked NROs)"); return 0; }
    return RO_FAIL;
}
HLE_FORCE("_ZN2nn2ro20UnregisterModuleInfoEPNS0_16RegistrationInfoE", "no ldr:ro registration was made", void, h_ro_UnregisterModuleInfo, void *info) { (void)info; }
