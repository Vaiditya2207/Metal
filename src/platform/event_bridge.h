#ifndef EVENT_BRIDGE_H
#define EVENT_BRIDGE_H

typedef enum {
  EVENT_SCROLL,
  EVENT_MOUSE_DOWN,
  EVENT_MOUSE_UP,
  EVENT_MOUSE_MOVED,
  EVENT_KEY_DOWN,
  EVENT_KEY_UP,
  EVENT_RESIZE
} EventType;

typedef struct {
  EventType type;
  float x, y;             // Mouse position or scroll delta
  float width, height;    // For resize events
  int button;             // Mouse button (0=left, 1=right, 2=middle)
  unsigned int keycode;   // Virtual keycode for keyboard events
  unsigned int modifiers; // Modifier flags (shift, cmd, ctrl, alt)
  char characters[8];     // Typed character(s)
} BridgeEvent;

// Callback type: Zig function called when an event occurs
typedef void (*EventCallback)(void *context, BridgeEvent event);

#ifdef __cplusplus
extern "C" {
#endif

// Register the event callback (called once at init)
void set_event_callback(void *view, void *context, EventCallback callback);

// Create a MetalEventView (replaces the plain MTKView)
// This custom view subclass overrides NSResponder methods
void *create_event_metal_view(void *window, void *device);

void set_cursor_style(int style); // 0 = arrow, 1 = pointer (hand), 2 = ibeam
void terminate_application(void);

#ifdef __cplusplus
}
#endif

#endif
