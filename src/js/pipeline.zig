/// Re-render pipeline state coordination.
///
/// PipelineState tracks whether the DOM has been mutated since the last
/// render pass. Node mutation operations call notifyDirty() to signal
/// that a re-render is needed. The actual re-render logic lives in
/// main.zig / renderer.zig (Task 8).
pub const PipelineState = struct {
    dirty: bool,

    pub fn init() PipelineState {
        return .{ .dirty = false };
    }

    pub fn markDirty(self: *PipelineState) void {
        self.dirty = true;
    }

    pub fn isDirty(self: *const PipelineState) bool {
        return self.dirty;
    }

    pub fn clearDirty(self: *PipelineState) void {
        self.dirty = false;
    }
};

var g_pipeline: ?*PipelineState = null;

pub fn setGlobal(p: *PipelineState) void {
    g_pipeline = p;
}

pub fn resetGlobal() void {
    g_pipeline = null;
}

pub fn getGlobal() ?*PipelineState {
    return g_pipeline;
}

/// Called by node mutation operations to signal a re-render is needed.
pub fn notifyDirty() void {
    if (g_pipeline) |p| p.markDirty();
}
