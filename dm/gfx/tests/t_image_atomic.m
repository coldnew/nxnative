// Native image atomics retain the array layer and never use a linear dummy buffer.
#include "../nvn/nvn_mtl.m"
uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t address) { (void)address; return 0; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
int main(void) { @autoreleasepool {
    mtl_init();
    nvn_refl rf; char why[256] = {0};
    NSDictionary *binding = @{@"kind":@"img", @"reg":@1, @"arg_id":@5,
        @"msl_name":@"fp_i_cb2_4A_r32ui", @"msl_type":@"texture2d_array<uint, access::read_write>"};
    if (nvn_refl_from_json(@{@"route":@"B", @"bindings":@[binding]}, &rf, why, sizeof why) ||
        rf.nb != 1 || rf.b[0].kind != NVN_RB_IMG || !rf.b[0].rw ||
        rf.b[0].dtt != MTLTextureType2DArray || rf.b[0].dpf != NVN_DPF_UINT) {
        fprintf(stderr,"native image reflection failed: %s\n",why); return 1;
    }
    free(rf.c1);
    tex_t t = {.magic=MAGIC('T','E','X',0), .serial=99001};
    t.d = (nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D_ARRAY, .format=NVN_FORMAT_R32UI,
                       .width=480, .height=270, .depth=3, .levels=1, .samples=1, .flags=NVN_TEXTURE_FLAGS_IMAGE};
    MTLTextureDescriptor *d = tex_desc(&t, 0); d.storageMode = MTLStorageModeShared;
    id<MTLTexture> image = [g_dev newTextureWithDescriptor:d];
    if (!image || !(d.usage & MTLTextureUsageShaderAtomic)) { fprintf(stderr,"image creation/atomic usage failed: format %lu usage %#lx type %lu\n",(unsigned long)d.pixelFormat,(unsigned long)d.usage,(unsigned long)d.textureType); fprintf(stderr,"image %p usage %#lx\n",(__bridge void *)image,(unsigned long)image.usage); return 1; }
    size_t bytes = 480*270*4; uint32_t *zero = calloc(1, bytes);
    for (int layer=0; layer<3; layer++) [image replaceRegion:MTLRegionMake2D(0,0,480,270) mipmapLevel:0 slice:layer withBytes:zero bytesPerRow:480*4 bytesPerImage:bytes];
    free(zero);
    NSError *error = nil; MTLCompileOptions *opts = [MTLCompileOptions new]; opts.languageVersion = MTLLanguageVersion3_1;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void update(texture2d_array<uint,access::read_write> t [[texture(0)]], uint3 p [[thread_position_in_grid]]) { uint a=p.z*1000000+p.y*480+p.x+1; t.atomic_fetch_max(p.xy,p.z,a); t.atomic_fetch_max(p.xy,p.z,a-1); }\n"
        "kernel void readback(texture2d_array<uint,access::read> t [[texture(0)]], device uint *o [[buffer(0)]], uint3 p [[thread_position_in_grid]]) { o[(p.z*270+p.y)*480+p.x]=t.read(p.xy,p.z).x; }\n" options:opts error:&error];
    if (!lib) { fprintf(stderr,"%s\n",error.localizedDescription.UTF8String); return 1; }
    id<MTLComputePipelineState> put = [g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"update"] error:&error];
    id<MTLComputePipelineState> get = [g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"readback"] error:&error];
    if (!put || !get) { fprintf(stderr,"atomic pipeline: %s\n",error.localizedDescription.UTF8String); return 1; }
    id<MTLBuffer> out = [g_dev newBufferWithLength:bytes*3 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = q_cb();
    for (int read=0; read<2; read++) {
        id<MTLComputeCommandEncoder> en = [cb computeCommandEncoder];
        [en setComputePipelineState:read ? get : put]; [en setTexture:image atIndex:0];
        if (read) [en setBuffer:out offset:0 atIndex:0];
        [en dispatchThreads:MTLSizeMake(480,270,3) threadsPerThreadgroup:MTLSizeMake(8,2,1)]; [en endEncoding];
    }
    [cb commit]; [cb waitUntilCompleted];
    if (cb.status != MTLCommandBufferStatusCompleted) { fprintf(stderr,"atomic GPU error: %s\n",cb.error.localizedDescription.UTF8String); return 1; }
    uint32_t *values = out.contents;
    for (int z=0; z<3; z++) for (int y=0; y<270; y++) for (int x=0; x<480; x++)
        if (values[(z*270+y)*480+x] != z*1000000+y*480+x+1) { fprintf(stderr,"atomic mismatch at %d,%d,%d\n",x,y,z); return 1; }
    puts("native image atomics: 388800 values across three layers passed"); return 0;
} }
