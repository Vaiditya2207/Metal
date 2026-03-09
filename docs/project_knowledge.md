# Metal Browser Engine - Project Knowledge Base

Based on a detailed exploration of the source code, this document provides a comprehensive overview of the **Metal** project architecture, its core components, control flow, and technical stack. This knowledge base is derived strictly from the codebase itself.

## 1. Project Overview

`Metal` is a lightweight, natively compiled browser engine written in **Zig**, designed specifically for macOS. It builds its own DOM, CSS, and Layout engines from scratch, and leverages native macOS frameworks to provide rendering and JavaScript execution.

- **Primary Language:** Zig
- **Platform Bridging:** Objective-C / C (for macOS frameworks)
- **Rendering API:** Apple Metal (`MTKView`, `MTLRenderCommandEncoder`)
- **JavaScript Engine:** JavaScriptCore (JSC)
- **GUI & Events:** AppKit, Foundation, CoreGraphics, CoreText

The project is structured into modular layers (`dom`, `css`, `layout`, `render`, `js`, `net`, and `platform`), coordinated by a central `main.zig` execution pipeline.

## 2. Core Architecture & Pipeline

The browser engine executes a classic rendering pipeline steps for a given URL or local HTML file:

### 1. Networking (`net/`)
- Uses `net.fetch.FetchClient` and an Objective-C `net_bridge.m` to make HTTP requests. 
- A `ResourceLoader` discovers sub-resources (CSS, JS, Images, Favicons) from the parsed DOM and asynchronously fetches them in parallel.

### 2. DOM Parsing (`dom/`)
- Handles HTML parsing through a custom `Tokenizer` and `TreeBuilder` (`dom/builder.zig`).
- Implements implicit tag insertion (e.g., auto-creating `<html>`, `<head>`, `<body>` when missing) compliant with HTML5 specifications.
- Produces a tree of `Node` elements (Document, Element, Text, Comment).

### 3. CSS Resolution (`css/`)
- A custom CSS parser (`css/parser.zig`) processes User-Agent styles, page `<style>` blocks, and external stylesheets.
- **`StyleResolver`** (`css/resolver.zig`): 
  - Matches selectors against DOM nodes.
  - Sorts matched rules by specificity, `!important` flags, and source order.
  - Substitutes CSS custom properties (e.g., `var(--my-color, red)`).
  - Resolves relative units (`em`, `rem`, `%`) to absolute pixels based on the layout context.
  - Generates a `StyledNode` tree mirroring the DOM.

### 4. Layout Engine (`layout/`)
- The `layoutTree` function (`layout/layout.zig`) converts the `StyledNode` tree into a tree of `LayoutBox` objects.
- Supports multiple layout modes:
  - **Block Layout**: Standard vertical stacking (`block.zig`).
  - **Flexbox Layout**: Modern flex containers and items (`flex.zig`).
  - **Table Layout**: Specialized table grid sizing (`table.zig`).
  - **Inline / Text Layout**: Incorporates text measurement via CoreText bindings (`atlasMeasure`).
- Handles floating elements (left/right floats and clear properties) via a `FloatContext`.

### 5. Display List & Rendering (`render/` & `platform/`)
- The layout tree is flattened into a **Display List** (`render/display_list.zig`), effectively a sequence of primitive draw commands.
- The `Renderer` (`render/renderer.zig`) processes these commands.
- The actual GUI surface is created via `platform/objc_bridge.m` which initializes an `NSWindow` and attaches an `MTKView` (MetalKit View).
- Textures for images are decoded using `ImageIO` and cached in the renderer.

### 6. JavaScript Integration (`js/`)
- Bridges Zig to macOS's native `JavaScriptCore` runtime (`platform/jsc_bridge.m`).
- `js/context.zig` wraps the JSC API, allowing execution of scripts (`<script>` tags mapped heavily to `js.script_runner`).
- Exposes DOM element bindings and a JS `console` (log, warn, error) natively to the environment.

## 3. Directory Layout Details

- `src/main.zig` - The entry point. Handles bootstrapping the app, fetching resources, spinning up the pipeline, and entering the NSApplication run loop.
- `src/dom/` - DOM tree structures (`Document`, `Node`), HTML tokenization and tree-building.
- `src/css/` - CSS Tokenization, rule parsing, styling properties definition, and the style resolver.
- `src/layout/` - Block/Flex/Table/Inline layout mathematical calculations.
- `src/js/` - JavaScriptCore API wrappers, DOM bindings (turning Zig DOM nodes into JS objects), and event dispatcher loops.
- `src/net/` - URL parsing, asynchronous `ResourceLoader`, and platform fetch bindings.
- `src/platform/` - Interfacing files (`.m` and `.h`) wrapping native Apple API classes in C-callable functions, to allow Zig to consume AppKit, Metal, and JSC.
- `tests/` - A comprehensive test suite (`test_runner.zig`) containing tests for CSS flex-box calculations, DOM tokenization rules, etc.

## 4. Build System

- Employs `build.zig`, natively integrated with Zig's build system.
- Compiles the `metal` executable spanning all modular code.
- Explicitly links external macOS Frameworks needed: `AppKit`, `Foundation`, `Metal`, `MetalKit`, `QuartzCore`, `CoreText`, `CoreGraphics`, `JavaScriptCore`, `ImageIO`.
- Uses `test.zig` to run all module-specific unit tests.
