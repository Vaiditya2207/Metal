const std = @import("std");
const config = @import("../config.zig");
const node_mod = @import("node.zig");
const tag_mod = @import("tag.zig");

pub const Node = node_mod.Node;
pub const NodeType = node_mod.NodeType;
pub const TagName = tag_mod.TagName;

/// Security and size limits for DOM operations.
pub const Limits = struct {
    max_depth: u16,
    max_children: u32,
    max_total_nodes: u32,

    pub fn fromConfig() Limits {
        const cfg = config.getConfig();
        return Limits{
            .max_depth = cfg.parser.max_tree_depth,
            .max_children = cfg.parser.max_children_per_node,
            .max_total_nodes = cfg.parser.max_total_nodes,
        };
    }
};

/// A parsed HTML document. Owns its arena allocator.
pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: *Node,
    node_count: u32,
    limits: Limits,

    pub fn init(backing_allocator: std.mem.Allocator) !*Document {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);

        const doc = try arena.allocator().create(Document);
        doc.* = Document{
            .arena = arena,
            .root = undefined,
            .node_count = 0,
            .limits = Limits.fromConfig(),
        };

        const stable_alloc = doc.arena.allocator();
        const root = try stable_alloc.create(Node);
        root.* = Node.init(stable_alloc, .document);
        doc.root = root;
        doc.node_count = 1;

        return doc;
    }

    /// Allocate a new node within this document's arena.
    pub fn createNode(self: *Document, node_type: NodeType) !*Node {
        if (self.node_count >= self.limits.max_total_nodes) return error.TooManyNodes;
        const node = try self.arena.allocator().create(Node);
        node.* = Node.init(self.arena.allocator(), node_type);
        self.node_count += 1;
        return node;
    }

    /// Create an element node with the given tag.
    pub fn createElement(self: *Document, tag_name: []const u8) !*Node {
        const node = try self.createNode(.element);
        node.tag = TagName.fromString(tag_name);
        node.tag_name_str = try self.arena.allocator().dupe(u8, tag_name);
        return node;
    }

    /// Create a text node.
    pub fn createTextNode(self: *Document, text: []const u8) !*Node {
        const node = try self.createNode(.text);
        node.data = try self.arena.allocator().dupe(u8, text);
        return node;
    }

    /// Destroy the document and free all memory in O(1).
    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
};
