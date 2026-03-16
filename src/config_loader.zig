const std = @import("std");
const Config = @import("config_types.zig").Config;

fn valueToF32(value: std.json.Value) ?f32 {
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        else => null,
    };
}

fn valueToU32(value: std.json.Value) ?u32 {
    return switch (value) {
        .integer => |v| if (v >= 0) @intCast(v) else null,
        .float => |v| if (v >= 0) @intFromFloat(v) else null,
        else => null,
    };
}

fn valueToU16(value: std.json.Value) ?u16 {
    const v = valueToU32(value) orelse return null;
    if (v > std.math.maxInt(u16)) return null;
    return @intCast(v);
}

fn readColor(value: std.json.Value, fallback: [4]f32) [4]f32 {
    if (value != .array) return fallback;
    const items = value.array.items;
    if (items.len != 4) return fallback;
    var out = fallback;
    for (items, 0..) |item, idx| {
        if (valueToF32(item)) |v| out[idx] = v;
    }
    return out;
}

fn applyWindowConfig(cfg: *Config.WindowConfig, value: std.json.Value, alloc: std.mem.Allocator) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("title")) |v| {
        if (v == .string) {
            const title_buf = alloc.dupeZ(u8, v.string) catch return;
            cfg.title = title_buf;
        }
    }
    if (obj.get("width")) |v| {
        if (valueToU16(v)) |w| cfg.width = w;
    }
    if (obj.get("height")) |v| {
        if (valueToU16(v)) |h| cfg.height = h;
    }
}

fn applyRendererConfig(cfg: *Config.RendererConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("clear_color")) |v| cfg.clear_color = readColor(v, cfg.clear_color);
    if (obj.get("target_fps")) |v| {
        if (valueToU16(v)) |fps| cfg.target_fps = fps;
    }
}

fn applyParserConfig(cfg: *Config.ParserConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("max_document_size_bytes")) |v| {
        if (valueToU32(v)) |n| cfg.max_document_size_bytes = n;
    }
    if (obj.get("max_tag_name_length")) |v| {
        if (valueToU16(v)) |n| cfg.max_tag_name_length = n;
    }
    if (obj.get("max_attribute_name_length")) |v| {
        if (valueToU16(v)) |n| cfg.max_attribute_name_length = n;
    }
    if (obj.get("max_attribute_value_length")) |v| {
        if (valueToU32(v)) |n| cfg.max_attribute_value_length = n;
    }
    if (obj.get("max_attributes_per_element")) |v| {
        if (valueToU16(v)) |n| cfg.max_attributes_per_element = n;
    }
    if (obj.get("max_tree_depth")) |v| {
        if (valueToU16(v)) |n| cfg.max_tree_depth = n;
    }
    if (obj.get("max_children_per_node")) |v| {
        if (valueToU32(v)) |n| cfg.max_children_per_node = n;
    }
    if (obj.get("max_total_nodes")) |v| {
        if (valueToU32(v)) |n| cfg.max_total_nodes = n;
    }
    if (obj.get("max_entity_length")) |v| {
        if (valueToU32(v)) |n| {
        if (n <= std.math.maxInt(u8)) cfg.max_entity_length = @intCast(n);
        }
    }
}

fn applyCssConfig(cfg: *Config.CssConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("max_selector_depth")) |v| {
        if (valueToU16(v)) |n| cfg.max_selector_depth = n;
    }
    if (obj.get("max_rules_per_stylesheet")) |v| {
        if (valueToU32(v)) |n| cfg.max_rules_per_stylesheet = n;
    }
    if (obj.get("max_declarations_per_rule")) |v| {
        if (valueToU16(v)) |n| cfg.max_declarations_per_rule = n;
    }
    if (obj.get("max_stylesheets")) |v| {
        if (valueToU16(v)) |n| cfg.max_stylesheets = n;
    }
    if (obj.get("max_selector_parts")) |v| {
        if (valueToU16(v)) |n| cfg.max_selector_parts = n;
    }
    if (obj.get("max_value_length")) |v| {
        if (valueToU32(v)) |n| cfg.max_value_length = n;
    }
}

fn applyLayoutConfig(cfg: *Config.LayoutConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("max_layout_depth")) |v| {
        if (valueToU16(v)) |n| cfg.max_layout_depth = n;
    }
    if (obj.get("max_layout_nodes")) |v| {
        if (valueToU32(v)) |n| cfg.max_layout_nodes = n;
    }
    if (obj.get("max_children_per_node")) |v| {
        if (valueToU32(v)) |n| cfg.max_children_per_node = n;
    }
}

fn applyNetworkConfig(cfg: *Config.NetworkConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("request_timeout_ms")) |v| {
        if (valueToU32(v)) |n| cfg.request_timeout_ms = n;
    }
    if (obj.get("max_response_size_bytes")) |v| {
        if (valueToU32(v)) |n| cfg.max_response_size_bytes = n;
    }
    if (obj.get("max_concurrent_fetches")) |v| {
        if (valueToU32(v)) |n| {
        if (n <= std.math.maxInt(u8)) cfg.max_concurrent_fetches = @intCast(n);
        }
    }
    if (obj.get("max_redirects")) |v| {
        if (valueToU32(v)) |n| {
        if (n <= std.math.maxInt(u8)) cfg.max_redirects = @intCast(n);
        }
    }
}

