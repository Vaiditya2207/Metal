#import "event_bridge.h"
#import <MetalKit/MetalKit.h>
#import <AppKit/AppKit.h>

@interface MetalEventView : MTKView
@property (nonatomic, assign) void *zigContext;
@property (nonatomic, assign) EventCallback eventCallback;
@end

@implementation MetalEventView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)sendEvent:(BridgeEvent)event {
    if (self.eventCallback) {
        self.eventCallback(self.zigContext, event);
    }
}

- (void)scrollWheel:(NSEvent *)event {
    BridgeEvent e = {0};
    e.type = EVENT_SCROLL;
    e.x = (float)[event scrollingDeltaX];
    e.y = (float)[event scrollingDeltaY];
    [self sendEvent:e];
}

- (void)handleMouseEvent:(NSEvent *)event type:(EventType)type {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    BridgeEvent e = {0};
    e.type = type;
    e.x = (float)point.x;
    e.y = (float)(self.bounds.size.height - point.y);
    e.button = (int)[event buttonNumber];
    e.modifiers = (unsigned int)[event modifierFlags];
    [self sendEvent:e];
}

- (void)mouseDown:(NSEvent *)event { [self handleMouseEvent:event type:EVENT_MOUSE_DOWN]; }
- (void)mouseUp:(NSEvent *)event { [self handleMouseEvent:event type:EVENT_MOUSE_UP]; }
- (void)mouseMoved:(NSEvent *)event { [self handleMouseEvent:event type:EVENT_MOUSE_MOVED]; }
- (void)mouseDragged:(NSEvent *)event { [self handleMouseEvent:event type:EVENT_MOUSE_MOVED]; }

- (void)handleKeyEvent:(NSEvent *)event type:(EventType)type {
    BridgeEvent e = {0};
    e.type = type;
    e.keycode = (unsigned int)[event keyCode];
    e.modifiers = (unsigned int)[event modifierFlags];
    [self sendEvent:e];
}

- (void)keyDown:(NSEvent *)event { [self handleKeyEvent:event type:EVENT_KEY_DOWN]; }
- (void)keyUp:(NSEvent *)event { [self handleKeyEvent:event type:EVENT_KEY_UP]; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:area];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    BridgeEvent e = {0};
    e.type = EVENT_RESIZE;
    e.width = (float)newSize.width;
    e.height = (float)newSize.height;
    [self sendEvent:e];
}

@end

void set_event_callback(void *view, void *context, EventCallback callback) {
    MetalEventView *v = (__bridge MetalEventView *)view;
    v.zigContext = context;
    v.eventCallback = callback;
}

void *create_event_metal_view(void *window, void *device) {
    NSWindow *win = (__bridge NSWindow *)window;
    id<MTLDevice> dev = (__bridge id<MTLDevice>)device;
    
    MetalEventView *view = [[MetalEventView alloc] initWithFrame:win.contentView.frame device:dev];
    view.paused = NO;
    view.enableSetNeedsDisplay = NO;
    
    win.contentView = view;
    [win makeFirstResponder:view];
    
    return (__bridge_retained void *)view;
}

void set_cursor_style(int style) {
    switch (style) {
        case 1:
            [[NSCursor pointingHandCursor] set];
            break;
        case 2:
            [[NSCursor IBeamCursor] set];
            break;
        default:
            [[NSCursor arrowCursor] set];
            break;
    }
}

void terminate_application(void) {
    [NSApp terminate:nil];
}
