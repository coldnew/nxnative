#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdint.h>
#include <stdio.h>

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) { fprintf(stderr, "No Metal device\n"); return 77; }
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithURL:[NSURL fileURLWithPath:@(argv[1])] error:&error];
    if (!library) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
    MTLRenderPipelineDescriptor *description = [MTLRenderPipelineDescriptor new];
    description.vertexFunction = [library newFunctionWithName:@"main0"];
    description.rasterizationEnabled = NO;
    description.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> render = [device newRenderPipelineStateWithDescriptor:description error:&error];
    if (!render) { fprintf(stderr, "Render pipeline: %s\n", error.localizedDescription.UTF8String); return 1; }
    id<MTLComputePipelineState> fill = [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"fill"] error:&error];
    if (!render || !fill) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
    id<MTLBuffer> driver = [device newBufferWithLength:101 * 16 options:MTLResourceStorageModeShared];
    memset(driver.contents, 0, driver.length);
    id<MTLBuffer> result = [device newBufferWithLength:8 options:MTLResourceStorageModeShared];
    id<MTLBuffer> arguments = [device newBufferWithLength:20 options:MTLResourceStorageModePrivate];
    const uint16_t triangle[] = {0, 1, 2};
    id<MTLBuffer> indices = [device newBufferWithBytes:triangle length:sizeof triangle options:MTLResourceStorageModeShared];
    MTLTextureDescriptor *textureDescription = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    textureDescription.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [device newTextureWithDescriptor:textureDescription];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    const uint32_t bases[] = {0, 5, 0x80000005u};
    for (unsigned b = 0; b < 3; b++) for (unsigned kind = 0; kind < 4; kind++) {
        unsigned indirect = kind & 1, indexed = kind >> 1;
        memset(result.contents, 0xff, result.length);
        id<MTLCommandBuffer> command = [queue commandBuffer];
        if (indirect) {
            id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
            [encoder setComputePipelineState:fill];
            [encoder setBuffer:arguments offset:0 atIndex:0];
            uint32_t config[] = {bases[b], indexed};
            [encoder setBytes:config length:sizeof config atIndex:1];
            [encoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
            [encoder endEncoding];
        }
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = target;
        pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        pass.colorAttachments[0].storeAction = MTLStoreActionDontCare;
        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
        [encoder setRenderPipelineState:render];
        [encoder setVertexBuffer:driver offset:0 atIndex:0];
        [encoder setVertexBuffer:result offset:0 atIndex:2];
        if (indexed && indirect) [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexType:MTLIndexTypeUInt16 indexBuffer:indices indexBufferOffset:0 indirectBuffer:arguments indirectBufferOffset:0];
        else if (indexed) [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:3 indexType:MTLIndexTypeUInt16 indexBuffer:indices indexBufferOffset:0 instanceCount:2 baseVertex:0 baseInstance:bases[b]];
        else if (indirect) [encoder drawPrimitives:MTLPrimitiveTypeTriangle indirectBuffer:arguments indirectBufferOffset:0];
        else [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:2 baseInstance:bases[b]];
        [encoder endEncoding];
        [command commit]; [command waitUntilCompleted];
        if (command.status == MTLCommandBufferStatusError) { fprintf(stderr, "%s\n", command.error.localizedDescription.UTF8String); return 1; }
        uint32_t *values = result.contents;
        printf("%u %u %u %u\n", bases[b], kind, values[0], values[1]);
    }
    return 0;
} }
