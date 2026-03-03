# Phase Checklist — Metal Browser Engine
> Living document. Mark items `[/]` when in progress, `[x]` when done.

---

## Phase 0 — Toolchain Bootstrap *(~1 week)* [x]

### Setup
- [ ] Install Zig 0.14+ via `brew install zig` or official tarball
- [ ] Verify `zig version` on Apple Silicon

### Build System
- [ ] Create `build.zig` with `aarch64-macos` target
- [ ] Add C/ObjC compilation step (`addCSourceFiles`)
- [ ] Link frameworks: `AppKit`, `Metal`, `MetalKit`, `QuartzCore`, `JavaScriptCore`
- [ ] Create `build.zig.zon` package manifest
- [ ] Verify `@cImport` works for `<Cocoa/Cocoa.h>` and `<Metal/Metal.h>`

### Project Structure
- [ ] Create directory tree:
  ```
  src/{main.zig, platform/, dom/, css/, layout/, render/, js/, net/, ipc/, ui/, devtools/, ml/}
  resources/{shaders/, fonts/}
  tests/
  ```
- [ ] `main.zig` — entry point that prints startup banner and exits
- [ ] Add `.gitignore` for `zig-out/`, `zig-cache/`, `.DS_Store`

### Verification
- [ ] `zig build` succeeds with zero errors
- [ ] `zig build run` prints banner and exits cleanly

---

## Phase 1 — Native Window & Metal Surface *(~1–2 weeks)* [x]

### ObjC Bridge (`src/platform/`)
- [x] `app.zig` — `NSApplication` setup, run loop
- [x] `window.zig` — `NSWindow` creation (title, size, style)
- [x] `metal_view.zig` — `MTKView` delegate, `drawInMTKView` callback
- [x] `objc_bridge.m` — ObjC implementations for delegate protocols

### Metal Setup (`src/render/`)
- [x] Acquire `MTLDevice` (system default)
- [x] Create `MTLCommandQueue`
- [x] Implement clear-color render pass (solid background)
- [x] Sync to display refresh (`CVDisplayLink` or `MTKViewDelegate`)

### QoS Threading
- [x] Set render thread to `QOS_CLASS_USER_INTERACTIVE`
- [x] Verify with `Activity Monitor` → thread QoS column

### Verification
- [x] Window opens with title "Metal"
- [x] Solid color clears at 60/120 Hz (no tearing)
- [x] RSS < 20 MB idle
- [x] Profile: GPU utilization visible in Xcode Instruments (Metal System Trace)

---

## Phase 2 — HTML Tokenizer & DOM Tree *(~2–3 weeks)* [x]

### HTML Tokenizer (`src/dom/tokenizer.zig`)
- [x] State machine: Data, TagOpen, TagName, Attribute, SelfClosing, EndTag
- [x] Emit tokens: StartTag, EndTag, Character, EOF
- [x] Handle entities: `&amp;`, `&lt;`, `&gt;`, `&quot;` (via `entity.zig`)
- [x] Error recovery: unclosed tags, mismatched nesting

### DOM Tree (modular split)
- [x] `tag.zig`: TagName enum with `fromString()` and `isVoid()`
- [x] `node.zig`: Node, NodeType, DomAttribute, tree operations
- [x] `document.zig`: Document, Limits, arena lifecycle
- [x] `mod.zig`: Barrel file re-exporting all public types

### Tree Builder (`src/dom/builder.zig`)
- [x] Consume token stream → build DOM tree
- [x] Handle implicit elements (`<html>`, `<head>`, `<body>`)
- [x] API: `parseHTML(allocator, html_bytes) -> *Document`

### Tests (`tests/dom/`)
- [x] Tokenizer: 150+ test cases (valid HTML, malformed, XSS, fuzzing)
- [x] Tree: 8 test cases (document, node, relationships, queries)
- [x] Builder: 10 test cases (parsing, implicit elements, void elements)
- [x] Fuzz: 100+ random byte sequences don't crash the tokenizer


---

## Phase 3 — CSS Parser & Style Resolution *(~2–3 weeks)*

