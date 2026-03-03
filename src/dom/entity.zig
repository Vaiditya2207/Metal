const std = @import("std");

/// Decode an HTML character reference (entity).
/// Given a position right after '&', reads until ';' and returns the decoded byte.
/// If the entity is unknown, resets pos to start and returns '&' for literal output.
pub fn decode(input: []const u8, pos: *usize) u8 {
    const start = pos.*;
    var buf: [32]u8 = undefined;
    var len: usize = 0;

    while (pos.* < input.len and len < 31) {
        const c = input[pos.*];
        pos.* += 1;
        if (c == ';') {
            const entity = buf[0..len];
            if (std.mem.eql(u8, entity, "amp")) return '&';
            if (std.mem.eql(u8, entity, "lt")) return '<';
            if (std.mem.eql(u8, entity, "gt")) return '>';
            if (std.mem.eql(u8, entity, "quot")) return '"';
            if (std.mem.eql(u8, entity, "apos")) return '\'';
            if (len > 1 and entity[0] == '#') {
                if (entity[1] == 'x' or entity[1] == 'X') {
                    const val = std.fmt.parseInt(u8, entity[2..], 16) catch return '&';
                    return val;
                } else {
                    const val = std.fmt.parseInt(u8, entity[1..], 10) catch return '&';
                    return val;
                }
            }
            // Unknown named entity — reset and return literal &
            pos.* = start;
            return '&';
        }
        buf[len] = c;
        len += 1;
    }

    pos.* = start;
    return '&';
}
