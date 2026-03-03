const std = @import("std");
const tokenizer_mod = @import("../../src/dom/tokenizer.zig");
const Tokenizer = tokenizer_mod.Tokenizer;
const TokenType = tokenizer_mod.TokenType;

// Helper: tokenize to completion and assert no crash
fn mustNotCrash(input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tok = Tokenizer.init(arena.allocator(), input);
    while (true) {
        const t = try tok.next();
        if (t.type == .eof) break;
    }
}

// Helper: get first token (arena intentionally not freed — test process is short-lived)
fn firstToken(input: []const u8) !tokenizer_mod.Token {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    _ = &arena;
    var tok = Tokenizer.init(arena.allocator(), input);
    return try tok.next();
}

// ============================================================================
// 1. Basic Start Tags (1-20)
// ============================================================================

test "tag:01 div" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<div>")).type); }
test "tag:02 span" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<span>")).type); }
test "tag:03 p" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<p>")).type); }
test "tag:04 a" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<a>")).type); }
test "tag:05 h1" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h1>")).type); }
test "tag:06 h2" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h2>")).type); }
test "tag:07 h3" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h3>")).type); }
test "tag:08 h4" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h4>")).type); }
test "tag:09 h5" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h5>")).type); }
test "tag:10 h6" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<h6>")).type); }
test "tag:11 ul" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<ul>")).type); }
test "tag:12 ol" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<ol>")).type); }
test "tag:13 li" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<li>")).type); }
test "tag:14 table" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<table>")).type); }
test "tag:15 tr" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<tr>")).type); }
test "tag:16 td" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<td>")).type); }
test "tag:17 th" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<th>")).type); }
test "tag:18 form" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<form>")).type); }
test "tag:19 input" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<input>")).type); }
test "tag:20 button" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<button>")).type); }

// ============================================================================
// 2. More Tags & Semantic Elements (21-35)
// ============================================================================

test "tag:21 nav" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<nav>")).type); }
test "tag:22 header" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<header>")).type); }
test "tag:23 footer" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<footer>")).type); }
test "tag:24 main" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<main>")).type); }
test "tag:25 section" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<section>")).type); }
test "tag:26 article" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<article>")).type); }
test "tag:27 aside" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<aside>")).type); }
test "tag:28 textarea" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<textarea>")).type); }
test "tag:29 select" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<select>")).type); }
test "tag:30 option" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<option>")).type); }
test "tag:31 thead" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<thead>")).type); }
test "tag:32 tbody" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<tbody>")).type); }
test "tag:33 strong" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<strong>")).type); }
test "tag:34 em" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<em>")).type); }
test "tag:35 pre" { try std.testing.expectEqual(TokenType.start_tag, (try firstToken("<pre>")).type); }

// ============================================================================
// 3. Case Normalization (36-42)
// ============================================================================

test "case:36 DIV" {
    const t = try firstToken("<DIV>");
    try std.testing.expectEqualStrings("div", t.tag_name.?);
}
test "case:37 sPaN" {
    const t = try firstToken("<sPaN>");
    try std.testing.expectEqualStrings("span", t.tag_name.?);
}
test "case:38 HTML" {
    const t = try firstToken("<HTML>");
    try std.testing.expectEqualStrings("html", t.tag_name.?);
}
test "case:39 BODY" {
    const t = try firstToken("<BODY>");
    try std.testing.expectEqualStrings("body", t.tag_name.?);
}
test "case:40 SCRIPT" {
    const t = try firstToken("<SCRIPT>");
    try std.testing.expectEqualStrings("script", t.tag_name.?);
}
test "case:41 STYLE" {
    const t = try firstToken("<STYLE>");
    try std.testing.expectEqualStrings("style", t.tag_name.?);
}
test "case:42 P" {
    const t = try firstToken("<P>");
    try std.testing.expectEqualStrings("p", t.tag_name.?);
}

// ============================================================================
// 4. End Tags (43-48)
// ============================================================================

