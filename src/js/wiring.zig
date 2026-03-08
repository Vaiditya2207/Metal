const std = @import("std");
const context = @import("context.zig");
const JsContext = context.JsContext;
const node_wrap = @import("node_wrap.zig");
const NodeRegistry = node_wrap.NodeRegistry;
const callback_registry_mod = @import("callback_registry.zig");
const CallbackRegistry = callback_registry_mod.CallbackRegistry;
const event_dispatch = @import("event_dispatch.zig");
const EventDispatcher = event_dispatch.EventDispatcher;
const timers = @import("timers.zig");
const TimerQueue = timers.TimerQueue;
const raf = @import("raf.zig");
const RafQueue = raf.RafQueue;
const pipeline = @import("pipeline.zig");
const PipelineState = pipeline.PipelineState;
const document_global = @import("document_global.zig");
const dom = @import("../dom/mod.zig");
const node_methods = @import("node_methods.zig");
const node_event_methods = @import("node_event_methods.zig");

var g_bridge: ?*const context.JsBridge = null;

fn jsNoop(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    return bridge.make_undefined(ctx);
}

fn jsPerformanceNow(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    _: c_int,
    _: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    const ms: f64 = @floatFromInt(std.time.milliTimestamp());
    return bridge.make_number_value(ctx, ms);
}

fn jsGoogleX(
    ctx: ?*anyopaque,
    _: ?*anyopaque,
    _: ?*anyopaque,
    arg_count: c_int,
    args: ?[*]const ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const bridge = g_bridge orelse return null;
    if (arg_count >= 2) {
        if (args) |arg_slice| {
            const this_obj = arg_slice[0];
            const callback = arg_slice[1];
            if (callback != null) {
                _ = bridge.call_function(ctx, callback, this_obj, 0, null);
                if (bridge.has_exception(ctx) != 0) {
                    if (bridge.clear_exception) |clear_ex| {
                        clear_ex(ctx);
                    } else {
                        _ = bridge.evaluate_script(ctx, "".ptr, 0);
                    }
                }
            }
        }
    }
    return bridge.make_undefined(ctx);
}

fn registerBrowserGlobals(js_ctx: *JsContext) void {
    const bridge = js_ctx.bridge;
    const ctx = js_ctx.ctx;
    const global = bridge.global_object(ctx);
    g_bridge = bridge;

    // window/self/globalThis aliases
    bridge.object_set_property(ctx, global, "window", global);
    bridge.object_set_property(ctx, global, "self", global);
    bridge.object_set_property(ctx, global, "globalThis", global);

    // Minimal browser APIs expected by bootstrap scripts
    bridge.object_set_property(ctx, global, "addEventListener", bridge.make_function(ctx, "addEventListener", @ptrCast(&jsNoop)));
    bridge.object_set_property(ctx, global, "removeEventListener", bridge.make_function(ctx, "removeEventListener", @ptrCast(&jsNoop)));

    const navigator = bridge.make_object(ctx);
    bridge.object_set_property(ctx, navigator, "userAgent", bridge.make_string_value(ctx, "Mozilla/5.0 (Macintosh; Intel Mac OS X) MetalBrowser/0.1"));
    bridge.object_set_property(ctx, navigator, "platform", bridge.make_string_value(ctx, "MacIntel"));
    bridge.object_set_property(ctx, navigator, "language", bridge.make_string_value(ctx, "en-US"));
    bridge.object_set_property(ctx, global, "navigator", navigator);

    const performance = bridge.make_object(ctx);
    bridge.object_set_property(ctx, performance, "now", bridge.make_function(ctx, "now", @ptrCast(&jsPerformanceNow)));
    bridge.object_set_property(ctx, global, "performance", performance);

    // Common Google bootstrap globals
    const dump_exception_fn = bridge.make_function(ctx, "_DumpException", @ptrCast(&jsNoop));
    bridge.object_set_property(ctx, global, "_DumpException", dump_exception_fn);

    const underscore = bridge.make_object(ctx);
    bridge.object_set_property(ctx, underscore, "_DumpException", dump_exception_fn);
    bridge.object_set_property(ctx, global, "_", underscore);

    const object_ctor = bridge.object_get_property(ctx, global, "Object");
    if (object_ctor != null) {
        const object_proto = bridge.object_get_property(ctx, object_ctor, "prototype");
        if (object_proto != null) {
            bridge.object_set_property(ctx, object_proto, "_DumpException", dump_exception_fn);
        }
    }

    const google = bridge.make_object(ctx);
    const google_c = bridge.make_object(ctx);
    bridge.object_set_property(ctx, google_c, "e", bridge.make_function(ctx, "e", @ptrCast(&jsNoop)));
    bridge.object_set_property(ctx, google, "c", google_c);
    bridge.object_set_property(ctx, google, "x", bridge.make_function(ctx, "x", @ptrCast(&jsGoogleX)));
    bridge.object_set_property(ctx, google, "sx", bridge.make_function(ctx, "sx", @ptrCast(&jsGoogleX)));
    bridge.object_set_property(ctx, global, "google", google);

    const gbar = bridge.make_object(ctx);
    bridge.object_set_property(ctx, gbar, "_DumpException", dump_exception_fn);
    bridge.object_set_property(ctx, global, "gbar_", gbar);
}

