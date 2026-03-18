#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGES_DIR="$SCRIPT_DIR/pages"
RESULTS_DIR="$SCRIPT_DIR/results"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

THRESHOLD_FLAG=""
SKIP_BUILD=0
MODE=""
TARGETS=()
FAIL_UNDER=""

for arg in "$@"; do
    case "$arg" in
        --threshold=*)
            THRESHOLD_FLAG="$arg"
            ;;
        --fail-under=*)
            FAIL_UNDER="${arg#--fail-under=}"
            ;;
        --skip-build)
            SKIP_BUILD=1
            ;;
        --all)
            MODE="all"
            ;;
        --snapshot)
            MODE="snapshot"
            ;;
        --help|-h)
            MODE="help"
            ;;
        *)
            TARGETS+=("$arg")
            ;;
    esac
done

if [[ -z "$MODE" && ${#TARGETS[@]} -eq 0 ]]; then
    MODE="help"
fi

if [[ "$MODE" == "help" ]]; then
    echo "Usage:"
    echo "  ./run_visual_test.sh <html_file_or_url>   Run visual test on a single page"
    echo "  ./run_visual_test.sh --all                 Run visual tests on all pages/"
    echo "  ./run_visual_test.sh --snapshot            Re-test existing snapshot.html"
    echo ""
    echo "Flags:"
    echo "  --threshold=N    Pass through to visual_compare.js (0..1, default 0.1)"
    echo "  --fail-under=N   Exit non-zero if match percentage is below N"
    echo "  --skip-build     Skip the 'zig build render-screenshot' step"
    echo ""
    echo "Available test pages:"
    ls "$PAGES_DIR"/*.html 2>/dev/null || echo "  (none)"
    exit 0
fi

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

BUILD_DONE=0
declare -a SUMMARY_NAMES=()
declare -a SUMMARY_MATCHES=()
VISUAL_FAILED=0

# ---------------------------------------------------------------------------
# Build render-screenshot (once)
# ---------------------------------------------------------------------------

ensure_build() {
    if [[ "$SKIP_BUILD" -eq 1 ]]; then
        echo "[build] Skipping render-screenshot build (--skip-build)"
        return
    fi
    if [[ "$BUILD_DONE" -eq 1 ]]; then
        return
    fi
    echo ""
    echo "========================================"
    echo "  Building render-screenshot"
    echo "========================================"
    (cd "$PROJECT_ROOT" && zig build render-screenshot)
    BUILD_DONE=1
}

# ---------------------------------------------------------------------------
# Run a single visual test
#   $1 = input (html file or URL)
#   $2 = if "skip-chrome", skip the Chrome dump step
#   $3 = basename override (optional)
#   $4 = chrome png override (optional)
#   $5 = snapshot html override (optional)
# ---------------------------------------------------------------------------

run_visual() {
    local input="$1"
    local skip_chrome="$2"
    local base_name="$3"
    local chrome_png_override="$4"
    local snapshot_override="$5"

    # Derive base_name if not provided
    if [[ -z "$base_name" ]]; then
        if [[ "$input" == http* ]]; then
            base_name="$(echo "$input" | sed -E 's|https?://||; s|/.*||; s|\.|-|g')"
        else
            base_name="$(basename "$input" .html)"
        fi
    fi

    echo ""
    echo "========================================"
    echo "  Visual Test: $base_name"
    echo "========================================"

    # --- Step 1: Chrome screenshot ---
    local chrome_png="${chrome_png_override:-$RESULTS_DIR/${base_name}_chrome.png}"
    local snapshot_html="${snapshot_override:-$RESULTS_DIR/${base_name}_snapshot.html}"

    if [[ "$skip_chrome" != "skip-chrome" ]]; then
        echo "[Step 1] Chrome screenshot..."
        if node "$SCRIPT_DIR/chrome_dump.js" "$input" "$RESULTS_DIR" --name="$base_name"; then
            echo "[Step 1] Chrome done."
        else
            echo "[Step 1] WARNING: Chrome dump failed — skipping this test"
            SUMMARY_NAMES+=("$base_name")
            SUMMARY_MATCHES+=("SKIP (chrome failed)")
            return
        fi
    else
        echo "[Step 1] Skipping Chrome dump (using existing screenshot)"
    fi

    # Verify Chrome screenshot exists
    if [[ ! -f "$chrome_png" ]]; then
        echo "[ERROR] Chrome screenshot not found: $chrome_png"
        SUMMARY_NAMES+=("$base_name")
        SUMMARY_MATCHES+=("SKIP (no chrome png)")
        return
    fi

    # --- Step 2: Build render-screenshot ---
    echo "[Step 2] Ensuring render-screenshot is built..."
    ensure_build

    # --- Step 3: Metal screenshot ---
    # Use the snapshot HTML (resolved by Chrome) so both engines render the same thing
    if [[ ! -f "$snapshot_html" ]]; then
        echo "[ERROR] Snapshot HTML not found: $snapshot_html"
        SUMMARY_NAMES+=("$base_name")
        SUMMARY_MATCHES+=("SKIP (no snapshot)")
        return
    fi

    local metal_png="$RESULTS_DIR/${base_name}_metal.png"
    echo "[Step 3] Metal screenshot from $(basename "$snapshot_html")..."
    "$PROJECT_ROOT/zig-out/bin/render_screenshot" "$snapshot_html" "$metal_png"
    echo "[Step 3] Metal done: $metal_png"

    # --- Step 4: Pixel diff ---
    local diff_png="$RESULTS_DIR/${base_name}_diff.png"
    echo "[Step 4] Comparing screenshots..."
    local compare_output
    compare_output=$(node "$SCRIPT_DIR/visual_compare.js" "$chrome_png" "$metal_png" "$diff_png" $THRESHOLD_FLAG 2>&1)
    echo "$compare_output"

    # Extract match percentage
    local match_pct
    match_pct=$(echo "$compare_output" | grep -o 'Match: [0-9.]*%' | grep -o '[0-9.]*%' || echo "??%")
    local match_val
    match_val=$(echo "$match_pct" | tr -d '%')
    if [[ -n "$FAIL_UNDER" ]]; then
        if awk "BEGIN {exit !($match_val < $FAIL_UNDER)}"; then
            SUMMARY_NAMES+=("$base_name")
            SUMMARY_MATCHES+=("$match_pct FAIL")
            VISUAL_FAILED=1
        else
            SUMMARY_NAMES+=("$base_name")
            SUMMARY_MATCHES+=("$match_pct PASS")
        fi
    else
        SUMMARY_NAMES+=("$base_name")
        SUMMARY_MATCHES+=("$match_pct")
    fi

    echo "[Step 4] Diff saved: $diff_png"
}

# ---------------------------------------------------------------------------
# Execute based on mode
# ---------------------------------------------------------------------------

if [[ "$MODE" == "snapshot" ]]; then
    # --snapshot: use existing chrome_screenshot.png and snapshot.html
    run_visual \
        "$RESULTS_DIR/snapshot.html" \
        "skip-chrome" \
        "snapshot" \
        "$RESULTS_DIR/chrome_screenshot.png" \
        "$RESULTS_DIR/snapshot.html"

elif [[ "$MODE" == "all" ]]; then
    echo ""
    echo "========================================"
    echo "  Running ALL visual tests"
    echo "========================================"

    # Build once up front
    ensure_build

    for page in "$PAGES_DIR"/*.html; do
        [ -f "$page" ] || continue
        run_visual "$page" "" "" "" ""
    done

else
    # Single target(s)
    for target in "${TARGETS[@]}"; do
        run_visual "$target" "" "" "" ""
    done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Visual Test Summary"
echo "========================================"

# Determine column width for page names
local_max=24
for name in "${SUMMARY_NAMES[@]}"; do
    if [[ ${#name} -gt $local_max ]]; then
        local_max=${#name}
    fi
done

printf "  %-${local_max}s  %s\n" "Page" "Match"
for i in "${!SUMMARY_NAMES[@]}"; do
    printf "  %-${local_max}s  %s\n" "${SUMMARY_NAMES[$i]}" "${SUMMARY_MATCHES[$i]}"
done

echo "========================================"
echo ""

if [[ "$VISUAL_FAILED" -eq 1 ]]; then
    exit 2
fi
