#import "text_atlas.h"
#import "objc_bridge.h"
#import <AppKit/NSFont.h>
#import <CoreText/CoreText.h>
#import <Metal/Metal.h>

// Uniforms must match Metal side
typedef struct {
  float projection[16];
} Uniforms;

typedef struct {
  float position[2];
  float uv[2];
  float color[4];
} TextVertex;

static const char *text_shader_source =
    "using namespace metal;\n"
    "struct TextVertexIn {\n"
    "    float2 position;\n"
    "    float2 uv;\n"
    "    float4 color;\n"
    "};\n"
    "struct TextVertexOut {\n"
    "    float4 position [[position]];\n"
    "    float2 uv;\n"
    "    float4 color;\n"
    "};\n"
    "struct Uniforms {\n"
    "    float4x4 projection;\n"
    "};\n"
    "vertex TextVertexOut text_vertex_main(uint vid [[vertex_id]],\n"
    "                                       constant TextVertexIn *vertices "
    "[[buffer(0)]],\n"
    "                                       constant Uniforms &uniforms "
    "[[buffer(1)]]) {\n"
    "    TextVertexOut out;\n"
    "    out.position = uniforms.projection * float4(vertices[vid].position, "
    "0.0, 1.0);\n"
    "    out.uv = vertices[vid].uv;\n"
    "    out.color = vertices[vid].color;\n"
    "    return out;\n"
    "}\n"
    "fragment float4 text_fragment_main(TextVertexOut in [[stage_in]],\n"
    "                                    texture2d<float> atlas "
    "[[texture(0)]]) {\n"
    "    constexpr sampler s(mag_filter::linear, min_filter::linear, "
    "mip_filter::linear);\n"
    "    float alpha = atlas.sample(s, in.uv).r;\n"
    "    return float4(in.color.rgb, in.color.a * alpha);\n"
    "}\n";

void *create_font_atlas_ext(void *device_ptr, void *queue_ptr, const char *family_name,
                            float font_size, float weight, bool is_italic,
                            float scale_factor, GlyphMetrics *metrics_out,
                            float *ascent_out) {
  id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
  id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)queue_ptr;

  NSString *family = family_name ? [NSString stringWithUTF8String:family_name] : @"Helvetica";
  CTFontRef base_font = CTFontCreateWithName((__bridge CFStringRef)family, font_size, NULL);
  
  CTFontSymbolicTraits traits = 0;
  if (weight >= 700) traits |= kCTFontBoldTrait;
  if (is_italic) traits |= kCTFontItalicTrait;
  
  CTFontRef ct_font = CTFontCreateCopyWithSymbolicTraits(base_font, font_size, NULL, traits, traits);
  if (!ct_font) ct_font = base_font;
  else CFRelease(base_font);

  if (ascent_out)
    *ascent_out = (float)CTFontGetAscent(ct_font);

  int atlas_size = (int)(2048 * scale_factor);
  uint8_t *bitmap_data = calloc(atlas_size * atlas_size, 1);
  CGColorSpaceRef color_space = CGColorSpaceCreateDeviceGray();
  CGContextRef context =
      CGBitmapContextCreate(bitmap_data, atlas_size, atlas_size, 8, atlas_size,
                            color_space, (CGBitmapInfo)kCGImageAlphaNone);
  
  CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  CGContextSetShouldAntialias(context, true);
  CGContextSetShouldSmoothFonts(context, true);

  CGContextTranslateCTM(context, 0, atlas_size);
  CGContextScaleCTM(context, scale_factor, -scale_factor);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  CGContextSetGrayFillColor(context, 1.0, 1.0);

  float cur_x = 0;
  float cur_y = 0;
  float line_height = font_size * 1.4; // Slightly more room for synthetic strokes

  for (int i = 0; i < 95; i++) {
    char c = (char)(32 + i);
    UniChar unichar = (UniChar)c;
    CGGlyph glyph;
    CTFontGetGlyphsForCharacters(ct_font, &unichar, &glyph, 1);

    // Use GetBoundingRects to get the precise glyph bounds
    CGRect rect = CTFontGetBoundingRectsForGlyphs(
        ct_font, kCTFontOrientationHorizontal, &glyph, NULL, 1);
    
    // Use GetAdvances to get the spacing, which is affected by synthetic bolding
    CGSize advance_size;
    CTFontGetAdvancesForGlyphs(ct_font, kCTFontOrientationHorizontal, &glyph, &advance_size, 1);
    double advance = advance_size.width;

    if ((cur_x + rect.size.width + 4) * scale_factor > atlas_size) {
      cur_x = 0;
      cur_y += line_height;
    }

    // Add 2px padding to avoid bleeding
    float draw_x = cur_x - rect.origin.x + 2;
    float draw_y = cur_y - rect.origin.y + 2;

    CGPoint position = CGPointMake(draw_x, draw_y);
    CTFontDrawGlyphs(ct_font, &glyph, &position, 1, context);

    metrics_out[i].uv_x = (cur_x + 2) * scale_factor / (float)atlas_size;
    metrics_out[i].uv_y = (cur_y + 2) * scale_factor / (float)atlas_size;
    metrics_out[i].uv_w = rect.size.width * scale_factor / (float)atlas_size;
    metrics_out[i].uv_h = rect.size.height * scale_factor / (float)atlas_size;
    metrics_out[i].width = rect.size.width;
    metrics_out[i].height = rect.size.height;
    metrics_out[i].bearing_x = rect.origin.x;
    metrics_out[i].bearing_y = rect.origin.y;
    metrics_out[i].advance = (float)advance;

    cur_x += rect.size.width + 4;
  }

  MTLTextureDescriptor *desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                   width:atlas_size
                                  height:atlas_size
                               mipmapped:YES];
  id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
  [texture replaceRegion:MTLRegionMake2D(0, 0, atlas_size, atlas_size)
             mipmapLevel:0
               withBytes:bitmap_data
             bytesPerRow:atlas_size];

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
  CFRelease(ct_font);

  return (__bridge_retained void *)texture;
}

