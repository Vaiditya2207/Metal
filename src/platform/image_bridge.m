#import "image_bridge.h"
#import "objc_bridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>

// Vertex layout matches TextVertex from text_atlas.m
typedef struct {
  float position[2];
  float uv[2];
  float color[4];
} ImageVertex;

// Image fragment shader: samples full RGBA from texture (not just red channel)
static const char *image_shader_source =
    "using namespace metal;\n"
    "struct ImageVertexIn {\n"
    "    float2 position;\n"
    "    float2 uv;\n"
    "    float4 color;\n"
    "};\n"
    "struct ImageVertexOut {\n"
    "    float4 position [[position]];\n"
    "    float2 uv;\n"
    "    float4 color;\n"
    "};\n"
    "struct Uniforms {\n"
    "    float4x4 projection;\n"
    "};\n"
    "vertex ImageVertexOut image_vertex_main(uint vid [[vertex_id]],\n"
    "                                        constant ImageVertexIn *vertices "
    "[[buffer(0)]],\n"
    "                                        constant Uniforms &uniforms "
    "[[buffer(1)]]) {\n"
    "    ImageVertexOut out;\n"
    "    out.position = uniforms.projection * float4(vertices[vid].position, "
    "0.0, 1.0);\n"
    "    out.uv = vertices[vid].uv;\n"
    "    out.color = vertices[vid].color;\n"
    "    return out;\n"
    "}\n"
    "fragment float4 image_fragment_main(ImageVertexOut in [[stage_in]],\n"
    "                                     texture2d<float> tex "
    "[[texture(0)]]) {\n"
    "    constexpr sampler s(mag_filter::linear, min_filter::linear);\n"
    "    float4 texColor = tex.sample(s, in.uv);\n"
    "    return float4(texColor.rgb * in.color.a, texColor.a * in.color.a);\n"
    "}\n";

void *decode_image_to_texture(void *device_ptr, void *queue_ptr,
                              const unsigned char *data, int data_len,
                              int *width_out, int *height_out) {
  @autoreleasepool {
    if (!data || data_len <= 0)
      return NULL;

    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;

    // Decode image via ImageIO
    CFDataRef cf_data = CFDataCreate(kCFAllocatorDefault, data, data_len);
    if (!cf_data)
      return NULL;

    CGImageSourceRef source = CGImageSourceCreateWithData(cf_data, NULL);
    CFRelease(cf_data);
    if (!source)
      return NULL;

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!cgImage)
      return NULL;

    size_t w = CGImageGetWidth(cgImage);
    size_t h = CGImageGetHeight(cgImage);

    if (w == 0 || h == 0 || w > 8192 || h > 8192) {
      CGImageRelease(cgImage);
      return NULL;
    }

    // Render into RGBA bitmap
    uint8_t *pixels = calloc(w * h * 4, 1);
    if (!pixels) {
      CGImageRelease(cgImage);
      return NULL;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, colorSpace,
                                             kCGImageAlphaPremultipliedLast |
                                                 kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    if (!ctx) {
      free(pixels);
      CGImageRelease(cgImage);
      return NULL;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImage);
    CGContextRelease(ctx);
    CGImageRelease(cgImage);

    // Upload to Metal texture
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                     width:w
                                    height:h
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    [texture replaceRegion:MTLRegionMake2D(0, 0, w, h)
               mipmapLevel:0
                 withBytes:pixels
               bytesPerRow:w * 4];
    free(pixels);

    if (width_out)
      *width_out = (int)w;
    if (height_out)
      *height_out = (int)h;

    return (__bridge_retained void *)texture;
  }
}

void *create_image_pipeline(void *device_ptr) {
  @autoreleasepool {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
    NSError *error = nil;
    id<MTLLibrary> library = [device
        newLibraryWithSource:[NSString stringWithUTF8String:image_shader_source]
                     options:nil
                       error:&error];
    if (!library)
      return NULL;

    MTLRenderPipelineDescriptor *desc =
        [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = [library newFunctionWithName:@"image_vertex_main"];
    desc.fragmentFunction =
        [library newFunctionWithName:@"image_fragment_main"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationRGBBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;

    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!pipeline)
      return NULL;
    return (__bridge_retained void *)pipeline;
  }
}

void batch_image_quads(void *frame_context, void *device_ptr, void *tex_ptr,
                       const void *vertex_data, int vertex_count) {
  if (vertex_count == 0)
    return;

  FrameContext *ctx = (FrameContext *)frame_context;
  id<MTLRenderCommandEncoder> encoder =
      (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
  id<MTLTexture> texture = (__bridge id<MTLTexture>)tex_ptr;

  size_t byte_count = vertex_count * sizeof(ImageVertex);
  id<MTLBuffer> buffer =
      [device newBufferWithBytes:vertex_data
                          length:byte_count
                         options:MTLResourceStorageModeShared];
  [encoder setFragmentTexture:texture atIndex:0];
  [encoder setVertexBuffer:buffer offset:0 atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle
              vertexStart:0
              vertexCount:vertex_count];
}
