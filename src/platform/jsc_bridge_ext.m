#import <JavaScriptCore/JavaScriptCore.h>
#import "jsc_bridge.h"
#include <stdlib.h>

// Thread-local exception storage (defined in jsc_bridge.m)
extern _Thread_local JSValueRef g_last_exception;

// -- GC protection -------------------------------------------------------

void jsc_value_protect(JSContextHandle ctx, JSValueHandle value) {
    if (!ctx || !value) return;
    JSValueProtect((JSContextRef)ctx, (JSValueRef)value);
}

void jsc_value_unprotect(JSContextHandle ctx, JSValueHandle value) {
    if (!ctx || !value) return;
    JSValueUnprotect((JSContextRef)ctx, (JSValueRef)value);
}

// -- Class instance with property interceptors ---------------------------

typedef struct {
    void *private_data;
    JSCGetPropCallback get_cb;
    JSCSetPropCallback set_cb;
} ClassInstanceData;

static JSValueRef class_get_property_trampoline(JSContextRef ctx,
                                                 JSObjectRef object,
                                                 JSStringRef propertyName,
                                                 JSValueRef *exception) {
    (void)exception;
    ClassInstanceData *data = (ClassInstanceData *)JSObjectGetPrivate(object);
    if (!data || !data->get_cb) return NULL;
    char name_buf[256];
    JSStringGetUTF8CString(propertyName, name_buf, sizeof(name_buf));
    return (JSValueRef)data->get_cb((JSContextHandle)ctx,
                                     (JSObjectHandle)object,
                                     name_buf, data->private_data);
}

static bool class_set_property_trampoline(JSContextRef ctx,
                                           JSObjectRef object,
                                           JSStringRef propertyName,
                                           JSValueRef value,
                                           JSValueRef *exception) {
    (void)exception;
    ClassInstanceData *data = (ClassInstanceData *)JSObjectGetPrivate(object);
    if (!data || !data->set_cb) return false;
    char name_buf[256];
    JSStringGetUTF8CString(propertyName, name_buf, sizeof(name_buf));
    return data->set_cb((JSContextHandle)ctx, (JSObjectHandle)object,
                        name_buf, (JSValueHandle)value,
                        data->private_data) != 0;
}

static void class_instance_finalize(JSObjectRef object) {
    ClassInstanceData *data = (ClassInstanceData *)JSObjectGetPrivate(object);
    if (data) free(data);
}

JSObjectHandle jsc_make_class_instance(JSContextHandle ctx, void *private_data,
                                        JSCGetPropCallback get_cb,
                                        JSCSetPropCallback set_cb) {
    if (!ctx) return NULL;
    ClassInstanceData *data = (ClassInstanceData *)malloc(sizeof(ClassInstanceData));
    if (!data) return NULL;
    data->private_data = private_data;
    data->get_cb = get_cb;
    data->set_cb = set_cb;

    JSClassDefinition def = kJSClassDefinitionEmpty;
    def.getProperty = class_get_property_trampoline;
    def.setProperty = class_set_property_trampoline;
    def.finalize = class_instance_finalize;

    JSClassRef cls = JSClassCreate(&def);
    JSObjectRef obj = JSObjectMake((JSContextRef)ctx, cls, data);
    JSClassRelease(cls);
    return (JSObjectHandle)obj;
}

// -- Exception retrieval -------------------------------------------------

JSValueHandle jsc_get_exception(JSContextHandle ctx) {
    (void)ctx;
    return (JSValueHandle)g_last_exception;
}

void jsc_clear_exception(JSContextHandle ctx) {
    (void)ctx;
    g_last_exception = NULL;
}

// -- Call function -------------------------------------------------------

JSValueHandle jsc_call_function(JSContextHandle ctx, JSObjectHandle function,
                                 JSObjectHandle this_object, int arg_count,
                                 const JSValueHandle *args) {
    if (!ctx || !function) return NULL;
    JSValueRef exception = NULL;
    JSValueRef result = JSObjectCallAsFunction(
        (JSContextRef)ctx, (JSObjectRef)function,
        this_object ? (JSObjectRef)this_object : NULL,
        (size_t)arg_count,
        (const JSValueRef *)args,
        &exception);
    if (exception) {
        g_last_exception = exception;
        return NULL;
    }
    return (JSValueHandle)result;
}

// -- Class instance user data -------------------------------------------

void *jsc_class_get_user_data(JSObjectHandle obj) {
    if (!obj) return NULL;
    ClassInstanceData *data = (ClassInstanceData *)JSObjectGetPrivate((JSObjectRef)obj);
    if (!data) return NULL;
    return data->private_data;
}
