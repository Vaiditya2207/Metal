# JavaScript Engine Strategy: JSC + QuickJS Hybrid

This document analyzes the technical landscape for JavaScript execution in the **Metal** browser and justifies the choice of a hybrid strategy over V8 or a custom implementation.

## 1. Comparative Analysis

| Feature | JavaScriptCore (JSC) | Google V8 | Custom Engine | QuickJS |
| :--- | :--- | :--- | :--- | :--- |
| **Origin** | Apple (WebKit) | Google (Chromium) | N/A | Fabrice Bellard |
| **macOS Native** | **Yes** (Framework) | No (Requires Bundle) | Yes | No (Static Link) |
| **Startup Speed** | Ultra-Fast (Tiered JIT) | Fast (Ignition) | Slow (No JIT) | **Instant** (Interpreter) |
| **Peak Throughput**| Very High (FTL JIT) | **Highest** (TurboFan) | Very Low | Low |
| **Memory (Idle)**| ~4-8 MB (Shared) | ~15-30 MB | Low | **< 1 MB** |
| **Platform Optimization** | Deep Apple Silicon | Generic ARM64 | None | Generic |
| **Complexity** | Low (Bridged) | Extreme (C++ CGO) | Impossible | Low (Pure C) |

## 2. Why JavaScriptCore (JSC) is the Primary Engine

### A. The "Home Court" Advantage
JSC is built specifically for Apple's UMA (Unified Memory Architecture) and instruction sets. Since **Metal** is a macOS-exclusive browser, using the engine Apple engineers optimize for battery life and M-series performance is strictly better than using V8.

### B. OS Integration
JSC is a system framework. This means it doesn't count against our total binary size, and its memory footprint is managed by the OS more efficiently than a custom-linked binary.

### C. Tiered Compilation
JSC uses a 4-tier compilation strategy:
1.  **LLInt** (Low Level Interpreter) - Starts instantly.
2.  **Baseline JIT** - For warm code.
3.  **DFG JIT** (Data Flow Graph) - High optimization.
4.  **FTL JIT** (Faster Than Light) - Uses LLVM for peak performance.

## 3. The QuickJS Hybrid Strategy

While JSC is great for active tabs, keeping a separate JSC context for 50+ tabs consumes significant RAM (~500+ MB).

### The "Hibernation" Protocol:
1.  **Tab Active**: Run full **JavaScriptCore** for maximum speed.
2.  **Tab Backgrounded (> 30s)**:
    *   Serialize essential state (global variables, timers).
    *   Swap the context to **QuickJS**.
    *   Free the JSC memory back to the OS.
3.  **Tab Restored**:
    *   Restore state back to JSC.
    *   User experiences zero lag and we save **90% RAM** in the background.

## 4. Why Not V8?
- **Binary Bloat**: V8 would add ~25 MB to our app.
- **Memory Greed**: V8's GC and JIT are tuned for server-level or "performance at any cost" scenarios, which runs contrary to our "Minimalist & Efficient" target.
- **Complexity**: V8 uses a custom build system (GN/Ninja) that is extremely difficult to bridge with Zig's `build.zig`.

## 5. Conclusion
Metal will use **JavaScriptCore** as its primary engine via the `JavaScriptCore.framework` bridge, supplemented by **QuickJS** for intelligent background tab management. This achieves the world-class performance of a Tier-1 browser with the resource footprint of a modern native macOS app.
