const std = @import("std");
const css = @import("../src/css/mod.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ua_sheet = try css.Parser.parse(allocator, css.ua.default_css);
    std.debug.print("Parsed {d} rules\n", .{ua_sheet.rules.len});
    
    for (ua_sheet.rules, 0..) |rule, i| {
        std.debug.print("Rule {d}:\n", .{i});
        for (rule.selectors) |sel| {
            std.debug.print("  Selector: ", .{});
            for (sel.components) |comp| {
                if (comp.part.tag) |t| std.debug.print("{s} ", .{t});
            }
            std.debug.print("\n", .{});
        }
    }
}
