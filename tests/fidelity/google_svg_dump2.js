const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.goto('https://google.com', { waitUntil: 'networkidle2' });
    const svgs = await page.$$eval('svg', els => els.map(el => {
        return {
            inline_style: el.getAttribute('style') || '',
            tag_name: el.tagName
        };
    }));
    svgs.forEach((s, i) => console.log(`SVG ${i}:`, s));
    await browser.close();
})();
