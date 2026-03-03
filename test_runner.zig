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
    _ = @import("src/dom/tokenizer_states.zig");
    _ = @import("src/dom/builder.zig");
    _ = @import("src/dom/mod.zig");
    _ = @import("src/dom/event_target.zig");
    _ = @import("src/css/mod.zig");
    _ = @import("src/css/resolver.zig");
    _ = @import("src/css/user_agent.zig");
    _ = @import("src/css/style_extract.zig");
    _ = @import("src/layout/mod.zig");
    _ = @import("src/layout/block.zig");
    _ = @import("src/layout/inline.zig");
    _ = @import("src/layout/text_measure.zig");
    _ = @import("src/layout/position.zig");
    _ = @import("src/layout/flex.zig");
    _ = @import("src/render/hit_test.zig");
    _ = @import("src/render/scroll.zig");
    _ = @import("src/render/display_list.zig");
    _ = @import("src/js/mod.zig");
    _ = @import("src/js/context.zig");
    _ = @import("src/js/console.zig");
    _ = @import("src/js/dom_bindings.zig");
    _ = @import("src/js/script_runner.zig");

    // External test files
    _ = @import("tests/dom/tokenizer_tests.zig");
    _ = @import("tests/dom/entity_tests.zig");
    _ = @import("tests/dom/tree_tests.zig");
    _ = @import("tests/dom/tree_mutation_tests.zig");
    _ = @import("tests/dom/builder_tests.zig");
    _ = @import("tests/dom/attribute_mutation_tests.zig");
    _ = @import("tests/dom/text_content_tests.zig");
    _ = @import("tests/dom/event_target_tests.zig");
    _ = @import("tests/css/values_tests.zig");
    _ = @import("tests/css/tokenizer_tests.zig");
    _ = @import("tests/css/selector_tests.zig");
    _ = @import("tests/css/parser_tests.zig");
    _ = @import("tests/css/resolver_tests.zig");
    _ = @import("tests/css/user_agent_tests.zig");
    _ = @import("tests/css/style_extract_tests.zig");
    _ = @import("tests/layout/box_tests.zig");
    _ = @import("tests/layout/box_sizing_tests.zig");
    _ = @import("tests/layout/constraints_tests.zig");
    _ = @import("tests/layout/auto_margin_tests.zig");
    _ = @import("tests/layout/block_tests.zig");
    _ = @import("tests/layout/inline_tests.zig");
    _ = @import("tests/layout/inline_wrap_tests.zig");
    _ = @import("tests/layout/text_measure_tests.zig");
    _ = @import("tests/layout/position_tests.zig");
    _ = @import("tests/layout/units_tests.zig");
    _ = @import("tests/layout/flex_tests.zig");
    _ = @import("tests/layout/flex_shrink_tests.zig");
    _ = @import("tests/layout/margin_collapse_tests.zig");
    _ = @import("tests/platform/event_tests.zig");
    _ = @import("tests/render/display_list_tests.zig");
    _ = @import("tests/render/scroll_tests.zig");
    _ = @import("tests/render/hit_test_tests.zig");
    _ = @import("tests/render/resize_tests.zig");
    _ = @import("tests/render/interaction_tests.zig");
    _ = @import("tests/render/text_scale_tests.zig");
    _ = @import("tests/config_tests.zig");
    _ = @import("src/render/interaction.zig");
    _ = @import("src/render/batch.zig");
    _ = @import("src/render/compositor.zig");
    _ = @import("tests/render/batch_tests.zig");
    _ = @import("tests/render/compositor_tests.zig");
    _ = @import("tests/js/context_tests.zig");
    _ = @import("tests/js/console_tests.zig");
    _ = @import("tests/js/dom_bindings_tests.zig");
    _ = @import("tests/js/script_runner_tests.zig");
}

test "test runner loaded" {}