### CSS Tokenizer (`src/css/tokenizer.zig`)
- [ ] Tokens: Ident, Hash, String, Number, Delim, Whitespace, Colon, Semicolon, LeftBrace, RightBrace, etc.
- [ ] Handle comments `/* */`

### CSS Parser (`src/css/parser.zig`)
- [ ] Parse selectors: tag, `.class`, `#id`, descendant ` `, child `>`, `,` list
- [ ] Parse declarations: `property: value;`
- [ ] Parse `<style>` blocks and inline `style=""` attributes
- [ ] Property value types: Length (px, em, %), Color (hex, named, rgb), Keyword

### Supported Properties (initial set)
- [ ] `display` (block, inline, none, flex)
- [ ] `width`, `height`, `min-*`, `max-*`
- [ ] `margin`, `padding` (shorthand + individual)
- [ ] `border`, `border-radius`
- [ ] `color`, `background-color`, `background`
- [ ] `font-size`, `font-family`, `font-weight`
- [ ] `position`, `top`, `right`, `bottom`, `left`
- [ ] `overflow`, `z-index`, `opacity`

### Style Resolution (`src/css/resolver.zig`)
- [ ] Cascade: user-agent → author → inline styles
- [ ] Specificity calculation (a, b, c, d)
- [ ] Inheritance: propagate inheritable properties (color, font-*)
- [ ] `StyledNode` tree: DOM node + resolved computed style

### Tests
- [ ] CSS tokenizer: 15+ test cases
- [ ] Specificity: verify ordering of conflicting rules
- [ ] Inheritance: child inherits `color` from parent
- [ ] Integration: HTML + CSS → correct computed styles on nodes

---

## Phase 4 — Layout Engine (Box Model) *(~3–4 weeks)*

### Box Generation (`src/layout/box.zig`)
- [ ] `LayoutBox`: `(x, y, width, height)`, margin/padding/border edges
- [ ] Map `display: block | inline | none` → box types
- [ ] Anonymous block/inline boxes for mixed content

### Block Layout (`src/layout/block.zig`)
- [ ] Width: resolve from parent containing block
- [ ] Height: determined by children content
- [ ] Vertical margin collapsing (adjacent siblings, parent-child)
- [ ] `auto` margins for centering

### Inline Layout (`src/layout/inline.zig`)
- [ ] Line box generation
- [ ] Word wrapping (break at whitespace)
- [ ] `text-align`: left (start with left-only)
- [ ] Inline-level element boxes within line boxes

### Positioning (`src/layout/position.zig`)
- [ ] `position: relative` — offset from normal flow
- [ ] `position: absolute` — offset from nearest positioned ancestor
- [ ] `position: fixed` — offset from viewport

### Flexbox (`src/layout/flex.zig`)
- [ ] `flex-direction`: row, column
- [ ] `justify-content`: flex-start, center, space-between
- [ ] `align-items`: stretch, center, flex-start, flex-end
- [ ] `flex-grow`, `flex-shrink`, `flex-basis`

### Tests
- [ ] Block layout: div(width:200px, padding:10px) → total width = 220px
- [ ] Margin collapsing: two blocks with margin 20px → gap = 20px not 40px
- [ ] Inline: text wraps correctly at container boundary
- [ ] Flexbox: 3 items with `justify-content: space-between` → correct spacing
- [ ] Visual test: render layout tree as colored rectangles on Metal surface

---

## Phase 5 — GPU Rasterizer & MSDF Text *(~3–4 weeks)*

### Rectangle Renderer (`src/render/rect.zig`)
- [ ] Metal render pipeline: vertex + fragment shaders
- [ ] Vertex format: position (x, y), color (rgba), border params
- [ ] Emit 2 triangles per layout box → vertex buffer
- [ ] Fragment shader: solid fill + border + border-radius (SDF)
- [ ] Batch all quads into single draw call

### MSDF Text Pipeline (`src/render/text.zig`)
- [ ] Integrate HarfBuzz (C library) for text shaping
- [ ] Generate MSDF font atlas (build-time tool, `msdfgen`)
- [ ] Atlas texture: load as `MTLTexture` (RGB = distance channels)
- [ ] Vertex buffer: 2 triangles per glyph (position + UV)
- [ ] Fragment shader: sample MSDF, compute alpha from distance field
- [ ] Subpixel positioning for crisp text at all sizes

