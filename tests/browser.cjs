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
            await page.goto((process.env.MW_URL || 'http://127.0.0.1:8080') + '/index.php?title=Charts_advanced', { waitUntil: 'networkidle' });
            await page.screenshot({ path: `tests/artifacts/advanced-${width}.png`, fullPage: true });
            assert.equal(await page.locator('.scribunto-chart').count(), 5);
            assert.equal(await page.locator('.scribunto-error, .scribunto-chart-error').count(), 0);
            const heights = await page.locator('.sc-column').evaluateAll(nodes => nodes.map(n => n.getBoundingClientRect().height / n.parentElement.clientHeight));
            const expectedHeights = [0.25, 0.5, 1, 0.4, 0.3, 0.6, 0.65, 0.8, 0.75];
            assert.equal(heights.length, expectedHeights.length);
            heights.forEach((ratio, i) => assert.ok(Math.abs(ratio - expectedHeights[i]) < 0.015, 'common column scale'));
            const taskGeometry = await page.locator('.sc-task-bar').evaluateAll(nodes => nodes.map(n => {
                const bar = n.getBoundingClientRect(), track = n.parentElement.getBoundingClientRect();
                return { left: (bar.left - track.left) / track.width, width: bar.width / track.width };
            }));
            assert.equal(taskGeometry.length, 3);
            taskGeometry.forEach((bar, i) => {
                assert.ok(Math.abs(bar.left - [0, 0.2, 0.9][i]) < 0.01, 'Gantt task offset');
                assert.ok(Math.abs(bar.width - [0.3, 0.6, 0.1][i]) < 0.01, 'inclusive Gantt durations');
            });
            const marker = await page.locator('.sc-target').evaluate(n => parseFloat(getComputedStyle(n).left) / n.parentElement.clientWidth);
            assert.ok(Math.abs(marker - 0.85) < 0.01, 'bullet target is distinct from actual value');
            const heat = await page.locator('.sc-heat-cell').evaluateAll(nodes => nodes.map(n => ({ value: n.textContent, background: getComputedStyle(n).backgroundColor, color: getComputedStyle(n).color })));
            assert.equal(heat.length, 21);
            assert.ok(heat.filter(n => n.value === '0').every(n => n.background === 'rgb(255, 255, 255)' && n.color === 'rgb(0, 0, 0)'));
            assert.ok(heat.some(n => n.value === '20' && n.background === 'rgb(15, 118, 110)' && n.color === 'rgb(255, 255, 255)'));
            const advancedSizes = await page.locator('.scribunto-chart').evaluateAll(nodes => nodes.map(n => ({ scroll: n.scrollWidth, client: n.clientWidth, right: n.getBoundingClientRect().right })));
            advancedSizes.forEach(s => assert.ok(s.scroll <= s.client + 1 && s.right <= width + 1, 'advanced cards contain wide data'));
            if (width === 390) {
                assert.ok(await page.locator('.sc-chart-heatmap .sc-scroll').evaluate(n => n.scrollWidth > n.clientWidth), 'wide heatmap scrolls inside its card');
            }
            console.log(`PASS: ${width}px, five advanced charts, scales / dates / targets / heatmap contrast`);
            await page.goto((process.env.MW_URL || 'http://127.0.0.1:8080') + '/index.php?title=Charts_leaderboard', { waitUntil: 'networkidle' });
            await page.screenshot({ path: `tests/artifacts/leaderboard-${width}.png`, fullPage: true });
            assert.equal(await page.locator('.sc-chart-leaderboard').count(), 3);
            assert.equal(await page.locator('.scribunto-error, .scribunto-chart-error').count(), 0);
            const rankings = await page.locator('.sc-ranking').evaluateAll(tables => tables.map(t => ({
                labels: [...t.querySelectorAll('.sc-ranking-label')].map(n => n.textContent),
                ranks: [...t.querySelectorAll('.sc-ranking-row')].map(n => n.getAttribute('data-rank')),
                trophies: t.querySelectorAll('.sc-trophy').length
            })));
            assert.deepEqual(rankings[0], { labels: ['Совы', 'Рыси', 'Лисы'], ranks: ['1','2','3'], trophies: 1 });
            assert.deepEqual(rankings[1], { labels: ['Аня', 'Борис', 'Вера'], ranks: ['1','1','3'], trophies: 2 });
            assert.deepEqual(rankings[2], { labels: ['Команда B', 'Команда C', 'Команда A'], ranks: ['1','2','3'], trophies: 0 });
            const rankingSizes = await page.locator('.sc-chart-leaderboard').evaluateAll(nodes => nodes.map(n => ({ scroll: n.scrollWidth, client: n.clientWidth, right: n.getBoundingClientRect().right })));
            rankingSizes.forEach(s => assert.ok(s.scroll <= s.client + 1 && s.right <= width + 1, 'leaderboard stays within viewport'));
            console.log(`PASS: ${width}px, leaderboard sorting / ties / optional trophies`);
            await context.close();
        }
    } finally {
        await browser.close();
    }
})().catch(error => { console.error(error); process.exitCode = 1; });
