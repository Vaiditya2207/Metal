#ifndef OBJC_BRIDGE_H
#define OBJC_BRIDGE_H

// Pure C header for Zig interop. No Objective-C allowed here.

#include "event_bridge.h"
#include "image_bridge.h"
#include "text_atlas.h"

typedef void *MetalDelegateHandle;

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  void *commandBuffer;
  void *renderEncoder;
  void *drawable;
} FrameContext;

void *create_application_delegate(void);
void *create_window(const char *title, float width, float height);
void set_window_title(void *window, const char *title);
void *create_metal_view(void *window, void *device);
void *create_command_queue(void *device);
void *begin_frame(void *command_queue, void *view);
void end_frame(void *frame_context);
void set_clear_color(void *view, float r, float g, float b, float a);
void set_metal_delegate(void *view, void *zig_context,
                        void (*draw_callback)(void *));
void run_application(void);
void activate_app(void);

// Create pipeline state from embedded shader source
void *create_render_pipeline(void *device);

// Set the pipeline state on the encoder
void set_pipeline(void *frame_context, void *pipeline_state);

// Set the orthographic projection matrix as uniforms
void set_projection(void *frame_context, float width, float height);

// Draw a filled rectangle
void draw_solid_rect(void *frame_context, float x, float y, float w, float h,
                     float r, float g, float b, float a);

// Scissor rect operations
void set_scissor_rect(void *frame_context, float x, float y, float w, float h,
                      float drawable_h);
void reset_scissor_rect(void *frame_context, float drawable_w,
                        float drawable_h);

// Get the current drawable size
void get_drawable_size(void *view, float *width, float *height);

// Get the backing scale factor (1.0 for standard, 2.0 for Retina)
float get_content_scale(void *view);

// Get the main screen backing scale factor (does not require a view)
float get_screen_scale_factor(void);

// Rasterize an SVG string into a Metal texture
void *rasterize_svg(void *device, void *queue, const char *svg_xml, float width, float height);

// Batched draw: submit all rect vertices in a single draw call
void batch_solid_rects(void *frame_context, void *device,
                       const void *vertex_data, int vertex_count);

#ifdef __cplusplus
}
#endif

#endif // OBJC_BRIDGE_H