test "end:43 div" {
    const t = try firstToken("</div>");
    try std.testing.expectEqual(TokenType.end_tag, t.type);
    try std.testing.expectEqualStrings("div", t.tag_name.?);
}
test "end:44 span" {
    try std.testing.expectEqual(TokenType.end_tag, (try firstToken("</span>")).type);
}
test "end:45 p" {
    try std.testing.expectEqual(TokenType.end_tag, (try firstToken("</p>")).type);
}
test "end:46 html" {
    try std.testing.expectEqual(TokenType.end_tag, (try firstToken("</html>")).type);
}
test "end:47 body" {
    try std.testing.expectEqual(TokenType.end_tag, (try firstToken("</body>")).type);
}
test "end:48 script" {
    try std.testing.expectEqual(TokenType.end_tag, (try firstToken("</script>")).type);
}

// ============================================================================
// 5. Self-Closing Tags (49-53)
// ============================================================================

test "self:49 br" {
    const t = try firstToken("<br/>");
    try std.testing.expect(t.self_closing);
    try std.testing.expectEqualStrings("br", t.tag_name.?);
}
test "self:50 hr" {
    try std.testing.expect((try firstToken("<hr/>")).self_closing);
}
test "self:51 img" {
    try std.testing.expect((try firstToken("<img/>")).self_closing);
}
test "self:52 input" {
    try std.testing.expect((try firstToken("<input/>")).self_closing);
}
test "self:53 meta" {
    try std.testing.expect((try firstToken("<meta/>")).self_closing);
}

// ============================================================================
// 6. Text Content (54-57)
// ============================================================================

test "text:54 plain text" {
    const t = try firstToken("Hello World");
    try std.testing.expectEqual(TokenType.character, t.type);
    try std.testing.expectEqualStrings("Hello World", t.data.?);
}
test "text:55 empty string is eof" {
    try std.testing.expectEqual(TokenType.eof, (try firstToken("")).type);
}
test "text:56 whitespace only" {
    const t = try firstToken("   \n\t  ");
    try std.testing.expectEqual(TokenType.character, t.type);
}
test "text:57 mixed content" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var tok = Tokenizer.init(arena.allocator(), "<p>Hello</p>");
    const t1 = try tok.next();
    try std.testing.expectEqual(TokenType.start_tag, t1.type);
    const t2 = try tok.next();
    try std.testing.expectEqual(TokenType.character, t2.type);
    try std.testing.expectEqualStrings("Hello", t2.data.?);
}

// ============================================================================
// 7. Attributes — Double Quoted (58-62)
// ============================================================================

test "attr:58 double quoted" {
    const t = try firstToken("<div class=\"main\">");
    try std.testing.expectEqualStrings("class", t.attributes[0].name);
    try std.testing.expectEqualStrings("main", t.attributes[0].value);
}
test "attr:59 two attrs" {
    const t = try firstToken("<div class=\"main\" id=\"app\">");
    try std.testing.expectEqual(@as(usize, 2), t.attributes.len);
}
test "attr:60 three attrs" {
    const t = try firstToken("<input type=\"text\" name=\"user\" value=\"hello\">");
    try std.testing.expectEqual(@as(usize, 3), t.attributes.len);
}
test "attr:61 empty double quoted" {
    const t = try firstToken("<div a=\"\">");
    try std.testing.expectEqualStrings("", t.attributes[0].value);
}
test "attr:62 space in double quoted" {
    const t = try firstToken("<div a=\" \">");
    try std.testing.expectEqualStrings(" ", t.attributes[0].value);
}

// ============================================================================
// 8. Attributes — Single Quoted (63-66)
// ============================================================================

test "attr:63 single quoted" {
    const t = try firstToken("<a href='http://example.com'>");
    try std.testing.expectEqualStrings("href", t.attributes[0].name);
    try std.testing.expectEqualStrings("http://example.com", t.attributes[0].value);
}
test "attr:64 empty single quoted" {
    const t = try firstToken("<div a=''>");
    try std.testing.expectEqualStrings("", t.attributes[0].value);
}
test "attr:65 single quoted special chars" {
    const t = try firstToken("<div a='<>\"'>");
    try std.testing.expect(t.attributes[0].value.len > 0);
}
test "attr:66 mixed quote styles" {
    const t = try firstToken("<div class=\"a\" id='b'>");
    try std.testing.expectEqual(@as(usize, 2), t.attributes.len);
}

