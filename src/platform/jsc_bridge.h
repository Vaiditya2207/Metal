#ifndef JSC_BRIDGE_H
#define JSC_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles for JSC types
typedef void *JSContextHandle;
typedef void *JSValueHandle;
typedef void *JSObjectHandle;
typedef void *JSStringHandle;

// Context lifecycle
JSContextHandle jsc_context_create(void);
void jsc_context_release(JSContextHandle ctx);

// String utilities
JSStringHandle jsc_string_create(const char *utf8);
void jsc_string_release(JSStringHandle str);
int jsc_string_get_utf8(JSStringHandle str, char *buffer, int buffer_size);
int jsc_string_get_length(JSStringHandle str);

// Script evaluation
JSValueHandle jsc_evaluate_script(JSContextHandle ctx, const char *script, int script_len);

// Value inspection
int jsc_value_is_string(JSContextHandle ctx, JSValueHandle val);
int jsc_value_is_number(JSContextHandle ctx, JSValueHandle val);
int jsc_value_is_undefined(JSContextHandle ctx, JSValueHandle val);
int jsc_value_is_null(JSContextHandle ctx, JSValueHandle val);
int jsc_value_is_object(JSContextHandle ctx, JSValueHandle val);
double jsc_value_to_number(JSContextHandle ctx, JSValueHandle val);
JSStringHandle jsc_value_to_string(JSContextHandle ctx, JSValueHandle val);

// Object operations
JSValueHandle jsc_object_get_property(JSContextHandle ctx, JSObjectHandle obj, const char *name);
void jsc_object_set_property(JSContextHandle ctx, JSObjectHandle obj, const char *name, JSValueHandle val);
JSObjectHandle jsc_global_object(JSContextHandle ctx);

// Function callback type: receives (ctx, function, thisObject, argumentCount, arguments) -> JSValueHandle
// The arguments pointer is a C array of JSValueHandle
typedef JSValueHandle (*JSCCallbackFn)(JSContextHandle ctx, JSObjectHandle function,
                                        JSObjectHandle this_object, int arg_count,
                                        const JSValueHandle *args);

// Create a function object from a C callback
JSObjectHandle jsc_make_function(JSContextHandle ctx, const char *name, JSCCallbackFn callback);

// Create a plain object
JSObjectHandle jsc_make_object(JSContextHandle ctx);

// Value creation
JSValueHandle jsc_make_string_value(JSContextHandle ctx, const char *utf8);
JSValueHandle jsc_make_number_value(JSContextHandle ctx, double number);
JSValueHandle jsc_make_undefined(JSContextHandle ctx);
JSValueHandle jsc_make_null(JSContextHandle ctx);

// Object private data (for wrapping DOM nodes)
void jsc_object_set_private(JSObjectHandle obj, void *data);
void *jsc_object_get_private(JSObjectHandle obj);

// Exception checking
int jsc_has_exception(JSContextHandle ctx);

#ifdef __cplusplus
}
#endif

#endif // JSC_BRIDGE_H
