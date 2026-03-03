/// DOM module barrel file.
/// Import this file to access all public DOM types.
pub const tag = @import("tag.zig");
pub const node = @import("node.zig");
pub const document = @import("document.zig");
pub const entity = @import("entity.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const builder = @import("builder.zig");

// Re-export commonly used types at the top level
pub const TagName = tag.TagName;
pub const Node = node.Node;
pub const NodeType = node.NodeType;
pub const DomAttribute = node.DomAttribute;
pub const Document = document.Document;
pub const Limits = document.Limits;
pub const Tokenizer = tokenizer.Tokenizer;
pub const TokenType = tokenizer.TokenType;
pub const Token = tokenizer.Token;
pub const Attribute = tokenizer.Attribute;
pub const parseHTML = builder.parseHTML;
