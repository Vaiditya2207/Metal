#ifndef IMAGE_BRIDGE_H
#define IMAGE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Decode image data (JPEG/PNG/GIF/etc) and upload as a Metal RGBA texture.
// Returns opaque MTLTexture handle, or NULL on failure.
// Writes natural image dimensions to width_out/height_out.
void *decode_image_to_texture(void *device, void *queue,
                              const unsigned char *data, int data_len,
                              int *width_out, int *height_out);

// Create a render pipeline for drawing image quads (full RGBA texture
// sampling).
void *create_image_pipeline(void *device);

// Batched draw: submit image quad vertices in a single draw call.
void batch_image_quads(void *frame_context, void *device, void *texture,
                       const void *vertex_data, int vertex_count);

#ifdef __cplusplus
}
#endif

#endif // IMAGE_BRIDGE_H