### Image Rendering (`src/render/image.zig`)
- [ ] Decode JPEG/PNG via `ImageIO.framework`
- [ ] Upload decoded bitmap as `MTLTexture`
- [ ] Render as textured quad in the existing pipeline
- [ ] Sparse textures for large images (Metal 3)

### Shader Sources (`resources/shaders/`)
- [ ] `rect.metal` — rectangle vertex + fragment shaders
- [ ] `msdf_text.metal` — MSDF text fragment shader
- [ ] `image.metal` — textured quad shader
- [ ] `composite.metal` — final compositing pass

### Tests
- [ ] Render `<h1>Hello</h1><p>Paragraph text</p>` — text is crisp at 2× Retina
- [ ] Zoom 4× — text remains sharp (MSDF)
- [ ] Render colored divs with borders and border-radius
- [ ] Frame time < 2 ms on M1 for simple page (measured via Metal GPU profiler)

---

## Phase 6 — JavaScript Engine Binding *(~3–4 weeks)*

### JavaScriptCore Integration (`src/js/jsc.zig`)
- [ ] Link `JavaScriptCore.framework`
- [ ] Create `JSGlobalContextRef` per tab
- [ ] `JSEvaluateScript()` — execute JS strings
- [ ] Inject native functions via `JSObjectMakeFunctionWithCallback`
- [ ] Error handling: catch JS exceptions, surface to console

### QuickJS Integration (`src/js/quickjs.zig`)
- [ ] Vendor QuickJS C source (or use `zig-quickjs-ng`)
- [ ] Create `JSRuntime` + `JSContext` per tab
- [ ] `JS_Eval()` — execute JS strings
- [ ] Inject native functions via `JS_NewCFunction`

### DOM Bindings (`src/js/dom_bindings.zig`)
- [ ] `document.getElementById(id)` → DOM node lookup
- [ ] `document.querySelector(selector)` → CSS selector match
- [ ] `document.createElement(tag)` → allocate new node
- [ ] `node.appendChild(child)` → tree manipulation
- [ ] `node.removeChild(child)`
- [ ] `node.textContent` (get/set)
- [ ] `node.innerHTML` (get/set → re-parse)
- [ ] `node.setAttribute(name, value)`
- [ ] `node.addEventListener(event, callback)`

### Timer APIs (`src/js/timers.zig`)
- [ ] `setTimeout(fn, ms)` / `clearTimeout`
- [ ] `setInterval(fn, ms)` / `clearInterval`
- [ ] `requestAnimationFrame(fn)`

### Console (`src/js/console.zig`)
- [ ] `console.log()`, `.warn()`, `.error()` → native log output

### Engine Switching
- [ ] JSC → QuickJS state migration for backgrounded tabs
- [ ] Serialize essential state (variables, pending timers)

### Tests
- [ ] `document.getElementById('x').textContent = 'Hello'` → text updates on screen
- [ ] `addEventListener('click', fn)` → click div → callback fires
- [ ] `setTimeout(() => ..., 100)` → fires after ~100 ms
- [ ] QuickJS context < 500 KB RSS
- [ ] JSC context cold-start < 5 ms

---

## Phase 7 — Networking & Resource Loader *(~2–3 weeks)*

### Network Layer (`src/net/session.zig`)
- [ ] ObjC bridge for `NSURLSession` (shared session)
- [ ] `fetch(url) -> Response` — async callback-based
- [ ] HTTP/1.1 and HTTP/2 (automatic via NSURLSession)
- [ ] HTTPS with system certificate store
- [ ] Response streaming (chunked data to parser)

### Resource Loader (`src/net/loader.zig`)
- [ ] Pipeline: URL → fetch → parse → discover sub-resources → fetch children
- [ ] Priority: HTML > CSS > fonts > JS > images
- [ ] Sub-resource discovery from DOM: `<link>`, `<script src>`, `<img src>`, `@import`
- [ ] Parallel fetching with concurrency limit

