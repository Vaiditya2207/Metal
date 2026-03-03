const std = @import("std");
const tok = @import("../../src/css/tokenizer.zig");

fn expectToken(actual: tok.CssToken, expected_type: tok.CssTokenType, expected_value: []const u8) !void {
    try std.testing.expectEqual(expected_type, actual.type);
    try std.testing.expectEqualStrings(expected_value, actual.value);
}

test "css_tok:01 simple property" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "color: red;");

    try expectToken(try tokenizer.next(), .ident, "color");
    try expectToken(try tokenizer.next(), .colon, ":");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "red");
    try expectToken(try tokenizer.next(), .semicolon, ";");
    try expectToken(try tokenizer.next(), .eof, "");
}

test "css_tok:02 class selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, ".class");
    try expectToken(try tokenizer.next(), .delim, ".");
    try expectToken(try tokenizer.next(), .ident, "class");
}

test "css_tok:03 id selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "#id");
    try expectToken(try tokenizer.next(), .hash, "id");
}

test "css_tok:04 complex selector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "div > p");
    try expectToken(try tokenizer.next(), .ident, "div");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .delim, ">");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "p");
}

test "css_tok:05 full rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "div { color: red; }");
    try expectToken(try tokenizer.next(), .ident, "div");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .left_brace, "{");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "color");
    try expectToken(try tokenizer.next(), .colon, ":");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "red");
    try expectToken(try tokenizer.next(), .semicolon, ";");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .right_brace, "}");
}

test "css_tok:06 skip comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "/* comment */ color: red;");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "color");
}

test "css_tok:07 unclosed comment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "/* unclosed");
    try expectToken(try tokenizer.next(), .eof, "");
}

test "css_tok:08 double quoted string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "\"hello world\"");
    try expectToken(try tokenizer.next(), .string, "hello world");
}

test "css_tok:09 single quoted string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "'hello world'");
    try expectToken(try tokenizer.next(), .string, "hello world");
}

test "css_tok:10 number integer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "123");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.number, t.type);
    try std.testing.expectEqual(@as(f32, 123), t.number_value);
}

test "css_tok:11 number float" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "123.45");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.number, t.type);
    try std.testing.expectEqual(@as(f32, 123.45), t.number_value);
}

test "css_tok:12 dimension px" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "10px");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.dimension, t.type);
    try std.testing.expectEqual(@as(f32, 10), t.number_value);
    try std.testing.expectEqualStrings("px", t.unit);
}

test "css_tok:13 percentage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "50%");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.percentage, t.type);
    try std.testing.expectEqual(@as(f32, 50), t.number_value);
}

test "css_tok:14 at-keyword" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "@media");
    try expectToken(try tokenizer.next(), .at_keyword, "media");
}

test "css_tok:15 collapse whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "  \n  \t  ");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .eof, "");
}

test "css_tok:16 delimiters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "+~*");
    try expectToken(try tokenizer.next(), .delim, "+");
    try expectToken(try tokenizer.next(), .delim, "~");
    try expectToken(try tokenizer.next(), .delim, "*");
}

test "css_tok:17 empty input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "");
    try expectToken(try tokenizer.next(), .eof, "");
}

test "css_tok:18 parenthesized" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "(content)");
    try expectToken(try tokenizer.next(), .left_paren, "(");
    try expectToken(try tokenizer.next(), .ident, "content");
    try expectToken(try tokenizer.next(), .right_paren, ")");
}

test "css_tok:19 brackets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "[attr]");
    try expectToken(try tokenizer.next(), .left_bracket, "[");
    try expectToken(try tokenizer.next(), .ident, "attr");
    try expectToken(try tokenizer.next(), .right_bracket, "]");
}

test "css_tok:20 comma" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "a, b");
    try expectToken(try tokenizer.next(), .ident, "a");
    try expectToken(try tokenizer.next(), .comma, ",");
    try expectToken(try tokenizer.next(), .whitespace, " ");
    try expectToken(try tokenizer.next(), .ident, "b");
}

test "css_tok:21 unclosed string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "\"unclosed");
    try expectToken(try tokenizer.next(), .string, "unclosed");
}

test "css_tok:22 negative dimension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "-10px");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.dimension, t.type);
    try std.testing.expectEqual(@as(f32, -10), t.number_value);
    try std.testing.expectEqualStrings("px", t.unit);
}

test "css_tok:23 negative number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "-42");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.number, t.type);
    try std.testing.expectEqual(@as(f32, -42), t.number_value);
}

test "css_tok:24 negative percentage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "-50%");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.percentage, t.type);
    try std.testing.expectEqual(@as(f32, -50), t.number_value);
}

test "css_tok:25 negative float dimension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "-1.5em");
    const t = try tokenizer.next();
    try std.testing.expectEqual(tok.CssTokenType.dimension, t.type);
    try std.testing.expectEqual(@as(f32, -1.5), t.number_value);
    try std.testing.expectEqualStrings("em", t.unit);
}

test "css_tok:26 ident starting with dash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokenizer = tok.CssTokenizer.init(allocator, "--custom");
    try expectToken(try tokenizer.next(), .ident, "--custom");
}
