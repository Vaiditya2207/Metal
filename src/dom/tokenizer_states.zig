const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

pub fn handleData(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        if (tok.flushText()) |t| return t;
        return Token{ .type = .eof };
    };
    if (c == '<') {
        if (tok.flushText()) |t| {
            tok.state = .tag_open;
            return t;
        }
        tok.state = .tag_open;
    } else if (c == '&') {
        tok.pos -= 1;
        const decoded = tok.decodeEntity();
        try tok.text_buf.appendSlice(tok.allocator, decoded.slice());
    } else {
        try tok.text_buf.append(tok.allocator, c);
    }
    return null;
}

pub fn handleTagOpen(tok: *Tokenizer) !?Token {
    tok.resetTagState();
    const c = tok.consume() orelse {
        try tok.text_buf.append(tok.allocator, '<');
        tok.state = .data;
        return null;
    };
    if (c == '/') {
        tok.is_end_tag = true;
        tok.state = .end_tag_open;
    } else if (c == '!') {
        tok.state = .markup_declaration_open;
    } else if (std.ascii.isAlphabetic(c)) {
        try tok.appendToTagName(c);
        tok.state = .tag_name;
    } else {
        try tok.text_buf.append(tok.allocator, '<');
        try tok.text_buf.append(tok.allocator, c);
        tok.state = .data;
    }
    return null;
}

pub fn handleEndTagOpen(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        try tok.text_buf.appendSlice(tok.allocator, "</");
        tok.state = .data;
        return null;
    };
    if (std.ascii.isAlphabetic(c)) {
        try tok.appendToTagName(c);
        tok.state = .tag_name;
    } else {
        tok.state = .bogus_comment;
    }
    return null;
}

pub fn handleTagName(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (Tokenizer.isWhitespace(c)) {
        tok.state = .before_attribute_name;
    } else if (c == '/') {
        tok.state = .self_closing_start_tag;
    } else if (c == '>') {
        tok.state = .data;
        return try tok.buildTagToken();
    } else {
        try tok.appendToTagName(c);
    }
    return null;
}

pub fn handleSelfClosingStartTag(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (c == '>') {
        tok.self_closing = true;
        tok.state = .data;
        return try tok.buildTagToken();
    } else {
        tok.state = .before_attribute_name;
    }
    return null;
}

pub fn handleBogusComment(tok: *Tokenizer) !?Token {
    const c = tok.consume() orelse {
        tok.state = .data;
        return null;
    };
    if (c == '>') tok.state = .data;
    return null;
}

pub fn handleMarkupDeclarationOpen(tok: *Tokenizer) !?Token {
    if (tok.pos + 1 < tok.input.len and tok.input[tok.pos] == '-' and tok.input[tok.pos + 1] == '-') {
        tok.pos += 2;
        while (tok.pos + 2 < tok.input.len) {
            if (tok.input[tok.pos] == '-' and tok.input[tok.pos + 1] == '-' and tok.input[tok.pos + 2] == '>') {
                tok.pos += 3;
                break;
            }
            tok.pos += 1;
        } else {
            tok.pos = tok.input.len;
        }
        tok.state = .data;
        return Token{ .type = .comment };
    } else {
        const remaining = tok.input[tok.pos..];
        if (remaining.len >= 7 and std.ascii.eqlIgnoreCase(remaining[0..7], "DOCTYPE")) {
            while (tok.pos < tok.input.len and tok.input[tok.pos] != '>') tok.pos += 1;
            if (tok.pos < tok.input.len) tok.pos += 1;
            tok.state = .data;
            return Token{ .type = .doctype };
        } else {
            tok.state = .bogus_comment;
        }
    }
    return null;
}

pub fn handleRawtext(tok: *Tokenizer) !?Token {
    const end_tag = tok.rawtext_end_tag orelse {
        tok.state = .data;
        return null;
    };
    const start_pos = tok.pos;
    while (tok.pos < tok.input.len) {
        if (tok.input[tok.pos] == '<' and tok.pos + 1 < tok.input.len and tok.input[tok.pos + 1] == '/') {
            const after_slash = tok.pos + 2;
            if (after_slash + end_tag.len <= tok.input.len) {
                if (std.ascii.eqlIgnoreCase(tok.input[after_slash .. after_slash + end_tag.len], end_tag)) {
                    const after_name = after_slash + end_tag.len;
                    if (after_name < tok.input.len and tok.input[after_name] == '>') {
                        if (tok.pos > start_pos) {
                            const text = try tok.allocator.dupe(u8, tok.input[start_pos..tok.pos]);
                            tok.rawtext_end_tag = null;
                            tok.state = .data;
                            return Token{ .type = .character, .data = text };
                        }
                        tok.rawtext_end_tag = null;
                        tok.state = .data;
                        return null; // Process the end tag in .data state
                    }
                }
            }
        }
        tok.pos += 1;
    }
    if (tok.pos == tok.input.len and tok.pos > start_pos) {
        const text = try tok.allocator.dupe(u8, tok.input[start_pos..tok.pos]);
        tok.rawtext_end_tag = null;
        tok.state = .data;
        return Token{ .type = .character, .data = text };
    }
    tok.rawtext_end_tag = null;
    tok.state = .data;
    return null;
}
