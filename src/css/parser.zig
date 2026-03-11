const std = @import("std");
const css_tokenizer = @import("tokenizer.zig");
const selector_mod = @import("selector.zig");
const config = @import("../config.zig");

pub const Declaration = struct {
    property: []const u8,
    value: []const u8,
    is_important: bool = false,
};

pub const Rule = struct {
    selectors: []const selector_mod.Selector,
    declarations: []const Declaration,
};

pub const Stylesheet = struct {
    rules: []const Rule,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokenizer: css_tokenizer.CssTokenizer,
    current: css_tokenizer.CssToken,
    max_rules: u32,
    max_declarations: u16,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !Parser {
        const cfg = config.getConfig();
        var p = Parser{
            .allocator = allocator,
            .tokenizer = css_tokenizer.CssTokenizer.init(allocator, input),
            .current = .{ .type = .eof },
            .max_rules = cfg.css.max_rules_per_stylesheet,
            .max_declarations = cfg.css.max_declarations_per_rule,
        };
        p.current = try p.tokenizer.next();
        return p;
    }

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Stylesheet {
        var p = try Parser.init(allocator, input);
        var rules: std.ArrayListUnmanaged(Rule) = .empty;

        while (p.current.type != .eof and rules.items.len < p.max_rules) {
            if (p.current.type == .whitespace) {
                p.current = try p.tokenizer.next();
                continue;
            }
            if (p.current.type == .at_keyword) {
                if (std.mem.eql(u8, p.current.value, "media")) {
                    p.current = try p.tokenizer.next();
                    var match_media = true;
                    // Check conditions until opening brace
                    while (p.current.type != .left_brace and p.current.type != .eof) {
                        if (p.current.type == .ident) {
                            if (std.mem.eql(u8, p.current.value, "print")) {
                                match_media = false;
                            }
                        } else if (p.current.type == .left_paren) {
                            // Basic support for (max-width: XXXpx) and (min-width: XXXpx)
                            p.current = try p.tokenizer.next();
                            if (p.current.type == .ident) {
                                const prop = p.current.value;
                                p.current = try p.tokenizer.next();
                                if (p.current.type == .colon) {
                                    p.current = try p.tokenizer.next();
                                    if (p.current.type == .dimension) {
                                        const val = p.current.number_value;
                                        if (std.mem.eql(u8, prop, "max-width")) {
                                            if (val < 1200) match_media = false;
                                        } else if (std.mem.eql(u8, prop, "min-width")) {
                                            if (val > 1200) match_media = false;
                                        }
                                    }
                                }
                            }
                            while (p.current.type != .right_paren and p.current.type != .eof) {
                                p.current = try p.tokenizer.next();
                            }
                        }
                        if (p.current.type != .eof) p.current = try p.tokenizer.next();
                    }
                    if (p.current.type == .left_brace) {
                        p.current = try p.tokenizer.next();
                    }
                    
                    if (match_media) {
                        // Parse the nested rules and flatten them into the main rules list
                        while (p.current.type != .right_brace and p.current.type != .eof) {
                            if (p.current.type == .whitespace) {
                                p.current = try p.tokenizer.next();
                                continue;
                            }
                            const rule = p.parseRule() catch |err| {
                                if (err == error.OutOfMemory) return err;
                                // Skip to next '}' (which closes the failed nested rule)
                                while (p.current.type != .right_brace and p.current.type != .eof) {
                                    p.current = try p.tokenizer.next();
                                }
                                if (p.current.type == .right_brace) p.current = try p.tokenizer.next();
                                continue;
                            };
                            try rules.append(allocator, rule);
                        }
                        if (p.current.type == .right_brace) {
                            p.current = try p.tokenizer.next();
                        }
                        continue;
                    } else {
                        // Skip the entire block
                        var nest_level: usize = 1;
                        while (p.current.type != .eof and nest_level > 0) {
                            if (p.current.type == .left_brace) nest_level += 1;
                            if (p.current.type == .right_brace) nest_level -= 1;
                            p.current = try p.tokenizer.next();
                        }
                        continue;
                    }
                } else {
                    // Skip other at-rules
                    var nest_level: usize = 0;
                    if (p.current.type == .left_brace) nest_level += 1;
                    
                    while (p.current.type != .eof) {
                        if (p.current.type == .left_brace) nest_level += 1;
                        if (p.current.type == .right_brace) {
                            if (nest_level > 0) nest_level -= 1;
                            if (nest_level == 0) {
                                p.current = try p.tokenizer.next();
                                break;
                            }
                        }
                        if (nest_level == 0 and p.current.type == .semicolon) {
                            p.current = try p.tokenizer.next();
                            break;
                        }
                        p.current = try p.tokenizer.next();
                    }
                    continue;
                }
            }

            const rule = p.parseRule() catch |err| {
                if (err == error.OutOfMemory) return err;
                // Skip to next '}'
                while (p.current.type != .right_brace and p.current.type != .eof) {
                    p.current = try p.tokenizer.next();
                }
                if (p.current.type == .right_brace) p.current = try p.tokenizer.next();
                continue;
            };
            try rules.append(allocator, rule);
        }

        return Stylesheet{ .rules = try rules.toOwnedSlice(allocator) };
    }

    fn parseRule(self: *Parser) !Rule {
        var selectors: std.ArrayListUnmanaged(selector_mod.Selector) = .empty;
        var current_selector_str: std.ArrayListUnmanaged(u8) = .empty;
        defer current_selector_str.deinit(self.allocator);

        while (self.current.type != .left_brace and self.current.type != .eof) {
            if (self.current.type == .comma) {
                const sel = try selector_mod.Selector.parse(self.allocator, current_selector_str.items);
                if (sel.components.len > 0) try selectors.append(self.allocator, sel);
                current_selector_str.clearRetainingCapacity();
            } else {
                if (self.current.type == .hash) {
                    try current_selector_str.append(self.allocator, '#');
                }
                try current_selector_str.appendSlice(self.allocator, self.current.value);
            }
            self.current = try self.tokenizer.next();
        }

        if (current_selector_str.items.len > 0) {
            const sel = try selector_mod.Selector.parse(self.allocator, current_selector_str.items);
            if (sel.components.len > 0) try selectors.append(self.allocator, sel);
        }

        if (self.current.type == .left_brace) {
            self.current = try self.tokenizer.next();
        }

        var declarations: std.ArrayListUnmanaged(Declaration) = .empty;
        while (self.current.type != .right_brace and self.current.type != .eof and declarations.items.len < self.max_declarations) {
            if (self.current.type == .whitespace or self.current.type == .semicolon) {
                self.current = try self.tokenizer.next();
                continue;
            }

            const decl = self.parseDeclaration() catch |err| {
                if (err == error.OutOfMemory) return err;
                // Skip to next ';' or '}'
                while (self.current.type != .semicolon and self.current.type != .right_brace and self.current.type != .eof) {
                    self.current = try self.tokenizer.next();
                }
                if (self.current.type == .semicolon) self.current = try self.tokenizer.next();
                continue;
            };
            try declarations.append(self.allocator, decl);
        }

        if (self.current.type == .right_brace) {
            self.current = try self.tokenizer.next();
        }

        return Rule{
            .selectors = try selectors.toOwnedSlice(self.allocator),
            .declarations = try declarations.toOwnedSlice(self.allocator),
        };
    }

    fn parseDeclaration(self: *Parser) !Declaration {
        var property: std.ArrayListUnmanaged(u8) = .empty;
        defer property.deinit(self.allocator);
        while (self.current.type != .colon and self.current.type != .eof and self.current.type != .semicolon) {
            try property.appendSlice(self.allocator, self.current.value);
            self.current = try self.tokenizer.next();
        }

        if (self.current.type == .colon) {
            self.current = try self.tokenizer.next();
        }

        var value: std.ArrayListUnmanaged(u8) = .empty;
        defer value.deinit(self.allocator);
        while (self.current.type != .semicolon and self.current.type != .right_brace and self.current.type != .eof) {
            if (self.current.type == .whitespace and value.items.len == 0) {
                self.current = try self.tokenizer.next();
                continue;
            }
            if (self.current.type == .dimension or self.current.type == .number or self.current.type == .percentage) {
                var num_buf: [64]u8 = undefined;
                const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{self.current.number_value}) catch "";
                try value.appendSlice(self.allocator, num_str);
                if (self.current.type == .dimension) {
                    try value.appendSlice(self.allocator, self.current.unit);
                } else if (self.current.type == .percentage) {
                    try value.append(self.allocator, '%');
                }
            } else {
                try value.appendSlice(self.allocator, self.current.value);
            }
            self.current = try self.tokenizer.next();
        }

        const raw_value = std.mem.trim(u8, value.items, " \t\n\r");
        var is_important = false;
        var final_value = raw_value;
        if (std.mem.endsWith(u8, raw_value, "important")) {
            const without_important = std.mem.trimRight(u8, raw_value[0 .. raw_value.len - 9], " \t\n\r");
            if (std.mem.endsWith(u8, without_important, "!")) {
                is_important = true;
                final_value = std.mem.trimRight(u8, without_important[0 .. without_important.len - 1], " \t\n\r");
            }
        }

        return Declaration{
            .property = try self.allocator.dupe(u8, std.mem.trim(u8, property.items, " \t\n\r")),
            .value = try self.allocator.dupe(u8, final_value),
            .is_important = is_important,
        };
    }

    pub fn parseInlineStyle(allocator: std.mem.Allocator, style_attr: []const u8) ![]const Declaration {
        var declarations: std.ArrayListUnmanaged(Declaration) = .empty;
        var iter = std.mem.splitScalar(u8, style_attr, ';');
        while (iter.next()) |part| {
            var kv_iter = std.mem.splitScalar(u8, part, ':');
            const k = std.mem.trim(u8, kv_iter.next() orelse continue, " \t\n\r");
            const v = std.mem.trim(u8, kv_iter.next() orelse continue, " \t\n\r");
            if (k.len > 0 and v.len > 0) {
                var is_important = false;
                var final_value = v;
                if (std.mem.endsWith(u8, v, "important")) {
                    const without_important = std.mem.trimRight(u8, v[0 .. v.len - 9], " \t\n\r");
                    if (std.mem.endsWith(u8, without_important, "!")) {
                        is_important = true;
                        final_value = std.mem.trimRight(u8, without_important[0 .. without_important.len - 1], " \t\n\r");
                    }
                }
                try declarations.append(allocator, .{
                    .property = try allocator.dupe(u8, k),
                    .value = try allocator.dupe(u8, final_value),
                    .is_important = is_important,
                });
            }
        }
        return try declarations.toOwnedSlice(allocator);
    }
};
