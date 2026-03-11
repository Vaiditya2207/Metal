const std = @import("std");
const dom = @import("src/dom/mod.zig");
pub fn main() !void {
    var alloc = std.heap.page_allocator;
    const input = try std.fs.cwd().readFileAlloc(alloc, "tests/fidelity/google_snapshot.html", ~@as(usize, 0));
    var tok = dom.tokenizer.Tokenizer.init(alloc, input);
    var count: usize = 0;
    while (true) {
        const t = tok.next() catch |err| {
            std.debug.print("CRASH at count {d} pos {d}: {any}\n", .{count, tok.pos, err});
            std.debug.print("Surrounding text: {s}\n", .{input[tok.pos - 50 .. tok.pos + 50]});
            break;
        };
        count += 1;
        if (t.type == .eof) {
            std.debug.print("EOF at count {d}\n", .{count});
            break;
        }
    }
}
