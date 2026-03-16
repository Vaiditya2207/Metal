const std = @import("std");
const loader = @import("config_loader.zig");

pub const Config = @import("config_types.zig").Config;

/// Global configuration instance.
var global_config: Config = .{};
var config_initialized: bool = false;
var config_arena: std.heap.ArenaAllocator = undefined;
var config_arena_initialized: bool = false;

fn configAllocator() std.mem.Allocator {
    if (!config_arena_initialized) {
        config_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        config_arena_initialized = true;
    }
    return config_arena.allocator();
}

/// Returns the global config and applies JSON overrides on first use.
pub fn getConfig() *const Config {
    if (!config_initialized) {
        config_initialized = true;
        loader.loadConfig(&global_config, configAllocator());
    }
    return &global_config;
}
