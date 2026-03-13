#!/usr/bin/env node
//
// diagnose.js — Metal vs Chrome rendering diagnostic tool
//
// Usage:
//   node tests/fidelity/diagnose.js [url]
//   node tests/fidelity/diagnose.js https://www.google.com
//   node tests/fidelity/diagnose.js tests/fidelity/pages/01_simple.html
//
// Requires: puppeteer (npm install puppeteer in tests/fidelity/)
// Requires: zig build dump_dom (run from project root)
//

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_ROOT = path.resolve(__dirname, '../..');
const RESULTS_DIR = path.join(__dirname, 'results');
const VIEWPORT = { width: 1200, height: 800 };

// ── Colors for terminal output ──────────────────────────────
const R = '\x1b[31m', G = '\x1b[32m', Y = '\x1b[33m', B = '\x1b[34m',
      C = '\x1b[36m', DIM = '\x1b[2m', BOLD = '\x1b[1m', RST = '\x1b[0m';

function hr(char = '─', len = 72) { return DIM + char.repeat(len) + RST; }

// ── Step 1: Chrome Reference Dump ───────────────────────────
async function chromeCapture(url) {
    console.log(`\n${BOLD}[1/4] Chrome Reference Capture${RST}`);
    console.log(`  URL: ${url}`);

    const browser = await puppeteer.launch({ headless: 'new' });
    const page = await browser.newPage();
    await page.setViewport({ ...VIEWPORT, deviceScaleFactor: 1 });

    try {
        await page.goto(url, { waitUntil: 'networkidle2', timeout: 20000 });
    } catch (e) {
        console.log(`  ${Y}Warning: navigation issue: ${e.message.slice(0, 80)}${RST}`);
    }

    // Save HTML
    const html = await page.content();
    const htmlPath = path.join(RESULTS_DIR, 'snapshot.html');
    fs.writeFileSync(htmlPath, html, 'utf8');
    console.log(`  HTML saved: ${html.length} bytes`);

    // Save screenshot
    const ssPath = path.join(RESULTS_DIR, 'chrome_screenshot.png');
    await page.screenshot({ path: ssPath, fullPage: false });
    console.log(`  Screenshot: ${ssPath}`);

    // Extract full layout tree
    const data = await page.evaluate((vp) => {
        let nodeId = 0;

        function dump(node, depth) {
            if (depth > 30) return null; // prevent infinite recursion on weird DOMs
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent.trim();
                if (!text) return null;
                return { type: 'text', text: text.substring(0, 100), id: nodeId++ };
            }
            if (node.nodeType !== Node.ELEMENT_NODE) return null;

            const tag = node.tagName.toLowerCase();
            if (['script', 'style', 'link', 'meta', 'noscript', 'br'].includes(tag)) return null;

            // Skip display:none elements — Metal's resolver skips them entirely
            const cs_pre = window.getComputedStyle(node);
            if (cs_pre.display === 'none') return null;

            const rect = node.getBoundingClientRect();
            const cs = cs_pre;

            const children = [];
            for (const child of node.childNodes) {
                const d = dump(child, depth + 1);
                if (d) children.push(d);
            }

            return {
                type: 'element',
                nid: nodeId++,
                tag,
                elId: node.id || null,
                cls: (node.className || '').toString().split(/\s+/).filter(Boolean).join(' ') || null,
                rect: {
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    w: Math.round(rect.width),
                    h: Math.round(rect.height),
                },
                display: cs.display,
                visibility: cs.visibility,
                color: cs.color,
                bg: cs.backgroundColor,
                fontSize: parseFloat(cs.fontSize),
                fontWeight: cs.fontWeight,
                overflow: cs.overflow,
                position: cs.position,
                children,
            };
        }

        const tree = dump(document.documentElement, 0);

        // Viewport coverage: sample every 10px
        const allRects = [];
        function collectRects(el) {
            if (el.nodeType !== 1) return;
            const r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0 && r.x < vp.w && r.y < vp.h) {
                allRects.push({ x: r.x, y: r.y, w: r.width, h: r.height });
            }
            for (const c of el.children) collectRects(c);
        }
        collectRects(document.body || document.documentElement);
        let covered = 0, total = 0;
        for (let y = 0; y < vp.h; y += 10) {
            for (let x = 0; x < vp.w; x += 10) {
                total++;
                for (const r of allRects) {
                    if (x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) { covered++; break; }
                }
            }
        }

        return { tree, coverage: total > 0 ? Math.round(covered / total * 100) : 0 };
    }, { w: VIEWPORT.width, h: VIEWPORT.height });

    console.log(`  Viewport coverage: ${data.coverage}%`);
    const chromeDump = path.join(RESULTS_DIR, 'chrome_dump.json');
    fs.writeFileSync(chromeDump, JSON.stringify(data, null, 2), 'utf8');

    await browser.close();
    return data;
}

