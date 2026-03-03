const std = @import("std");
const document_mod = @import("../../src/dom/document.zig");
const Document = document_mod.Document;

test "addEventListener registers listener" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    try el.event_target.addEventListener(el.allocator, "click", 42);
    try std.testing.expectEqual(@as(usize, 1), el.event_target.listeners.items.len);
    try std.testing.expectEqualStrings("click", el.event_target.listeners.items[0].event_type);
    try std.testing.expectEqual(@as(u64, 42), el.event_target.listeners.items[0].callback_id);
}

test "addEventListener ignores duplicate" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    try el.event_target.addEventListener(el.allocator, "click", 42);
    try el.event_target.addEventListener(el.allocator, "click", 42);
    try std.testing.expectEqual(@as(usize, 1), el.event_target.listeners.items.len);
}

test "addEventListener allows different callbacks for same event" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    try el.event_target.addEventListener(el.allocator, "click", 1);
    try el.event_target.addEventListener(el.allocator, "click", 2);
    try std.testing.expectEqual(@as(usize, 2), el.event_target.listeners.items.len);
}

test "removeEventListener removes listener" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    try el.event_target.addEventListener(el.allocator, "click", 42);
    el.event_target.removeEventListener("click", 42);
    try std.testing.expectEqual(@as(usize, 0), el.event_target.listeners.items.len);
}

test "removeEventListener no-op on missing" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    el.event_target.removeEventListener("click", 99);
    try std.testing.expectEqual(@as(usize, 0), el.event_target.listeners.items.len);
}

test "hasListeners returns correct state" {
    const doc = try Document.init(std.testing.allocator);
    defer doc.deinit();
    const el = try doc.createElement("div");
    try std.testing.expect(!el.event_target.hasListeners("click"));
    try el.event_target.addEventListener(el.allocator, "click", 1);
    try std.testing.expect(el.event_target.hasListeners("click"));
    try std.testing.expect(!el.event_target.hasListeners("mouseover"));
}