### Cookie Jar (`src/net/cookies.zig`)
- [ ] Parse `Set-Cookie` headers
- [ ] Send matching cookies on requests
- [ ] Persistent storage (per-profile)
- [ ] `HttpOnly`, `Secure`, `SameSite` enforcement

### Cache (`src/net/cache.zig`)
- [ ] Volatile arena cache (first-visit assets)
- [ ] Persistent disk cache (committed after ML approval or repeat visit)
- [ ] `Cache-Control`, `ETag`, `Last-Modified` support
- [ ] Cache size limit with LRU eviction

### Tests
- [ ] Fetch `http://example.com` → receive HTML
- [ ] Sub-resource loading: page with CSS + image renders fully
- [ ] Close tab → arena freed, RSS drops
- [ ] Cookie round-trip: set on response → sent on next request

---

## Phase 8 — Event Loop & User Input *(~2–3 weeks)*

### Event System (`src/platform/events.zig`)
- [ ] Bridge `NSEvent` → internal `Event` union (Click, Scroll, KeyDown, KeyUp, MouseMove)
- [ ] Event dispatch queue integrated with render loop

### Hit Testing (`src/layout/hit_test.zig`)
- [ ] Screen coordinates → layout box → DOM node
- [ ] Traverse layout tree in paint order (z-index aware)
- [ ] Return topmost interactive node

### Scrolling (`src/render/scroll.zig`)
- [ ] Content overflow detection
- [ ] Smooth scroll with momentum (trackpad physics)
- [ ] Scroll offset → viewport transform in Metal
- [ ] Scroll bar rendering (native-style overlay)

### Navigation
- [ ] Click `<a href="...">` → trigger page load
- [ ] Form submission (GET)
- [ ] `history.pushState` / `popState` (basic)

### Text Input (`src/ui/input.zig`)
- [ ] `<input type="text">` — cursor, character insertion, deletion
- [ ] `<textarea>` — multi-line input
- [ ] Clipboard: ⌘C, ⌘V, ⌘X
- [ ] Text selection (click-drag, ⌘A)

### Cursor
- [ ] Arrow cursor (default)
- [ ] Pointer cursor (over links)
- [ ] Text cursor (over input fields)

### Tests
- [ ] Click link → navigate to new page
- [ ] Scroll long page smoothly at 120 Hz
- [ ] Type into input field → characters appear
- [ ] ⌘V paste → text inserted
- [ ] Hit test: clicking nested elements targets correct node

---

## Phase 9 — Process Isolation & IPC *(~3–4 weeks)*

### Process Spawning (`src/ipc/process.zig`)
- [ ] Fork renderer processes via `posix_spawn`
- [ ] Each renderer has own arena, JS context, DOM
- [ ] Configure App Sandbox entitlements per process

### Mach Ports (`src/ipc/mach.zig`)
- [ ] Create Mach port pairs (send + receive)
- [ ] Message types: Navigate, Resize, Close, InputEvent, FrameReady
- [ ] Secure port transfer between UI and renderer

### Shared Memory (`src/ipc/shm.zig`)
- [ ] `shm_open` + `mmap` for zero-copy vertex buffers
- [ ] Lock-free ring buffer protocol
- [ ] Atomic signaling (renderer done writing → GPU can read)

### IOSurface Compositing (`src/ipc/iosurface.zig`)
- [ ] Renderer creates `IOSurface` for its framebuffer
- [ ] Transfer IOSurface handle via Mach port to UI process
- [ ] UI process composites all tab surfaces into final frame

### Crash Handling
- [ ] Detect renderer crash (SIGCHLD / Mach exception port)
- [ ] Show "tab crashed" page in UI
- [ ] Offer reload
- [ ] No other tabs affected

### Tests
- [ ] Crash renderer → UI stays alive
- [ ] `Activity Monitor` shows separate processes
- [ ] Frame time unchanged vs single-process (zero-copy validated)
- [ ] Sandbox prevents renderer from reading ~/Desktop

---

## Phase 10 — Tab Manager & Browser Chrome *(~2–3 weeks)*