// ============================================================================
// 9. Attributes — Unquoted (67-70)
// ============================================================================

test "attr:67 unquoted" {
    const t = try firstToken("<input type=text>");
    try std.testing.expectEqualStrings("type", t.attributes[0].name);
    try std.testing.expectEqualStrings("text", t.attributes[0].value);
}
test "attr:68 unquoted multiple" {
    const t = try firstToken("<div class=a id=b>");
    try std.testing.expectEqual(@as(usize, 2), t.attributes.len);
}
test "attr:69 boolean attribute" {
    const t = try firstToken("<input checked>");
    try std.testing.expectEqualStrings("checked", t.attributes[0].name);
}
test "attr:70 boolean + value attr" {
    const t = try firstToken("<div class=a id='b' title=\"c\" data-val=d checked>");
    try std.testing.expectEqual(@as(usize, 5), t.attributes.len);
}

// ============================================================================
// 10. Attributes — Entity in Value (71-73)
// ============================================================================

test "attr:71 entity in double quoted value" {
    const t = try firstToken("<a title=\"a &amp; b\">");
    try std.testing.expectEqualStrings("a & b", t.attributes[0].value);
}
test "attr:72 lt entity in value" {
    const t = try firstToken("<a title=\"&lt;div&gt;\">");
    try std.testing.expectEqualStrings("<div>", t.attributes[0].value);
}
test "attr:73 numeric entity in value" {
    const t = try firstToken("<a title=\"&#65;\">");
    try std.testing.expectEqualStrings("A", t.attributes[0].value);
}

// ============================================================================
// 11. Entities in Text (74-80)
// ============================================================================

test "entity:74 amp" {
    const t = try firstToken("&amp;");
    try std.testing.expectEqualStrings("&", t.data.?);
}
test "entity:75 lt" {
    const t = try firstToken("&lt;");
    try std.testing.expectEqualStrings("<", t.data.?);
}
test "entity:76 gt" {
    const t = try firstToken("&gt;");
    try std.testing.expectEqualStrings(">", t.data.?);
}
test "entity:77 quot" {
    const t = try firstToken("&quot;");
    try std.testing.expectEqualStrings("\"", t.data.?);
}
test "entity:78 apos" {
    const t = try firstToken("&apos;");
    try std.testing.expectEqualStrings("'", t.data.?);
}
test "entity:79 decimal numeric" {
    const t = try firstToken("&#65;");
    try std.testing.expectEqualStrings("A", t.data.?);
}
test "entity:80 hex numeric" {
    const t = try firstToken("&#x41;");
    try std.testing.expectEqualStrings("A", t.data.?);
}

// ============================================================================
// 12. Entity Edge Cases (81-84)
// ============================================================================

test "entity:81 unknown entity preserved" {
    const t = try firstToken("&unknown;");
    try std.testing.expectEqualStrings("&unknown;", t.data.?);
}
test "entity:82 combined entities" {
    const t = try firstToken("&lt;div&gt;");
    try std.testing.expectEqualStrings("<div>", t.data.?);
}
test "entity:83 all named entities combined" {
    const t = try firstToken("&amp;&lt;&gt;&quot;&apos;");
    try std.testing.expectEqualStrings("&<>\"'", t.data.?);
}
test "entity:84 numeric + named" {
    const t = try firstToken("&#65;&#x41;&amp;");
    try std.testing.expectEqualStrings("AA&", t.data.?);
}

// ============================================================================
// 13. Comments (85-88)
// ============================================================================

test "comment:85 simple" {
    try std.testing.expectEqual(TokenType.comment, (try firstToken("<!-- comment -->")).type);
}
test "comment:86 empty" {
    try std.testing.expectEqual(TokenType.comment, (try firstToken("<!---->")).type);
}
test "comment:87 dashes inside" {
    try std.testing.expectEqual(TokenType.comment, (try firstToken("<!-- -- -->")).type);
}
test "comment:88 multiline" {
    try std.testing.expectEqual(TokenType.comment, (try firstToken("<!--\n--\n-->")).type);
}

