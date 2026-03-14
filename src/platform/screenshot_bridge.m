#import "objc_bridge.h"
#import "screenshot_bridge.h"
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

// Separate static FrameContext for offscreen rendering (NOT the same as
// g_frame_context in objc_bridge.m).
static FrameContext g_offscreen_frame_context;

// Track the offscreen texture so end_offscreen_frame can synchronize it.
static id<MTLTexture> g_offscreen_texture = nil;
// Track the command buffer so end_offscreen_frame can commit it.
static id<MTLCommandBuffer> g_offscreen_command_buffer = nil;

void *create_offscreen_texture(void *device_ptr, int width, int height) {
    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;

        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                        width:(NSUInteger)width
                                       height:(NSUInteger)height
                                    mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
#if TARGET_OS_OSX
        desc.storageMode = MTLStorageModeManaged;
#endif

        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        if (!texture) {
            NSLog(@"[screenshot_bridge] Failed to create offscreen texture %dx%d", width, height);
            return NULL;
        }
        return (__bridge_retained void *)texture;
    }
}

void *begin_offscreen_frame(void *device_ptr, void *command_queue_ptr,
                            void *texture_ptr) {
    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
        (void)device; // unused but kept for API symmetry
        id<MTLCommandQueue> queue =
            (__bridge id<MTLCommandQueue>)command_queue_ptr;
        id<MTLTexture> texture = (__bridge id<MTLTexture>)texture_ptr;

        MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
        rpd.colorAttachments[0].texture = texture;
        rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
        rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);

        id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
        if (!commandBuffer) {
            NSLog(@"[screenshot_bridge] Failed to create command buffer");
            return NULL;
        }

        id<MTLRenderCommandEncoder> encoder =
            [commandBuffer renderCommandEncoderWithDescriptor:rpd];
        if (!encoder) {
            NSLog(@"[screenshot_bridge] Failed to create render encoder");
            return NULL;
        }

        // Store for end_offscreen_frame
        g_offscreen_texture = texture;
        g_offscreen_command_buffer = commandBuffer;

        g_offscreen_frame_context.commandBuffer =
            (__bridge_retained void *)commandBuffer;
        g_offscreen_frame_context.renderEncoder =
            (__bridge_retained void *)encoder;
        g_offscreen_frame_context.drawable = NULL; // no drawable for offscreen

        return (void *)&g_offscreen_frame_context;
    }
}

void end_offscreen_frame(void *frame_context_ptr) {
    if (frame_context_ptr == NULL) return;
    FrameContext *ctx = (FrameContext *)frame_context_ptr;

    id<MTLRenderCommandEncoder> encoder =
        (__bridge_transfer id<MTLRenderCommandEncoder>)ctx->renderEncoder;
    // Note: commandBuffer was bridge_retained in begin; transfer ownership back.
    id<MTLCommandBuffer> commandBuffer =
        (__bridge_transfer id<MTLCommandBuffer>)ctx->commandBuffer;

    [encoder endEncoding];

#if TARGET_OS_OSX
    // Synchronize managed texture for CPU readback
    if (g_offscreen_texture != nil) {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit synchronizeResource:g_offscreen_texture];
        [blit endEncoding];
    }
#endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    g_offscreen_texture = nil;
    g_offscreen_command_buffer = nil;
}

int save_texture_to_png(void *texture_ptr, const char *path) {
    @autoreleasepool {
        if (!texture_ptr || !path) return -1;

        id<MTLTexture> texture = (__bridge id<MTLTexture>)texture_ptr;
        NSUInteger w = texture.width;
        NSUInteger h = texture.height;
        NSUInteger bytesPerRow = w * 4;

        // Allocate buffer for pixel data
        uint8_t *pixels = (uint8_t *)malloc(bytesPerRow * h);
        if (!pixels) return -1;

        [texture getBytes:pixels
              bytesPerRow:bytesPerRow
               fromRegion:MTLRegionMake2D(0, 0, w, h)
              mipmapLevel:0];

        // Swap BGRA -> RGBA
        for (NSUInteger i = 0; i < w * h; i++) {
            uint8_t tmp = pixels[i * 4 + 0];       // B
            pixels[i * 4 + 0] = pixels[i * 4 + 2]; // R -> slot 0
            pixels[i * 4 + 2] = tmp;               // B -> slot 2
        }

        // Create CGImage from RGBA data
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef cgCtx = CGBitmapContextCreate(
            pixels, w, h, 8, bytesPerRow, colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

        if (!cgCtx) {
            CGColorSpaceRelease(colorSpace);
            free(pixels);
            return -1;
        }

        CGImageRef image = CGBitmapContextCreateImage(cgCtx);
        CGContextRelease(cgCtx);
        CGColorSpaceRelease(colorSpace);
        free(pixels);

        if (!image) return -1;

        // Write PNG
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
        CGImageDestinationRef dest =
            CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                            CFSTR("public.png"), 1, NULL);
        if (!dest) {
            CGImageRelease(image);
            return -1;
        }

        CGImageDestinationAddImage(dest, image, NULL);
        bool ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        CGImageRelease(image);

        return ok ? 0 : -1;
    }
}
