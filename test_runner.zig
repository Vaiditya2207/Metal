// Project-wide test runner.
// Imports all source modules and external test files.

comptime {
    _ = @import("src/config.zig");
    _ = @import("src/dom/tokenizer.zig");
    _ = @import("src/dom/tree.zig");
    _ = @import("src/dom/builder.zig");
    _ = @import("tests/dom/tokenizer_tests.zig");
}

test "test runner loaded" {
    // Basic verification of the test discovery mechanism.
}
