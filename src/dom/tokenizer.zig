const std = @import("std");
const config = @import("../config.zig");
const entity = @import("entity.zig");
const states = @import("tokenizer_states.zig");
const attr_states = @import("tokenizer_attr_states.zig");

/// HTML Token types emitted by the tokenizer.
pub const TokenType = enum {
    start_tag,
    end_tag,
    character,
    comment,
    doctype,
    eof,
};

/// A single HTML attribute (name = value).
pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

/// Token produced by the tokenizer.
pub const Token = struct {
    type: TokenType,
    tag_name: ?[]const u8 = null,
    self_closing: bool = false,
    attributes: []const Attribute = &[_]Attribute{},
    data: ?[]const u8 = null,
};

/// Tokenizer states following the HTML5 spec.
pub const State = enum {
    data,
    tag_open,
    end_tag_open,
    tag_name,
    before_attribute_name,
    attribute_name,
    after_attribute_name,
    before_attribute_value,
    attribute_value_double_quoted,
    attribute_value_single_quoted,
    attribute_value_unquoted,
    self_closing_start_tag,
    bogus_comment,
    markup_declaration_open,
    rawtext,
};

/// HTML5-compliant tokenizer with configurable security limits.
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    state: State,
    allocator: std.mem.Allocator,
    is_end_tag: bool,

    tag_name_buf: std.ArrayListUnmanaged(u8),
    attr_name_buf: std.ArrayListUnmanaged(u8),
    attr_value_buf: std.ArrayListUnmanaged(u8),
    attr_list: std.ArrayListUnmanaged(Attribute),
    text_buf: std.ArrayListUnmanaged(u8),
    self_closing: bool,
    rawtext_end_tag: ?[]const u8 = null,

    max_tag_name_len: u16,
    max_attr_name_len: u16,
    max_attr_value_len: u32,
    max_attrs_per_element: u16,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Tokenizer {
        const cfg = config.getConfig();
        return .{
            .input = input,
            .pos = 0,
            .state = .data,
            .allocator = allocator,
            .is_end_tag = false,
            .tag_name_buf = .empty,
            .attr_name_buf = .empty,
            .attr_value_buf = .empty,
            .attr_list = .empty,
            .text_buf = .empty,
            .self_closing = false,
            .max_tag_name_len = cfg.parser.max_tag_name_length,
            .max_attr_name_len = cfg.parser.max_attribute_name_length,
            .max_attr_value_len = cfg.parser.max_attribute_value_length,
            .max_attrs_per_element = cfg.parser.max_attributes_per_element,
        };
    }

    pub fn consume(self: *Tokenizer) ?u8 {
        if (self.pos >= self.input.len) return null;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    pub fn peek(self: *Tokenizer) ?u8 {
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    pub fn resetTagState(self: *Tokenizer) void {
        self.tag_name_buf.clearRetainingCapacity();
        self.attr_list.clearRetainingCapacity();
        self.self_closing = false;
        self.is_end_tag = false;
    }

    pub fn resetAttrState(self: *Tokenizer) void {
        self.attr_name_buf.clearRetainingCapacity();
        self.attr_value_buf.clearRetainingCapacity();
    }

    pub fn finalizeAttribute(self: *Tokenizer) !void {
        if (self.attr_name_buf.items.len == 0) return;
        if (self.attr_list.items.len >= self.max_attrs_per_element) return;
        const name = try self.allocator.dupe(u8, self.attr_name_buf.items);
        const value = try self.allocator.dupe(u8, self.attr_value_buf.items);
        try self.attr_list.append(self.allocator, .{ .name = name, .value = value });
        self.resetAttrState();
    }

    pub fn flushText(self: *Tokenizer) ?Token {
        if (self.text_buf.items.len == 0) return null;
        const data = self.allocator.dupe(u8, self.text_buf.items) catch return null;
        self.text_buf.clearRetainingCapacity();
        return Token{ .type = .character, .data = data };
    }

    pub fn buildTagToken(self: *Tokenizer) !Token {
        const name = try self.allocator.dupe(u8, self.tag_name_buf.items);
        const attrs = try self.allocator.dupe(Attribute, self.attr_list.items);
        const tok = Token{
            .type = if (self.is_end_tag) .end_tag else .start_tag,
            .tag_name = name,
            .self_closing = self.self_closing,
            .attributes = attrs,
        };

        if (!self.is_end_tag and name.len > 0) {
            if (std.mem.eql(u8, name, "script") or std.mem.eql(u8, name, "style")) {
                self.state = .rawtext;
                self.rawtext_end_tag = name;
            }
        }
        return tok;
    }

    pub fn decodeEntity(self: *Tokenizer) entity.DecodeResult {
        return entity.decode(self.input, &self.pos);
    }

    pub fn appendToTagName(self: *Tokenizer, c: u8) !void {
        if (self.tag_name_buf.items.len < self.max_tag_name_len)
            try self.tag_name_buf.append(self.allocator, std.ascii.toLower(c));
    }

    pub fn appendToAttrName(self: *Tokenizer, c: u8) !void {
        if (self.attr_name_buf.items.len < self.max_attr_name_len)
            try self.attr_name_buf.append(self.allocator, std.ascii.toLower(c));
    }

    pub fn appendToAttrValue(self: *Tokenizer, c: u8) !void {
        if (self.attr_value_buf.items.len < self.max_attr_value_len)
            try self.attr_value_buf.append(self.allocator, c);
    }

    pub fn isWhitespace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }

    pub fn next(self: *Tokenizer) !Token {
        while (true) {
            const result: ?Token = try switch (self.state) {
                .data => states.handleData(self),
                .tag_open => states.handleTagOpen(self),
                .end_tag_open => states.handleEndTagOpen(self),
                .tag_name => states.handleTagName(self),
                .before_attribute_name => attr_states.handleBeforeAttributeName(self),
                .attribute_name => attr_states.handleAttributeName(self),
                .after_attribute_name => attr_states.handleAfterAttributeName(self),
                .before_attribute_value => attr_states.handleBeforeAttributeValue(self),
                .attribute_value_double_quoted => attr_states.handleAttributeValueDoubleQuoted(self),
                .attribute_value_single_quoted => attr_states.handleAttributeValueSingleQuoted(self),
                .attribute_value_unquoted => attr_states.handleAttributeValueUnquoted(self),
                .self_closing_start_tag => states.handleSelfClosingStartTag(self),
                .bogus_comment => states.handleBogusComment(self),
                .markup_declaration_open => states.handleMarkupDeclarationOpen(self),
                .rawtext => states.handleRawtext(self),
            };
            if (result) |token| return token;
        }
    }
};
