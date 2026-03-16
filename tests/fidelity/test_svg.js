const puppeteer = require('puppeteer');
(async () => {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.setContent(`
        <!DOCTYPE html>
        <html><body>
        <svg id="s1" viewBox="0 0 24 24"><rect width="24" height="24" fill="red"/></svg>
        <svg id="s2" viewBox="0 -960 960 960"><rect x="0" y="-960" width="960" height="960" fill="blue"/></svg>
        </body></html>
    `);
    const d1 = await page.$eval('#s1', el => [el.getBoundingClientRect().width, el.getBoundingClientRect().height]);
    const d2 = await page.$eval('#s2', el => [el.getBoundingClientRect().width, el.getBoundingClientRect().height]);
    console.log("SVG 0 0 24 24:", d1);
    console.log("SVG 0 -960 960 960:", d2);
    await browser.close();
})();
