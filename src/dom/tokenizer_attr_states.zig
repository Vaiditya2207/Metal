const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub fn handleBeforeAttributeName(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (Tokenizer.isWhitespace(c)) {
        return null;
    } else if (c == '/') {
        tok.state = .self_closing_start_tag;
    } else if (c == '>') {
        tok.state = .data;
        return try tok.buildTagToken();
    } else {
        tok.resetAttrState();
        try tok.appendToAttrName(c);
        tok.state = .attribute_name;
    }
    return null;
}

pub fn handleAttributeName(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (c == '=') {
        tok.state = .before_attribute_value;
    } else if (Tokenizer.isWhitespace(c)) {
        tok.state = .after_attribute_name;
    } else if (c == '/' or c == '>') {
        try tok.finalizeAttribute();
        if (c == '/') {
            tok.state = .self_closing_start_tag;
        } else {
            tok.state = .data;
            return try tok.buildTagToken();
        }
    } else {
        try tok.appendToAttrName(c);
    }
    return null;
}

pub fn handleAfterAttributeName(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (Tokenizer.isWhitespace(c)) {
        return null;
    } else if (c == '=') {
        tok.state = .before_attribute_value;
    } else if (c == '/' or c == '>') {
        try tok.finalizeAttribute();
        if (c == '/') {
            tok.state = .self_closing_start_tag;
        } else {
            tok.state = .data;
            return try tok.buildTagToken();
        }
    } else {
        try tok.finalizeAttribute();
        tok.resetAttrState();
        try tok.appendToAttrName(c);
        tok.state = .attribute_name;
    }
    return null;
}

pub fn handleBeforeAttributeValue(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (Tokenizer.isWhitespace(c)) {
        return null;
    } else if (c == '"') {
        tok.state = .attribute_value_double_quoted;
    } else if (c == '\'') {
        tok.state = .attribute_value_single_quoted;
    } else if (c == '>') {
        try tok.finalizeAttribute();
        tok.state = .data;
        return try tok.buildTagToken();
    } else {
        try tok.appendToAttrValue(c);
        tok.state = .attribute_value_unquoted;
    }
    return null;
}

pub fn handleAttributeValueDoubleQuoted(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (c == '"') {
        try tok.finalizeAttribute();
        tok.state = .before_attribute_name;
    } else if (c == '&') {
        tok.pos -= 1;
        const decoded = tok.decodeEntity();
        try tok.attr_value_buf.appendSlice(tok.allocator, decoded.slice());
    } else {
        try tok.appendToAttrValue(c);
    }
    return null;
}

pub fn handleAttributeValueSingleQuoted(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (c == '\'') {
        try tok.finalizeAttribute();
        tok.state = .before_attribute_name;
    } else if (c == '&') {
        tok.pos -= 1;
        const decoded = tok.decodeEntity();
        try tok.attr_value_buf.appendSlice(tok.allocator, decoded.slice());
    } else {
        try tok.appendToAttrValue(c);
    }
    return null;
}

pub fn handleAttributeValueUnquoted(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        try tok.finalizeAttribute();
        tok.state = .data;
        return null;
    };
    if (Tokenizer.isWhitespace(c)) {
        try tok.finalizeAttribute();
        tok.state = .before_attribute_name;
    } else if (c == '>') {
        try tok.finalizeAttribute();
        tok.state = .data;
        return try tok.buildTagToken();
    } else if (c == '&') {
        tok.pos -= 1;
        const decoded = tok.decodeEntity();
        try tok.attr_value_buf.appendSlice(tok.allocator, decoded.slice());
    } else {
        try tok.appendToAttrValue(c);
    }
    return null;
}
