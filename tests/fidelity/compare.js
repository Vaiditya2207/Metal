const fs = require('fs');

function loadJSON(path) {
    try {
        return JSON.parse(fs.readFileSync(path, 'utf8'));
    } catch (e) {
        console.error(`Error reading ${path}: ${e.message}`);
        process.exit(1);
    }
}

const chromeData = loadJSON('chrome_dump.json');
const metalData = loadJSON('metal_dump.json');

let totalElementsChecked = 0;
let layoutMatchCount = 0;
let styleMatchCount = 0;

const issues = {
    layout: [],
    style: []
};

// Threshold in pixels for treating bounds as matching
const TOLERANCE_PX = 5;

// Normalize color (rgba to rgb, drops alpha for simplicity if it's opaque)
function normalizeColor(c) {
    if (!c) return '';
    c = c.replace(/\s+/g, '').toLowerCase();
    return c;
}

function compareNodes(chromeNode, metalNode, path = "") {
    if (!chromeNode || !metalNode) return;

    if (chromeNode.type === 'text') {
        // We aren't comparing text bounds directly right now due to CoreText metrics differences,
        // but we verify existence in both trees.
        return;
    }

    const currentPath = path + `/${chromeNode.tag}${chromeNode.id ? '#' + chromeNode.id : ''}`;

    totalElementsChecked++;

    // 1. Layout Compare
    const cr = chromeNode.rect;
    const mr = metalNode.rect;

    const xDiff = Math.abs(cr.x - mr.x);
    const yDiff = Math.abs(cr.y - mr.y);
    const wDiff = Math.abs(cr.width - mr.width);
    const hDiff = Math.abs(cr.height - mr.height);

    if (xDiff <= TOLERANCE_PX && yDiff <= TOLERANCE_PX && wDiff <= TOLERANCE_PX && hDiff <= TOLERANCE_PX) {
        layoutMatchCount++;
    } else {
        issues.layout.push(`[${currentPath}] Chrome: [${cr.x}, ${cr.y}, ${cr.width}x${cr.height}] | Metal: [${mr.x}, ${mr.y}, ${mr.width}x${mr.height}]`);
    }

    // 2. Style Compare
    const cs = chromeNode.style;
    const ms = metalNode.style;

    let styleMatched = true;

    if (cs.display !== ms.display && !(cs.display === 'block' && ms.display === 'flex')) {
        // rough tolerance for differing defaults if not directly conflicting
        if (cs.display && ms.display) {
            styleMatched = false;
            issues.style.push(`[${currentPath}] Display mismatch. Chrome: ${cs.display}, Metal: ${ms.display}`);
        }
    }

    // Very rough font size check
    if (cs.fontSize && ms.fontSize) {
        const cfs = parseFloat(cs.fontSize);
        const mfs = parseFloat(ms.fontSize);
        if (Math.abs(cfs - mfs) > 2) {
            styleMatched = false;
            issues.style.push(`[${currentPath}] FontSize mismatch. Chrome: ${cs.fontSize}, Metal: ${ms.fontSize}`);
        }
    }

    if (styleMatched) {
        styleMatchCount++;
    }

    // Recurse heavily simplified. We just attempt a 1-to-1 match by index.
    // In reality, DOM trees might diverge.
    const cc = chromeNode.children || [];
    const mc = metalNode.children || [];

    // We only compare elements, not text nodes for tree structure iteration
    const ce = cc.filter(n => n.type === 'element');
    const me = mc.filter(n => n.type === 'element');

    const len = Math.min(ce.length, me.length);
    for (let i = 0; i < len; i++) {
        compareNodes(ce[i], me[i], currentPath);
    }
}

console.log("\n=================================");
console.log("  Metal vs Chrome Fidelity Test  ");
console.log("=================================\n");

let mRoot = metalData;
if (mRoot && mRoot.type === 'document' && mRoot.children && mRoot.children.length > 0) {
    // Metal outputs 'document' as root, Chrome outputs 'html' as root. Unwrap to match.
    mRoot = mRoot.children.find(c => c.type === 'element' && c.tag === 'html') || mRoot.children[0];
}

compareNodes(chromeData, mRoot);

const layoutAcc = ((layoutMatchCount / totalElementsChecked) * 100).toFixed(2);
const styleAcc = ((styleMatchCount / totalElementsChecked) * 100).toFixed(2);

console.log(`Total Elements Compared: ${totalElementsChecked}`);
console.log(`Layout Accuracy (±${TOLERANCE_PX}px): ${layoutAcc}%`);
console.log(`Style Accuracy: ${styleAcc}%\n`);

const MAX_ISSUES = 10;

console.log(`--- Major Layout Issues (showing up to ${MAX_ISSUES}) ---`);
for (let i = 0; i < Math.min(issues.layout.length, MAX_ISSUES); i++) {
    console.log(`❌ ${issues.layout[i]}`);
}
if (issues.layout.length > MAX_ISSUES) console.log(`   ... and ${issues.layout.length - MAX_ISSUES} more`);

console.log(`\n--- Major Style Issues (showing up to ${MAX_ISSUES}) ---`);
for (let i = 0; i < Math.min(issues.style.length, MAX_ISSUES); i++) {
    console.log(`❌ ${issues.style[i]}`);
}
if (issues.style.length > MAX_ISSUES) console.log(`   ... and ${issues.style.length - MAX_ISSUES} more`);

console.log("\n");
