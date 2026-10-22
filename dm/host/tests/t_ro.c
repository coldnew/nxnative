// Prelinked NRO loading: constructor timing, copied Module handles, scoped symbol
// lookup, rejected images and unload. No game files are used.
#include "../hle_ro.c"
#include <assert.h>
module_t g_mod[MAX_MOD]; int g_nmod;
static int initialized, finalized;
static void ctor(void) { initialized++; }
static void dtor(void) { finalized++; }
static void entry(void) { }
void *module_sym(module_t *m, const char *name) { return m == &g_mod[0] && !strcmp(name, "entry") ? (void *)entry : NULL; }
void *guest_sym(const char *name) { return module_sym(&g_mod[0], name); }
static void put32(uint8_t *p, size_t off, uint32_t value) { memcpy(p + off, &value, 4); }
int main(void) {
    uint8_t image[0x80] = {0}, bss[0x1000], nrr[4] = {'N','R','R','0'};
    memcpy(image + 0x10, "NRO0", 4); put32(image, 0x18, sizeof image);
    put32(image, 0x24, 0x40); put32(image, 0x28, 0x40); put32(image, 0x2c, 0x20);
    put32(image, 0x30, 0x60); put32(image, 0x34, 0x20); put32(image, 0x38, sizeof bss);
    for (int i = 0; i < 16; i++) image[0x40 + i] = i;
    module_t *mod = &g_mod[0]; g_nmod = 1; mod->nro = 1;
    strcpy(mod->name, "plugin"); strcpy(mod->build_id, "000102030405060708090a0b0c0d0e0f");
    uintptr_t base = (uintptr_t)ctor < (uintptr_t)dtor ? (uintptr_t)ctor : (uintptr_t)dtor;
    mod->base = (uint8_t *)(base - 16); mod->init = (uintptr_t)ctor - (uintptr_t)mod->base;
    Elf64_Dyn dyn[] = {{.d_tag=13, .d_un.d_ptr=(uintptr_t)dtor-(uintptr_t)mod->base}, {.d_tag=0}}; mod->dyn = dyn;
    size_t size = 0; assert(!h_ro_GetBufferSize(&size, image) && size == sizeof bss);
    ro_guest_module a = {0}, b = {0}; uintptr_t symbol = 0;
    assert(h_ro_LoadModule(&a, image, bss, sizeof bss - 1, 1)); assert(!initialized);
    image[0x40] ^= 1; assert(h_ro_LoadModule(&a, image, bss, sizeof bss, 1)); image[0x40] ^= 1;
    assert(!h_ro_RegisterModuleInfo(NULL, nrr));
    assert(!h_ro_LoadModule(&a, image, bss, sizeof bss, 1)); assert(initialized == 1 && a.state == 1);
    assert(h_ro_LoadModule(&b, image, bss, sizeof bss, 1)); assert(initialized == 1);
    b = a; memset(&a, 0, sizeof a);   // Unity copies its stack Module into a heap object.
    assert(!h_ro_LookupModuleSymbol(&symbol, &b, "entry") && symbol == (uintptr_t)entry);
    assert(h_ro_LookupModuleSymbol(&symbol, &b, "optional"));
    assert(h_ro_LookupModuleSymbol(&symbol, &a, "entry"));
    h_ro_UnloadModule(&b); assert(finalized == 1 && !b.state);
    assert(h_ro_LookupModuleSymbol(&symbol, &b, "entry"));
    h_ro_UnloadModule(&b); assert(finalized == 1);
    put32(image, 0x14, 1); assert(h_ro_GetBufferSize(&size, image)); put32(image, 0x14, 0);
    put32(image, 0x30, 0x50); assert(h_ro_GetBufferSize(&size, image));
    puts("prelinked NRO lifecycle and copied handle checks passed");
}
