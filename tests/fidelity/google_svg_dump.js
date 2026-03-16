const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.goto('https://google.com', { waitUntil: 'networkidle2' });
    const svgs = await page.$$eval('svg', els => els.map(el => {
        const style = window.getComputedStyle(el);
        return {
            classes: el.className.baseVal || el.className,
            width: style.width,
            height: style.height,
            display: style.display,
            bb_width: el.getBoundingClientRect().width,
            bb_height: el.getBoundingClientRect().height,
            parent_tag: el.parentElement.tagName,
            parent_w: window.getComputedStyle(el.parentElement).width,
            parent_h: window.getComputedStyle(el.parentElement).height
        };
    }));
    svgs.forEach((s, i) => console.log(`SVG ${i}:`, s));
    await browser.close();
})();