void *create_font_atlas(void *device_ptr, void *queue_ptr, float font_size,
                        float scale_factor, GlyphMetrics *metrics_out,
                        float *ascent_out) {
  return create_font_atlas_ext(device_ptr, queue_ptr, "Helvetica", font_size, 400, false, scale_factor, metrics_out, ascent_out);
}

void *create_bold_font_atlas(void *device_ptr, void *queue_ptr, float font_size,
                             float scale_factor, GlyphMetrics *metrics_out,
                             float *ascent_out) {
  return create_font_atlas_ext(device_ptr, queue_ptr, "Helvetica", font_size, 700, false, scale_factor, metrics_out, ascent_out);
}

void *create_text_pipeline(void *device_ptr) {
  @autoreleasepool {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
    NSError *error = nil;
    id<MTLLibrary> library = [device
        newLibraryWithSource:[NSString stringWithUTF8String:text_shader_source]
                     options:nil
                       error:&error];
    if (!library)
      return NULL;

    MTLRenderPipelineDescriptor *desc =
        [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = [library newFunctionWithName:@"text_vertex_main"];
    desc.fragmentFunction = [library newFunctionWithName:@"text_fragment_main"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor =
        MTLBlendFactorOneMinusSourceAlpha;

    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!pipeline)
      return NULL;
    return (__bridge_retained void *)pipeline;
  }
}

void draw_text_quad(void *fc_ptr, void *tex_ptr, float x, float y, float w,
                    float h, float ux, float uy, float uw, float uh, float r,
                    float g, float b, float a) {
  FrameContext *ctx = (FrameContext *)fc_ptr;
  id<MTLRenderCommandEncoder> encoder =
      (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  id<MTLTexture> texture = (__bridge id<MTLTexture>)tex_ptr;

  TextVertex vertices[6] = {{{x, y}, {ux, uy + uh}, {r, g, b, a}},
                            {{x + w, y}, {ux + uw, uy + uh}, {r, g, b, a}},
                            {{x, y + h}, {ux, uy}, {r, g, b, a}},
                            {{x + w, y}, {ux + uw, uy + uh}, {r, g, b, a}},
                            {{x, y + h}, {ux, uy}, {r, g, b, a}},
                            {{x + w, y + h}, {ux + uw, uy}, {r, g, b, a}}};

  [encoder setFragmentTexture:texture atIndex:0];
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

void batch_text_quads(void *frame_context, void *device_ptr, void *tex_ptr,
                      const void *vertex_data, int vertex_count) {
  if (vertex_count == 0)
    return;

  FrameContext *ctx = (FrameContext *)frame_context;
  id<MTLRenderCommandEncoder> encoder =
      (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
  id<MTLTexture> texture = (__bridge id<MTLTexture>)tex_ptr;

  size_t byte_count = vertex_count * sizeof(TextVertex);
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

float measure_text_width(const char *text, int len, float font_size) {
  if (!text || len <= 0 || font_size <= 0)
    return 0.0f;
  NSFont *font = [NSFont systemFontOfSize:font_size];
  CTFontRef ct_font = (__bridge CTFontRef)font;

  CFStringRef str =
      CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)text, len,
                              kCFStringEncodingUTF8, false);
  if (!str)
    return 0.0f;

  CFDictionaryRef attrs = CFDictionaryCreate(
      kCFAllocatorDefault, (const void **)&(CFStringRef){kCTFontAttributeName},
      (const void **)&ct_font, 1, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFAttributedStringRef attr_str =
      CFAttributedStringCreate(kCFAllocatorDefault, str, attrs);
  CTLineRef line = CTLineCreateWithAttributedString(attr_str);

  double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);

  CFRelease(line);
  CFRelease(attr_str);
  CFRelease(attrs);
  CFRelease(str);

  return (float)width;
}
