# Development Guide — Metal Browser Engine

## 1. Toolchain
- **Zig**: 0.14.0 or later.
- **macOS**: 14.0 (Sonoma) or later.
- **Hardware**: Apple Silicon (M1/M2/M3/M4).

## 2. Shared Principles
- **Explicit Allocation**: Functions that allocate must accept an `Allocator`.
- **Zero-Copy**: Prefer passing pointers or shared memory handles over copying data.
- **Safety**: Use Zig's `try`, `catch`, and `errdefer` for robust error handling.
- **Configurability**: Hardcoded values are prohibited for UI and engine parameters. Use JSON or TOML for all settings to facilitate a unified preferences system.

## 3. Objective-C Interop
We use Zig's `@cImport` to bridge with AppKit and Metal.
- Keep the bridge thin.
- Wrap complex ObjC logic in `src/platform/objc_bridge.m` if necessary and expose via simple C functions.

## 4. Rendering Standards
- **Metal 3**: Leverage modern features like sparse textures and unified memory.
- **MSDF**: All text is rendered using Signed Distance Fields for perfect scaling.
- **Frame Budget**: Target 8.33ms (120Hz) for the main render pass.

## 5. Process Isolation
- Renderer processes are sandboxed.
- Communication via Mach ports and shared memory.

## 6. Testing
- `zig build test` runs all unit tests.
- Visual regressions are checked against the `tests/visual/` baseline.
