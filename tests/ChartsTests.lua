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
    check(contains(html, 'sc-chart-donut') and contains(html, 'Item 2') and contains(html, '>Frame<'), 'frame trimming and fixed entry point')
    html = charts.chart({ args = { type = 'progress', value = '50' } })
    check(contains(html, 'sc-progress'), 'generic frame entry point')
    html = valid({ type = 'columns', value1 = 10, value2 = 20, max = 40 })
    check(contains(html, 'height:25.000000%') and contains(html, 'height:50.000000%'), 'columns use shared explicit scale')
    valid({ type = 'columns', value1 = 0 })
    invalid({ type = 'columns', value1 = 10, max = 5 }, 'cover every value')
    invalid({ type = 'columns', value1 = 0, max = 0 }, 'positive')
    invalid({ type = 'columns', value1 = 1, height = 500 }, 'Height must')
    local matrix = { { label = 'A', values = { 10, 20 } }, { label = 'B', values = { 40, 0 } } }
    html = valid({ type = 'grouped', columns = { 'Plan', { label = 'Actual', color = '#123456' } }, rows = matrix, max = 80 })
    check(contains(html, 'height:12.500000%') and contains(html, 'height:50.000000%'), 'groups share scale across rows')
    check(contains(html, '#123456') and contains(html, 'scope="col"'), 'series colors and accessible matrix')
    html = valid({ type = 'heatmap', column1 = 'Mon', column2 = 'Tue', row1 = '0,20', color = '#000', max = 20 })
    check(contains(html, 'background:#ffffff') and contains(html, 'background:#000000'), 'heatmap zero and max endpoints')
    check(contains(html, 'color:#ffffff') and contains(html, 'color:#000000'), 'heatmap contrast')
    html = valid({ type = 'heatmap', column1 = 'A', row1 = '0' })
    check(contains(html, 'No positive values'), 'empty heatmap notice')
    for _, kind in ipairs({ 'grouped', 'heatmap' }) do
        invalid({ type = kind, column1 = 'A', column2 = 'B', row1 = '1' }, 'Row width')
        invalid({ type = kind, column1 = 'A', row1 = '1,2' }, 'Row width')
        invalid({ type = kind, column1 = 'A', row1 = '-1' }, 'non-negative')
        invalid({ type = kind, column1 = 'A', row1 = '1', row3 = '2' }, 'missing item 2')
        invalid({ type = kind, column2 = 'A', row1 = '1' }, 'missing item 1')
        invalid({ type = kind, column1 = 'A', row1 = '1', max = 0 }, 'positive')
        invalid({ type = kind, column1 = 'A', row1 = 'nan' }, 'finite number')
        invalid({ type = kind, column1 = 'A', column2 = 'B', row1 = '1,' }, 'finite number')
        invalid({ type = kind, column13 = 'A', row1 = '1' }, 'too many items')
        invalid({ type = kind, column1 = 'A', row31 = '1' }, 'too many items')
        invalid({ type = kind, columns = { 'A' }, rows = { { values = { [1] = 1, other = 2 } } } }, 'Row width')
    end
    html = valid({ type = 'bullet', value = 72, target = 85 })
    check(contains(html, 'width:72.000000%') and contains(html, 'left:85.000000%'), 'bullet value and target differ')
    html = valid({ type = 'bullet', min = -50, max = 50, value = 100, target = 0, lang = 'ru' })
    check(contains(html, 'left:50.000000%') and contains(html, 'Цель') and contains(html, '>100<'), 'bullet negative scale and unclipped text')
    valid({ type = 'bullet', value = 0, target = 0 })
    valid({ type = 'bullet', value = 100, target = 100 })
    invalid({ type = 'bullet', value = 1 }, 'Target must')
    invalid({ type = 'bullet', value = 1, target = 101 }, 'Target must')
    html = valid({ type = 'gantt', from = '2028-02-28', to = '2028-03-08', tasks = {
        { label = 'Build', start = '2028-02-28', finish = '2028-03-01', progress = 100 },
        { label = 'Release', start = '2028-03-08', finish = '2028-03-08' }
    } })
    check(contains(html, 'width:30.000000%'), 'Gantt includes leap day and final day')
    check(contains(html, 'left:90.000000%') and contains(html, 'width:10.000000%'), 'last-day task has visible one-day duration')
    html = valid({ type = 'gantt', start1 = '2026-12-31', finish1 = '2027-01-01', progress1 = 25 })
    check(contains(html, 'width:100.000000%') and contains(html, 'width:25.000000%'), 'automatic Gantt bounds and progress')
    valid({ type = 'gantt', start1 = '2000-02-29', finish1 = '2000-02-29' })
    for _, badDate in ipairs({ '2027-02-29', '1900-02-29', '2026-04-31', '2026-13-01', '2026-01-00', '0000-01-01', '2026-1-1', '<script>' }) do
        invalid({ type = 'gantt', start1 = badDate, finish1 = '2028-01-01' }, 'Invalid date')
    end
    invalid({ type = 'gantt', start1 = '2026-01-02', finish1 = '2026-01-01' }, 'must not precede')
    invalid({ type = 'gantt', start1 = '2026-01-01', finish1 = '2026-01-02', from = '2026-01-02' }, 'cover every task')
    invalid({ type = 'gantt', start1 = '2026-01-01', finish1 = '2026-01-01', progress1 = 101 }, 'Task progress')
    invalid({ type = 'gantt', start1 = '2026-01-01', finish1 = '2026-01-01', start3 = '2026-01-02', finish3 = '2026-01-02' }, 'missing item 2')
    invalid({ type = 'gantt', start31 = '2026-01-01', finish31 = '2026-01-01' }, 'too many items')
    local manyColumns, manyRows = {}, {}
    for j = 1, 12 do manyColumns[j] = 'Column ' .. j end
    for i = 1, 30 do
        local values = {}
        for j = 1, 12 do values[j] = i * j end
        manyRows[i] = { label = 'Row ' .. i, values = values }
    end
    html = valid({ type = 'heatmap', columns = manyColumns, rows = manyRows })
    local _, cells = html:gsub('sc%-heat%-cell', '')
    check(cells == 360, 'maximum matrix preserves all 360 cells')
    html = valid({ type = 'grouped', column1 = '<script>', label1 = '[[Category:Bad]]', row1 = '2' })
    check(not contains(html, '<script>') and not contains(html, '[[Category:Bad]]'), 'matrix text is escaped')
    for _, kind in ipairs({ 'columns', 'grouped', 'heatmap', 'bullet', 'gantt' }) do
        check(type(charts[kind]) == 'function', 'public entry point ' .. kind)
    end
    return 'PASS: ' .. count .. ' chart assertions'
end
return p
