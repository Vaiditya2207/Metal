const std = @import("std");

pub const objc = @cImport({
    @cInclude("objc_bridge.h");
});

pub const App = struct {
    delegate: *anyopaque,

    pub fn init() !App {
        const delegate = objc.create_application_delegate() orelse return error.DelegateCreationFailed;
        return App{ .delegate = delegate };
    }

    pub fn run(self: *App) void {
        _ = self;
        // In a real app, we'd use NSApplicationMain or [NSApp run]
        // For simplicity in this bootstrap, we'll use a custom loop if needed
        // but NSApplicationMain is the standard way.
    }
};

// We'll use a simpler approach for the bootstrap main.zig
extern "c" fn NSApplicationMain(argc: i32, argv: [*]const [*]const u8) i32;
