const std = @import("std");
const testing = std.testing;
const batch = @import("../../src/render/batch.zig");

// -- RectBatch tests --

test "RectBatch starts empty" {
    var b: batch.RectBatch = .{};
    try testing.expectEqual(@as(usize, 0), b.vertexCount());
    try testing.expect(!b.isFull());
}

test "RectBatch appendRect adds 6 vertices" {
    var b: batch.RectBatch = .{};
    b.appendRect(10, 20, 100, 50, 1.0, 0.0, 0.0, 1.0);
    try testing.expectEqual(@as(usize, 6), b.vertexCount());
}

test "RectBatch appendRect produces correct triangle vertices" {
    var b: batch.RectBatch = .{};
    b.appendRect(10, 20, 100, 50, 1.0, 0.5, 0.0, 1.0);

    // Triangle 1: top-left, top-right, bottom-left
    try testing.expectApproxEqAbs(@as(f32, 10), b.vertices[0].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), b.vertices[0].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 110), b.vertices[1].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), b.vertices[1].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 10), b.vertices[2].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 70), b.vertices[2].position[1], 0.001);

    // Triangle 2: top-right, bottom-left, bottom-right
    try testing.expectApproxEqAbs(@as(f32, 110), b.vertices[3].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), b.vertices[3].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 10), b.vertices[4].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 70), b.vertices[4].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 110), b.vertices[5].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 70), b.vertices[5].position[1], 0.001);

    // All vertices share the same color
    for (0..6) |i| {
        try testing.expectApproxEqAbs(@as(f32, 1.0), b.vertices[i].color[0], 0.001);
        try testing.expectApproxEqAbs(@as(f32, 0.5), b.vertices[i].color[1], 0.001);
        try testing.expectApproxEqAbs(@as(f32, 0.0), b.vertices[i].color[2], 0.001);
        try testing.expectApproxEqAbs(@as(f32, 1.0), b.vertices[i].color[3], 0.001);
    }
}

test "RectBatch isFull returns true at capacity" {
    var b: batch.RectBatch = .{};
    const max_quads = batch.max_rect_vertices / 6;
    for (0..max_quads) |_| {
        b.appendRect(0, 0, 1, 1, 1, 1, 1, 1);
    }
    try testing.expectEqual(batch.max_rect_vertices, b.vertexCount());
    try testing.expect(b.isFull());
}

test "RectBatch appendRect silently drops when full" {
    var b: batch.RectBatch = .{};
    const max_quads = batch.max_rect_vertices / 6;
    for (0..max_quads) |_| {
        b.appendRect(0, 0, 1, 1, 1, 1, 1, 1);
    }
    // One more should be silently dropped
    b.appendRect(99, 99, 99, 99, 0, 0, 0, 0);
    try testing.expectEqual(batch.max_rect_vertices, b.vertexCount());
}

test "RectBatch clear resets count" {
    var b: batch.RectBatch = .{};
    b.appendRect(0, 0, 10, 10, 1, 0, 0, 1);
    try testing.expectEqual(@as(usize, 6), b.vertexCount());
    b.clear();
    try testing.expectEqual(@as(usize, 0), b.vertexCount());
    try testing.expect(!b.isFull());
}

// -- TextBatch tests --

test "TextBatch starts empty" {
    var b: batch.TextBatch = .{};
    try testing.expectEqual(@as(usize, 0), b.vertexCount());
    try testing.expect(!b.isFull());
}

test "TextBatch appendQuad adds 6 vertices with correct UV mapping" {
    var b: batch.TextBatch = .{};
    // dst: x=10 y=20 w=8 h=12, uv: ux=0.1 uy=0.2 uw=0.05 uh=0.08
    b.appendQuad(10, 20, 8, 12, 0.1, 0.2, 0.05, 0.08, 1.0, 1.0, 1.0, 1.0);
    try testing.expectEqual(@as(usize, 6), b.vertexCount());

    // Vertex 0: top-left position, UV = {ux, uy + uh} (flipped)
    try testing.expectApproxEqAbs(@as(f32, 10), b.vertices[0].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 20), b.vertices[0].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.1), b.vertices[0].uv[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.28), b.vertices[0].uv[1], 0.001);

    // Vertex 2: bottom-left position, UV = {ux, uy}
    try testing.expectApproxEqAbs(@as(f32, 10), b.vertices[2].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 32), b.vertices[2].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.1), b.vertices[2].uv[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.2), b.vertices[2].uv[1], 0.001);

    // Vertex 5: bottom-right, UV = {ux + uw, uy}
    try testing.expectApproxEqAbs(@as(f32, 18), b.vertices[5].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 32), b.vertices[5].position[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.15), b.vertices[5].uv[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.2), b.vertices[5].uv[1], 0.001);

    // Color check on all vertices
    for (0..6) |i| {
        try testing.expectApproxEqAbs(@as(f32, 1.0), b.vertices[i].color[0], 0.001);
    }
}

test "TextBatch isFull returns true at capacity" {
    var b: batch.TextBatch = .{};
    const max_quads = batch.max_text_vertices / 6;
    for (0..max_quads) |_| {
        b.appendQuad(0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1);
    }
    try testing.expectEqual(batch.max_text_vertices, b.vertexCount());
    try testing.expect(b.isFull());
}

test "TextBatch clear resets count" {
    var b: batch.TextBatch = .{};
    b.appendQuad(0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1);
    b.clear();
    try testing.expectEqual(@as(usize, 0), b.vertexCount());
}

test "RectVertex is extern struct with correct size" {
    // 2 floats position + 4 floats color = 6 * 4 = 24 bytes
    try testing.expectEqual(@as(usize, 24), @sizeOf(batch.RectVertex));
}

test "TextVertex is extern struct with correct size" {
    // 2 floats position + 2 floats uv + 4 floats color = 8 * 4 = 32 bytes
    try testing.expectEqual(@as(usize, 32), @sizeOf(batch.TextVertex));
}

test "Multiple rects accumulate sequentially" {
    var b: batch.RectBatch = .{};
    b.appendRect(0, 0, 10, 10, 1, 0, 0, 1);
    b.appendRect(20, 20, 10, 10, 0, 1, 0, 1);
    try testing.expectEqual(@as(usize, 12), b.vertexCount());

    // Second rect's first vertex starts at index 6
    try testing.expectApproxEqAbs(@as(f32, 20), b.vertices[6].position[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), b.vertices[6].color[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), b.vertices[6].color[1], 0.001);
}
