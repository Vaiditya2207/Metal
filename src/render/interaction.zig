const hit_test = @import("hit_test.zig");
const layout_box = @import("../layout/box.zig");
const dom = @import("../dom/mod.zig");
const Node = dom.Node;
const events = @import("../platform/events.zig");
const std = @import("std");

pub const InteractionHandler = struct {
    last_hit: ?hit_test.HitTestResult = null,
    cursor_state: CursorState = .default_cursor,

    pub const CursorState = enum {
        default_cursor,
        pointer,
        text_cursor,
    };

    pub const KeyAction = enum {
        quit,
        scroll_up,
        scroll_down,
        scroll_to_top,
        scroll_to_bottom,
    };

    pub const ClickResult = struct {
        href: ?[]const u8,
        target_node: ?*const Node,
    };

    pub fn handleMouseMove(
        self: *InteractionHandler,
        root: *const layout_box.LayoutBox,
        x: f32,
        y: f32,
        scroll_y: f32,
    ) CursorState {
        const maybe_result = hit_test.hitTest(root, x, y, scroll_y);
        self.last_hit = maybe_result;

        if (maybe_result) |result| {
            var current_node = result.node;
            while (current_node) |node| {
                if (node.tag == .a) {
                    self.cursor_state = .pointer;
                    return .pointer;
                }
                current_node = node.parent;
            }
        }

        self.cursor_state = .default_cursor;
        return .default_cursor;
    }

    pub fn handleClick(
        self: *InteractionHandler,
        root: *const layout_box.LayoutBox,
        x: f32,
        y: f32,
        scroll_y: f32,
    ) ClickResult {
        const maybe_result = hit_test.hitTest(root, x, y, scroll_y);
        self.last_hit = maybe_result;

        if (maybe_result) |result| {
            var href: ?[]const u8 = null;
            var current_node = result.node;
            while (current_node) |node| {
                if (node.tag == .a and href == null) {
                    href = node.getAttribute("href");
                }
                current_node = node.parent;
            }
            return .{ .href = href, .target_node = result.node };
        }

        return .{ .href = null, .target_node = null };
    }

    pub fn handleKeyDown(keycode: u32, modifiers: u32) ?KeyAction {
        if (keycode == 12 and (modifiers & events.MOD_COMMAND) != 0) {
            return .quit;
        }

        if (keycode == 49) {
            if ((modifiers & events.MOD_SHIFT) != 0) {
                return .scroll_up;
            }
            return .scroll_down;
        }

        if (keycode == 115) {
            return .scroll_to_top;
        }

        if (keycode == 119) {
            return .scroll_to_bottom;
        }

        return null;
    }
};
