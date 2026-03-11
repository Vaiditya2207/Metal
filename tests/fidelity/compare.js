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

console.log("\n=================================");
console.log("  Metal vs Chrome Fidelity Test  ");
console.log("=================================\n");

let mRoot = metalData;
if (mRoot && mRoot.type === 'document' && mRoot.children && mRoot.children.length > 0) {
    mRoot = mRoot.children.find(c => c.type === 'element' && c.tag === 'html') || mRoot.children[0];
}

function flatten(node, path = "", list = []) {
    if (!node || node.type !== 'element') return list;
    const newPath = path + '/' + node.tag;
    list.push({ path: newPath, node });
    if (node.children) {
        let tagCounts = {};
        for (const c of node.children) {
            if (c.type === 'element') {
                tagCounts[c.tag] = (tagCounts[c.tag] || 0) + 1;
                flatten(c, newPath + '[' + tagCounts[c.tag] + ']', list);
            }
        }
    }
    return list;
}

const chromeFlat = flatten(chromeData);
const metalFlat = flatten(mRoot);

const chromeByPath = {};
for (const item of chromeFlat) {
    chromeByPath[item.path] = chromeByPath[item.path] || [];
    chromeByPath[item.path].push(item.node);
}

const metalByPath = {};
for (const item of metalFlat) {
    metalByPath[item.path] = metalByPath[item.path] || [];
    metalByPath[item.path].push(item.node);
}

for (const path of Object.keys(chromeByPath)) {
    const cNodes = chromeByPath[path];
    const mNodes = metalByPath[path] || [];

    const len = Math.min(cNodes.length, mNodes.length);
    for (let i = 0; i < len; i++) {
        const cNode = cNodes[i];
        const mNode = mNodes[i];

        totalElementsChecked++;
        const currentPath = path + (cNodes.length > 1 ? `[${i}]` : '') + (cNode.id ? '#' + cNode.id : '');

        // 1. Layout Compare
        const cr = cNode.rect;
        const mr = mNode.rect;

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
        const cs = cNode.style;
        const ms = mNode.style;

        let styleMatched = true;
        let normalizedMsDisplay = ms.display;
        if (normalizedMsDisplay) {
            normalizedMsDisplay = normalizedMsDisplay.replace('_val', '').replace('_', '-');
        }

        if (cs.display !== normalizedMsDisplay && !(cs.display === 'block' && normalizedMsDisplay === 'flex')) {
            if (cs.display && normalizedMsDisplay) {
                styleMatched = false;
                issues.style.push(`[${currentPath}] Display mismatch. Chrome: ${cs.display}, Metal: ${normalizedMsDisplay}`);
            }
        }

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
    }
}

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
