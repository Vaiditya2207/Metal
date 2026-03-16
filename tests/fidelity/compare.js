#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const SVG_CHILD_TAGS = new Set([
  'path','image','circle','rect','line','g','polygon','polyline','ellipse','text','use','defs','clipPath','mask','filter','linearGradient','radialGradient','stop','symbol','marker','pattern','foreignObject'
]);

const args = process.argv.slice(2);
const flags = args.filter(a => a.startsWith('--'));
const positional = args.filter(a => !a.startsWith('--'));

const report = flags.includes('--report');
const tolFlag = flags.find(f => f.startsWith('--tol='));
const failUnderFlag = flags.find(f => f.startsWith('--fail-under='));

const tol = tolFlag ? parseFloat(tolFlag.split('=')[1]) : 5;
const failUnder = failUnderFlag ? parseFloat(failUnderFlag.split('=')[1]) : null;

if (Number.isNaN(tol) || tol < 0) {
  console.error('[compare] ERROR: --tol must be a non-negative number');
  process.exit(1);
}
if (failUnder !== null && (Number.isNaN(failUnder) || failUnder < 0 || failUnder > 100)) {
  console.error('[compare] ERROR: --fail-under must be in 0..100');
  process.exit(1);
}

function loadJson(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(raw);
}

function normalizeChromeRoot(chrome) {
  if (chrome && chrome.tree) return chrome.tree;
  return chrome;
}

function normalizeMetalRoot(metal) {
  if (metal && metal.type === 'document' && Array.isArray(metal.children)) {
    return metal.children[0] || metal;
  }
  return metal;
}

function flatten(node, list, depth, isChrome, insideSvg) {
  list = list || [];
  depth = depth || 0;
  insideSvg = insideSvg || false;
  if (!node) return list;

  const r = node.rect || {};
  const w = r.width || 0;
  const h = r.height || 0;
  const id = isChrome ? (node.elId || node.id || '') : (node.id || '');
  const rawCls = isChrome ? (node.cls || node.className || '') : (node.className || '');
  let clsParts = typeof rawCls === 'string' ? rawCls.split(' ').filter(Boolean) : [];
  if (clsParts.some(c => c.includes('SVGAnimatedString'))) clsParts = [];
  const tag = node.tag || '';
  if (tag === 'svg') clsParts = [];
  let cls = clsParts.slice(0, 3).sort().join(' ');

  const isSvg = tag === 'svg';
  const isSvgChild = insideSvg;

  if (!isSvgChild) {
    list.push({ tag, id, cls, x: r.x || 0, y: r.y || 0, w: w, h: h, depth });
  }

  const childInsideSvg = insideSvg || isSvg;
  (node.children || []).forEach(c => flatten(c, list, depth + 1, isChrome, childInsideSvg));
  return list;
}

function compareTrees(chromeJson, metalJson) {
  const chromeRoot = normalizeChromeRoot(chromeJson);
  const metalRoot = normalizeMetalRoot(metalJson);
  const cn = flatten(chromeRoot, null, 0, true);
  const mn = flatten(metalRoot, null, 0, false);

  let match = 0;
  let total = 0;
  const mismatches = [];

  // Match nodes by tree position (index).
  // This is much more reliable than matching by class/tag when the trees have slight structural differences.
  const maxIdx = Math.max(cn.length, mn.length);

  for (let i = 0; i < maxIdx; i++) {
    const c = cn[i];
    const m = mn[i];

    if (c) {
      if (!c.tag || c.tag === '#text') continue;
      if (c.w === 0 && c.h === 0) continue;
      total++;
    }

    if (c && m) {
      const ckey = c.id + '|' + c.cls + '|' + c.tag;
      const mkey = m.id + '|' + m.cls + '|' + m.tag;

      const posMatch = Math.abs(c.x - m.x) <= tol && Math.abs(c.y - m.y) <= tol && Math.abs(c.w - m.w) <= tol && Math.abs(c.h - m.h) <= tol;
      const tagMatch = c.tag === m.tag;

      if (posMatch && tagMatch) {
        match++;
      } else {
        mismatches.push({
          key: ckey,
          chrome: { x: c.x, y: c.y, w: c.w, h: c.h, tag: c.tag },
          metal: { x: m.x, y: m.y, w: m.w, h: m.h, tag: m.tag }
        });
      }
    } else if (c) {
      const ckey = c.id + '|' + c.cls + '|' + c.tag;
      mismatches.push({ key: ckey, chrome: { x: c.x, y: c.y, w: c.w, h: c.h }, metal: 'NOT FOUND' });
    }
  }

  const accuracy = total > 0 ? (match / total) * 100 : 0;
  return { accuracy, match, total, mismatches };
}

