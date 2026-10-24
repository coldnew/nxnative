// A usage upgrade replaces one shared image, including every serial naming it.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)
int main(void) { @autoreleasepool {
    mtl_init(); mtl_sub_begin();
    tex_t a = {.magic=MAGIC('T','E','X',0), .serial=99301};
    a.d = (nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D, .format=NVN_FORMAT_RGBA8, .width=4, .height=4, .depth=1, .levels=1, .samples=1};
    nvn_tex_layout(&a.d, &a.L); tex_t b = a, ghost = a;
    b.serial++; ghost.serial += 2;
    mtl_tex_init(&a); mtl_tex_init(&b);
    id<MTLTexture> old = tex_mtl(&a);
    CHECK(tex_mtl(&b) == old && tex_mtl(&ghost) == old, "live and finalized serials initially share storage");
    // Exercise replacement at the hash table's growth threshold: reinserting while iterating would resize and reshuffle it.
    uint64_t extra = 99400;
    while ((g_by_serial.n + 1) * 4 <= g_by_serial.cap * 3) { hm_put_id(&g_by_serial, &extra, old); extra++; }
    uint32_t capacity = g_by_serial.cap, count = g_by_serial.n;
    id<MTLTexture> upgraded = tex_upgrade_pfv(&a, old, MTLPixelFormatR32Uint);
    CHECK(upgraded && upgraded != old, "usage upgrade creates a replacement");
    CHECK(g_by_serial.cap == capacity && g_by_serial.n == count, "replacement does not grow or reshape the serial table");
    int all = 1; for (uint64_t serial = 99400; serial < extra; serial++) all &= tex_get(serial) == upgraded;
    CHECK(all, "every shared serial at the growth threshold sees the replacement");
    CHECK(tex_get(b.serial) == upgraded, "other live serial sees the replacement");
    CHECK(tex_get(ghost.serial) == upgraded, "finalized serial sees the replacement");
    CHECK(!alias_has(old) && alias_has(upgraded), "sharing membership follows the replacement");
    uint32_t pixels[16]; for (int i = 0; i < 16; i++) pixels[i] = 0x44332211u;
    id<MTLBuffer> src = [g_dev newBufferWithBytes:pixels length:sizeof pixels options:MTLResourceStorageModeShared]; res_add(src);
    id<MTL4ComputeCommandEncoder> encoder = blit();
    enc_b_copy_buffer_texture(encoder, src, 0, 16, sizeof pixels, MTLSizeMake(4,4,1), upgraded, 0, 0, MTLOriginMake(0,0,0));
    for (int j = 0; j < 2; j++) {
        id<MTLTexture> texture = tex_mtl(j ? &ghost : &b);
        id<MTLBuffer> dst = [g_dev newBufferWithLength:sizeof pixels options:MTLResourceStorageModeShared]; res_add(dst);
        encoder = blit(); enc_b_copy_texture_buffer(encoder, texture, 0, 0, MTLOriginMake(0,0,0), MTLSizeMake(4,4,1), dst, 0, 16, sizeof pixels);
        mtl_sub_commit(); mtl_drain();
        CHECK(!memcmp(dst.contents, pixels, sizeof pixels), "other serial reads every GPU-written pixel after upgrade");
        if (!j) mtl_sub_begin();
    }
    CHECK(![g_res_objects containsObject:old], "retired base is removed from the residency set after GPU completion");
    // A pool may have only alternate / image / alpha cached views left. Each
    // retains the linear parent's no-copy buffer even with no main ID view.
    pool_t finalized_pool = {0};
    tex_t linear = {.magic=MAGIC('T','E','X',0), .serial=99701, .pool=&finalized_pool};
    linear.d = (nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D, .format=NVN_FORMAT_RGBA8, .width=4, .height=4, .depth=1, .levels=1, .samples=1};
    mtl_reg_tex(991, &linear, NULL);
    __weak id<MTLBuffer> weak_buffer;
    @autoreleasepool {
        id<MTLBuffer> buffer = [g_dev newBufferWithLength:16384 options:MTLResourceStorageModeShared];
        weak_buffer = buffer;
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared; descriptor.usage=MTLTextureUsageShaderRead;
        NSUInteger row=[g_dev minimumLinearTextureAlignmentForPixelFormat:descriptor.pixelFormat];
        if (row < 16) row=16;
        id<MTLTexture> view = [buffer newTextureWithDescriptor:descriptor offset:0 bytesPerRow:row];
        CHECK(view != nil, "linear cached view created");
        treg_t *entry=&g_treg[991];
        entry->alt=(void *)CFBridgingRetain(view); entry->alt_of=(__bridge void *)view; entry->alt_rid=view.gpuResourceID._impl;
        entry->ar=(void *)CFBridgingRetain(view); entry->im=(void *)CFBridgingRetain(view);
    }
    CHECK(weak_buffer != nil && !g_treg[991].view, "secondary caches alone retain the pool buffer");
    treg_drop_pool_views(&finalized_pool);
    CHECK(!g_treg[991].alt && !g_treg[991].alt_of && !g_treg[991].alt_rid && !g_treg[991].ar && !g_treg[991].im,
          "pool finalize clears all secondary caches without a main view");
    @autoreleasepool { mtl_sub_begin(); mtl_sub_commit(); mtl_drain(); }
    CHECK(weak_buffer == nil, "pool buffer released after deferred GPU retirement");
    NvPkg *cached=[NvPkg new];
    cached->tex=[g_dev newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO]];
    cached->spare=[g_dev newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO]];
    id<MTLTexture> current=cached->tex;
    cached->spare_fence=g_done+2; cached->spare_sub=g_sub_serial;
    serial_put(99801,cached);
    pkg_trim_spares(1);
    CHECK(cached->spare != nil, "memory pressure never retires an in-flight spare");
    cached->spare_fence=g_done;
    pkg_trim_spares(0);
    CHECK(cached->spare != nil, "recent spare is reused when memory is available");
    CHECK(pkg_trim_spares(1)>0 && cached->spare==nil && cached->tex==current,
          "memory pressure retires only the completed spare, preserving current storage");
    cached->spare=[g_dev newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO]];
    cached->spare_fence=g_done; cached->spare_sub=g_sub_serial;
    g_sub_serial+=300;
    CHECK(pkg_trim_spares(0)>0 && cached->spare==nil && cached->tex==current,
          "idle spare expires without memory pressure");
    // Pool registration can run on a long-lived guest thread outside a replay
    // autorelease pool. Churn must not retain finalized no-copy buffers there.
    enum { POOLS=64 }; void *pool_memory[POOLS];
    for(int i=0;i<POOLS;i++) {
        size_t page=(size_t)getpagesize(); if(posix_memalign(&pool_memory[i],page,page))return 2;
        mtl_pool_add(pool_memory[i],page);
        void *buffer; uint64_t offset,address;
        CHECK(mtl_gpu_addr((uint64_t)pool_memory[i],4,&buffer,&offset,&address), "churn pool becomes resident");
        mtl_pool_del(pool_memory[i]);
    }
    @autoreleasepool { mtl_sub_begin();mtl_sub_commit();mtl_drain(); res_commit(); }
    unsigned alive=0;
    // g_done wakes waiters before the feedback handler finishes releasing its
    // local references; poll within fresh pools until that cleanup completes.
    for(int attempt=0;attempt<100;attempt++) {
        @autoreleasepool { defer_drain();res_commit();alive=0;for(id buffer in g_dead_pools)if(buffer)alive++; }
        if(!alive)break;usleep(10000);
    }
    CHECK(alive==0,"finalized resident pool buffers do not survive GPU retirement");
    if(alive)fprintf(stderr,"finalized pool buffers alive: %u\n",alive);
    for(int i=0;i<POOLS;i++)free(pool_memory[i]);
    printf("texture upgrade aliases: %d checks, %d failed\n", checks, failed);
    return failed != 0;
} }