fn applyToolbarConfig(cfg: *Config.UiConfig.ToolbarConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("height")) |v| {
        if (valueToF32(v)) |n| cfg.height = n;
    }
    if (obj.get("padding_x")) |v| {
        if (valueToF32(v)) |n| cfg.padding_x = n;
    }
    if (obj.get("padding_y")) |v| {
        if (valueToF32(v)) |n| cfg.padding_y = n;
    }
    if (obj.get("border_height")) |v| {
        if (valueToF32(v)) |n| cfg.border_height = n;
    }
    if (obj.get("button_size")) |v| {
        if (valueToF32(v)) |n| cfg.button_size = n;
    }
    if (obj.get("button_gap")) |v| {
        if (valueToF32(v)) |n| cfg.button_gap = n;
    }
    if (obj.get("address_height")) |v| {
        if (valueToF32(v)) |n| cfg.address_height = n;
    }
    if (obj.get("address_gap")) |v| {
        if (valueToF32(v)) |n| cfg.address_gap = n;
    }
    if (obj.get("address_padding_x")) |v| {
        if (valueToF32(v)) |n| cfg.address_padding_x = n;
    }
    if (obj.get("address_border_width")) |v| {
        if (valueToF32(v)) |n| cfg.address_border_width = n;
    }
    if (obj.get("url_text_size")) |v| {
        if (valueToF32(v)) |n| cfg.url_text_size = n;
    }
    if (obj.get("title_text_size")) |v| {
        if (valueToF32(v)) |n| cfg.title_text_size = n;
    }
    if (obj.get("title_area_width")) |v| {
        if (valueToF32(v)) |n| cfg.title_area_width = n;
    }
    if (obj.get("favicon_size")) |v| {
        if (valueToF32(v)) |n| cfg.favicon_size = n;
    }
    if (obj.get("favicon_gap")) |v| {
        if (valueToF32(v)) |n| cfg.favicon_gap = n;
    }
    if (obj.get("loading_bar_height")) |v| {
        if (valueToF32(v)) |n| cfg.loading_bar_height = n;
    }
    if (obj.get("loading_bar_offset")) |v| {
        if (valueToF32(v)) |n| cfg.loading_bar_offset = n;
    }
    if (obj.get("loading_bar_width_ratio")) |v| {
        if (valueToF32(v)) |n| cfg.loading_bar_width_ratio = n;
    }
}

fn applyScrollbarConfig(cfg: *Config.UiConfig.ScrollbarConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("width")) |v| {
        if (valueToF32(v)) |n| cfg.width = n;
    }
    if (obj.get("thumb_inset")) |v| {
        if (valueToF32(v)) |n| cfg.thumb_inset = n;
    }
    if (obj.get("min_thumb_height")) |v| {
        if (valueToF32(v)) |n| cfg.min_thumb_height = n;
    }
}

fn applyUiColors(cfg: *Config.UiConfig.UiColors, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("toolbar_bg")) |v| cfg.toolbar_bg = readColor(v, cfg.toolbar_bg);
    if (obj.get("toolbar_border")) |v| cfg.toolbar_border = readColor(v, cfg.toolbar_border);
    if (obj.get("address_bg")) |v| cfg.address_bg = readColor(v, cfg.address_bg);
    if (obj.get("address_border")) |v| cfg.address_border = readColor(v, cfg.address_border);
    if (obj.get("address_focus_border")) |v| cfg.address_focus_border = readColor(v, cfg.address_focus_border);
    if (obj.get("button_bg")) |v| cfg.button_bg = readColor(v, cfg.button_bg);
    if (obj.get("button_hover_bg")) |v| cfg.button_hover_bg = readColor(v, cfg.button_hover_bg);
    if (obj.get("button_disabled_bg")) |v| cfg.button_disabled_bg = readColor(v, cfg.button_disabled_bg);
    if (obj.get("button_icon")) |v| cfg.button_icon = readColor(v, cfg.button_icon);
    if (obj.get("button_icon_disabled")) |v| cfg.button_icon_disabled = readColor(v, cfg.button_icon_disabled);
    if (obj.get("url_text")) |v| cfg.url_text = readColor(v, cfg.url_text);
    if (obj.get("url_placeholder")) |v| cfg.url_placeholder = readColor(v, cfg.url_placeholder);
    if (obj.get("title_text")) |v| cfg.title_text = readColor(v, cfg.title_text);
    if (obj.get("loading_bar")) |v| cfg.loading_bar = readColor(v, cfg.loading_bar);
    if (obj.get("scrollbar_track")) |v| cfg.scrollbar_track = readColor(v, cfg.scrollbar_track);
    if (obj.get("scrollbar_thumb")) |v| cfg.scrollbar_thumb = readColor(v, cfg.scrollbar_thumb);
}

fn applyUiConfig(cfg: *Config.UiConfig, value: std.json.Value) void {
    if (value != .object) return;
    const obj = value.object;
    if (obj.get("toolbar")) |v| applyToolbarConfig(&cfg.toolbar, v);
    if (obj.get("scrollbar")) |v| applyScrollbarConfig(&cfg.scrollbar, v);
    if (obj.get("colors")) |v| applyUiColors(&cfg.colors, v);
}

pub fn loadConfig(cfg: *Config, allocator: std.mem.Allocator) void {
    const env_path = std.process.getEnvVarOwned(allocator, "METAL_CONFIG") catch null;
    const config_path = env_path orelse "resources/default_config.json";
    var file = std.fs.cwd().openFile(config_path, .{}) catch return;
    defer file.close();
    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch return;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    const obj = parsed.value.object;
    if (obj.get("parser")) |v| applyParserConfig(&cfg.parser, v);
    if (obj.get("window")) |v| applyWindowConfig(&cfg.window, v, allocator);
    if (obj.get("renderer")) |v| applyRendererConfig(&cfg.renderer, v);
    if (obj.get("css")) |v| applyCssConfig(&cfg.css, v);
    if (obj.get("layout")) |v| applyLayoutConfig(&cfg.layout, v);
    if (obj.get("network")) |v| applyNetworkConfig(&cfg.network, v);
    if (obj.get("ui")) |v| applyUiConfig(&cfg.ui, v);
}
