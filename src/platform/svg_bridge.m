#import "objc_bridge.h"
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>

void *rasterize_svg(void *device_ptr, void *queue_ptr, const char *svg_xml, float width, float height) {
    @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)queue_ptr;

        NSString *svg_str = [NSString stringWithUTF8String:svg_xml];
        NSData *svg_data = [svg_str dataUsingEncoding:NSUTF8StringEncoding];
        
        NSImage *image = [[NSImage alloc] initWithData:svg_data];
        if (!image) return NULL;

        // Set size if explicitly provided
        if (width > 0 && height > 0) {
            [image setSize:NSMakeSize(width, height)];
        } else {
            width = image.size.width;
            height = image.size.height;
        }

        // We'll use a 2x scale for Retina-friendly rasterization
        float scale = 2.0;
        int w = (int)(width * scale);
        int h = (int)(height * scale);

        if (w <= 0 || h <= 0) return NULL;

        uint8_t *bitmap_data = calloc(w * h * 4, 1);
        CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(
            bitmap_data, w, h, 8, w * 4, color_space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

        NSGraphicsContext *ns_ctx = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
        [NSGraphicsContext setCurrentContext:ns_ctx];

        [image drawInRect:NSMakeRect(0, 0, w, h)
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1.0];

        [NSGraphicsContext setCurrentContext:nil];

        MTLTextureDescriptor *desc = [MTLTextureDescriptor
            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                         width:w
                                        height:h
                                     mipmapped:YES];
        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        [texture replaceRegion:MTLRegionMake2D(0, 0, w, h)
                   mipmapLevel:0
                     withBytes:bitmap_data
                   bytesPerRow:w * 4];

        if (queue) {
            id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
            id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
            [blitEncoder generateMipmapsForTexture:texture];
            [blitEncoder endEncoding];
            [commandBuffer commit];
        }

        CGContextRelease(context);
        CGColorSpaceRelease(color_space);
        free(bitmap_data);

        return (__bridge_retained void *)texture;
    }
}
