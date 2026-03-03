const std = @import("std");

/// Central configuration for the Metal browser engine.
/// Defaults are compiled in. In future phases, a JSON config file
/// at resources/default_config.json will be loaded at runtime to override these.
pub const Config = struct {
    parser: ParserConfig = .{},
    window: WindowConfig = .{},
    renderer: RendererConfig = .{},
    css: CssConfig = .{},
    layout: LayoutConfig = .{},

    pub const LayoutConfig = struct {
        max_layout_depth: u16 = 512,
        max_layout_nodes: u32 = 1000000,
        max_children_per_node: u32 = 65536,
    };

    pub const CssConfig = struct {
        max_selector_depth: u16 = 64,
        max_rules_per_stylesheet: u32 = 10000,
        max_declarations_per_rule: u16 = 128,
        max_stylesheets: u16 = 64,
        max_selector_parts: u16 = 32,
        max_value_length: u32 = 4096,
    };

    pub const ParserConfig = struct {
        max_document_size_bytes: u32 = 52428800,
        max_tag_name_length: u16 = 128,
        max_attribute_name_length: u16 = 256,
        max_attribute_value_length: u32 = 65536,
        max_attributes_per_element: u16 = 512,
        max_tree_depth: u16 = 512,
        max_children_per_node: u32 = 65536,
        max_total_nodes: u32 = 1000000,
        max_entity_length: u8 = 32,
    };

    pub const WindowConfig = struct {
        title: [:0]const u8 = "Metal",
        width: u16 = 1280,
        height: u16 = 800,
    };

    pub const RendererConfig = struct {
        clear_color: [4]f32 = .{ 0.1, 0.1, 0.1, 1.0 },
        target_fps: u16 = 120,
    };
};

/// Global configuration instance.
var global_config: Config = .{};
var config_initialized: bool = false;

/// Returns the global config. Uses compiled defaults.
/// In future phases, this will also load user overrides from JSON on disk.
pub fn getConfig() *const Config {
    if (!config_initialized) {
        config_initialized = true;
        // Defaults are already set in the struct initializer.
        // Runtime JSON loading will be added in a later phase
        // when the file system and settings UI are available.
    }
    return &global_config;
}