// ── Step 2: Metal Layout Dump ───────────────────────────────
function metalCapture() {
    console.log(`\n${BOLD}[2/4] Metal Layout Capture${RST}`);

    const htmlPath = path.join(RESULTS_DIR, 'snapshot.html');
    const metalDump = path.join(RESULTS_DIR, 'metal_dump.json');

    // Build dump_dom
    try {
        execSync('zig build dump_dom', { cwd: PROJECT_ROOT, stdio: 'pipe' });
    } catch (e) {
        console.log(`  ${R}BUILD FAILED:${RST} ${e.stderr?.toString().slice(0, 200)}`);
        return null;
    }

    // Run dump_dom
    try {
        const result = execSync(`./zig-out/bin/dump_dom "${htmlPath}" "${metalDump}"`, {
            cwd: PROJECT_ROOT,
            stdio: ['pipe', 'pipe', 'pipe'],
            timeout: 30000,
        });
        const stderr = result.toString ? result.toString() : '';
        // dump_dom prints diagnostics to stderr
    } catch (e) {
        const stderr = e.stderr?.toString() || '';
        const stdout = e.stdout?.toString() || '';
        // dump_dom uses stderr for diagnostics, which is fine
        if (stderr) console.log(`  ${DIM}${stderr.trim()}${RST}`);
        if (!fs.existsSync(metalDump)) {
            console.log(`  ${R}FAILED: no output produced${RST}`);
            if (stderr) console.log(`  ${stderr.slice(0, 500)}`);
            return null;
        }
    }

    // Read stderr from the process (dump_dom writes diagnostics there)
    try {
        const result = execSync(`./zig-out/bin/dump_dom "${htmlPath}" "${metalDump}" 2>&1 || true`, {
            cwd: PROJECT_ROOT, stdio: 'pipe', timeout: 30000,
        });
        console.log(`  ${DIM}${result.toString().trim()}${RST}`);
    } catch(_) {}

    if (!fs.existsSync(metalDump)) {
        console.log(`  ${R}No output from dump_dom${RST}`);
        return null;
    }

    try {
        const raw = fs.readFileSync(metalDump, 'utf8');
        console.log(`  Metal JSON: ${raw.length} bytes`);
        return JSON.parse(raw);
    } catch (e) {
        console.log(`  ${R}Failed to parse metal_dump.json: ${e.message}${RST}`);
        return null;
    }
}

// ── Step 3: Flatten trees for comparison ────────────────────
// Uses tag[childIdx] paths for structural matching (no class/id to avoid mismatch)
function flattenTree(node, path_str, depth, list, childIdx) {
    if (!node || depth > 30) return;
    if (node.type === 'text') return;
    if (node.type === 'document') {
        const kids = node.children || [];
        for (let i = 0; i < kids.length; i++) {
            flattenTree(kids[i], path_str, depth, list, i);
        }
        return;
    }

    // Path uses only tag+childIndex for structural matching
    // (Chrome includes .class/#id but Metal doesn't — both use same child indices)
    const tag = node.tag || '?';
    const p = path_str + '/' + tag + '[' + (childIdx || 0) + ']';

    // Human-readable label with id/class for display
    const label = tag + (node.elId ? `#${node.elId}` : '') + (node.cls ? `.${node.cls.split(' ')[0]}` : '');

    const rect = node.rect || { x: 0, y: 0, w: 0, h: 0 };
    // Normalize rect keys: Chrome uses w/h, Metal uses width/height
    const normRect = {
        x: rect.x || 0,
        y: rect.y || 0,
        w: rect.w ?? rect.width ?? 0,
        h: rect.h ?? rect.height ?? 0,
    };

    list.push({
        path: p,
        label,
        tag,
        elId: node.elId || node.id || null,
        cls: node.cls || node.className || null,
        rect: normRect,
        display: node.display || (node.style?.display) || '?',
        visibility: node.visibility || (node.style?.visibility) || 'visible',
        fontSize: node.fontSize || (node.style?.fontSize ? parseFloat(node.style.fontSize) : null),
        bg: node.bg || (node.style?.backgroundColor) || null,
        color: node.color || (node.style?.color) || null,
        depth,
    });

    const kids = node.children || [];
    for (let i = 0; i < kids.length; i++) {
        flattenTree(kids[i], p, depth + 1, list, i);
    }
}