### Tab Bar (`src/ui/tab_bar.zig`)
- [ ] Metal-rendered tabs with smooth open/close animations
- [ ] Tab title from `<title>` element
- [ ] Favicon display
- [ ] Close button per tab
- [ ] Tab drag reordering

### URL Bar (`src/ui/url_bar.zig`)
- [ ] `NSTextField` embedded in chrome
- [ ] Show current URL
- [ ] Edit → Enter → navigate
- [ ] Autocomplete from history

### Navigation Controls (`src/ui/nav.zig`)
- [ ] Back / Forward buttons (per-tab history stack)
- [ ] Reload button
- [ ] Stop loading button
- [ ] Loading progress indicator

### Background Tab Management
- [ ] JSC → QuickJS swap after 30s background
- [ ] Arena compression (`madvise` to release physical pages)
- [ ] RSS target: < 2 MB per compressed background tab

### Keyboard Shortcuts
- [ ] ⌘T — new tab
- [ ] ⌘W — close tab
- [ ] ⌘L — focus URL bar
- [ ] ⌘R — reload
- [ ] ⌘[ / ⌘] — back / forward
- [ ] ⌘1–⌘9 — switch to tab N

### Tests
- [ ] Open 50 tabs → RSS < 1 GB
- [ ] Switch tab → instant restore (< 50 ms)
- [ ] Close tab → RSS drops proportionally
- [ ] Back/forward navigates correctly
- [ ] All keyboard shortcuts work

---

## Phase 11 — Predictive Caching & ML *(~3–4 weeks)*

### Browsing History Graph (`src/ml/history.zig`)
- [ ] Record navigation edges: (source_url, target_url, timestamp)
- [ ] SQLite or custom arena-backed graph structure
- [ ] Privacy: local-only, per-profile

### Prediction Model (`src/ml/predictor.zig`)
- [ ] Markov chain: transition probability matrix
- [ ] Train incrementally on new navigation events
- [ ] Core ML model export (optional, for ANE acceleration)
- [ ] Confidence threshold tuning (start at 0.7)

### Prefetch Engine (`src/ml/prefetch.zig`)
- [ ] On high-confidence prediction: DNS resolve + TLS handshake + fetch HTML
- [ ] Run on `QOS_CLASS_BACKGROUND` (E-cores)
- [ ] Store prefetched content in volatile arena
- [ ] Cancel prefetch if user navigates elsewhere

### Delayed Cache Commit (`src/net/cache.zig` update)
- [ ] First visit to domain: assets stay in volatile memory only
- [ ] Commit to disk only when domain appears ≥ 2× in history graph
- [ ] Bounce detection: tab closed < 10s → zero disk writes

### Adaptive Throttling
- [ ] Monitor battery level (`IOPSCopyPowerSourcesInfo`)
- [ ] Monitor CPU thermal state
- [ ] Reduce prefetch aggressiveness when resources constrained

### Tests
- [ ] Visit A → B → C loop 10× → 11th time B prefetched
- [ ] Bounce site → zero disk cache footprint
- [ ] `Energy Impact` stays "Low" during prefetching
- [ ] Throttle engages on low battery simulation

---

## Phase 12 — Native Developer Tools *(~4–5 weeks)*

### DOM Inspector (`src/devtools/inspector.zig`)
- [ ] Secondary Metal render pass: box-model overlay (content, padding, border, margin)
- [ ] Hover → highlight element + show dimensions
- [ ] Click → select element
- [ ] Element tree view (native UI panel)
- [ ] Computed styles panel

### JS Console (`src/devtools/console.zig`)
- [ ] REPL: type JS → evaluate → show result
- [ ] `console.log` output stream
- [ ] Error highlighting with stack traces
- [ ] Object inspection (expandable tree)

### JS Debugger (`src/devtools/debugger.zig`)
- [ ] Set breakpoints by line number
- [ ] Step over / step into / step out / continue
- [ ] Variable inspection at break point
- [ ] DAP (Debug Adapter Protocol) server for external IDE integration
- [ ] LLDB bridge for system-level debugging

### Network Monitor (`src/devtools/network.zig`)
- [ ] Log all requests: URL, method, status, timing, size
- [ ] Waterfall visualization
- [ ] Filter by type (HTML, CSS, JS, Image, XHR)
- [ ] Request/response header inspection

