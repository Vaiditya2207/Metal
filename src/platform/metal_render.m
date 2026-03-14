#import "objc_bridge.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

static const char *shader_source =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VertexIn { float2 position [[attribute(0)]]; float4 color "
    "[[attribute(1)]]; };\n"
    "struct VertexOut { float4 position [[position]]; float4 color; };\n"
    "struct Uniforms { float4x4 projection; };\n"
    "vertex VertexOut vertex_main(VertexIn in [[stage_in]], constant Uniforms "
    "&uniforms [[buffer(1)]]) {\n"
    "  VertexOut out;\n"
    "  out.position = uniforms.projection * float4(in.position, 0.0, 1.0);\n"
    "  out.color = in.color;\n"
    "  return out;\n"
    "}\n"
    "fragment float4 fragment_main(VertexOut in [[stage_in]]) {\n"
    "  return in.color;\n"
    "}\n";

void *create_render_pipeline(void *device_ptr) {
  @autoreleasepool {
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
    NSError *error = nil;
    id<MTLLibrary> library = [device
        newLibraryWithSource:[NSString stringWithUTF8String:shader_source]
                     options:nil
                       error:&error];
    if (!library) {
      NSLog(@"Failed to create shader library: %@", error);
      return NULL;
    }

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vertexFunc;
    desc.fragmentFunction = fragmentFunc;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    MTLVertexDescriptor *vDesc = [MTLVertexDescriptor vertexDescriptor];
    vDesc.attributes[0].format = MTLVertexFormatFloat2;
    vDesc.attributes[0].offset = 0;
    vDesc.attributes[0].bufferIndex = 0;
    vDesc.attributes[1].format = MTLVertexFormatFloat4;
    vDesc.attributes[1].offset = sizeof(simd_float2);
    vDesc.attributes[1].bufferIndex = 0;
    vDesc.layouts[0].stride = sizeof(simd_float2) + sizeof(simd_float4);

    desc.vertexDescriptor = vDesc;

    id<MTLRenderPipelineState> pipeline =
        [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!pipeline) {
      NSLog(@"Failed to create pipeline state: %@", error);
      return NULL;
    }

    return (__bridge_retained void *)pipeline;
  }
}

void set_pipeline(void *frame_context, void *pipeline_state) {
  FrameContext *ctx = (FrameContext *)frame_context;
  id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  [encoder setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pipeline_state];
}

void set_projection(void *frame_context, float width, float height) {
  FrameContext *ctx = (FrameContext *)frame_context;
  id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  simd_float4x4 projection = {
      .columns[0] = {2.0f / width, 0, 0, 0},
      .columns[1] = {0, -2.0f / height, 0, 0},
      .columns[2] = {0, 0, 1, 0},
      .columns[3] = {-1.0f, 1.0f, 0, 1}};
  [encoder setVertexBytes:&projection
                                length:sizeof(projection)
                               atIndex:1];
}

void draw_solid_rect(void *frame_context, float x, float y, float w, float h,
                     float r, float g, float b, float a) {
  FrameContext *ctx = (FrameContext *)frame_context;
  id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
  struct Vertex {
    simd_float2 pos;
    simd_float4 color;
  } vertices[] = {
      {{x, y}, {r, g, b, a}},         {{x + w, y}, {r, g, b, a}},
      {{x, y + h}, {r, g, b, a}},     {{x + w, y}, {r, g, b, a}},
      {{x, y + h}, {r, g, b, a}},     {{x + w, y + h}, {r, g, b, a}},
  };
  [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:6];
}

void set_scissor_rect(void *frame_context, float x, float y, float w, float h, float drawable_h) {
    (void)drawable_h;
    FrameContext *ctx = (FrameContext *)frame_context;
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
    
    MTLScissorRect rect;
    rect.x = (NSUInteger)fmaxf(0.0f, x);
    rect.y = (NSUInteger)fmaxf(0.0f, y);
    rect.width = (NSUInteger)fmaxf(0.0f, w);
    rect.height = (NSUInteger)fmaxf(0.0f, h);
    
    // Simple clamping
    if (rect.x >= 4096) rect.x = 4095;
    if (rect.y >= 4096) rect.y = 4095;
    if (rect.width == 0) rect.width = 1;
    if (rect.height == 0) rect.height = 1;
    
    [encoder setScissorRect:rect];
}

void reset_scissor_rect(void *frame_context, float drawable_w, float drawable_h) {
    FrameContext *ctx = (FrameContext *)frame_context;
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
    
    MTLScissorRect rect;
    rect.x = 0;
    rect.y = 0;
    rect.width = (NSUInteger)fmaxf(1.0f, drawable_w);
    rect.height = (NSUInteger)fmaxf(1.0f, drawable_h);
    
    [encoder setScissorRect:rect];
}

void batch_solid_rects(void *frame_context, void *device_ptr, const void *vertex_data, int vertex_count) {
    if (vertex_count == 0) return;
    FrameContext *ctx = (FrameContext *)frame_context;
    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)ctx->renderEncoder;
    id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;

    size_t byte_count = vertex_count * (sizeof(simd_float2) + sizeof(simd_float4));
    id<MTLBuffer> buffer = [device newBufferWithBytes:vertex_data
                                               length:byte_count
                                              options:MTLResourceStorageModeShared];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertex_count];
}
