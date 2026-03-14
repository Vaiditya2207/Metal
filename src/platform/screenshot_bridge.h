#ifndef SCREENSHOT_BRIDGE_H
#define SCREENSHOT_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Create an offscreen Metal texture for rendering (BGRA8Unorm, managed storage)
void *create_offscreen_texture(void *device, int width, int height);

// Begin an offscreen render pass targeting the given texture.
// Returns a FrameContext pointer (same struct as in objc_bridge.h).
void *begin_offscreen_frame(void *device, void *command_queue, void *texture);

// End offscreen render pass: end encoding, synchronize texture, commit + wait.
void end_offscreen_frame(void *frame_context);

// Save a Metal texture to a PNG file. Returns 0 on success, -1 on failure.
int save_texture_to_png(void *texture, const char *path);

#ifdef __cplusplus
}
#endif

#endif // SCREENSHOT_BRIDGE_H
