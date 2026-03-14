/**
 * visual_compare.js — Pixel-diff comparison between Chrome and Metal screenshots.
 *
 * Handles the dimension mismatch between Chrome (1200x800 RGB) and Metal (2400x1600 RGBA)
 * by downscaling the larger image to match the smaller one before running pixelmatch.
 *
 * Usage:
 *   node tests/fidelity/visual_compare.js <chrome_png> <metal_png> [output_diff_png] [--threshold=0.1]
 *
 * Exit codes:
 *   0 — comparison completed (regardless of match percentage)
 *   1 — error (missing files, bad arguments, etc.)
 */

const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const pixelmatchModule = require('pixelmatch');
const pixelmatch = pixelmatchModule.default || pixelmatchModule;

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const args = process.argv.slice(2);
const flagArgs = args.filter(a => a.startsWith('--'));
const positionalArgs = args.filter(a => !a.startsWith('--'));

let threshold = 0.1;
for (const flag of flagArgs) {
  const match = flag.match(/^--threshold=(.+)$/);
  if (match) {
    const val = parseFloat(match[1]);
    if (isNaN(val) || val < 0 || val > 1) {
      console.error('[visual] ERROR: --threshold must be a number between 0 and 1');
      process.exit(1);
    }
    threshold = val;
  }
}

const chromePath = positionalArgs[0];
const metalPath = positionalArgs[1];
const diffPath = positionalArgs[2] || path.join(__dirname, 'results', 'diff.png');

if (!chromePath || !metalPath) {
  console.error('Usage: node visual_compare.js <chrome_png> <metal_png> [output_diff_png] [--threshold=0.1]');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Read a PNG file and return a pngjs PNG object with RGBA data.
 * Handles the case where pngjs reads an RGB PNG — the data buffer may
 * already be expanded to RGBA (pngjs does this by default), but we verify.
 */
function readPNG(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }
  const buffer = fs.readFileSync(filePath);
  const png = PNG.sync.read(buffer);

  const expectedRGBA = png.width * png.height * 4;
  if (png.data.length === expectedRGBA) {
    // Already RGBA — nothing to do
    return png;
  }

  // Unlikely path: pngjs gave us raw RGB. Expand to RGBA with alpha=255.
  const expectedRGB = png.width * png.height * 3;
  if (png.data.length === expectedRGB) {
    const rgba = Buffer.alloc(expectedRGBA);
    for (let i = 0, j = 0; i < png.data.length; i += 3, j += 4) {
      rgba[j] = png.data[i];
      rgba[j + 1] = png.data[i + 1];
      rgba[j + 2] = png.data[i + 2];
      rgba[j + 3] = 255;
    }
    png.data = rgba;
    return png;
  }

  throw new Error(
    `Unexpected data length for ${filePath}: got ${png.data.length}, ` +
    `expected ${expectedRGBA} (RGBA) or ${expectedRGB} (RGB) for ${png.width}x${png.height}`
  );
}

/**
 * Downscale an RGBA image by an integer factor using 2x2 block averaging.
 * For non-integer ratios, falls back to nearest-neighbor sampling.
 *
 * @param {PNG} src - Source PNG object with RGBA data
 * @param {number} targetW - Target width
 * @param {number} targetH - Target height
 * @returns {PNG} New PNG object at target dimensions
 */
