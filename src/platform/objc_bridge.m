#import "objc_bridge.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@interface MetalViewDelegate : NSObject <MTKViewDelegate>
@property(nonatomic, assign) void *zig_context;
@property(nonatomic, assign) void (*draw_callback)(void *);
@end

@implementation MetalViewDelegate
- (void)drawInMTKView:(nonnull MTKView *)view {
  if (self.draw_callback) {
    self.draw_callback(self.zig_context);
  }
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)theApplication {
  return YES;
}
@end

void *create_application_delegate(void) {
  return (__bridge_retained void *)[[AppDelegate alloc] init];
}

void *create_window(const char *title, float width, float height) {
  NSRect frame = NSMakeRect(0, 0, width, height);
  NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                         NSWindowStyleMaskResizable |
                         NSWindowStyleMaskMiniaturizable;

  NSWindow *window =
      [[NSWindow alloc] initWithContentRect:frame
                                  styleMask:styleMask
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  [window setTitle:[NSString stringWithUTF8String:title]];
  [window makeKeyAndOrderFront:nil];
  [window center];

  return (__bridge_retained void *)window;
}

void *create_metal_view(void *window_ptr, void *device_ptr) {
  NSWindow *window = (__bridge NSWindow *)window_ptr;
  id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;

  MTKView *view = [[MTKView alloc] initWithFrame:[window.contentView bounds]
                                          device:device];
  [window setContentView:view];

  return (__bridge void *)view;
}

void *create_command_queue(void *device_ptr) {
  id<MTLDevice> device = (__bridge id<MTLDevice>)device_ptr;
  return (__bridge_retained void *)[device newCommandQueue];
}

void run_application(void) { [NSApp run]; }

void set_metal_delegate(void *view_ptr, void *zig_context,
                        void (*draw_callback)(void *)) {
  MTKView *view = (__bridge MTKView *)view_ptr;
  MetalViewDelegate *delegate = [[MetalViewDelegate alloc] init];
  delegate.zig_context = zig_context;
  delegate.draw_callback = draw_callback;
  [view setDelegate:delegate];
}
