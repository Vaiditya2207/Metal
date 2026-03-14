# Metal Browser Engine - Visual Fidelity Progress Report

## Achieved So Far
- **VR-1 to VR-4**: Fixed alpha blending, background shorthand reset, scissor reset, and UA form styles.
- **VR-5**: Added visual correctness tests for display list and backgrounds.
- **VR-6**: `measureIntrinsicWidth` respects `min-width` on auto-width children.
- **VR-7**: Fixed SVG rendering in the screenshot pipeline by properly initializing the `svg_cache`.
- **VR-8**: Fixed input button text centering by calculating centered text coordinates based on `text-align` property instead of defaulting to a 4px inset.
- **VR-12**: Corrected `line-height: normal` to use accurate CoreText font metrics `(ascent + descent + leading) / font_size` instead of a hardcoded `1.2` multiplier, eliminating 1px cascading vertical shifts.
- **VR-13**: Fixed CSS pseudo-class matching (`:focus`, `:hover`) which was leaking styles to the default state, resolving phantom blue borders on input fields.
- **VR-14**: Fixed inline layout `shiftBox` not translating `text_runs`, correctly rendering previously misplaced inline-block text.
- **VR-9 (Partial)**: Implemented base `border-radius` support in the Metal GPU rect pipeline using a fragment shader `smoothstep` discard.

Overall, the visual pixel-perfect match rate on the Google homepage (`snapshot.html`) has increased from an initial baseline of **~97.98%** to **98.71%**. All 650 tests are passing.

## Remaining Issues to Tackle
1. **Indic Script Glyphs (~2,100 pixels)**: The "Google offered in:" section renders garbled text because the current glyph atlas in `text_atlas.m` only generates ASCII characters. Needs font fallback or extended Unicode block support (Devanagari, Bengali, Telugu, etc.).
2. **Sub-pixel Text Positioning & Anti-aliasing (~2,500 pixels)**: Differences between Chrome's Skia native sub-pixel text rendering and Metal's half-pixel snapped texture atlas approach cause minor edge differences in font rendering.
3. **Advanced Border Radius & Clipping**: The current border-radius implementation applies one radius to all corners. Advanced CSS shapes might require per-corner radii and proper clipping of child elements within rounded borders.
4. **Header Sign-in Button Combinators**: CSS child combinators (`>`) and specific `border-radius` pill shapes for the sign-in button need further refinement in the CSS parser.