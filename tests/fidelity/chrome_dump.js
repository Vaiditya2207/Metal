const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

async function run() {
    const args = process.argv.slice(2);
    const inputPath = args[0];
    const outputDir = args[1] || '.';

    if (!inputPath) {
        console.error('Usage: node chrome_dump.js <html_file_or_url> [output_dir]');
        process.exit(1);
    }

    // Determine if input is a local file or URL
    let url;
    if (inputPath.startsWith('http://') || inputPath.startsWith('https://')) {
        url = inputPath;
    } else {
        url = 'file://' + path.resolve(inputPath);
    }

    const baseName = path.basename(inputPath, path.extname(inputPath));

    console.log(`[Chrome] Launching Headless Chrome for ${url}...`);
    const browser = await puppeteer.launch({ headless: 'new' });
    const page = await browser.newPage();

    // Match Metal's default viewport
    await page.setViewport({ width: 1200, height: 800, deviceScaleFactor: 2 });

    await page.goto(url, { waitUntil: 'networkidle2', timeout: 15000 });

    // Take screenshot for visual comparison
    const screenshotPath = path.join(outputDir, `${baseName}_chrome.png`);
    await page.screenshot({ path: screenshotPath, fullPage: false });
    console.log(`[Chrome] Saved screenshot to ${screenshotPath}`);

    // Save rendered HTML
    const html = await page.content();
    const htmlPath = path.join(outputDir, `${baseName}_snapshot.html`);
    fs.writeFileSync(htmlPath, html, 'utf8');

    // Extract layout tree with expanded style properties
    const layoutTree = await page.evaluate(() => {
        function dumpNode(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent.trim();
                if (!text) return null;
                return {
                    type: 'text',
                    text: text.substring(0, 80) + (text.length > 80 ? '...' : '')
                };
            }

            if (node.nodeType !== Node.ELEMENT_NODE) return null;
            const tag = node.tagName.toLowerCase();
            if (tag === 'script' || tag === 'style' || tag === 'link' || tag === 'meta') return null;

            const rect = node.getBoundingClientRect();
            const style = window.getComputedStyle(node);

            const children = [];
            for (const child of node.childNodes) {
                const dumped = dumpNode(child);
                if (dumped) children.push(dumped);
            }

            return {
                type: 'element',
                tag: tag,
                id: node.id || undefined,
                className: node.className || undefined,
                rect: {
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                },
                style: {
                    display: style.display,
                    color: style.color,
                    fontSize: style.fontSize,
                    fontWeight: style.fontWeight,
                    fontStyle: style.fontStyle,
                    backgroundColor: style.backgroundColor,
                    margin: style.margin,
                    padding: style.padding,
                    textAlign: style.textAlign,
                    lineHeight: style.lineHeight,
                    textDecoration: style.textDecorationLine || style.textDecoration,
                    visibility: style.visibility,
                    overflow: style.overflow,
                    position: style.position
                },
                children
            };
        }

        // Compute viewport coverage: what % of viewport has visible content
        const allRects = [];
        function collectRects(el) {
            if (el.nodeType !== Node.ELEMENT_NODE) return;
            const r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0) {
                allRects.push({ x: r.x, y: r.y, w: r.width, h: r.height });
            }
            for (const child of el.children) collectRects(child);
        }
        collectRects(document.body);

        // Approximate coverage by sampling pixels
        const vw = window.innerWidth, vh = window.innerHeight;
        let coveredPixels = 0;
        const step = 10; // sample every 10px
        for (let y = 0; y < vh; y += step) {
            for (let x = 0; x < vw; x += step) {
                for (const r of allRects) {
                    if (x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) {
                        coveredPixels++;
                        break;
                    }
                }
            }
        }
        const totalSamples = (Math.floor(vw / step)) * (Math.floor(vh / step));
        const viewportCoverage = totalSamples > 0 ? (coveredPixels / totalSamples) : 0;

        // Count images and check loading
        const images = Array.from(document.querySelectorAll('img'));
        const imageStats = {
            total: images.length,
            loaded: images.filter(img => img.complete && img.naturalWidth > 0).length,
            broken: images.filter(img => img.complete && img.naturalWidth === 0).length
        };

        return {
            tree: dumpNode(document.documentElement),
            viewportCoverage: Math.round(viewportCoverage * 100),
            imageStats,
            viewport: { width: vw, height: vh }
        };
    });

    const dumpPath = path.join(outputDir, `${baseName}_chrome.json`);
    fs.writeFileSync(dumpPath, JSON.stringify(layoutTree, null, 2), 'utf8');
    console.log(`[Chrome] Saved layout dump to ${dumpPath}`);
    console.log(`[Chrome] Viewport coverage: ${layoutTree.viewportCoverage}%`);
    console.log(`[Chrome] Images: ${layoutTree.imageStats.loaded}/${layoutTree.imageStats.total} loaded`);

    await browser.close();
}

run().catch(err => {
    console.error(err);
    process.exit(1);
});
