const std = @import("std");
const parser_mod = @import("../../src/css/parser.zig");
const properties_mod = @import("../../src/css/properties.zig");

test "css_parse:01 single rule one declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "div { color: red; }";
    const sheet = try parser_mod.Parser.parse(allocator, css);

    try std.testing.expectEqual(@as(usize, 1), sheet.rules.len);
    try std.testing.expectEqual(@as(usize, 1), sheet.rules[0].selectors.len);
    try std.testing.expectEqual(@as(usize, 1), sheet.rules[0].declarations.len);
    try std.testing.expectEqualStrings("color", sheet.rules[0].declarations[0].property);
    try std.testing.expectEqualStrings("red", sheet.rules[0].declarations[0].value);
}

test "css_parse:02 multiple declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "div { color: red; display: block; }";
    const sheet = try parser_mod.Parser.parse(allocator, css);

    try std.testing.expectEqual(@as(usize, 2), sheet.rules[0].declarations.len);
}

test "css_parse:03 multiple rules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "div { color: red; } p { color: blue; }";
    const sheet = try parser_mod.Parser.parse(allocator, css);

    try std.testing.expectEqual(@as(usize, 2), sheet.rules.len);
}

test "css_parse:04 comma separated selectors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "h1, h2 { color: red; }";
    const sheet = try parser_mod.Parser.parse(allocator, css);

    try std.testing.expectEqual(@as(usize, 1), sheet.rules.len);
    try std.testing.expectEqual(@as(usize, 2), sheet.rules[0].selectors.len);
}

test "css_parse:05 inline style" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "color: red; font-size: 16px;";
    const decls = try parser_mod.Parser.parseInlineStyle(allocator, css);

    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("color", decls[0].property);
    try std.testing.expectEqualStrings("red", decls[0].value);
}

test "css_parse:06 empty stylesheet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sheet = try parser_mod.Parser.parse(allocator, "");
    try std.testing.expectEqual(@as(usize, 0), sheet.rules.len);
}

test "css_parse:07 malformed missing brace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "div { color: red;";
    _ = try parser_mod.Parser.parse(allocator, css);
}

test "css_parse:08 malformed missing value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const css = "div { color: ; }";
    const sheet = try parser_mod.Parser.parse(allocator, css);
    try std.testing.expectEqual(@as(usize, 1), sheet.rules.len);
}

test "css_parse:09 shorthand margin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};
    try style.applyProperty("margin", "10px 20px", allocator);
    try std.testing.expectEqual(@as(f32, 10), style.margin_top.value);
    try std.testing.expectEqual(@as(f32, 10), style.margin_bottom.value);
    try std.testing.expectEqual(@as(f32, 20), style.margin_right.value);
    try std.testing.expectEqual(@as(f32, 20), style.margin_left.value);
}

test "css_parse:10 shorthand padding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};
    try style.applyProperty("padding", "5px", allocator);
    try std.testing.expectEqual(@as(f32, 5), style.padding_top.value);
    try std.testing.expectEqual(@as(f32, 5), style.padding_right.value);
    try std.testing.expectEqual(@as(f32, 5), style.padding_bottom.value);
    try std.testing.expectEqual(@as(f32, 5), style.padding_left.value);

    try style.applyProperty("padding", "1px 2px 3px", allocator);
    try std.testing.expectEqual(@as(f32, 1), style.padding_top.value);
    try std.testing.expectEqual(@as(f32, 2), style.padding_right.value);
    try std.testing.expectEqual(@as(f32, 3), style.padding_bottom.value);
    try std.testing.expectEqual(@as(f32, 2), style.padding_left.value);
}

test "css_parse:10b shorthand inset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};
    try style.applyProperty("inset", "0", allocator);
    try std.testing.expectEqual(@as(f32, 0), style.top.?.value);
    try std.testing.expectEqual(@as(f32, 0), style.right_pos.?.value);
    try std.testing.expectEqual(@as(f32, 0), style.bottom.?.value);
    try std.testing.expectEqual(@as(f32, 0), style.left_pos.?.value);

    try style.applyProperty("inset", "1px 2px 3px 4px", allocator);
    try std.testing.expectEqual(@as(f32, 1), style.top.?.value);
    try std.testing.expectEqual(@as(f32, 2), style.right_pos.?.value);
    try std.testing.expectEqual(@as(f32, 3), style.bottom.?.value);
    try std.testing.expectEqual(@as(f32, 4), style.left_pos.?.value);
}

test "css_parse:13 new properties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};

    try style.applyProperty("position", "absolute", allocator);
    try std.testing.expectEqual(properties_mod.Position.absolute, style.position);

    try style.applyProperty("overflow", "hidden", allocator);
    try std.testing.expectEqual(properties_mod.Overflow.hidden, style.overflow);

    try style.applyProperty("z-index", "100", allocator);
    try std.testing.expectEqual(@as(?i32, 100), style.z_index);

    try style.applyProperty("margin-top", "10px", allocator);
    try std.testing.expectEqual(@as(f32, 10), style.margin_top.value);

    try style.applyProperty("padding-left", "20px", allocator);
    try std.testing.expectEqual(@as(f32, 20), style.padding_left.value);

    try style.applyProperty("border-width", "2px", allocator);
    try std.testing.expectEqual(@as(f32, 2), style.border_width.value);

    try style.applyProperty("border-color", "blue", allocator);
    try std.testing.expectEqual(@as(u8, 255), style.border_color.b);

    try style.applyProperty("border-radius", "4px", allocator);
    try std.testing.expectEqual(@as(f32, 4), style.border_radius.value);

    try style.applyProperty("font-weight", "bold", allocator);
    try std.testing.expectEqual(@as(f32, 700), style.font_weight);

    try style.applyProperty("font-weight", "500", allocator);
    try std.testing.expectEqual(@as(f32, 500), style.font_weight);

    try style.applyProperty("font-family", "Arial", allocator);
    try std.testing.expectEqualStrings("Arial", style.font_family);

    try style.applyProperty("min-width", "100px", allocator);
    try std.testing.expectEqual(@as(f32, 100), style.min_width.?.value);

    try style.applyProperty("max-height", "200px", allocator);
    try std.testing.expectEqual(@as(f32, 200), style.max_height.?.value);

    try style.applyProperty("top", "5px", allocator);
    try std.testing.expectEqual(@as(f32, 5), style.top.?.value);

    try style.applyProperty("left", "15px", allocator);
    try std.testing.expectEqual(@as(f32, 15), style.left_pos.?.value);
}

test "css_parse:11 property application" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};
    try style.applyProperty("display", "block", allocator);
    try std.testing.expectEqual(properties_mod.Display.block, style.display);

    try style.applyProperty("color", "red", allocator);
    try std.testing.expectEqual(@as(u8, 255), style.color.r);
    try std.testing.expectEqual(@as(u8, 0), style.color.g);
}

test "css_parse:12 opacity clamp" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var style = properties_mod.ComputedStyle{};
    try style.applyProperty("opacity", "1.5", allocator);
    try std.testing.expectEqual(@as(f32, 1.0), style.opacity);

    try style.applyProperty("opacity", "-0.5", allocator);
    try std.testing.expectEqual(@as(f32, 0.0), style.opacity);
}
