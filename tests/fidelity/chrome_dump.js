const puppeteer = require('puppeteer');
const fs = require('fs');

async function run() {
    const args = process.argv.slice(2);
    const url = args[0] || 'https://www.google.com';

    console.log(`[Chrome] Launching Headless Chrome to fetch ${url}...`);
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    
    // Set a standard viewport
    await page.setViewport({ width: 1200, height: 800 });
    
    await page.goto(url, { waitUntil: 'networkidle2' });

    // Save the raw HTML so Metal can parse exactly the same string
    const html = await page.content();
    fs.writeFileSync('google_snapshot.html', html, 'utf8');
    console.log(`[Chrome] Saved HTML snapshot to google_snapshot.html (${html.length} bytes)`);

    // Extract layout tree
    const layoutTree = await page.evaluate(() => {
        function dumpNode(node) {
            if (node.nodeType === Node.TEXT_NODE) {
                const text = node.textContent.trim();
                if (!text) return null;
                return {
                    type: 'text',
                    text: text.substring(0, 50) + (text.length > 50 ? '...' : '')
                };
            }

            if (node.nodeType !== Node.ELEMENT_NODE) return null;

            // Skip scripts and styles for comparison output to keep JSON clean
            if (node.tagName.toLowerCase() === 'script' || node.tagName.toLowerCase() === 'style') {
                return null;
            }

            const rect = node.getBoundingClientRect();
            const style = window.getComputedStyle(node);
            
            const children = [];
            for (const child of node.childNodes) {
                const dumped = dumpNode(child);
                if (dumped) children.push(dumped);
            }

            return {
                type: 'element',
                tag: node.tagName.toLowerCase(),
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
                    backgroundColor: style.backgroundColor
                },
                children
            };
        }
        
        return dumpNode(document.documentElement);
    });

    fs.writeFileSync('chrome_dump.json', JSON.stringify(layoutTree, null, 2), 'utf8');
    console.log(`[Chrome] Saved Chrome layout dump to chrome_dump.json`);

    await browser.close();
}

run().catch(err => {
    console.error(err);
    process.exit(1);
});
