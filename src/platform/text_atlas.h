#ifndef TEXT_ATLAS_H
#define TEXT_ATLAS_H

#ifdef __cplusplus
extern "C" {
#endif

// Metrics for a single glyph in the atlas
typedef struct {
    float uv_x, uv_y, uv_w, uv_h;  // UV coordinates in atlas (0..1)
    float width, height;           // Glyph size in pixels
    float bearing_x, bearing_y;    // Offset from baseline
    float advance;                 // Horizontal advance
} GlyphMetrics;

// Create a font atlas texture. Returns opaque MTLTexture handle.
// Populates the metrics array for ASCII 32..126 (95 glyphs).
// metrics_out must point to an array of at least 95 GlyphMetrics.
void *create_font_atlas(void *device, void *queue, float font_size, float scale_factor, GlyphMetrics *metrics_out, float *ascent_out);

// Create a text-specific render pipeline (with texture sampling)
void *create_text_pipeline(void *device);

// Draw a single textured glyph quad
void draw_text_quad(void *frame_context, void *texture,
                    float dst_x, float dst_y, float dst_w, float dst_h,
                    float uv_x, float uv_y, float uv_w, float uv_h,
                    float r, float g, float b, float a);

// Batched draw: submit all text glyph vertices in a single draw call
void batch_text_quads(void *frame_context, void *device, void *texture,
                      const void *vertex_data, int vertex_count);

// Measure text width using CoreText (no Metal device required)
float measure_text_width(const char *text, int len, float font_size);

#ifdef __cplusplus
}
#endif

#endif // TEXT_ATLAS_H
