# WALKTHROUGH - Tokenizer State Split

This change splits `src/dom/tokenizer_states.zig` into two files to comply with the project's line count limit (~200 lines per file).

## Changes

### 1. State Separation
- Created `src/dom/tokenizer_attr_states.zig` to house attribute-related state handlers.
- Retained core and special states in `src/dom/tokenizer_states.zig`.
- Logical line counts (excluding blanks and comments):
    - `src/dom/tokenizer_states.zig`: 163 lines
    - `src/dom/tokenizer_attr_states.zig`: 146 lines

### 2. Tokenizer Integration (`src/dom/tokenizer.zig`)
- Updated `Tokenizer` to import both state files.
- Refactored the state machine dispatch in `next()` to call handlers from the appropriate file:
    - Attribute states (e.g., `.before_attribute_name`, `.attribute_value_unquoted`) now call `attr_states`.
    - Core states (e.g., `.data`, `.tag_name`, `.rawtext`) continue to call `states`.

### 3. Module Exports (`src/dom/mod.zig`)
- Added `pub const tokenizer_attr_states = @import("tokenizer_attr_states.zig");` to the DOM barrel file for consistency with existing patterns.

## Verification Results

### Test Output
```
Build Summary: 3/3 steps succeeded; 340/340 tests passed
test success
+- run test 340 passed 701ms MaxRSS:11M
   +- compile test Debug native success 3s MaxRSS:329M
```

### Line Counts (Logical Lines)
- `src/dom/tokenizer_states.zig`: 163
- `src/dom/tokenizer_attr_states.zig`: 146
- Total: 309 logical lines (previously 306+ in a single file).

### Compliance
- No new dependencies added.
- No changes to function signatures or public APIs.
- No tests modified.
- All 340 tests passing with 0 memory leaks.
