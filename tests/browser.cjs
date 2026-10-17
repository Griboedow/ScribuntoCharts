// Run only against the disposable wiki populated by tests/wiki.php.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
    const browser = await chromium.launch();
    fs.mkdirSync('tests/artifacts', { recursive: true });
    try {
        for (const width of [1366, 390]) {
            const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width, height: 1000 } });
            const page = await context.newPage();
            await page.goto((process.env.MW_URL || 'http://127.0.0.1:8080') + '/index.php?title=Charts_demo', { waitUntil: 'networkidle' });
            await page.screenshot({ path: `tests/artifacts/gallery-${width}.png`, fullPage: true });
            assert.equal(await page.locator('.scribunto-chart').count(), 9, 'all chart instances render without JavaScript');
            assert.equal(await page.locator('.scribunto-error, .scribunto-chart-error').count(), 0);
            const shapes = await page.locator('.sc-round, .sc-gauge').evaluateAll(nodes => nodes.map(node => {
                const box = node.getBoundingClientRect();
                return { width: box.width, height: box.height, gauge: node.classList.contains('sc-gauge') };
            }));
            for (const shape of shapes) {
                assert.ok(shape.width > 80 && shape.height > 40, 'CSS sizing survives the wiki parser');
                assert.ok(Math.abs(shape.width / shape.height - (shape.gauge ? 2 : 1)) < 0.03, 'correct circular/semicircular proportions: ' + JSON.stringify(shape));
            }
            const backgrounds = await page.locator('.sc-round, .sc-gauge-arc').evaluateAll(nodes => nodes.map(node => getComputedStyle(node).backgroundImage));
            assert.equal(backgrounds.filter(value => value.includes('conic-gradient')).length, 5, 'two distributions and three gauges have gradients; zero donut has none');
            const sizes = await page.locator('.scribunto-chart').evaluateAll(nodes => nodes.map(node => ({ scroll: node.scrollWidth, client: node.clientWidth, right: node.getBoundingClientRect().right })));
            for (const size of sizes) {
                assert.ok(size.scroll <= size.client + 1, 'chart content does not overflow horizontally');
                assert.ok(size.right <= width + 1, 'chart stays within viewport');
            }
            assert.equal(await page.locator('.sc-data th[scope="col"]').count(), 15, 'five accessible series tables');
            const text = await page.locator('#mw-content-text').innerText();
            assert.ok(!text.includes('<thead>') && !text.includes('<tbody>'), 'no escaped unsupported table tags');
            assert.ok(text.includes('Outside the scale') && text.includes('125'), 'out-of-range value remains readable');
            console.log(`PASS: ${width}px, JavaScript disabled, shapes / gradients / data / overflow`);
            await context.close();
        }
    } finally {
        await browser.close();
    }
})().catch(error => { console.error(error); process.exitCode = 1; });
