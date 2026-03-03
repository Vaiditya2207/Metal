const std = @import("std");
const node_mod = @import("../dom/node.zig");
const document_mod = @import("../dom/document.zig");
const config = @import("../config.zig");

pub const Node = node_mod.Node;
pub const Document = document_mod.Document;
pub const Limits = document_mod.Limits;

/// Limits applied to JS-initiated DOM mutations, derived from global config.
const JsLimits = struct {
    max_children: u32,
    max_depth: u16,

    fn fromConfig() JsLimits {
        const cfg = config.getConfig();
        return .{
            .max_children = cfg.parser.max_children_per_node,
            .max_depth = cfg.parser.max_tree_depth,
        };
    }
};

/// Find the first descendant element with the given id attribute.
/// Delegates to Node.getElementById on the provided root.
pub fn getElementById(root: *Node, id: []const u8) ?*Node {
    return root.getElementById(id);
}

/// Return the concatenated text content of a node and its descendants.
/// Caller owns the returned slice and must free it with the same allocator.
pub fn getTextContent(node_ptr: *const Node, allocator: std.mem.Allocator) ![]const u8 {
    return node_ptr.getTextContent(allocator);
}

/// Replace all children of the node with a single text node containing the
/// given string. Uses config-derived limits for child/depth constraints.
pub fn setTextContent(node_ptr: *Node, text: []const u8) !void {
    const limits = JsLimits.fromConfig();
    try node_ptr.setTextContent(text, limits);
}

/// Return the value of the named attribute, or null if not present.
pub fn getAttribute(node_ptr: *const Node, name: []const u8) ?[]const u8 {
    return node_ptr.getAttribute(name);
}

/// Set (or update) an attribute on the node.
pub fn setAttribute(node_ptr: *Node, name: []const u8, value: []const u8) !void {
    try node_ptr.setAttribute(name, value);
}

/// Return the element tag name string, or null for non-element nodes.
pub fn getTagName(node_ptr: *const Node) ?[]const u8 {
    return node_ptr.tag_name_str;
}
