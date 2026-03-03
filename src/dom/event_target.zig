const std = @import("std");

/// A stored event listener binding.
pub const EventListener = struct {
    event_type: []const u8,
    /// Opaque callback identifier for JS binding (Phase 6).
    callback_id: u64,
};

/// EventTarget mixin providing addEventListener/removeEventListener storage.
/// Designed to be embedded as a field on Node.
pub const EventTarget = struct {
    listeners: std.ArrayListUnmanaged(EventListener) = .empty,

    /// Register a listener for the given event type.
    pub fn addEventListener(self: *EventTarget, allocator: std.mem.Allocator, event_type: []const u8, callback_id: u64) !void {
        for (self.listeners.items) |l| {
            if (l.callback_id == callback_id and std.mem.eql(u8, l.event_type, event_type)) return;
        }
        try self.listeners.append(allocator, .{
            .event_type = try allocator.dupe(u8, event_type),
            .callback_id = callback_id,
        });
    }

    /// Remove a listener. No-op if not found.
    pub fn removeEventListener(self: *EventTarget, event_type: []const u8, callback_id: u64) void {
        var i: usize = 0;
        while (i < self.listeners.items.len) {
            const l = self.listeners.items[i];
            if (l.callback_id == callback_id and std.mem.eql(u8, l.event_type, event_type)) {
                _ = self.listeners.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Check if any listeners are registered for the given event type.
    pub fn hasListeners(self: *const EventTarget, event_type: []const u8) bool {
        for (self.listeners.items) |l| {
            if (std.mem.eql(u8, l.event_type, event_type)) return true;
        }
        return false;
    }
};