// ── Step 4: Compare and Diagnose ────────────────────────────
function diagnose(chromeData, metalData) {
    console.log(`\n${BOLD}[3/4] Structural Analysis${RST}`);

    const chromeFlat = [];
    const metalFlat = [];

    flattenTree(chromeData.tree, '', 0, chromeFlat, 0);

    // Metal tree might be wrapped in document > html
    let metalRoot = metalData;
    if (metalRoot && metalRoot.type === 'document' && metalRoot.children) {
        metalRoot = metalRoot.children.find(c => c.tag === 'html') || metalRoot.children[0] || metalRoot;
    }
    flattenTree(metalRoot, '', 0, metalFlat, 0);

    console.log(`  Chrome elements: ${chromeFlat.length}`);
    console.log(`  Metal elements:  ${metalFlat.length}`);

    if (metalFlat.length === 0) {
        console.log(`\n  ${R}${BOLD}CRITICAL: Metal produced ZERO layout elements.${RST}`);
        console.log(`  The style resolver returned nothing. Check CSS parsing / <style> extraction.`);
        return;
    }

    const ratio = metalFlat.length / Math.max(chromeFlat.length, 1);
    if (ratio < 0.5) {
        console.log(`  ${R}WARNING: Metal has ${(ratio * 100).toFixed(0)}% of Chrome's elements — many nodes are missing or display:none'd${RST}`);
    }

    // Build path-based lookup maps for matching
    const chromeByPath = new Map();
    for (const n of chromeFlat) chromeByPath.set(n.path, n);
    const metalByPath = new Map();
    for (const n of metalFlat) metalByPath.set(n.path, n);

    // Also build tag-based lookup for fuzzy matching (elements with same tag+depth)
    const chromeByTag = {};
    for (const n of chromeFlat) {
        const key = `${n.tag}:${n.depth}`;
        if (!chromeByTag[key]) chromeByTag[key] = [];
        chromeByTag[key].push(n);
    }

    // Match elements: first try exact path, then fuzzy by tag+depth+order
    const matched = []; // [{chrome, metal}]
    const unmatchedChrome = [];
    const unmatchedMetal = [];

    for (const m of metalFlat) {
        const c = chromeByPath.get(m.path);
        if (c) {
            matched.push({ chrome: c, metal: m });
        } else {
            unmatchedMetal.push(m);
        }
    }
    for (const c of chromeFlat) {
        if (!metalByPath.has(c.path)) {
            unmatchedChrome.push(c);
        }
    }

    console.log(`  Matched by path:     ${matched.length}`);
    console.log(`  Chrome-only:         ${unmatchedChrome.length}`);
    console.log(`  Metal-only:          ${unmatchedMetal.length}`);

    // ── Start Report ────────────────────────────────────
    console.log(`\n${BOLD}[4/4] Diagnostic Report${RST}`);
    console.log(hr());

    // 4a. Zero-size analysis
    const metalNonZero = metalFlat.filter(n => n.rect.w > 0 && n.rect.h > 0);
    const metalZero = metalFlat.filter(n => n.rect.w === 0 || n.rect.h === 0);
    const chromeNonZero = chromeFlat.filter(n => n.rect.w > 0 && n.rect.h > 0);

    console.log(`\n  ${BOLD}A. Size Analysis${RST}`);
    console.log(`     Chrome visible (non-zero size): ${chromeNonZero.length}`);
    console.log(`     Metal visible (non-zero size):  ${metalNonZero.length}`);
    console.log(`     Metal zero-size elements:       ${metalZero.length}`);

    if (metalZero.length > 0) {
        console.log(`\n     ${Y}Zero-size elements in Metal that Chrome renders with size:${RST}`);
        let zeroCount = 0;
        const shown = new Set();
        for (const { chrome: c, metal: m } of matched) {
            if ((m.rect.w === 0 || m.rect.h === 0) && c.rect.w > 0 && c.rect.h > 0) {
                const key = `${m.tag}${m.elId ? '#' + m.elId : ''}${m.cls ? '.' + m.cls.split(' ')[0] : ''}`;
                if (!shown.has(key)) {
                    shown.add(key);
                    zeroCount++;
                    if (zeroCount <= 15) {
                        console.log(`     ${R}•${RST} ${DIM}${m.path}${RST}`);
                        console.log(`       Chrome: ${c.rect.w}×${c.rect.h} at (${c.rect.x},${c.rect.y}) display:${c.display}`);
                        console.log(`       Metal:  ${m.rect.w}×${m.rect.h} display:${m.display}`);
                    }
                }
            }
        }
        if (zeroCount > 15) console.log(`     ... and ${zeroCount - 15} more`);
        if (zeroCount === 0) console.log(`     ${G}(All zero-size Metal elements are also zero in Chrome)${RST}`);
    }

    // 4b. Position mismatches
    console.log(`\n  ${BOLD}B. Position Mismatches (>10px off)${RST}`);
    let posMismatch = 0;
    const posIssues = [];
    for (const { chrome: c, metal: m } of matched) {
        if (m.rect.w === 0 && m.rect.h === 0) continue;
        if (c.rect.w === 0 && c.rect.h === 0) continue;

        const dx = Math.abs(m.rect.x - c.rect.x);
        const dy = Math.abs(m.rect.y - c.rect.y);
        const dw = Math.abs(m.rect.w - c.rect.w);
        const dh = Math.abs(m.rect.h - c.rect.h);

        if (dx > 10 || dy > 10 || dw > 10 || dh > 10) {
            posMismatch++;
            if (posIssues.length < 15) {
                posIssues.push({ m, c, dx, dy, dw, dh });
            }
        }
    }
    console.log(`     Mismatched: ${posMismatch} / ${matched.length}`);
    for (const iss of posIssues) {
        const m = iss.m, c = iss.c;
        console.log(`     ${Y}•${RST} ${DIM}${m.path}${RST}`);
        console.log(`       Chrome: (${c.rect.x},${c.rect.y}) ${c.rect.w}×${c.rect.h}`);
        console.log(`       Metal:  (${m.rect.x},${m.rect.y}) ${m.rect.w}×${m.rect.h}`);
        const parts = [];
        if (iss.dx > 10) parts.push(`x off by ${iss.dx}`);
        if (iss.dy > 10) parts.push(`y off by ${iss.dy}`);
        if (iss.dw > 10) parts.push(`width off by ${iss.dw}`);
        if (iss.dh > 10) parts.push(`height off by ${iss.dh}`);
        console.log(`       ${R}Δ ${parts.join(', ')}${RST}`);
    }
    if (posMismatch > 15) console.log(`     ... and ${posMismatch - 15} more`);

    // 4c. Display property mismatches (path-matched only — reliable!)
    console.log(`\n  ${BOLD}C. Display Mode Mismatches${RST}`);
    const displayMismatches = {};
    for (const { chrome: c, metal: m } of matched) {
        // Normalize Metal's display names to match Chrome's format
        let metalDisplay = m.display;
        if (metalDisplay === 'inline_val') metalDisplay = 'inline';
        if (metalDisplay === 'static_val') metalDisplay = 'static';
        if (metalDisplay === 'inline_block') metalDisplay = 'inline-block';

        // Also normalize Chrome display names
        let chromeDisplay = c.display;
        if (chromeDisplay === 'inline_val') chromeDisplay = 'inline';
        if (chromeDisplay === 'inline_block') chromeDisplay = 'inline-block';

        if (metalDisplay !== chromeDisplay && metalDisplay !== '?') {
            const key = `Chrome:${chromeDisplay} → Metal:${metalDisplay}`;
            if (!displayMismatches[key]) displayMismatches[key] = { count: 0, examples: [] };
            displayMismatches[key].count++;
            if (displayMismatches[key].examples.length < 3) {
                displayMismatches[key].examples.push(`${m.path} (${m.label || m.tag})`);
            }
        }
    }
    const dmKeys = Object.keys(displayMismatches);
    if (dmKeys.length === 0) {
        console.log(`     ${G}No display mismatches found${RST}`);
    } else {
        for (const key of dmKeys.sort((a, b) => displayMismatches[b].count - displayMismatches[a].count)) {
            const dm = displayMismatches[key];
            console.log(`     ${Y}${key}${RST} — ${dm.count} elements`);
            dm.examples.forEach(ex => console.log(`       ${DIM}${ex}${RST}`));
        }
    }

    // 4d. Missing elements analysis
    console.log(`\n  ${BOLD}D. Missing Elements${RST}`);
    if (unmatchedChrome.length > 0) {
        console.log(`     ${Y}In Chrome but NOT in Metal (${unmatchedChrome.length}):${RST}`);
        const tagCounts = {};
        for (const c of unmatchedChrome) {
            const key = `${c.tag} (display:${c.display})`;
            tagCounts[key] = (tagCounts[key] || 0) + 1;
        }
        for (const [key, count] of Object.entries(tagCounts).sort((a, b) => b[1] - a[1]).slice(0, 10)) {
            console.log(`       ${R}${count}× ${key}${RST}`);
        }
    } else {
        console.log(`     ${G}No missing elements${RST}`);
    }
    if (unmatchedMetal.length > 0) {
        console.log(`     ${Y}In Metal but NOT in Chrome (${unmatchedMetal.length}):${RST}`);
        const tagCounts = {};
        for (const m of unmatchedMetal) {
            const key = `${m.tag} (display:${m.display})`;
            tagCounts[key] = (tagCounts[key] || 0) + 1;
        }
        for (const [key, count] of Object.entries(tagCounts).sort((a, b) => b[1] - a[1]).slice(0, 10)) {
            console.log(`       ${C}${count}× ${key}${RST}`);
        }
    }

    // 4e. Tree structure — first divergence point
    console.log(`\n  ${BOLD}E. Tree Structure${RST}`);
    let structMismatchAt = -1;
    const compareLen = Math.min(metalFlat.length, chromeFlat.length, 100);
    for (let i = 0; i < compareLen; i++) {
        if (metalFlat[i].tag !== chromeFlat[i].tag) {
            structMismatchAt = i;
            break;
        }
    }
    if (structMismatchAt >= 0) {
        console.log(`     ${Y}Positional tree diverges at element #${structMismatchAt}:${RST}`);
        console.log(`       Chrome: ${chromeFlat[structMismatchAt]?.tag} — ${chromeFlat[structMismatchAt]?.path}`);
        console.log(`       Metal:  ${metalFlat[structMismatchAt]?.tag} — ${metalFlat[structMismatchAt]?.path}`);
    } else {
        console.log(`     ${G}First ${compareLen} elements match in tag order${RST}`);
    }

    // 4f. Viewport utilization
    console.log(`\n  ${BOLD}F. Viewport Utilization${RST}`);
    const vw = VIEWPORT.width, vh = VIEWPORT.height;
    let metalMaxX = 0, metalMaxY = 0;
    for (const n of metalNonZero) {
        const x = n.rect.x + n.rect.w;
        const y = n.rect.y + n.rect.h;
        if (x > metalMaxX) metalMaxX = x;
        if (y > metalMaxY) metalMaxY = y;
    }
    console.log(`     Chrome viewport coverage: ${chromeData.coverage}%`);
    console.log(`     Metal content max-X: ${Math.round(metalMaxX)} / ${vw} (${Math.round(metalMaxX / vw * 100)}%)`);
    console.log(`     Metal content max-Y: ${Math.round(metalMaxY)} / ${vh} (${Math.round(metalMaxY / vh * 100)}%)`);

    if (metalMaxX < vw * 0.5) {
        console.log(`     ${R}PROBLEM: Content only using ${Math.round(metalMaxX / vw * 100)}% of viewport width${RST}`);
    }
    if (metalMaxX > vw * 1.1) {
        console.log(`     ${R}PROBLEM: Content overflows viewport width by ${Math.round((metalMaxX / vw - 1) * 100)}%${RST}`);
    }
    if (metalMaxY < vh * 0.25 && chromeData.coverage > 50) {
        console.log(`     ${R}PROBLEM: Content only in top ${Math.round(metalMaxY / vh * 100)}% of viewport${RST}`);
    }

    // 4g. Summary
    console.log(`\n${hr('═')}`);
    console.log(`${BOLD}  SUMMARY${RST}`);
    console.log(hr());
    const totalMatched = matched.length;
    const matchedNonZero = matched.filter(p => p.metal.rect.w > 0 && p.metal.rect.h > 0 && p.chrome.rect.w > 0 && p.chrome.rect.h > 0);
    const layoutAccuracy = matchedNonZero.length > 0 ? ((matchedNonZero.length - posMismatch) / matchedNonZero.length * 100).toFixed(1) : 0;
    const displayMismatchTotal = dmKeys.reduce((s, k) => s + displayMismatches[k].count, 0);
    console.log(`  Elements:  Chrome ${chromeFlat.length} | Metal ${metalFlat.length}`);
    console.log(`  Path-matched:      ${totalMatched} (${(totalMatched / Math.max(chromeFlat.length, 1) * 100).toFixed(0)}%)`);
    console.log(`  Layout accuracy:   ${layoutAccuracy}% (within 10px, of matched visible)`);
    console.log(`  Display mismatches: ${displayMismatchTotal} (of ${totalMatched} matched)`);
    console.log(`  Chrome coverage: ${chromeData.coverage}%`);
    console.log(`  Metal max extent: ${Math.round(metalMaxX)}×${Math.round(metalMaxY)}`);
    console.log(hr('═'));

    // Save flat data for further analysis
    fs.writeFileSync(path.join(RESULTS_DIR, 'chrome_flat.json'), JSON.stringify(chromeFlat.slice(0, 300), null, 2));
    fs.writeFileSync(path.join(RESULTS_DIR, 'metal_flat.json'), JSON.stringify(metalFlat.slice(0, 300), null, 2));
    fs.writeFileSync(path.join(RESULTS_DIR, 'matched_pairs.json'), JSON.stringify(matched.slice(0, 300).map(p => ({
        path: p.metal.path,
        chrome: { tag: p.chrome.tag, rect: p.chrome.rect, display: p.chrome.display },
        metal: { tag: p.metal.tag, rect: p.metal.rect, display: p.metal.display },
    })), null, 2));
    console.log(`\n  ${DIM}Raw data saved to tests/fidelity/results/ for manual inspection${RST}`);
}

// ── Main ────────────────────────────────────────────────────
async function main() {
    const args = process.argv.slice(2);
    let url = args[0] || 'https://www.google.com';

    // If it's a local file path, convert to file:// URL
    if (!url.startsWith('http') && !url.startsWith('file://')) {
        url = 'file://' + path.resolve(url);
    }

    fs.mkdirSync(RESULTS_DIR, { recursive: true });

    console.log(hr('═'));
    console.log(`${BOLD}  Metal Rendering Diagnostic${RST}`);
    console.log(`  ${DIM}Comparing Metal's layout engine against Chrome${RST}`);
    console.log(hr('═'));

    // Step 1: Chrome
    const chromeData = await chromeCapture(url);

    // Step 2: Metal
    const metalData = metalCapture();
    if (!metalData) {
        console.log(`\n${R}Cannot continue without Metal output.${RST}`);
        process.exit(1);
    }

    // Step 3+4: Compare & Report
    diagnose(chromeData, metalData);
}

main().catch(err => {
    console.error(`${R}Fatal: ${err.message}${RST}`);
    console.error(err.stack);
    process.exit(1);
});
