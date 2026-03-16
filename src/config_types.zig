pub const Config = struct {
    parser: ParserConfig = .{},
    window: WindowConfig = .{},
    renderer: RendererConfig = .{},
    css: CssConfig = .{},
    layout: LayoutConfig = .{},
    network: NetworkConfig = .{},
    ui: UiConfig = .{},

    pub const NetworkConfig = struct {
        request_timeout_ms: u32 = 30000,
        max_response_size_bytes: u32 = 52428800, // 50 MB
        max_concurrent_fetches: u8 = 6,
        max_redirects: u8 = 10,
    };

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
        clear_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
        target_fps: u16 = 120,
    };

    pub const UiConfig = struct {
        toolbar: ToolbarConfig = .{},
        scrollbar: ScrollbarConfig = .{},
        colors: UiColors = .{},

        pub const ToolbarConfig = struct {
            height: f32 = 52.0,
            padding_x: f32 = 12.0,
            padding_y: f32 = 8.0,
            border_height: f32 = 1.0,
            button_size: f32 = 28.0,
            button_gap: f32 = 8.0,
            address_height: f32 = 32.0,
            address_gap: f32 = 10.0,
            address_padding_x: f32 = 10.0,
            address_border_width: f32 = 1.0,
            url_text_size: f32 = 15.0,
            title_text_size: f32 = 12.0,
            title_area_width: f32 = 220.0,
            favicon_size: f32 = 16.0,
            favicon_gap: f32 = 6.0,
            loading_bar_height: f32 = 2.0,
            loading_bar_offset: f32 = 4.0,
            loading_bar_width_ratio: f32 = 0.3,
        };

        pub const ScrollbarConfig = struct {
            width: f32 = 10.0,
            thumb_inset: f32 = 2.0,
            min_thumb_height: f32 = 20.0,
        };

        pub const UiColors = struct {
            toolbar_bg: [4]f32 = .{ 0.97, 0.97, 0.98, 1.0 },
            toolbar_border: [4]f32 = .{ 0.83, 0.83, 0.85, 1.0 },
            address_bg: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 },
            address_border: [4]f32 = .{ 0.80, 0.80, 0.83, 1.0 },
            address_focus_border: [4]f32 = .{ 0.22, 0.52, 0.90, 1.0 },
            button_bg: [4]f32 = .{ 0.92, 0.92, 0.94, 1.0 },
            button_hover_bg: [4]f32 = .{ 0.84, 0.84, 0.86, 1.0 },
            button_disabled_bg: [4]f32 = .{ 0.94, 0.94, 0.96, 1.0 },
            button_icon: [4]f32 = .{ 0.18, 0.18, 0.20, 1.0 },
            button_icon_disabled: [4]f32 = .{ 0.60, 0.60, 0.62, 1.0 },
            url_text: [4]f32 = .{ 0.12, 0.12, 0.13, 1.0 },
            url_placeholder: [4]f32 = .{ 0.50, 0.50, 0.52, 1.0 },
            title_text: [4]f32 = .{ 0.45, 0.45, 0.47, 1.0 },
            loading_bar: [4]f32 = .{ 0.00, 0.55, 0.85, 1.0 },
            scrollbar_track: [4]f32 = .{ 0.94, 0.94, 0.95, 0.90 },
            scrollbar_thumb: [4]f32 = .{ 0.55, 0.55, 0.57, 0.90 },
        };
    };
};
