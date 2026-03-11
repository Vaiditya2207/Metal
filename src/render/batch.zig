// Batched vertex buffers for draw call coalescing.
// RectVertex matches the rect shader's stage_in layout (24 bytes).
// TextVertex matches text_atlas.m TextVertex layout (32 bytes).
// Fixed-size buffers: zero dynamic allocation on hot paths.

pub const RectVertex = extern struct {
    position: [2]f32,
    _pad: [2]f32 = .{ 0, 0 },
    color: [4]f32,
};

pub const TextVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};

// 256 quads * 6 vertices per quad = 1536 vertices
pub const max_rect_vertices: usize = 256 * 6;
pub const max_text_vertices: usize = 256 * 6;

pub const RectBatch = struct {
    vertices: [max_rect_vertices]RectVertex = undefined,
    count: usize = 0,

    pub fn clear(self: *RectBatch) void {
        self.count = 0;
    }

    pub fn isFull(self: *const RectBatch) bool {
        return self.count + 6 > max_rect_vertices;
    }

    pub fn vertexCount(self: *const RectBatch) usize {
        return self.count;
    }

    /// Append 6 vertices forming two triangles for one axis-aligned rect.
    pub fn appendRect(
        self: *RectBatch,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    ) void {
        if (self.count + 6 > max_rect_vertices) return;
        const color = [4]f32{ r, g, b, a };
        self.vertices[self.count + 0] = .{ .position = .{ x, y }, .color = color };
        self.vertices[self.count + 1] = .{ .position = .{ x + w, y }, .color = color };
        self.vertices[self.count + 2] = .{ .position = .{ x, y + h }, .color = color };
        self.vertices[self.count + 3] = .{ .position = .{ x + w, y }, .color = color };
        self.vertices[self.count + 4] = .{ .position = .{ x, y + h }, .color = color };
        self.vertices[self.count + 5] = .{ .position = .{ x + w, y + h }, .color = color };
        self.count += 6;
    }
};

pub const TextBatch = struct {
    vertices: [max_text_vertices]TextVertex = undefined,
    count: usize = 0,

    pub fn clear(self: *TextBatch) void {
        self.count = 0;
    }

    pub fn isFull(self: *const TextBatch) bool {
        return self.count + 6 > max_text_vertices;
    }

    pub fn vertexCount(self: *const TextBatch) usize {
        return self.count;
    }

    /// Append 6 vertices for one textured glyph quad.
    /// UV mapping matches text_atlas.m: top vertices get uy+uh, bottom get uy.
    pub fn appendQuad(
        self: *TextBatch,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        ux: f32,
        uy: f32,
        uw: f32,
        uh: f32,
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    ) void {
        if (self.count + 6 > max_text_vertices) return;
        const color = [4]f32{ r, g, b, a };
        self.vertices[self.count + 0] = .{ .position = .{ x, y }, .uv = .{ ux, uy + uh }, .color = color };
        self.vertices[self.count + 1] = .{ .position = .{ x + w, y }, .uv = .{ ux + uw, uy + uh }, .color = color };
        self.vertices[self.count + 2] = .{ .position = .{ x, y + h }, .uv = .{ ux, uy }, .color = color };
        self.vertices[self.count + 3] = .{ .position = .{ x + w, y }, .uv = .{ ux + uw, uy + uh }, .color = color };
        self.vertices[self.count + 4] = .{ .position = .{ x, y + h }, .uv = .{ ux, uy }, .color = color };
        self.vertices[self.count + 5] = .{ .position = .{ x + w, y + h }, .uv = .{ ux + uw, uy }, .color = color };
        self.count += 6;
    }
};
