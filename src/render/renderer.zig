const std = @import("std");
const app = @import("../platform/app.zig");
const objc = app.objc;

extern "C" fn MTLCreateSystemDefaultDevice() ?*anyopaque;

pub const Renderer = struct {
    device: *anyopaque,
    command_queue: *anyopaque,

    pub fn init() !Renderer {
        // MTLCreateSystemDefaultDevice
        const device = MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice;

        const queue = objc.create_command_queue(device) orelse return error.QueueCreationFailed;
        
        return Renderer{
            .device = device,
            .command_queue = queue,
        };
    }

    pub fn draw(ctx: ?*anyopaque) callconv(.c) void {
        _ = ctx;
        // This will be called by the MTKView delegate
        // Here we will eventually encode Metal commands
    }
};
