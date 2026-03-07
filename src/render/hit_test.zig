const std = @import("std");
const layout_box = @import("../layout/box.zig");
const dom = @import("../dom/mod.zig");

pub const HitTestResult = struct {
    box: *const layout_box.LayoutBox,
    node: ?*const dom.Node,
};

pub fn hitTest(root: *const layout_box.LayoutBox, x: f32, y: f32, scroll_y: f32) ?HitTestResult {
    const py = y + scroll_y;
    const px = x;

    // Always traverse children first (reverse paint order)
    var i: usize = root.children.items.len;
    while (i > 0) {
        i -= 1;
        const child = root.children.items[i];
        if (hitTest(child, x, y, scroll_y)) |result| {
            return result;
        }
    }

    // Check self after children
    if (containsPoint(root.dimensions.borderBox(), px, py)) {
        var node: ?*const dom.Node = null;
        if (root.styled_node) |sn| {
            node = sn.node;
        } else {
            var ancestor = root.parent;
            while (ancestor) |a| {
                if (a.styled_node) |sn| {
                    node = sn.node;
                    break;
                }
                ancestor = a.parent;
            }
        }
        
        // Prefer more interactive tags if we have multiple boxes hitting the same area
        // (common in anonymous blocks where multiple inputs/buttons are siblings)
        return HitTestResult{
            .box = root,
            .node = node,
        };
    }

    return null;
}

fn containsPoint(rect: layout_box.Rect, px: f32, py: f32) bool {
    return px >= rect.x and px < rect.x + rect.width and
        py >= rect.y and py < rect.y + rect.height;
}
