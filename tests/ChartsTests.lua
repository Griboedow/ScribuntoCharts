local charts = require('Module:Charts')
local p = {}
function p.run()
    local count = 0
    local function check(ok, name)
        if not ok then error('FAIL: ' .. name) end
        count = count + 1
    end
    local function contains(s, value) return s:find(value, 1, true) ~= nil end
    local function valid(config)
        local html = charts.render(config)
        check(not contains(html, 'scribunto-chart-error'), 'valid ' .. (config.type or 'donut'))
        check(not contains(html, '<script') and not contains(html, '<svg'), 'CSS only')
        return html
    end
    local function invalid(config, expected)
        local html = charts.render(config)
        check(contains(html, 'scribunto-chart-error') and contains(html, expected), expected)
    end
    local series = { { label = 'Alpha', value = 25 }, { label = 'Beta', value = 75, color = '#0f0' } }
    for _, kind in ipairs({ 'donut', 'pie', 'bars', 'stacked' }) do
        local html = valid({ type = kind, series = series })
        check(contains(html, 'sc-data') and contains(html, 'scope="row"'), 'semantic data table')
        check(contains(html, '25%') and contains(html, '75%'), 'shares')
    end
    local html = valid({ type = 'donut', series = series })
    check(contains(html, 'conic-gradient(#2563eb 0.000000% 25.000000%,#0f0 25.000000% 100.000000%)'), 'correct segment boundaries')
    check(contains(html, 'inset:18.000000%'), 'donut hole')
    html = valid({ type = 'pie', series = { { value = 0 }, { value = 2 } } })
    check(not contains(html, '#2563eb 0.000000% 0.000000%'), 'zero slice omitted')
    for _, kind in ipairs({ 'donut', 'pie', 'bars', 'stacked' }) do
        html = valid({ type = kind, series = { { value = 0 }, { value = 0 } } })
        check(contains(html, 'No positive values'), 'zero total notice')
        check(not contains(html, 'nan') and not contains(html, 'inf%'), 'no division by zero')
    end
    for _, value in ipairs({ -50, 0, 50, 100, 150 }) do
        html = valid({ type = 'gauge', value = value })
        local angle = math.max(0, math.min(100, value)) * 1.8
        check(contains(html, 'rotate(' .. string.format('%.6f', angle) .. 'deg)'), 'needle endpoint / midpoint')
        check(contains(html, 'Outside the scale') == (value < 0 or value > 100), 'clamp disclosed')
        check(contains(html, '>' .. mw.text.nowiki(tostring(value)) .. '<'), 'actual value preserved')
    end
    html = valid({ type = 'gauge', min = -100, max = 100, value = 0, warning = 20, danger = 70 })
    check(contains(html, 'rotate(90.000000deg)'), 'negative minimum scale')
    html = valid({ type = 'progress', min = 10, max = 50, value = 30 })
    check(contains(html, 'width:50.000000%'), 'progress uses range not raw value')
    html = valid({ type = 'progress', value = 150 })
    check(contains(html, 'width:100.000000%') and contains(html, '>150<'), 'progress clamps graphic only')
    html = valid({ type = 'bars', series = { { value = 2 }, { value = 4 } } })
    check(contains(html, 'width:50.000000%') and contains(html, 'width:100.000000%'), 'bars relative to maximum')
    html = valid({ type = 'stacked', series = series })
    check(contains(html, 'width:25.000000%') and contains(html, 'width:75.000000%'), 'stacked relative to total')
    html = valid({ title = '<script>alert(1)</script>', caption = '[[Category:Unexpected]]', value1 = 1, label1 = '{{Danger}}' })
    check(not contains(html, '<script>') and not contains(html, '[[Category:Unexpected]]') and not contains(html, '{{Danger}}'), 'labels are literal text')
    html = valid({ value1 = 0.125, decimals = 4, theme = 'dark', palette = 'forest' })
    check(contains(html, '0.125') and contains(html, '#111827'), 'precision and dark theme')
    html = valid({ value1 = 0, lang = 'ru' })
    check(contains(html, 'Всего') and contains(html, 'Нет положительных'), 'Russian messages')
    html = valid({ value1 = 1e12, value2 = 1e-12, size = 120, label1 = string.rep('long', 200) })
    check(contains(html, mw.text.nowiki('1e-12')), 'tiny values do not become zero')
    local many = {}
    for i = 1, 30 do many[i] = { label = 'Item ' .. i, value = i } end
    valid({ series = many })
    many[31] = { value = 1 }
    invalid({ series = many }, 'at most 30')
    invalid({ value1 = 1, value31 = 2 }, '1 to 30')
    invalid({ value1 = 1, value3 = 2 }, 'Value 2')
    invalid({ series = { [1] = { value = 1 }, [3] = { value = 3 } } }, 'Value 2')
    invalid({ series = 'wrong' }, 'Series must be a table')
    invalid({ value1 = -1 }, 'non-negative')
    invalid({ value1 = 0 / 0 }, 'finite number')
    invalid({ value1 = math.huge }, 'finite number')
    invalid({ value1 = '1,5' }, 'finite number')
    invalid({ value1 = 1, color1 = 'red;background:url(https://example.org)' }, 'Colors must be')
    invalid({ type = 'gauge', value = 1, min = 5, max = 5 }, 'Maximum must')
    invalid({ type = 'gauge', value = 1, warning = 90, danger = 50 }, 'Thresholds must')
    invalid({ type = 'gauge' }, 'Value must')
    invalid({ value1 = 1, size = 10000 }, 'Size must')
    invalid({ value1 = 1, decimals = 1.5 }, 'integer')
    invalid({ value1 = 1, hole = 99 }, 'Hole must')
    invalid({ value1 = 1, palette = 'missing' }, 'Unknown palette')
    invalid({ type = 'unknown' }, 'Unknown chart type')
    invalid({ theme = 'unknown' }, 'Theme must')
    invalid({ lang = 'unknown' }, 'Language must')
    invalid({}, 'Provide at least one')
    invalid(nil, 'configuration table')
    html = charts.donut({ args = { title = ' Frame ', value1 = ' 2 ', value2 = ' 3 ', label2 = '', type = 'bars' } })
    check(contains(html, 'sc-donut') and contains(html, 'Item 2') and contains(html, '>Frame<'), 'frame trimming and fixed entry point')
    html = charts.chart({ args = { type = 'progress', value = '50' } })
    check(contains(html, 'sc-progress'), 'generic frame entry point')
    return 'PASS: ' .. count .. ' chart assertions'
end
return p
