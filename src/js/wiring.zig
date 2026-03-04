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
