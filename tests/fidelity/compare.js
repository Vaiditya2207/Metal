const chrome = require('./results/chrome_dump.json').tree;
const metal = require('./results/metal_dump.json').children[0];
const TOL = 5;
const SVG_CHILD_TAGS = new Set(['path','image','circle','rect','line','g','polygon','polyline','ellipse','text','use','defs','clipPath','mask','filter','linearGradient','radialGradient','stop','symbol','marker','pattern','foreignObject']);

function flatten(node, list, depth, isChrome, insideSvg) {
  list = list || []; depth = depth || 0; insideSvg = insideSvg || false;
  const r = node.rect || {};
  const w = isChrome ? r.w : r.width;
  const h = isChrome ? r.h : r.height;
  const id = isChrome ? (node.elId || '') : (node.id || '');
  // Use sorted class string for matching. Chrome's diagnose.js truncates to first 3 classes
  // (unsorted) then compare.js sorts. Mirror this: take first 3 unsorted, then sort.
  const rawCls = isChrome ? (node.cls || '') : (node.className || '');
  // Chrome reports SVG className as "[object SVGAnimatedString]" — normalize to empty
  let clsParts = rawCls.split(' ').filter(Boolean);
  if (clsParts.some(c => c.includes('SVGAnimatedString'))) clsParts = [];
  const tag = node.tag || '';
  if (tag === 'svg') clsParts = [];
  // Truncate to first 3 classes (unsorted) to match Chrome dump format, then sort
  let cls = clsParts.slice(0, 3).sort().join(' ');

  // Skip SVG children on Chrome side (Metal treats SVG as opaque replaced elements)
  const isSvgChild = isChrome && insideSvg && SVG_CHILD_TAGS.has(tag);
  if (!isSvgChild) {
    list.push({ tag, id, cls, x: r.x||0, y: r.y||0, w: w||0, h: h||0, depth });
  }

  const childInsideSvg = insideSvg || (tag === 'svg');
  (node.children || []).forEach(c => flatten(c, list, depth+1, isChrome, childInsideSvg));
  return list;
}
const cn = flatten(chrome, null, 0, true);
const mn = flatten(metal, null, 0, false);
let match = 0, total = 0, mismatches = [];
// Track used Metal indices to prevent double-matching
const usedMetal = new Set();
for (const c of cn) {
  if (!c.tag || c.tag === '#text') continue;
  if (c.w === 0 && c.h === 0) continue;
  total++;
  const ckey = c.id + '|' + c.cls + '|' + c.tag;
  // Find first unused Metal element matching this key
  const mIdx = mn.findIndex((n, idx) => !usedMetal.has(idx) && (n.id+'|'+n.cls+'|'+n.tag) === ckey);
  const m = mIdx >= 0 ? mn[mIdx] : null;
  if (m) usedMetal.add(mIdx);
  if (m && Math.abs(c.x-m.x)<=TOL && Math.abs(c.y-m.y)<=TOL && Math.abs(c.w-m.w)<=TOL && Math.abs(c.h-m.h)<=TOL) {
    match++;
  } else if (m) {
    mismatches.push({key:ckey,chrome:{x:c.x,y:c.y,w:c.w,h:c.h},metal:{x:m.x,y:m.y,w:m.w,h:m.h}});
  } else {
    mismatches.push({key:ckey,chrome:{x:c.x,y:c.y,w:c.w,h:c.h},metal:'NOT FOUND'});
  }
}
console.log('Accuracy: '+(match/total*100).toFixed(1)+'% ('+match+'/'+total+')');
console.log('\nMATCHES:');
const usedMetal2 = new Set();
for (const c of cn) {
  if (!c.tag || c.tag === '#text') continue;
  if (c.w === 0 && c.h === 0) continue;
  const ckey = c.id + '|' + c.cls + '|' + c.tag;
  const mIdx = mn.findIndex((n, idx) => !usedMetal2.has(idx) && (n.id+'|'+n.cls+'|'+n.tag) === ckey);
  const m = mIdx >= 0 ? mn[mIdx] : null;
  if (m) usedMetal2.add(mIdx);
  if (m && Math.abs(c.x-m.x)<=TOL && Math.abs(c.y-m.y)<=TOL && Math.abs(c.w-m.w)<=TOL && Math.abs(c.h-m.h)<=TOL) {
    console.log('  OK '+ckey+' C:'+JSON.stringify({x:c.x,y:c.y,w:c.w,h:c.h})+' M:'+JSON.stringify({x:m.x,y:m.y,w:m.w,h:m.h}));
  }
}
console.log('\nMISMATCHES (top 35):');
mismatches.slice(0,35).forEach(m => {
  if (m.metal==='NOT FOUND') console.log('  MISSING: '+m.key+' C:'+JSON.stringify(m.chrome));
  else console.log('  '+m.key+': dx='+(m.metal.x-m.chrome.x)+' dy='+(m.metal.y-m.chrome.y)+' dw='+(m.metal.w-m.chrome.w)+' dh='+(m.metal.h-m.chrome.h)+'  C:'+JSON.stringify(m.chrome)+'  M:'+JSON.stringify(m.metal));
});
