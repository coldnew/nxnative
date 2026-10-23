// Real GPU readback for clamped integer-LOD min/max filtering, including NPOT
// mipmaps, zero-weight neighbours and fractions rounded up to the next texel.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include <math.h>
#include "../nvn/nvn_refl.h"

static vector_float4 pixel(int x, int y, int w, int l) {
    return (vector_float4){(x * 13 + y * 7 + l * 3) % 31, 100 - x - y * w,
                          x * x - y * 3, (x * 17 + y * 23 + l) % 43};
}
static int bound(int x, int n) { return x < 0 ? 0 : x >= n ? n - 1 : x; }
static vector_float4 reference(vector_float4 q, int width, int height) {
    int l = (int)q.z, w = MAX(width >> l, 1), h = MAX(height >> l, 1);
    float px = fminf(fmaxf(q.x, 0), 1) * w - 0.5f, py = fminf(fmaxf(q.y, 0), 1) * h - 0.5f;
    int x = (int)floorf(px), y = (int)floorf(py);
    float fx = floorf((px - x) * 256 + 0.5f) / 256, fy = floorf((py - y) * 256 + 0.5f) / 256;
    vector_float4 r = q.w == 1 ? (vector_float4){INFINITY, INFINITY, INFINITY, INFINITY}
                              : (vector_float4){-INFINITY, -INFINITY, -INFINITY, -INFINITY};
    for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++) {
        float weight = (i ? fx : 1 - fx) * (j ? fy : 1 - fy);
        if (weight <= 0) continue;
        vector_float4 v = pixel(bound(x + i, w), bound(y + j, h), w, l);
        for (int c = 0; c < 4; c++) r[c] = q.w == 1 ? fminf(r[c], v[c]) : fmaxf(r[c], v[c]);
    }
    return r;
}
int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    nvn_refl rf; char why[256];
    NSDictionary *binding = @{@"kind":@"samp_tex", @"reg":@17, @"arg_id":@0,
                              @"msl_name":@"tSmplr", @"msl_type":@"sampler", @"reduce":@1};
    NSDictionary *reflection = @{@"route":@"B", @"bindings":@[binding]};
    if (nvn_refl_from_json(reflection, &rf, why, sizeof why) || rf.nb != 1 || rf.b[0].reduce != 1) {
        fprintf(stderr, "reduction reflection failed: %s\n", why); return 1;
    }
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); NSError *error = nil;
    NSString *helper = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:&error];
    NSString *source = [@"#include <metal_stdlib>\nusing namespace metal;\n" stringByAppendingString:helper];
    source = [source stringByAppendingString:@"\nkernel void test(texture2d<float> t [[texture(0)]], device float4 *q [[buffer(0)]], device float4 *o [[buffer(1)]], uint i [[thread_position_in_grid]]) { o[i]=dm_minmax_2d_integer_clamp(t,q[i].xy,q[i].z,uint(q[i].w)); }\n"];
    id<MTLLibrary> lib = [dev newLibraryWithSource:source options:nil error:&error];
    id<MTLComputePipelineState> ps = lib ? [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"test"] error:&error] : nil;
    if (!ps) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
    id<MTLCommandQueue> queue = [dev newCommandQueue]; int failed = 0, checked = 0;
    int sizes[][2] = {{8,8}, {7,5}, {1,1}};
    for (int k = 0; k < 3; k++) {
        int width = sizes[k][0], height = sizes[k][1], levels = (int)floor(log2(MAX(width, height))) + 1;
        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:width height:height mipmapped:YES];
        d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> tex = [dev newTextureWithDescriptor:d];
        vector_float4 queries[4096]; int count = 0;
        for (int l = 0; l < levels; l++) {
            int w = MAX(width >> l, 1), h = MAX(height >> l, 1); vector_float4 data[64];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) data[y * w + x] = pixel(x, y, w, l);
            [tex replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:l withBytes:data bytesPerRow:w * 16];
            for (int mode = 1; mode <= 2; mode++) for (int y = -1; y <= h; y++) for (int x = -1; x <= w; x++) {
                float offsets[] = {0.0f, 0.5f, 0.500001f, 0.499999f, 1.0f};
                for (int a = 0; a < 5; a++) queries[count++] = (vector_float4){(x + offsets[a]) / w, (y + offsets[4-a]) / h, l, mode};
            }
        }
        id<MTLBuffer> in = [dev newBufferWithBytes:queries length:count * 16 options:MTLResourceStorageModeShared];
        id<MTLBuffer> out = [dev newBufferWithLength:count * 16 options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb = [queue commandBuffer]; id<MTLComputeCommandEncoder> en = [cb computeCommandEncoder];
        [en setComputePipelineState:ps]; [en setTexture:tex atIndex:0]; [en setBuffer:in offset:0 atIndex:0]; [en setBuffer:out offset:0 atIndex:1];
        [en dispatchThreads:MTLSizeMake(count,1,1) threadsPerThreadgroup:MTLSizeMake(ps.threadExecutionWidth,1,1)];
        [en endEncoding]; [cb commit]; [cb waitUntilCompleted];
        if (cb.error) { fprintf(stderr, "%s\n", cb.error.description.UTF8String); return 1; }
        vector_float4 *got = out.contents;
        for (int i = 0; i < count; i++) { vector_float4 want = reference(queries[i], width, height);
            for (int c = 0; c < 4; c++) { checked++; if (got[i][c] != want[c]) { if (failed++ < 8) fprintf(stderr, "%dx%d query %d channel %d: %g != %g\n", width,height,i,c,got[i][c],want[c]); } }
        }
    }
    printf("min/max GPU readback: %d channels, %d failed\n", checked, failed); return failed != 0;
} }
