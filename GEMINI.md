# Metal Browser Engine — Project Context

Metal is a high-performance, macOS-native web browser and engine built exclusively for Apple Silicon using the **Zig** programming language. It features a custom rendering engine built from the ground up using the Apple Metal API for GPU acceleration.

## Project Overview

- **Goal:** A modern, lightweight, deeply integrated browser for macOS with a target idle RSS of < 30MB.
- **Architecture:** Multi-process model (UI, Renderer, GPU, ML).
- **Core Engine:** Custom HTML parser, CSS resolver, and Layout engine (Block, Inline, Flexbox, Positioning).
- **Rendering:** GPU-accelerated pipeline using Metal API (target 120Hz ProMotion).
- **JavaScript:** Integrated via JavaScriptCore (JSC) with custom DOM bindings.
- **Networking:** Built on `NSURLSession` for native macOS performance and security.

## Key Technologies

- **Zig 0.14.0+**
- **Apple Metal API** (Shaders in `.metal`, Objective-C bridges)
- **JavaScriptCore** (via C-bridge)
- **AppKit / Foundation / CoreText / ImageIO** (macOS Frameworks)
- **Apple Silicon Optimization** (Unified Memory Architecture focus)

## Directory Structure

- `src/`: Core source code.
  - `dom/`: HTML tokenizer, tree builder, and Node definitions.
  - `css/`: CSS tokenizer, parser, selector matching, and style resolution.
  - `layout/`: Layout engine (Box model, Block/Inline/Flex/Positioning).
  - `render/`: Metal-based renderer, display lists, and text atlas.
  - `js/`: JavaScriptCore bindings, event dispatch, and DOM APIs.
  - `net/`: Networking, resource loader, and cookie management.
  - `platform/`: Low-level macOS/Metal/JSC bridges (Zig + ObjC).
  - `ui/`: User interface components and tab management.
- `docs/`: Technical specifications, architecture, and phase checklists.
- `resources/`: Assets, default configuration, and demo HTML files.
- `tests/`: Unit tests, fidelity tests, and visual regression tests.

## Building and Running

### Core Commands
- `zig build run`: Build and run the browser. Accepts an optional URL or file path.
- `zig build test`: Run the comprehensive unit test suite (550+ tests).
- `zig build test-fidelity`: Run cross-browser fidelity tests.

### Tooling
- `zig build dump_dom`: Build a tool to dump the DOM of a page for comparison.
- `zig build render-screenshot`: Build a tool for visual regression testing.

## CI/CD and Release Process

### Workflows
- **Zig Engine Unit Tests (`zig-engine-tests.yml`):** Runs on PRs and pushes to `main`/`develop`. Executes all internal Zig logic tests using `zig build test`.
- **DOM Fidelity Tests (`dom-fidelity-tests.yml`):** Runs on PRs and pushes to `main`/`develop`. Compares Metal's DOM tree against reference browsers (Chrome/Safari) using Puppeteer.
- **Visual Fidelity Tests (`visual-fidelity-tests.yml`):** Runs on PRs and pushes to `main`/`develop`. Performs pixel-by-pixel rendering comparisons.
- **Production Release (`production-release.yml`):** Triggered by merges to `main` or manual `workflow_dispatch`.
    - Automated building of production-ready binaries (`ReleaseFast`).
    - Automatic creation of GitHub Releases with Apple Silicon ZIP artifacts.

### Mandatory Release Procedure
When preparing a release for `main`:
1. Use `scripts/update_version.sh <new_version>` to synchronize versions across `build.zig.zon`, `package.json`, and `src/main.zig`.
2. Update `CHANGELOG.md` with the new version and its corresponding changes.
3. Commit and push/merge these changes to `main` to trigger the production deployment.
4. **DO NOT BYPASS:** Every merge to `main` must correspond to a version/changelog update to ensure traceability and correct artifact generation.


## Development Conventions

- **Memory Management:** Extensive use of `ArenaAllocator` for per-document/per-tab lifecycles to ensure zero-leak navigation.
- **Performance:** Target 8.33ms frame budget (120Hz). Avoid blocking the main UI thread.
- **Interop:** Heavy use of Objective-C bridges (`.m` files) for macOS system services.
- **Testing:** New features must include unit tests in `tests/` and pass fidelity checks.
- **Architecture:** Follow the Multi-process model described in `docs/architecture.md`.

## Current Status (Phase 6/7)

- [x] Phase 0-4: Toolchain, Windowing, DOM, CSS, Layout (Complete).
- [/] Phase 5: GPU Rasterizer (Advanced, supports SDF borders, MSDF-like text).
- [/] Phase 6: JS Bindings (In Progress, basic DOM APIs, Timers, Events active).
- [/] Phase 7: Networking (In Progress, `NSURLSession` fetch and Resource Loader active).
- [/] Phase 8: User Input (Basic scrolling, navigation, and URL bar active).

Refer to `docs/phase_checklist.md` for the detailed roadmap and `docs/architecture.md` for system design.