function collectPairsFromDir(resultsDir) {
  const entries = fs.readdirSync(resultsDir);
  const chromeByBase = new Map();
  const metalByBase = new Map();

  for (const entry of entries) {
    if (entry.endsWith('_chrome.json')) {
      const base = entry.replace(/_chrome\.json$/, '');
      chromeByBase.set(base, path.join(resultsDir, entry));
    } else if (entry === 'chrome_dump.json') {
      chromeByBase.set('dump', path.join(resultsDir, entry));
    }
  }

  for (const entry of entries) {
    if (entry.endsWith('_metal.json')) {
      const base = entry.replace(/_metal\.json$/, '');
      metalByBase.set(base, path.join(resultsDir, entry));
    } else if (entry === 'metal_dump.json') {
      metalByBase.set('dump', path.join(resultsDir, entry));
    }
  }

  const pairs = [];
  for (const [base, chromePath] of chromeByBase.entries()) {
    const metalPath = metalByBase.get(base);
    if (metalPath) {
      pairs.push({ name: base, chromePath, metalPath });
    }
  }
  return pairs;
}

function htmlEscape(str) {
  return str.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function writeReport(reportPath, summary) {
  const rows = summary.map(s => {
    const status = s.accuracy >= (failUnder ?? 0) ? 'PASS' : 'FAIL';
    return `<tr><td>${htmlEscape(s.name)}</td><td>${s.accuracy.toFixed(1)}%</td><td>${s.match}/${s.total}</td><td>${s.mismatches}</td><td>${status}</td></tr>`;
  }).join('\n');

  const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<title>Metal Fidelity Report</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #f4f4f6; }
</style>
</head>
<body>
<h1>Metal Fidelity Report</h1>
<table>
<thead><tr><th>Page</th><th>Accuracy</th><th>Matched</th><th>Mismatches</th><th>Status</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</body>
</html>`;

  fs.writeFileSync(reportPath, html, 'utf8');
}

function main() {
  let pairs = [];

  if (positional.length === 2) {
    pairs = [{ name: path.basename(positional[0]).replace(/\.json$/, ''), chromePath: positional[0], metalPath: positional[1] }];
  } else {
    const resultsDir = positional[0] ? positional[0] : path.join(__dirname, 'results');
    if (!fs.existsSync(resultsDir) || !fs.statSync(resultsDir).isDirectory()) {
      console.error(`[compare] ERROR: results dir not found: ${resultsDir}`);
      process.exit(1);
    }
    pairs = collectPairsFromDir(resultsDir);
    if (pairs.length === 0) {
      console.error(`[compare] ERROR: no *_chrome.json and *_metal.json pairs found in ${resultsDir}`);
      process.exit(1);
    }
  }

  const summary = [];
  let anyFail = false;

  for (const pair of pairs) {
    const chromeJson = loadJson(pair.chromePath);
    const metalJson = loadJson(pair.metalPath);

    const result = compareTrees(chromeJson, metalJson);
    summary.push({
      name: pair.name,
      accuracy: result.accuracy,
      match: result.match,
      total: result.total,
      mismatches: result.mismatches.length,
    });

    console.log(`\n[compare] ${pair.name}`);
    console.log(`Accuracy: ${result.accuracy.toFixed(1)}% (${result.match}/${result.total})`);
    if (result.mismatches.length > 0) {
      console.log('MISMATCHES (top 10):');
      result.mismatches.slice(0, 10).forEach(m => {
        if (m.metal === 'NOT FOUND') {
          console.log(`  MISSING: ${m.key} C:${JSON.stringify(m.chrome)}`);
        } else {
          console.log(`  ${m.key}: C:${JSON.stringify(m.chrome)} M:${JSON.stringify(m.metal)}`);
        }
      });
    }

    if (failUnder !== null && result.accuracy < failUnder) {
      anyFail = true;
    }
  }

  if (report) {
    const reportDir = positional.length === 2 ? path.dirname(positional[0]) : (positional[0] || path.join(__dirname, 'results'));
    const reportPath = path.join(reportDir, 'fidelity_report.html');
    writeReport(reportPath, summary);
    console.log(`\nReport: ${reportPath}`);
  }

  if (anyFail) {
    process.exitCode = 2;
  }
}

main();
