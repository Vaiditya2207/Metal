#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAGES_DIR="$SCRIPT_DIR/pages"
RESULTS_DIR="$SCRIPT_DIR/results"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mkdir -p "$RESULTS_DIR"

# Single page mode: run_test.sh <url_or_file>
# Multi page mode: run_test.sh --all
# Report mode: add --report flag

REPORT_FLAG=""
TOL_FLAG=""
FAIL_FLAG=""
for arg in "$@"; do
    case "$arg" in
        --report) REPORT_FLAG="--report" ;;
        --tol=*) TOL_FLAG="$arg" ;;
        --fail-under=*) FAIL_FLAG="$arg" ;;
    esac
done

run_single() {
    local input="$1"
    local base_name

    if [[ "$input" == http* ]]; then
        base_name="$(echo "$input" | sed -E 's|https?://||; s|/.*||; s|\.|-|g')"
    else
        base_name="$(basename "$input" .html)"
    fi

    echo ""
    echo "========================================"
    echo "  Testing: $base_name"
    echo "========================================"

    # 1. Chrome reference
    echo "[Step 1] Chrome dump..."
    node "$SCRIPT_DIR/chrome_dump.js" "$input" "$RESULTS_DIR" --name="$base_name"

    # 2. Build dump_dom
    echo "[Step 2] Building dump_dom..."
    (cd "$PROJECT_ROOT" && zig build dump_dom)

    # 3. Metal layout
    local snapshot="$RESULTS_DIR/${base_name}_snapshot.html"
    local metal_out="$RESULTS_DIR/${base_name}_metal.json"

    if [ -f "$snapshot" ]; then
        echo "[Step 3] Metal layout for $snapshot..."
        "$PROJECT_ROOT/zig-out/bin/dump_dom" "$snapshot" "$metal_out"
    else
        echo "[Step 3] SKIP — no snapshot found at $snapshot"
    fi
}

if [[ "$1" == "--all" ]]; then
    echo "[Fidelity Suite] Running all test pages..."
    for page in "$PAGES_DIR"/*.html; do
        [ -f "$page" ] || continue
        run_single "$page"
    done
elif [[ -n "$1" && "$1" != "--report" ]]; then
    run_single "$1"
else
    echo "Usage:"
    echo "  ./run_test.sh <html_file_or_url>     Run single test"
    echo "  ./run_test.sh --all                   Run all test pages"
    echo "  ./run_test.sh --all --report          Run all + generate HTML report"
    echo "  ./run_test.sh --all --tol=5           Set layout tolerance in pixels"
    echo "  ./run_test.sh --all --fail-under=95   Exit non-zero if accuracy < 95%"
    echo ""
    echo "Available test pages:"
    ls "$PAGES_DIR"/*.html 2>/dev/null || echo "  (none)"
    exit 0
fi

# 4. Compare
echo ""
echo "========================================"
echo "  Comparing Results"
echo "========================================"
node "$SCRIPT_DIR/compare.js" "$RESULTS_DIR" $REPORT_FLAG $TOL_FLAG $FAIL_FLAG

if [ -f "$RESULTS_DIR/fidelity_report.html" ]; then
    echo ""
    echo "Report: $RESULTS_DIR/fidelity_report.html"
fi