/// All JS runtime state bundled together for lifecycle management.
/// Use initRuntime() followed by wire() to avoid self-referential pointer issues.
pub const JsRuntime = struct {
    node_registry: NodeRegistry,
    callback_registry: CallbackRegistry,
    event_dispatcher: EventDispatcher,
    timer_queue: TimerQueue,
    raf_queue: RafQueue,
    pipeline_state: PipelineState,
    wired: bool,

    /// Create the runtime with all sub-systems allocated but not yet wired.
    /// The returned struct MUST be assigned to a stable location (stack var)
    /// before calling wire().
    pub fn initRuntime(allocator: std.mem.Allocator, js_ctx: *JsContext) JsRuntime {
        return .{
            .node_registry = NodeRegistry.init(allocator),
            .callback_registry = CallbackRegistry.init(allocator),
            .event_dispatcher = undefined,
            .timer_queue = TimerQueue.init(allocator, js_ctx),
            .raf_queue = RafQueue.init(allocator, js_ctx),
            .pipeline_state = PipelineState.init(),
            .wired = false,
        };
    }

    /// Wire all JS infrastructure onto the context and document.
    /// MUST be called after the JsRuntime is at its final stack address
    /// (i.e. after `var rt = initRuntime(...)`) so that interior pointers
    /// to callback_registry and node_registry remain valid.
    pub fn wire(
        self: *JsRuntime,
        allocator: std.mem.Allocator,
        js_ctx: *JsContext,
        document: *dom.Document,
    ) !void {
        registerBrowserGlobals(js_ctx);

        self.event_dispatcher = EventDispatcher.init(
            js_ctx,
            &self.callback_registry,
            &self.node_registry,
        );

        try document_global.registerDocument(
            js_ctx,
            document,
            &self.node_registry,
            allocator,
        );

        timers.registerTimerGlobals(js_ctx, &self.timer_queue);
        raf.registerRafGlobals(js_ctx, &self.raf_queue);
        pipeline.setGlobal(&self.pipeline_state);
        event_dispatch.setBridge(js_ctx.bridge);
        node_methods.setBridge(js_ctx.bridge);
        node_event_methods.setGlobal(js_ctx, &self.callback_registry);

        self.wired = true;
    }

    /// Tear down all JS runtime state. Call before JsContext.deinit().
    pub fn deinit(self: *JsRuntime, allocator: std.mem.Allocator, js_ctx: *JsContext) void {
        if (self.wired) {
            pipeline.resetGlobal();
            timers.resetGlobal();
            raf.resetGlobal();
            event_dispatch.resetBridge();
            node_methods.resetBridge();
            node_event_methods.resetGlobal();
            document_global.freeBinding(allocator);
        }
        self.raf_queue.deinit();
        self.timer_queue.deinit();
        self.callback_registry.deinit(js_ctx);
        self.node_registry.deinit();
    }
};
