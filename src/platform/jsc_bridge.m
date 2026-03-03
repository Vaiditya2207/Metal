#import <JavaScriptCore/JavaScriptCore.h>
#import "jsc_bridge.h"

JSContextHandle jsc_context_create(void) {
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    return (JSContextHandle)ctx;
}

void jsc_context_release(JSContextHandle ctx) {
    if (ctx) JSGlobalContextRelease((JSGlobalContextRef)ctx);
}

JSStringHandle jsc_string_create(const char *utf8) {
    if (!utf8) return NULL;
    return (JSStringHandle)JSStringCreateWithUTF8CString(utf8);
}

void jsc_string_release(JSStringHandle str) {
    if (str) JSStringRelease((JSStringRef)str);
}

int jsc_string_get_utf8(JSStringHandle str, char *buffer, int buffer_size) {
    if (!str || !buffer || buffer_size <= 0) return 0;
    size_t written = JSStringGetUTF8CString((JSStringRef)str, buffer, (size_t)buffer_size);
    return (int)written;
}

int jsc_string_get_length(JSStringHandle str) {
    if (!str) return 0;
    return (int)JSStringGetLength((JSStringRef)str);
}

JSValueHandle jsc_evaluate_script(JSContextHandle ctx, const char *script, int script_len) {
    if (!ctx || !script || script_len <= 0) return NULL;
    JSStringRef js_script = JSStringCreateWithUTF8CString(script);
    JSValueRef exception = NULL;
    JSValueRef result = JSEvaluateScript(
        (JSGlobalContextRef)ctx, js_script, NULL, NULL, 0, &exception);
    JSStringRelease(js_script);
    if (exception) return NULL;
    return (JSValueHandle)result;
}

int jsc_value_is_string(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0;
    return JSValueIsString((JSGlobalContextRef)ctx, (JSValueRef)val) ? 1 : 0;
}

int jsc_value_is_number(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0;
    return JSValueIsNumber((JSGlobalContextRef)ctx, (JSValueRef)val) ? 1 : 0;
}

int jsc_value_is_undefined(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0;
    return JSValueIsUndefined((JSGlobalContextRef)ctx, (JSValueRef)val) ? 1 : 0;
}

int jsc_value_is_null(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0;
    return JSValueIsNull((JSGlobalContextRef)ctx, (JSValueRef)val) ? 1 : 0;
}

int jsc_value_is_object(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0;
    return JSValueIsObject((JSGlobalContextRef)ctx, (JSValueRef)val) ? 1 : 0;
}

double jsc_value_to_number(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return 0.0;
    JSValueRef exception = NULL;
    double result = JSValueToNumber(
        (JSGlobalContextRef)ctx, (JSValueRef)val, &exception);
    if (exception) return 0.0;
    return result;
}

JSStringHandle jsc_value_to_string(JSContextHandle ctx, JSValueHandle val) {
    if (!ctx || !val) return NULL;
    JSValueRef exception = NULL;
    JSStringRef str = JSValueToStringCopy(
        (JSGlobalContextRef)ctx, (JSValueRef)val, &exception);
    if (exception) return NULL;
    return (JSStringHandle)str;
}

JSValueHandle jsc_object_get_property(JSContextHandle ctx, JSObjectHandle obj,
                                       const char *name) {
    if (!ctx || !obj || !name) return NULL;
    JSStringRef prop_name = JSStringCreateWithUTF8CString(name);
    JSValueRef exception = NULL;
    JSValueRef val = JSObjectGetProperty(
        (JSGlobalContextRef)ctx, (JSObjectRef)obj, prop_name, &exception);
    JSStringRelease(prop_name);
    if (exception) return NULL;
    return (JSValueHandle)val;
}

void jsc_object_set_property(JSContextHandle ctx, JSObjectHandle obj,
                              const char *name, JSValueHandle val) {
    if (!ctx || !obj || !name) return;
    JSStringRef prop_name = JSStringCreateWithUTF8CString(name);
    JSValueRef exception = NULL;
    JSObjectSetProperty(
        (JSGlobalContextRef)ctx, (JSObjectRef)obj, prop_name,
        (JSValueRef)val, 0, &exception);
    JSStringRelease(prop_name);
}

JSObjectHandle jsc_global_object(JSContextHandle ctx) {
    if (!ctx) return NULL;
    return (JSObjectHandle)JSContextGetGlobalObject((JSContextRef)ctx);
}

// Trampoline for JSC callbacks
static JSValueRef callback_trampoline(JSContextRef ctx, JSObjectRef function,
                                       JSObjectRef thisObject,
                                       size_t argumentCount,
                                       const JSValueRef arguments[],
                                       JSValueRef *exception) {
    (void)exception;
    JSCCallbackFn fn = (JSCCallbackFn)JSObjectGetPrivate(function);
    if (!fn) return JSValueMakeUndefined(ctx);
    JSValueHandle result = fn(
        (JSContextHandle)ctx, (JSObjectHandle)function,
        (JSObjectHandle)thisObject, (int)argumentCount,
        (const JSValueHandle *)arguments);
    return result ? (JSValueRef)result : JSValueMakeUndefined(ctx);
}

JSObjectHandle jsc_make_function(JSContextHandle ctx, const char *name,
                                  JSCCallbackFn callback) {
    if (!ctx || !callback) return NULL;
    JSStringRef fn_name = name ? JSStringCreateWithUTF8CString(name) : NULL;

    JSClassDefinition class_def = kJSClassDefinitionEmpty;
    class_def.callAsFunction = callback_trampoline;
    JSClassRef cls = JSClassCreate(&class_def);

    JSObjectRef fn_obj = JSObjectMake(
        (JSGlobalContextRef)ctx, cls, (void *)callback);
    JSClassRelease(cls);
    if (fn_name) JSStringRelease(fn_name);
    return (JSObjectHandle)fn_obj;
}

JSObjectHandle jsc_make_object(JSContextHandle ctx) {
    if (!ctx) return NULL;
    return (JSObjectHandle)JSObjectMake((JSGlobalContextRef)ctx, NULL, NULL);
}

JSValueHandle jsc_make_string_value(JSContextHandle ctx, const char *utf8) {
    if (!ctx || !utf8) return NULL;
    JSStringRef str = JSStringCreateWithUTF8CString(utf8);
    JSValueRef val = JSValueMakeString((JSGlobalContextRef)ctx, str);
    JSStringRelease(str);
    return (JSValueHandle)val;
}

JSValueHandle jsc_make_number_value(JSContextHandle ctx, double number) {
    if (!ctx) return NULL;
    return (JSValueHandle)JSValueMakeNumber((JSGlobalContextRef)ctx, number);
}

JSValueHandle jsc_make_undefined(JSContextHandle ctx) {
    if (!ctx) return NULL;
    return (JSValueHandle)JSValueMakeUndefined((JSGlobalContextRef)ctx);
}

JSValueHandle jsc_make_null(JSContextHandle ctx) {
    if (!ctx) return NULL;
    return (JSValueHandle)JSValueMakeNull((JSGlobalContextRef)ctx);
}

void jsc_object_set_private(JSObjectHandle obj, void *data) {
    if (obj) JSObjectSetPrivate((JSObjectRef)obj, data);
}

void *jsc_object_get_private(JSObjectHandle obj) {
    if (!obj) return NULL;
    return JSObjectGetPrivate((JSObjectRef)obj);
}

int jsc_has_exception(JSContextHandle ctx) {
    // JSC uses per-call exception out-parameters rather than global state.
    // Callers should check return values from evaluate/property calls.
    (void)ctx;
    return 0;
}
