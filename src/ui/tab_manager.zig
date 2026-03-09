const std = @import("std");
const Tab = @import("tab.zig").Tab;

pub const TabManager = struct {
    allocator: std.mem.Allocator,
    tabs: std.ArrayListUnmanaged(*Tab) = .{},
    active_idx: usize = 0,
    next_id: usize = 0,

    pub fn init(allocator: std.mem.Allocator) TabManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TabManager) void {
        for (self.tabs.items) |tab| {
            tab.deinit();
        }
        self.tabs.deinit(self.allocator);
    }

    pub fn createTab(self: *TabManager, url: []const u8) !*Tab {
        const tab = try Tab.init(self.allocator, self.next_id, url);
        self.next_id += 1;
        try self.tabs.append(self.allocator, tab);
        self.active_idx = self.tabs.items.len - 1;
        return tab;
    }

    pub fn closeTab(self: *TabManager, idx: usize) void {
        if (idx >= self.tabs.items.len) return;
        const tab = self.tabs.orderedRemove(idx);
        tab.deinit();
        if (self.active_idx >= self.tabs.items.len and self.tabs.items.len > 0) {
            self.active_idx = self.tabs.items.len - 1;
        }
    }

    pub fn activeTab(self: *TabManager) ?*Tab {
        if (self.tabs.items.len == 0) return null;
        return self.tabs.items[self.active_idx];
    }
};
