// Project-wide test runner.
// Imports all source modules and external test files.

comptime {
    // Source modules (for any remaining comptime checks)
    _ = @import("src/config.zig");
    _ = @import("src/dom/tag.zig");
    _ = @import("src/dom/entity.zig");
    _ = @import("src/dom/node.zig");
    _ = @import("src/dom/document.zig");
    _ = @import("src/dom/tokenizer.zig");
    _ = @import("src/dom/builder.zig");
    _ = @import("src/dom/mod.zig");

    // External test files
    _ = @import("tests/dom/tokenizer_tests.zig");
    _ = @import("tests/dom/tree_tests.zig");
    _ = @import("tests/dom/builder_tests.zig");
}

test "test runner loaded" {}
