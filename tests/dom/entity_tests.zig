const std = @import("std");
const entity = @import("../../src/dom/entity.zig");

test "entity:01 decode amp" {
    var pos: usize = 0;
    const input = "&amp;";
    const result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("&", result.slice());
    try std.testing.expectEqual(@as(usize, 5), pos);
}

test "entity:02 decode lt" {
    var pos: usize = 0;
    const input = "&lt;";
    const result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("<", result.slice());
    try std.testing.expectEqual(@as(usize, 4), pos);
}

test "entity:03 decode numeric ASCII" {
    var pos: usize = 0;
    const input = "&#65;";
    const result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("A", result.slice());
    try std.testing.expectEqual(@as(usize, 5), pos);
}

test "entity:04 decode hex ASCII" {
    var pos: usize = 0;
    const input = "&#x41;";
    const result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("A", result.slice());
    try std.testing.expectEqual(@as(usize, 6), pos);
}

test "entity:05 decode multibyte codepoint" {
    var pos: usize = 0;
    const input = "&#x00E9;";
    const result = entity.decode(input, &pos);
    // e-acute is U+00E9, UTF-8: 0xC3 0xA9
    try std.testing.expectEqualStrings("\u{00E9}", result.slice());
    try std.testing.expectEqual(@as(usize, 8), pos);
}

test "entity:06 decode emoji codepoint" {
    var pos: usize = 0;
    const input = "&#x1F600;";
    const result = entity.decode(input, &pos);
    // U+1F600 is 😀, UTF-8: 0xF0 0x9F 0x98 0x80
    try std.testing.expectEqualStrings("\u{1F600}", result.slice());
    try std.testing.expectEqual(@as(usize, 9), pos);
}

test "entity:07 decode unknown entity" {
    var pos: usize = 0;
    const input = "&unknown;";
    const result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("&", result.slice());
    try std.testing.expectEqual(@as(usize, 1), pos);
}

test "entity:08 decode new entities" {
    var pos: usize = 0;
    const input = "&nbsp;&copy;&euro;";

    // nbsp (U+00A0)
    var result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("\u{00A0}", result.slice());
    try std.testing.expectEqual(@as(usize, 6), pos);

    // copy (U+00A9)
    result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("\u{00A9}", result.slice());
    try std.testing.expectEqual(@as(usize, 12), pos);

    // euro (U+20AC)
    result = entity.decode(input, &pos);
    try std.testing.expectEqualStrings("\u{20AC}", result.slice());
    try std.testing.expectEqual(@as(usize, 18), pos);
}
