const objc = @import("app.zig").objc;
const std = @import("std");

pub const EventType = enum {
    scroll,
    mouse_down,
    mouse_up,
    mouse_moved,
    key_down,
    key_up,
    resize,
};

pub const Event = struct {
    event_type: EventType,
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    button: i32 = 0,
    keycode: u32 = 0,
    modifiers: u32 = 0,
};

// Modifier flag constants (macOS NSEventModifierFlags)
pub const MOD_SHIFT: u32 = 1 << 17;
pub const MOD_CONTROL: u32 = 1 << 18;
pub const MOD_ALT: u32 = 1 << 19;
pub const MOD_COMMAND: u32 = 1 << 20;

pub const EventQueue = struct {
    events: [256]Event = undefined,
    head: usize = 0,
    tail: usize = 0,

    pub fn push(self: *EventQueue, event: Event) void {
        const next = (self.head + 1) % self.events.len;
        if (next != self.tail) {
            self.events[self.head] = event;
            self.head = next;
        }
    }

    pub fn pop(self: *EventQueue) ?Event {
        if (self.head == self.tail) return null;
        const event = self.events[self.tail];
        self.tail = (self.tail + 1) % self.events.len;
        return event;
    }

    pub fn isEmpty(self: *const EventQueue) bool {
        return self.head == self.tail;
    }
};

pub var global_queue: EventQueue = .{};

pub fn eventCallback(_: ?*anyopaque, bridge_event: objc.BridgeEvent) callconv(.c) void {
    const event_type: EventType = switch (bridge_event.type) {
        objc.EVENT_SCROLL => .scroll,
        objc.EVENT_MOUSE_DOWN => .mouse_down,
        objc.EVENT_MOUSE_UP => .mouse_up,
        objc.EVENT_MOUSE_MOVED => .mouse_moved,
        objc.EVENT_KEY_DOWN => .key_down,
        objc.EVENT_KEY_UP => .key_up,
        objc.EVENT_RESIZE => .resize,
        else => return,
    };

    global_queue.push(.{
        .event_type = event_type,
        .x = bridge_event.x,
        .y = bridge_event.y,
        .width = bridge_event.width,
        .height = bridge_event.height,
        .button = bridge_event.button,
        .keycode = bridge_event.keycode,
        .modifiers = bridge_event.modifiers,
    });
}