### Performance Profiler (`src/devtools/profiler.zig`)
- [ ] Frame time graph (real-time)
- [ ] Layout thrash detection (consecutive style → layout → paint cycles)
- [ ] Memory usage over time
- [ ] Alert on frame drops

### Session Replay (`src/devtools/replay.zig`)
- [ ] Rolling buffer of DOM mutation snapshots
- [ ] Timeline scrubber: step through past states
- [ ] Capture user interactions (clicks, scrolls) with timestamps

### Tests
- [ ] Open DevTools → zero measurable change in page frame time
- [ ] Inspector hover → correct element highlighted
- [ ] JS breakpoint → execution pauses, variables visible
- [ ] Network monitor shows all requests with timing

---

## Phase 13 — LLM Integration (MLX) *(~3–4 weeks)*

### MLX Runtime (`src/ml/llm.zig`)
- [ ] Load quantized model (e.g., Llama-3.1-8B-4bit) via MLX
- [ ] Tokenizer integration
- [ ] Streaming text generation
- [ ] Memory budget: model + 5 tabs < 6 GB total RSS

### Page Summarization (`src/ml/summarize.zig`)
- [ ] Extract visible text content from DOM
- [ ] Feed to LLM with summarization prompt
- [ ] Display summary in sidebar panel
- [ ] Target: < 3 seconds on M1 Pro

### Semantic Search (`src/ml/search.zig`)
- [ ] User query: "find the pricing section"
- [ ] LLM identifies relevant DOM region
- [ ] Scroll to and highlight the matched section

### AI DevTools Copilot (`src/devtools/ai.zig`)
- [ ] Feed DOM tree + error stack to LLM
- [ ] Suggest CSS fixes for broken layouts
- [ ] Identify accessibility violations
- [ ] Highlight elements causing layout thrashing

### MCP Integration (`src/ml/mcp.zig`)
- [ ] Expose browser context via Model Context Protocol
- [ ] Allow external AI tools to query DOM, screenshots, console output

### Tests
- [ ] Summarize Wikipedia article < 3 seconds on M1 Pro
- [ ] AI suggests valid CSS fix for broken layout
- [ ] Semantic search: "pricing" → scrolls to correct section
- [ ] RSS with loaded model stays within budget

---

## Phase 14 — Profiles, Polish & Ship *(~4–6 weeks)*

### Profile System (`src/ui/profiles.zig`)
- [ ] Isolated containers per profile (cookies, localStorage, cache)
- [ ] App Groups for shared engine assets
- [ ] Profile switcher in UI
- [ ] Profile-specific history and bookmarks

### Settings (`src/ui/settings.zig`)
- [ ] Preferences window (native macOS)
- [ ] Default search engine (Google, DuckDuckGo, custom)
- [ ] Privacy controls (clear data, cookie policy, tracking protection)
- [ ] Appearance (light/dark/system)
- [ ] Font size override

### Missing Features
- [ ] Find-in-page (⌘F): highlight matches, navigate between
- [ ] Downloads manager: list, progress, open, reveal in Finder
- [ ] Print support via macOS print system
- [ ] PDF viewing
- [ ] Right-click context menus

### Accessibility
- [ ] VoiceOver support: semantic aria roles exposed to NSAccessibility
- [ ] Keyboard-only navigation (Tab / Shift+Tab / Enter)
- [ ] Dynamic Type: respect system font size

### Release Engineering
- [ ] App icon design
- [ ] `Info.plist` with proper `CFBundleIdentifier`
- [ ] Code signing with Developer ID
- [ ] Notarization via `notarytool`
- [ ] DMG creation with drag-to-Applications
- [ ] Auto-update mechanism (Sparkle or custom)
- [ ] Crash reporting (symbolicated stack traces)

### Final Validation
- [ ] Daily-drive for 1 week → track crashes and missing features
- [ ] Test on M1, M2, M3, M4 (if available)
- [ ] VoiceOver audit: all interactive elements accessible
- [ ] Memory soak: 8 hours with 30 tabs → no unbounded growth
- [ ] Clean install from DMG on fresh macOS
