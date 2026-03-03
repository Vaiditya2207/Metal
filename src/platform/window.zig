const std = @import("std");
const app = @import("app.zig");
const objc = app.objc;

pub const Window = struct {
    handle: *anyopaque,

    pub fn init(title: [:0]const u8, width: f32, height: f32) !Window {
        const handle = objc.create_window(title.ptr, width, height) orelse return error.WindowCreationFailed;
        return Window{ .handle = handle };
    }

    pub fn setMetalView(self: *Window, device: *anyopaque) !*anyopaque {
        return objc.create_event_metal_view(self.handle, device) orelse error.ViewCreationFailed;
    }
};
