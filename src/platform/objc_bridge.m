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
  @autoreleasepool {
    if (self.draw_callback) {
      self.draw_callback(self.zig_context);
    }
  }
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
}
@end

@interface MetalWindow : NSWindow
@end

@implementation MetalWindow
- (BOOL)canBecomeKeyWindow {
  return YES;
}
- (BOOL)canBecomeMainWindow {
  return YES;
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

  MetalWindow *window =
      [[MetalWindow alloc] initWithContentRect:frame
                                     styleMask:styleMask
                                       backing:NSBackingStoreBuffered
                                         defer:NO];
  [window setTitle:[NSString stringWithUTF8String:title]];
  [window setLevel:NSNormalWindowLevel];
  [window makeKeyAndOrderFront:nil];
  [window center];

  return (__bridge_retained void *)window;
}

void set_window_title(void *window_ptr, const char *title) {
  NSWindow *window = (__bridge NSWindow *)window_ptr;
  [window setTitle:[NSString stringWithUTF8String:title]];
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

static FrameContext g_frame_context;

void *begin_frame(void *command_queue_ptr, void *view_ptr) {
  id<MTLCommandQueue> commandQueue =
      (__bridge id<MTLCommandQueue>)command_queue_ptr;
  MTKView *view = (__bridge MTKView *)view_ptr;

  MTLRenderPassDescriptor *renderPassDescriptor =
      view.currentRenderPassDescriptor;
  id<CAMetalDrawable> drawable = view.currentDrawable;

  if (renderPassDescriptor == nil || drawable == nil) {
    return NULL;
  }

  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  id<MTLRenderCommandEncoder> renderEncoder =
      [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

  g_frame_context.commandBuffer = (__bridge_retained void *)commandBuffer;
  g_frame_context.renderEncoder = (__bridge_retained void *)renderEncoder;
  g_frame_context.drawable = (__bridge_retained void *)drawable;

  return (void *)&g_frame_context;
}

void end_frame(void *frame_context_ptr) {
  if (frame_context_ptr == NULL)
    return;
  FrameContext *context = (FrameContext *)frame_context_ptr;

  id<MTLRenderCommandEncoder> renderEncoder =
      (__bridge_transfer id<MTLRenderCommandEncoder>)context->renderEncoder;
  id<MTLCommandBuffer> commandBuffer =
      (__bridge_transfer id<MTLCommandBuffer>)context->commandBuffer;
  id<MTLDrawable> drawable =
      (__bridge_transfer id<MTLDrawable>)context->drawable;

  [renderEncoder endEncoding];
  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];
}

void set_clear_color(void *view_ptr, float r, float g, float b, float a) {
  MTKView *view = (__bridge MTKView *)view_ptr;
  view.clearColor = MTLClearColorMake(r, g, b, a);
}

void run_application(void) { [NSApp run]; }

static MetalViewDelegate *g_delegate = nil;

void set_metal_delegate(void *view_ptr, void *zig_context,
                        void (*draw_callback)(void *)) {
  MTKView *view = (__bridge MTKView *)view_ptr;
  g_delegate = [[MetalViewDelegate alloc] init];
  g_delegate.zig_context = zig_context;
  g_delegate.draw_callback = draw_callback;
  [view setDelegate:g_delegate];
}

void get_drawable_size(void *view_ptr, float *width, float *height) {
  MTKView *view = (__bridge MTKView *)view_ptr;
  CGSize size = view.bounds.size;
  *width = (float)size.width;
  *height = (float)size.height;
}

float get_content_scale(void *view_ptr) {
  MTKView *view = (__bridge MTKView *)view_ptr;
  return (float)view.window.backingScaleFactor;
}

float get_screen_scale_factor(void) {
  return (float)[NSScreen mainScreen].backingScaleFactor;
}

void activate_app(void) {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  // Create application menu
  NSMenu *menubar = [[NSMenu alloc] init];
  NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
  [menubar addItem:appMenuItem];
  [NSApp setMainMenu:menubar];

  NSMenu *appMenu = [[NSMenu alloc] init];
  NSString *appName = [[NSProcessInfo processInfo] processName];
  NSString *quitTitle = [@"Quit " stringByAppendingString:appName];
  NSMenuItem *quitMenuItem =
      [[NSMenuItem alloc] initWithTitle:quitTitle
                                 action:@selector(terminate:)
                          keyEquivalent:@"q"];
  [appMenu addItem:quitMenuItem];
  [appMenuItem setSubmenu:appMenu];

  // Add Edit menu for Copy/Paste shortcuts
  NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
                                                        action:nil
                                                 keyEquivalent:@""];
  [menubar addItem:editMenuItem];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Cut"
                                               action:@selector(cut:)
                                        keyEquivalent:@"x"]];
  [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Copy"
                                               action:@selector(copy:)
                                        keyEquivalent:@"c"]];
  [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Paste"
                                               action:@selector(paste:)
                                        keyEquivalent:@"v"]];
  [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All"
                                               action:@selector(selectAll:)
                                        keyEquivalent:@"a"]];
  [editMenuItem setSubmenu:editMenu];

  [NSApp activateIgnoringOtherApps:YES];
}
