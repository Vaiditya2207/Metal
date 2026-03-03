const std = @import("std");

pub const DecodeResult = struct {
    bytes: [4]u8,
    len: u3,

    pub fn slice(self: *const DecodeResult) []const u8 {
        return self.bytes[0..self.len];
    }
};

const named_entities = std.StaticStringMap(u21).initComptime(.{
    .{ "amp", '&' },
    .{ "lt", '<' },
    .{ "gt", '>' },
    .{ "quot", '"' },
    .{ "apos", '\'' },
    .{ "nbsp", 160 },
    .{ "copy", 169 },
    .{ "reg", 174 },
    .{ "trade", 8482 },
    .{ "mdash", 8212 },
    .{ "ndash", 8211 },
    .{ "hellip", 8230 },
    .{ "euro", 8364 },
    .{ "laquo", 171 },
    .{ "raquo", 187 },
    .{ "lsquo", 8216 },
    .{ "rsquo", 8217 },
    .{ "ldquo", 8220 },
    .{ "rdquo", 8221 },
    .{ "bull", 8226 },
    .{ "middot", 183 },
    .{ "deg", 176 },
    .{ "plusmn", 177 },
    .{ "times", 215 },
    .{ "divide", 247 },
    .{ "sect", 167 },
    .{ "para", 182 },
    .{ "pound", 163 },
    .{ "yen", 165 },
    .{ "cent", 162 },
    .{ "sup1", 185 },
    .{ "sup2", 178 },
    .{ "sup3", 179 },
    .{ "frac14", 188 },
    .{ "frac12", 189 },
    .{ "frac34", 190 },
});

/// Decode an HTML character reference (entity).
/// Given a position right at '&', reads until ';' and returns the decoded bytes.
/// If the entity is unknown, resets pos to start + 1 and returns '&' for literal output.
pub fn decode(input: []const u8, pos: *usize) DecodeResult {
    const start = pos.*;
    if (pos.* >= input.len or input[pos.*] != '&') return single('&');
    pos.* += 1; // skip '&'

    var buf: [32]u8 = undefined;
    var len: usize = 0;

    while (pos.* < input.len and len < 31) {
        const c = input[pos.*];
        pos.* += 1;
        if (c == ';') {
            const entity_name = buf[0..len];

            if (named_entities.get(entity_name)) |codepoint| {
                return encodeUtf8(codepoint);
            }

            if (len > 1 and entity_name[0] == '#') {
                const codepoint = if (entity_name[1] == 'x' or entity_name[1] == 'X')
                    std.fmt.parseInt(u21, entity_name[2..], 16) catch {
                        pos.* = start + 1;
                        return single('&');
                    }
                else
                    std.fmt.parseInt(u21, entity_name[1..], 10) catch {
                        pos.* = start + 1;
                        return single('&');
                    };
                return encodeUtf8(codepoint);
            }

            // Unknown named entity — reset and return literal &
            pos.* = start + 1;
            return single('&');
        }
        buf[len] = c;
        len += 1;
    }

    pos.* = start + 1;
    return single('&');
}

fn single(c: u8) DecodeResult {
    var res = DecodeResult{ .bytes = .{ 0, 0, 0, 0 }, .len = 1 };
    res.bytes[0] = c;
    return res;
}

fn encodeUtf8(codepoint: u21) DecodeResult {
    var result = DecodeResult{ .bytes = .{ 0, 0, 0, 0 }, .len = 0 };
    if (codepoint <= 0x7F) {
        result.bytes[0] = @intCast(codepoint);
        result.len = 1;
    } else if (codepoint <= 0x7FF) {
        result.bytes[0] = @intCast(0xC0 | (codepoint >> 6));
        result.bytes[1] = @intCast(0x80 | (codepoint & 0x3F));
        result.len = 2;
    } else if (codepoint <= 0xFFFF) {
        result.bytes[0] = @intCast(0xE0 | (codepoint >> 12));
        result.bytes[1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        result.bytes[2] = @intCast(0x80 | (codepoint & 0x3F));
        result.len = 3;
    } else if (codepoint <= 0x10FFFF) {
        result.bytes[0] = @intCast(0xF0 | (codepoint >> 18));
        result.bytes[1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
        result.bytes[2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        result.bytes[3] = @intCast(0x80 | (codepoint & 0x3F));
        result.len = 4;
    } else {
        return single('&');
    }
    return result;
}
