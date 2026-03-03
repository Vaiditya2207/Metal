// Test entry point — imports all modules to run their embedded tests.
// This file exists to work around Zig 0.15.2 module path restrictions.

comptime {
    _ = @import("config.zig");
    _ = @import("dom/tokenizer.zig");
    _ = @import("dom/tree.zig");
    _ = @import("dom/builder.zig");
}

test "all modules imported" {
    // This test ensures all module tests are discovered by the test runner.
}