function downscale(src, targetW, targetH) {
  const dst = new PNG({ width: targetW, height: targetH });

  const scaleX = src.width / targetW;
  const scaleY = src.height / targetH;

  const isExact2x = (scaleX === 2 && scaleY === 2);

  for (let y = 0; y < targetH; y++) {
    for (let x = 0; x < targetW; x++) {
      const dstIdx = (y * targetW + x) * 4;

      if (isExact2x) {
        // Average the 2x2 block from source
        const sx = x * 2;
        const sy = y * 2;
        const i00 = (sy * src.width + sx) * 4;
        const i10 = (sy * src.width + sx + 1) * 4;
        const i01 = ((sy + 1) * src.width + sx) * 4;
        const i11 = ((sy + 1) * src.width + sx + 1) * 4;

        dst.data[dstIdx] = (src.data[i00] + src.data[i10] + src.data[i01] + src.data[i11] + 2) >> 2;
        dst.data[dstIdx + 1] = (src.data[i00 + 1] + src.data[i10 + 1] + src.data[i01 + 1] + src.data[i11 + 1] + 2) >> 2;
        dst.data[dstIdx + 2] = (src.data[i00 + 2] + src.data[i10 + 2] + src.data[i01 + 2] + src.data[i11 + 2] + 2) >> 2;
        dst.data[dstIdx + 3] = (src.data[i00 + 3] + src.data[i10 + 3] + src.data[i01 + 3] + src.data[i11 + 3] + 2) >> 2;
      } else {
        // Nearest-neighbor for non-integer ratios
        const sx = Math.floor(x * scaleX);
        const sy = Math.floor(y * scaleY);
        const srcIdx = (sy * src.width + sx) * 4;

        dst.data[dstIdx] = src.data[srcIdx];
        dst.data[dstIdx + 1] = src.data[srcIdx + 1];
        dst.data[dstIdx + 2] = src.data[srcIdx + 2];
        dst.data[dstIdx + 3] = src.data[srcIdx + 3];
      }
    }
  }

  return dst;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

try {
  // Read both images
  const chrome = readPNG(chromePath);
  const metal = readPNG(metalPath);

  console.log(`[visual] Chrome: ${chrome.width}x${chrome.height} (source: ${chromePath})`);

  // Determine target dimensions (the smaller of the two)
  const targetW = Math.min(chrome.width, metal.width);
  const targetH = Math.min(chrome.height, metal.height);

  // Downscale if needed
  let chromeImg = chrome;
  let metalImg = metal;
  let chromeScaled = false;
  let metalScaled = false;

  if (chrome.width > targetW || chrome.height > targetH) {
    chromeImg = downscale(chrome, targetW, targetH);
    chromeScaled = true;
  }
  if (metal.width > targetW || metal.height > targetH) {
    metalImg = downscale(metal, targetW, targetH);
    metalScaled = true;
  }

  if (metalScaled) {
    console.log(`[visual] Metal: ${metal.width}x${metal.height} \u2192 downscaled to ${targetW}x${targetH} (source: ${metalPath})`);
  } else {
    console.log(`[visual] Metal: ${metal.width}x${metal.height} (source: ${metalPath})`);
  }
  if (chromeScaled) {
    console.log(`[visual] Chrome was downscaled from ${chrome.width}x${chrome.height} to ${targetW}x${targetH}`);
  }

  const totalPixels = targetW * targetH;
  console.log(`[visual] Comparing ${targetW}x${targetH} images (${totalPixels} pixels)`);

  // Create diff output image
  const diff = new PNG({ width: targetW, height: targetH });

  // Run pixelmatch
  const mismatched = pixelmatch(
    chromeImg.data,
    metalImg.data,
    diff.data,
    targetW,
    targetH,
    { threshold }
  );

  const mismatchPct = (mismatched / totalPixels * 100).toFixed(2);
  const matchPct = ((1 - mismatched / totalPixels) * 100).toFixed(2);

  console.log(`[visual] Mismatched: ${mismatched} pixels (${mismatchPct}%)`);
  console.log(`[visual] Match: ${matchPct}%`);

  // Save diff image
  const diffDir = path.dirname(diffPath);
  if (!fs.existsSync(diffDir)) {
    fs.mkdirSync(diffDir, { recursive: true });
  }
  const diffBuffer = PNG.sync.write(diff);
  fs.writeFileSync(diffPath, diffBuffer);
  console.log(`[visual] Diff saved to: ${diffPath}`);

  process.exit(0);
} catch (err) {
  console.error(`[visual] ERROR: ${err.message}`);
  process.exit(1);
}
