const std = @import("std");
const config = @import("../config.zig");

pub const CssTokenType = enum {
    ident,
    hash,
    string,
    number,
    dimension,
    percentage,
    delim,
    whitespace,
    colon,
    semicolon,
    comma,
    left_brace,
    right_brace,
    left_paren,
    right_paren,
    left_bracket,
    right_bracket,
    at_keyword,
    eof,
};

pub const CssToken = struct {
    type: CssTokenType,
    value: []const u8 = "",
    number_value: f32 = 0,
    unit: []const u8 = "",
};

pub const CssTokenizer = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize = 0,
    max_value_length: u32,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) CssTokenizer {
        const cfg = config.getConfig();
        return .{
            .allocator = allocator,
            .input = input,
            .max_value_length = cfg.css.max_value_length,
        };
    }

    fn peek(self: *CssTokenizer) u8 {
        if (self.pos >= self.input.len) return 0;
        return self.input[self.pos];
    }

    fn peekNext(self: *CssTokenizer) u8 {
        if (self.pos + 1 >= self.input.len) return 0;
        return self.input[self.pos + 1];
    }

    fn advance(self: *CssTokenizer) u8 {
        const char = self.peek();
        self.pos += 1;
        return char;
    }

    fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0C;
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isIdentStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c >= 0x80;
    }

    fn isIdent(c: u8) bool {
        return isIdentStart(c) or isDigit(c) or c == '-';
    }

    pub fn next(self: *CssTokenizer) !CssToken {
        while (true) {
            const char = self.peek();
            if (char == 0) return CssToken{ .type = .eof };

            if (char == '/' and self.peekNext() == '*') {
                self.pos += 2;
                while (self.pos < self.input.len) {
                    if (self.peek() == '*' and self.peekNext() == '/') {
                        self.pos += 2;
                        break;
                    }
                    self.pos += 1;
                }
                continue;
            }

            if (isWhitespace(char)) {
                while (isWhitespace(self.peek())) self.pos += 1;
                return CssToken{ .type = .whitespace, .value = " " };
            }

            if (char == '"' or char == '\'') {
                const quote = self.advance();
                const start = self.pos;
                while (self.pos < self.input.len and self.peek() != quote) {
                    self.pos += 1;
                }
                const value = self.input[start..@min(self.pos, self.input.len)];
                if (self.pos < self.input.len) self.pos += 1;
                return CssToken{ .type = .string, .value = value };
            }

            if (char == '#') {
                self.pos += 1;
                const start = self.pos;
                while (isIdent(self.peek())) self.pos += 1;
                return CssToken{ .type = .hash, .value = self.input[start..self.pos] };
            }

            if (char == '@') {
                self.pos += 1;
                const start = self.pos;
                while (isIdent(self.peek())) self.pos += 1;
                return CssToken{ .type = .at_keyword, .value = self.input[start..self.pos] };
            }

            const is_number_start = isDigit(char) or (char == '.' and isDigit(self.peekNext()));
            const is_negative_number = char == '-' and (isDigit(self.peekNext()) or (self.peekNext() == '.' and self.pos + 2 < self.input.len and isDigit(self.input[self.pos + 2])));

            if (is_number_start or is_negative_number) {
                const start = self.pos;
                if (char == '-') self.pos += 1;
                while (isDigit(self.peek()) or self.peek() == '.') self.pos += 1;
                const num_str = self.input[start..self.pos];
                const num = std.fmt.parseFloat(f32, num_str) catch 0;

                if (self.peek() == '%') {
                    self.pos += 1;
                    return CssToken{ .type = .percentage, .number_value = num };
                }

                if (isIdentStart(self.peek())) {
                    const unit_start = self.pos;
                    while (isIdent(self.peek())) self.pos += 1;
                    return CssToken{ .type = .dimension, .number_value = num, .unit = self.input[unit_start..self.pos] };
                }

                return CssToken{ .type = .number, .number_value = num };
            }

            if (isIdentStart(char) or (char == '-' and (isIdentStart(self.peekNext()) or self.peekNext() == '-'))) {
                const start = self.pos;
                while (isIdent(self.peek())) self.pos += 1;
                return CssToken{ .type = .ident, .value = self.input[start..self.pos] };
            }

            return self.consumeDelim();
        }
    }

    fn consumeDelim(self: *CssTokenizer) CssToken {
        const char = self.advance();
        const t: CssTokenType = switch (char) {
            ':' => .colon,
            ';' => .semicolon,
            ',' => .comma,
            '{' => .left_brace,
            '}' => .right_brace,
            '(' => .left_paren,
            ')' => .right_paren,
            '[' => .left_bracket,
            ']' => .right_bracket,
            else => .delim,
        };
        return .{ .type = t, .value = self.input[self.pos - 1 .. self.pos] };
    }
};
