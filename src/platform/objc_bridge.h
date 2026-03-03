#ifndef OBJC_BRIDGE_H
#define OBJC_BRIDGE_H

// Pure C header for Zig interop. No Objective-C allowed here.

typedef void *MetalDelegateHandle;

#ifdef __cplusplus
extern "C" {
#endif

void *create_application_delegate(void);
void *create_window(const char *title, float width, float height);
void *create_metal_view(void *window, void *device);
void *create_command_queue(void *device);
void set_metal_delegate(void *view, void *zig_context,
                        void (*draw_callback)(void *));
void run_application(void);

#ifdef __cplusplus
}
#endif

#endif // OBJC_BRIDGE_H
