const std = @import("std");
const dom = @import("../dom/mod.zig");
const events = @import("../platform/events.zig");

pub const InputState = enum {
    ignored,
    handled,
    submit,
};

pub const InputManager = struct {
    focused_node: ?*dom.Node = null,

    pub fn init() InputManager {
        return .{};
    }

    pub fn focus(self: *InputManager, node: *dom.Node) void {
        // If focusing a new node, maybe reset cursor blink state
        self.focused_node = node;
    }

    pub fn blur(self: *InputManager) void {
        self.focused_node = null;
    }

    pub fn handleEvent(self: *InputManager, allocator: std.mem.Allocator, event: events.Event) !InputState {
        const node = self.focused_node orelse return .ignored;
        if (node.node_type != .element or (node.tag != .input and node.tag != .textarea)) return .ignored;

        if (event.event_type == .key_down) {
            // macOS backspace keycode is 51
            if (event.keycode == 51) {
                const current_val = node.getAttribute("value") orelse "";
                if (current_val.len > 0) {
                    // Simple backspace (ASCII-only for now)
                    try node.setAttribute("value", current_val[0 .. current_val.len - 1]);
                    return .handled;
                }
            } else {
                var text_len: usize = 0;
                while (text_len < 8 and event.text[text_len] != 0) : (text_len += 1) {}
                
                if (text_len > 0) {
                    const slice = event.text[0..text_len];
                    
                    // Check for Enter/Return
                    if (std.mem.indexOfScalar(u8, slice, '\r') != null or std.mem.indexOfScalar(u8, slice, '\n') != null) {
                        return .submit;
                    }
                    
                    // Exclude control characters (< 32 except \r \n) and delete (127)
                    var is_printable = true;
                    for (slice) |c| {
                        if (c < 32 or c == 127) {
                            is_printable = false;
                            break;
                        }
                    }
                    
                    if (is_printable) {
                        const current_val = node.getAttribute("value") orelse "";
                        const new_val = try std.fmt.allocPrint(allocator, "{s}{s}", .{current_val, slice});
                        defer allocator.free(new_val);
                        // setAttribute duplicates the string internally
                        try node.setAttribute("value", new_val);
                        return .handled;
                    }
                }
            }
        }
        return .ignored;
    }
};
