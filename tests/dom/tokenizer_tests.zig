const std = @import("std");
const tokenizer_mod = @import("../../src/dom/tokenizer.zig");
const Tokenizer = tokenizer_mod.Tokenizer;
const TokenType = tokenizer_mod.TokenType;

fn expectTokens(allocator: std.mem.Allocator, input: []const u8, expected_types: []const TokenType) !void {
    var tok = Tokenizer.init(allocator, input);
    for (expected_types) |expected_type| {
        const t = try tok.next();
        try std.testing.expectEqual(expected_type, t.type);
    }
}

// ============================================================================
// Basic Tags (1-30)
// ============================================================================

test "basic: simple elements expanded" {
    const cases = [_][]const u8{
        "<a>", "<div>", "<span>", "<p>", "<h1>", "<h2>", "<h3>", "<h4>", "<h5>", "<h6>",
        "<ul>", "<li>", "<ol>", "<table>", "<tr>", "<td>", "<th>", "<thead>", "<tbody>", "<tfoot>",
        "<form>", "<input>", "<button>", "<textarea>", "<select>", "<option>", "<nav>", "<header>", "<footer>", "<main>",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        const t = try tok.next();
        try std.testing.expectEqual(TokenType.start_tag, t.type);
    }
}

test "basic: mixed case tags" {
    const cases = [_][]const u8{ "<DIV>", "<sPaN>", "<P>", "<hTmL>", "<BODY>", "<SCRIPT>", "<STYLE>" };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        const t = try tok.next();
        try std.testing.expectEqual(TokenType.start_tag, t.type);
        const expected = try std.ascii.allocLowerString(arena.allocator(), html[1 .. html.len - 1]);
        try std.testing.expectEqualStrings(expected, t.tag_name.?);
    }
}

// ============================================================================
// Attributes (31-60)
// ============================================================================

test "attr: various styles" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const input = "<div class=a id='b' title=\"c\" data-val = d checked>";
    var tok = Tokenizer.init(arena.allocator(), input);
    const t = try tok.next();
    try std.testing.expectEqual(@as(usize, 5), t.attributes.len);
    try std.testing.expectEqualStrings("class", t.attributes[0].name);
    try std.testing.expectEqualStrings("a", t.attributes[0].value);
    try std.testing.expectEqualStrings("id", t.attributes[1].name);
    try std.testing.expectEqualStrings("b", t.attributes[1].value);
    try std.testing.expectEqualStrings("title", t.attributes[2].name);
    try std.testing.expectEqualStrings("c", t.attributes[2].value);
    try std.testing.expectEqualStrings("data-val", t.attributes[3].name);
    try std.testing.expectEqualStrings("d", t.attributes[3].value);
    try std.testing.expectEqualStrings("checked", t.attributes[4].name);
}

test "attr: massive list" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var input_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buf.deinit(arena.allocator());
    try input_buf.appendSlice(arena.allocator(), "<div");
    for (0..20) |i| {
        try input_buf.writer(arena.allocator()).print(" attr{d}=\"val{d}\"", .{ i, i });
    }
    try input_buf.append(arena.allocator(), '>');
    
    var tok = Tokenizer.init(arena.allocator(), input_buf.items);
    const t = try tok.next();
    try std.testing.expectEqual(@as(usize, 20), t.attributes.len);
}

// ============================================================================
// Entities (61-80)
// ============================================================================

test "entities: comprehensive" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const input = "&amp;&lt;&gt;&quot;&apos;&#65;&#x41;&unknown;";
    var tok = Tokenizer.init(arena.allocator(), input);
    const t = try tok.next();
    try std.testing.expectEqualStrings("&<>\"'AA&unknown;", t.data.?);
}

// ============================================================================
// Security / Malicious / XSS (81-120)
// ============================================================================

test "security: malicious scripts and handlers" {
    const payloads = [_][]const u8{
        "<script>alert(1)</script>",
        "<img src=x onerror=alert(1)>",
        "<svg/onload=alert(1)>",
        "<details open ontoggle=alert(1)>",
        "<a href=\"javascript:alert(1)\">",
        "<iframe src=\"javascript:alert(1)\">",
        "<body onload=alert(1)>",
        "<input autofocus onfocus=alert(1)>",
        "<video><source onerror=alert(1)>",
        "<p style=\"width: expression(alert(1));\">",
        "<math><maction xlink:href=\"javascript:alert(1)\">",
        "<form action=\"javascript:alert(1)\">",
        "<button onfocus=alert(1) autofocus>",
        "<isindex formaction=\"javascript:alert(1)\" type=submit>",
        "<object data=\"javascript:alert(1)\">",
        "<%alert(1)%>", // Bogus comment / Template
        "<?alert(1)?>", // Bogus comment / XML
        "<a onmouseover=\"alert(1)\">XSS</a>",
        "<base href=\"javascript:alert(1)//\">",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (payloads) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        while (true) {
            const t = try tok.next();
            if (t.type == .eof) break;
        }
    }
}

test "security: obfuscated tags" {
    const cases = [_][]const u8{
        "<\x00script>alert(1)</script>",
        "<scr\x00ipt>alert(1)</script>",
        "<s c r i p t>alert(1)</script>",
        "<script\x0b>alert(1)</script>", // VT
        "<script\x0c>alert(1)</script>", // FF
        "<script/x>alert(1)</script>",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        while (true) {
            const t = try tok.next();
            if (t.type == .eof) break;
        }
    }
}

test "security: attribute quote bypass" {
    const cases = [_][]const u8{
        "<div title=\"x\"onmouseover=alert(1)>",
        "<div title='x'onmouseover=alert(1)>",
        "<div title=x onmouseover=alert(1)>",
        "<div onmouseover=\"alert(1)\"title=x>",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        while (true) {
            const t = try tok.next();
            if (t.type == .eof) break;
        }
    }
}

// ============================================================================
// Stress / Fuzzing (121-150)
// ============================================================================

test "security: stress test long strings" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    
    // 100kb attribute value
    const long_val = try arena.allocator().alloc(u8, 100000);
    @memset(long_val, 'A');
    const input = try std.fmt.allocPrint(arena.allocator(), "<div title=\"{s}\">", .{long_val});
    
    var tok = Tokenizer.init(arena.allocator(), input);
    const t = try tok.next();
    try std.testing.expect(t.attributes[0].value.len > 0);
}

test "fuzz: programmatic random input" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // Using fixed seed for reproducibility
    var prng = std.Random.DefaultPrng.init(1234);
    const random = prng.random();

    for (0..100) |_| {
        const size = random.uintAtMost(usize, 128);
        const buf = try arena.allocator().alloc(u8, size);
        random.bytes(buf);
        var tok = Tokenizer.init(arena.allocator(), buf);
        while (true) {
            _ = tok.next() catch break;
            if (tok.pos >= buf.len) break;
        }
    }
}

// ============================================================================
// Spec Edge Cases (151+)
// ============================================================================

test "spec: complex comments" {
    const cases = [_][]const u8{
        "<!-->", "<!--->", "<!------>", "<!-- -- -->",
        "<!-- --!>", "<!-- - ->", "<!--\n--\n-->",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        const t = try tok.next();
        try std.testing.expectEqual(TokenType.comment, t.type);
    }
}

test "spec: doctypes" {
    const cases = [_][]const u8{
        "<!DOCTYPE html>", "<!doctype html>", "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">",
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    for (cases) |html| {
        var tok = Tokenizer.init(arena.allocator(), html);
        const t = try tok.next();
        try std.testing.expectEqual(TokenType.doctype, t.type);
    }
}