// ============================================================================
// 14. Doctypes (89-91)
// ============================================================================

test "doctype:89 html5" {
    try std.testing.expectEqual(TokenType.doctype, (try firstToken("<!DOCTYPE html>")).type);
}
test "doctype:90 lowercase" {
    try std.testing.expectEqual(TokenType.doctype, (try firstToken("<!doctype html>")).type);
}
test "doctype:91 html4 public" {
    try std.testing.expectEqual(TokenType.doctype, (try firstToken("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">")).type);
}

// ============================================================================
// 15. XSS / Malicious — No Crash (92-110)
// ============================================================================

test "xss:92 script alert" { try mustNotCrash("<script>alert(1)</script>"); }
test "xss:93 img onerror" { try mustNotCrash("<img src=x onerror=alert(1)>"); }
test "xss:94 svg onload" { try mustNotCrash("<svg/onload=alert(1)>"); }
test "xss:95 details ontoggle" { try mustNotCrash("<details open ontoggle=alert(1)>"); }
test "xss:96 javascript href" { try mustNotCrash("<a href=\"javascript:alert(1)\">"); }
test "xss:97 iframe javascript" { try mustNotCrash("<iframe src=\"javascript:alert(1)\">"); }
test "xss:98 body onload" { try mustNotCrash("<body onload=alert(1)>"); }
test "xss:99 input onfocus" { try mustNotCrash("<input autofocus onfocus=alert(1)>"); }
test "xss:100 video source onerror" { try mustNotCrash("<video><source onerror=alert(1)>"); }
test "xss:101 css expression" { try mustNotCrash("<p style=\"width: expression(alert(1));\">"); }
test "xss:102 math xlink" { try mustNotCrash("<math><maction xlink:href=\"javascript:alert(1)\">"); }
test "xss:103 form action js" { try mustNotCrash("<form action=\"javascript:alert(1)\">"); }
test "xss:104 button onfocus" { try mustNotCrash("<button onfocus=alert(1) autofocus>"); }
test "xss:105 isindex formaction" { try mustNotCrash("<isindex formaction=\"javascript:alert(1)\" type=submit>"); }
test "xss:106 object data js" { try mustNotCrash("<object data=\"javascript:alert(1)\">"); }
test "xss:107 template injection" { try mustNotCrash("<%alert(1)%>"); }
test "xss:108 xml processing" { try mustNotCrash("<?alert(1)?>"); }
test "xss:109 onmouseover" { try mustNotCrash("<a onmouseover=\"alert(1)\">XSS</a>"); }
test "xss:110 base href js" { try mustNotCrash("<base href=\"javascript:alert(1)//\">"); }

// ============================================================================
// 16. Obfuscated / Evasion (111-118)
// ============================================================================

test "obfusc:111 null in tag" { try mustNotCrash("<\x00script>alert(1)</script>"); }
test "obfusc:112 null mid tag" { try mustNotCrash("<scr\x00ipt>alert(1)</script>"); }
test "obfusc:113 spaces in tag" { try mustNotCrash("<s c r i p t>alert(1)</script>"); }
test "obfusc:114 vertical tab" { try mustNotCrash("<script\x0b>alert(1)</script>"); }
test "obfusc:115 form feed" { try mustNotCrash("<script\x0c>alert(1)</script>"); }
test "obfusc:116 slash in tag" { try mustNotCrash("<script/x>alert(1)</script>"); }
test "obfusc:117 double encoding" { try mustNotCrash("&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"); }
test "obfusc:118 mixed null bytes" { try mustNotCrash("<div\x00class=\"a\">"); }

// ============================================================================
// 17. Attribute Quote Bypass (119-122)
// ============================================================================

test "bypass:119 dq no space" { try mustNotCrash("<div title=\"x\"onmouseover=alert(1)>"); }
test "bypass:120 sq no space" { try mustNotCrash("<div title='x'onmouseover=alert(1)>"); }
test "bypass:121 unquoted space" { try mustNotCrash("<div title=x onmouseover=alert(1)>"); }
test "bypass:122 reverse order" { try mustNotCrash("<div onmouseover=\"alert(1)\"title=x>"); }

// ============================================================================
// 18. Malformed Inputs (123-136)
// ============================================================================

test "malform:123 multiple lt"  { try mustNotCrash("<<<<<<");  }
test "malform:124 multiple gt"  { try mustNotCrash(">>>>>>");  }
test "malform:125 space slash"  { try mustNotCrash("< / >");   }
test "malform:126 slash class"  { try mustNotCrash("<p/class=a>"); }
test "malform:127 empty attr"   { try mustNotCrash("<div id= >"); }
test "malform:128 bad comment"  { try mustNotCrash("<!- ->");   }
test "malform:129 short comment" { try mustNotCrash("<!--->");  }
test "malform:130 unclosed comment" { try mustNotCrash("<!--"); }
test "malform:131 bare doctype" { try mustNotCrash("<!DOCTYPE"); }
test "malform:132 doctype space" { try mustNotCrash("<!DOCTYPE >"); }
test "malform:133 lt amp"       { try mustNotCrash("<&");       }
test "malform:134 quotes"       { try mustNotCrash("<' ' \" \""); }
test "malform:135 whitespace tag" { try mustNotCrash("<div\t\n \r>"); }
test "malform:136 control chars" { try mustNotCrash("<a\x01\x02\x03>"); }

// ============================================================================
// 19. Stress Tests (137-140)
// ============================================================================

test "stress:137 1000 nested divs" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var input_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buf.deinit(std.heap.page_allocator);
    for (0..1000) |_| try input_buf.appendSlice(std.heap.page_allocator, "<div>");
    var tok = Tokenizer.init(arena.allocator(), input_buf.items);
    var count: usize = 0;
    while (true) { const t = try tok.next(); if (t.type == .eof) break; count += 1; }
    try std.testing.expect(count == 1000);
}

test "stress:138 100kb attribute value" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const long_val = try arena.allocator().alloc(u8, 100000);
    @memset(long_val, 'A');
    const input = try std.fmt.allocPrint(arena.allocator(), "<div title=\"{s}\">", .{long_val});
    var tok = Tokenizer.init(arena.allocator(), input);
    const t = try tok.next();
    try std.testing.expect(t.attributes[0].value.len > 0);
}

test "stress:139 20 attributes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var input_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer input_buf.deinit(arena.allocator());
    try input_buf.appendSlice(arena.allocator(), "<div");
    for (0..20) |i| try input_buf.writer(arena.allocator()).print(" a{d}=\"v{d}\"", .{ i, i });
    try input_buf.append(arena.allocator(), '>');
    var tok = Tokenizer.init(arena.allocator(), input_buf.items);
    const t = try tok.next();
    try std.testing.expectEqual(@as(usize, 20), t.attributes.len);
}

test "stress:140 long tag name" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const long_name = try arena.allocator().alloc(u8, 5000);
    @memset(long_name, 'a');
    const input = try std.fmt.allocPrint(arena.allocator(), "<{s}>", .{long_name});
    var tok = Tokenizer.init(arena.allocator(), input);
    const t = try tok.next();
    try std.testing.expectEqual(TokenType.start_tag, t.type);
}

// ============================================================================
// 20. Fuzzing (141-150)
// ============================================================================

test "fuzz:141 seed_0" { try fuzzRun(0); }
test "fuzz:142 seed_1" { try fuzzRun(1); }
test "fuzz:143 seed_42" { try fuzzRun(42); }
test "fuzz:144 seed_100" { try fuzzRun(100); }
test "fuzz:145 seed_255" { try fuzzRun(255); }
test "fuzz:146 seed_1000" { try fuzzRun(1000); }
test "fuzz:147 seed_9999" { try fuzzRun(9999); }
test "fuzz:148 seed_12345" { try fuzzRun(12345); }
test "fuzz:149 seed_65535" { try fuzzRun(65535); }
test "fuzz:150 seed_99999" { try fuzzRun(99999); }

fn fuzzRun(seed: u64) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    for (0..10) |_| {
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
