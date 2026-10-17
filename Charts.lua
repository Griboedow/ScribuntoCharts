-- Module:Charts — CSS-only charts for MediaWiki Scribunto. MIT license.
local p = {}
local palettes = {
    ocean = { '#2563eb', '#0d9488', '#f59e0b', '#8b5cf6', '#e11d48', '#64748b' },
    sunset = { '#ea580c', '#e11d48', '#9333ea', '#f59e0b', '#be185d', '#475569' },
    forest = { '#047857', '#65a30d', '#0e7490', '#ca8a04', '#7c3aed', '#475569' },
    mono = { '#172554', '#1e40af', '#2563eb', '#60a5fa', '#93c5fd', '#bfdbfe' }
}
local kinds = { donut = true, pie = true, gauge = true, bars = true, stacked = true, progress = true, columns = true, grouped = true, bullet = true, heatmap = true, gantt = true, leaderboard = true }
local messages = {
    en = { total = 'Total', label = 'Label', value = 'Value', share = 'Share', warning = 'Warning', danger = 'Danger', empty = 'No positive values to plot.', outside = 'Outside the scale; the indicator is clamped to the nearest end.' },
    ru = { total = 'Всего', label = 'Название', value = 'Значение', share = 'Доля', warning = 'Внимание', danger = 'Опасность', empty = 'Нет положительных значений для диаграммы.', outside = 'Значение вне шкалы; указатель ограничен ближайшим краем.' }
}

local function fail(message) error(message, 0) end
local function text(value, fallback)
    if value == nil or value == '' then return fallback or '' end
    if type(value) ~= 'string' and type(value) ~= 'number' then fail('Labels must be text.') end
    value = tostring(value)
    if #value > 1000 then fail('Labels must be at most 1000 bytes.') end
    return value
end
local function number(value, fallback, name)
    if value == nil or value == '' then value = fallback end
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge or math.abs(n) > 1e12 then
        fail((name or 'Value') .. ' must be a finite number between -1e12 and 1e12.')
    end
    return n
end
local function bounded(value, fallback, low, high, name)
    local n = number(value, fallback, name)
    if n < low or n > high then fail(name .. ' must be between ' .. low .. ' and ' .. high .. '.') end
    return n
end
local function color(value, fallback)
    if value == nil or value == '' then return fallback end
    if type(value) ~= 'string' or not (value:match('^#%x%x%x$') or value:match('^#%x%x%x%x%x%x$')) then
        fail('Colors must be #RGB or #RRGGBB hex values.')
    end
    return value
end
local function literal(node, value)
    return node:wikitext(mw.text.nowiki(tostring(value)))
end
local function cssnum(n) return string.format('%.6f', n):gsub(',', '.') end
local function percent(n) return cssnum(n) .. '%' end
local function display(n, decimals)
    local s = string.format('%.' .. decimals .. 'f', n)
    -- Do not turn a real (tiny) nonzero value into a displayed zero.
    if n ~= 0 and tonumber(s) == 0 then return string.format('%.3g', n) end
    if decimals > 0 then s = s:gsub('0+$', ''):gsub('[.,]$', '') end
    if s == '-0' then return '0' end
    return s
end
local function div(parent, class, css)
    return parent:tag('div'):addClass(class):css(css or {})
end

-- Strict arrays and numbered parameters: never silently omit extra rows.
local function entries(config, field, prefixes, limit)
    local result, last = {}, 0
    if config[field] ~= nil then
        if type(config[field]) ~= 'table' then fail(field .. ' must be an array.') end
        for k in pairs(config[field]) do
            if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 or k > limit then fail(field .. ': invalid index or too many items.') end
            last = math.max(last, k)
        end
        for i = 1, last do
            if config[field][i] == nil then fail(field .. ': missing item ' .. i) end
            result[i] = config[field][i]
        end
    else
        for key in pairs(config) do
            if type(key) == 'string' then
                for _, prefix in ipairs(prefixes) do
                    local index = key:match('^' .. prefix .. '(%d+)$')
                    if index then
                        local n = tonumber(index)
                        if n < 1 or n > limit or tostring(n) ~= index then fail(field .. ': invalid index or too many items.') end
                        last = math.max(last, n)
                    end
                end
            end
        end
        for i = 1, last do
            result[i] = {}
            for _, prefix in ipairs(prefixes) do result[i][prefix] = config[prefix .. i] end
            if next(result[i]) == nil then fail(field .. ': missing item ' .. i) end
        end
    end
    if last == 0 then fail('Provide at least one ' .. field .. ' item.') end
    return result
end

local function date(value)
    if type(value) ~= 'string' then fail('Dates must use YYYY-MM-DD.') end
    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or y < 1 or m < 1 or m > 12 then fail('Invalid date: ' .. value) end
    local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if d < 1 or d > days[m] then fail('Invalid date: ' .. value) end
    local previous = y - 1
    local ordinal = 365 * previous + math.floor(previous / 4) - math.floor(previous / 100) + math.floor(previous / 400) + d
    for month = 1, m - 1 do ordinal = ordinal + days[month] end
    return ordinal
end

local function matrixOptions(config, o)
    o.columns, o.rows, o.largest = {}, {}, 0
    for i, column in ipairs(entries(config, 'columns', { 'column', 'seriescolor' }, 12)) do
        if type(column) == 'string' then column = { label = column } end
        if type(column) ~= 'table' then fail('Each column must be text or a table.') end
        o.columns[i] = { label = text(column.label or column.column, 'Series ' .. i), color = color(column.color or column.seriescolor, o.palette[(i - 1) % #o.palette + 1]) }
    end
    for i, row in ipairs(entries(config, 'rows', { 'row', 'label' }, 30)) do
        if type(row) ~= 'table' then fail('Each row must be a table.') end
        local values = row.values
        if values == nil and type(row.row) == 'string' then
            values = {}
            for part in (row.row .. ','):gmatch('(.-),') do values[#values + 1] = mw.text.trim(part) end
        end
        if type(values) ~= 'table' then fail('Each row needs a values array or comma-separated rowN.') end
        local count = 0
        for key in pairs(values) do
            if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #o.columns then fail('Row width must match the columns.') end
            count = count + 1
        end
        if count ~= #o.columns then fail('Row width must match the columns.') end
        local item = { label = text(row.label, 'Row ' .. i), values = {} }
        for j = 1, #o.columns do
            local n = number(values[j], nil, 'Cell ' .. i .. ',' .. j)
            if n < 0 then fail('Matrix values must be non-negative.') end
            item.values[j] = n
            o.largest = math.max(o.largest, n)
        end
        o.rows[i] = item
    end
    o.ceiling = number(config.max, o.largest > 0 and o.largest or 1, 'Maximum')
    if o.ceiling <= 0 or o.ceiling < o.largest then fail('Maximum must be positive and cover every value.') end
end

local function ganttOptions(config, o)
    o.tasks = {}
    local first, last
    for i, task in ipairs(entries(config, 'tasks', { 'label', 'start', 'finish', 'color', 'progress' }, 30)) do
        if type(task) ~= 'table' then fail('Each task must be a table.') end
        local a, b = date(task.start), date(task.finish)
        if b < a then fail('Task finish must not precede start.') end
        o.tasks[i] = { label = text(task.label, 'Task ' .. i), start = task.start, finish = task.finish, a = a, b = b,
            color = color(task.color, o.palette[(i - 1) % #o.palette + 1]), progress = bounded(task.progress, 0, 0, 100, 'Task progress') }
        if not first or a < first then first, o.from = a, task.start end
        if not last or b > last then last, o.to = b, task.finish end
    end
    o.from, o.to = text(config.from, o.from), text(config.to, o.to)
    o.first, o.last = date(o.from), date(o.to)
    if o.first > first or o.last < last then fail('Timeline must cover every task.') end
    o.days = o.last - o.first + 1
end

local function options(config)
    if type(config) ~= 'table' then fail('Pass a configuration table.') end
    local o = {}
    o.kind = text(config.type, 'donut')
    if not kinds[o.kind] then fail('Unknown chart type: ' .. o.kind) end
    o.title = text(config.title)
    o.caption = text(config.caption)
    o.unit = text(config.unit)
    o.lang = text(config.lang, 'en')
    o.messages = messages[o.lang]
    if not o.messages then fail('Language must be en or ru.') end
    o.centerlabel = text(config.centerlabel, o.messages.total)
    o.theme = text(config.theme, 'light')
    if o.theme ~= 'light' and o.theme ~= 'dark' then fail('Theme must be light or dark.') end
    local dark = o.theme == 'dark'
    o.bg = color(config.background, dark and '#111827' or '#ffffff')
    o.ink = dark and '#f3f4f6' or '#172033'
    o.muted = dark and '#cbd5e1' or '#526176'
    o.track = dark and '#334155' or '#e2e8f0'
    o.size = bounded(config.size, (o.kind == 'donut' or o.kind == 'pie' or o.kind == 'gauge') and 260 or 420, 120, 640, 'Size')
    o.height = bounded(config.height, 180, 80, 400, 'Height')
    o.decimals = bounded(config.decimals, 1, 0, 4, 'Decimals')
    if o.decimals % 1 ~= 0 then fail('Decimals must be an integer.') end
    o.hole = bounded(config.hole, 64, 35, 85, 'Hole')
    o.palette = palettes[text(config.palette, 'ocean')]
    if not o.palette then fail('Unknown palette. Use ocean, sunset, forest or mono.') end
    o.color = color(config.color, o.palette[1])
    o.format = function(n) return display(n, o.decimals) .. (o.unit ~= '' and ' ' .. o.unit or '') end
    if o.kind == 'grouped' or o.kind == 'heatmap' then
        matrixOptions(config, o)
    elseif o.kind == 'gantt' then
        ganttOptions(config, o)
    elseif o.kind == 'gauge' or o.kind == 'progress' or o.kind == 'bullet' then
        o.min = number(config.min, 0, 'Minimum')
        o.max = number(config.max, 100, 'Maximum')
        if o.max <= o.min then fail('Maximum must be greater than minimum.') end
        o.value = number(config.value, nil, 'Value')
        o.ratio = math.max(0, math.min(1, (o.value - o.min) / (o.max - o.min)))
        o.outside = o.value < o.min or o.value > o.max
        if o.kind == 'gauge' or o.kind == 'bullet' then
            o.warning = number(config.warning, o.min + (o.max - o.min) * 0.6, 'Warning threshold')
            o.danger = number(config.danger, o.min + (o.max - o.min) * 0.85, 'Danger threshold')
            if not (o.min < o.warning and o.warning < o.danger and o.danger < o.max) then
                fail('Thresholds must satisfy min < warning < danger < max.')
            end
            o.lowcolor = color(config.lowcolor, '#0d9488')
            o.warncolor = color(config.warncolor, '#f59e0b')
            o.highcolor = color(config.highcolor, '#ef4444')
        end
        if o.kind == 'bullet' then
            o.target = bounded(config.target, nil, o.min, o.max, 'Target')
        end
    else
        o.series, o.total, o.largest = {}, 0, 0
        if config.series ~= nil and type(config.series) ~= 'table' then fail('Series must be a table.') end
        if config.series then
            for key in pairs(config.series) do
                if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > 30 then
                    fail('Series must be a consecutive array with at most 30 items.')
                end
            end
        end
        local last = 0
        for i = 1, 30 do
            if config.series and config.series[i] ~= nil or not config.series and
                (config['value' .. i] ~= nil or config['label' .. i] ~= nil or config['color' .. i] ~= nil) then
                last = i
            end
        end
        if last == 0 then fail('Provide at least one value (value1, label1), or a series array.') end
        for i = 1, last do
            local item = config.series and config.series[i] or {
                label = config['label' .. i], value = config['value' .. i], color = config['color' .. i]
            }
            if type(item) ~= 'table' then fail('Each series item must be a table.') end
            local entry = {
                label = text(item.label, 'Item ' .. i),
                value = number(item.value, nil, 'Value ' .. i),
                color = color(item.color, o.palette[(i - 1) % #o.palette + 1])
            }
            if entry.value < 0 then fail('Series values must be non-negative.') end
            o.series[i] = entry
            o.total = o.total + entry.value
            o.largest = math.max(o.largest, entry.value)
        end
        -- Reject extra numbered values instead of silently dropping data.
        for key in pairs(config) do
            local index = type(key) == 'string' and (key:match('^value(%d+)$') or key:match('^label(%d+)$') or key:match('^color(%d+)$'))
            if index and (tonumber(index) < 1 or tonumber(index) > 30 or tostring(tonumber(index)) ~= index) then
                fail('Use consecutive item indexes from 1 to 30.')
            end
        end
        if o.kind == 'columns' then
            o.ceiling = number(config.max, o.largest > 0 and o.largest or 1, 'Maximum')
            if o.ceiling <= 0 or o.ceiling < o.largest then fail('Maximum must be positive and cover every value.') end
        end
        if o.kind == 'leaderboard' then
            o.order = text(config.order, 'desc')
            if o.order ~= 'asc' and o.order ~= 'desc' then fail('Order must be asc or desc.') end
            local trophy = config.trophy
            if trophy == nil or trophy == '' or trophy == false or trophy == 'no' or trophy == '0' or trophy == 0 then o.trophy = false
            elseif trophy == true or trophy == 'yes' or trophy == '1' or trophy == 1 then o.trophy = true
            else fail('Trophy must be yes or no (or a Lua boolean).') end
            for i, item in ipairs(o.series) do item.index = i end
            table.sort(o.series, function(a, b)
                if a.value == b.value then return a.index < b.index end
                if o.order == 'asc' then return a.value < b.value end
                return a.value > b.value
            end)
            local rank = 1
            for i, item in ipairs(o.series) do
                if i > 1 and item.value ~= o.series[i - 1].value then rank = i end
                item.rank = rank
            end
        end
    end
    return o
end

local function legend(root, o)
    local tableNode = root:tag('table'):addClass('sc-data'):css({ width = '100%', ['table-layout'] = 'fixed', ['overflow-wrap'] = 'anywhere', ['border-collapse'] = 'collapse', ['margin-top'] = '18px', ['font-size'] = '0.9em' })
    -- MediaWiki wikitext does not accept explicit thead/tbody elements.
    local head = tableNode:tag('tr')
    for index, name in ipairs({ o.messages.label, o.messages.value, o.messages.share }) do
        literal(head:tag('th'):attr('scope', 'col'):css({ width = ({ '45%', '35%', '20%' })[index], ['text-align'] = index == 1 and 'left' or 'right', padding = '5px 4px', color = o.muted, ['font-weight'] = '500' }), name)
    end
    for _, item in ipairs(o.series) do
        local row = tableNode:tag('tr')
        local label = row:tag('th'):attr('scope', 'row'):css({ ['text-align'] = 'left', padding = '7px 4px', ['font-weight'] = '400', ['overflow-wrap'] = 'anywhere' })
        label:tag('span'):attr('aria-hidden', 'true'):css({ display = 'inline-block', width = '9px', height = '9px', ['border-radius'] = '3px', background = item.color, ['margin-right'] = '8px' })
        literal(label, item.label)
        literal(row:tag('td'):css({ ['text-align'] = 'right', padding = '7px 4px', ['font-variant-numeric'] = 'tabular-nums' }), o.format(item.value))
        literal(row:tag('td'):css({ ['text-align'] = 'right', padding = '7px 4px', color = o.muted }), o.total > 0 and display(item.value / o.total * 100, 1) .. '%' or '—')
    end
end

local function roundChart(root, o)
    local stops, start = {}, 0
    if o.total > 0 then
        for _, item in ipairs(o.series) do
            if item.value > 0 then
                local finish = start + item.value / o.total * 100
                stops[#stops + 1] = item.color .. ' ' .. percent(start) .. ' ' .. percent(finish)
                start = finish
            end
        end
    end
    local visual = div(root, 'sc-round', { width = '100%', ['aspect-ratio'] = '1', ['border-radius'] = '50%', position = 'relative', background = o.total > 0 and 'conic-gradient(' .. table.concat(stops, ',') .. ')' or o.track })
    visual:attr('aria-hidden', 'true')
    if o.kind == 'donut' then
        local inner = div(visual, 'sc-hole', { position = 'absolute', inset = percent((100 - o.hole) / 2), ['border-radius'] = '50%', background = o.bg, display = 'flex', ['flex-direction'] = 'column', ['align-items'] = 'center', ['justify-content'] = 'center', ['text-align'] = 'center', ['overflow-wrap'] = 'anywhere', overflow = 'hidden' })
        literal(div(inner, 'sc-total', { ['font-size'] = '1.5em', ['font-weight'] = '700', ['line-height'] = '1.2', ['max-width'] = '92%' }), display(o.total, o.decimals))
        literal(div(inner, 'sc-center-label', { ['font-size'] = '0.75em', color = o.muted, ['max-width'] = '90%' }), o.centerlabel)
    end
end

local function bars(root, o)
    local visual = div(root, 'sc-bars')
    visual:attr('aria-hidden', 'true')
    for _, item in ipairs(o.series) do
        local row = div(visual, 'sc-bar-row', { ['margin-top'] = '12px' })
        local line = div(row, 'sc-bar-label', { display = 'flex', ['justify-content'] = 'space-between', gap = '12px', ['font-size'] = '0.85em', ['margin-bottom'] = '5px', ['overflow-wrap'] = 'anywhere' })
        literal(line:tag('span'), item.label)
        literal(line:tag('span'):css('flex-shrink', '0'), o.format(item.value))
        local track = div(row, 'sc-track', { background = o.track, height = '12px', ['border-radius'] = '6px', overflow = 'hidden' })
        div(track, 'sc-bar', { width = percent(o.largest > 0 and item.value / o.largest * 100 or 0), height = '100%', background = item.color })
    end
end

local function leaderboard(root, o)
    local tableNode = root:tag('table'):addClass('sc-ranking'):css({ width = '100%', ['table-layout'] = 'fixed', ['border-collapse'] = 'collapse', ['overflow-wrap'] = 'anywhere', ['font-size'] = '0.9em' })
    local header = tableNode:tag('tr')
    for i, label in ipairs({ o.lang == 'ru' and 'Место' or 'Rank', o.messages.label, o.messages.value }) do
        literal(header:tag('th'):attr('scope', 'col'):css({ width = ({ '18%', '52%', '30%' })[i], ['text-align'] = i == 3 and 'right' or 'left', padding = '6px 4px', color = o.muted, ['font-weight'] = '500' }), label)
    end
    for _, item in ipairs(o.series) do
        local row = tableNode:tag('tr'):addClass('sc-ranking-row'):attr('data-rank', item.rank)
        literal(row:tag('td'):addClass('sc-rank'):css({ padding = '12px 4px', ['vertical-align'] = 'top', ['font-weight'] = '700' }), item.rank .. '.')
        local label = row:tag('th'):attr('scope', 'row'):css({ padding = '12px 4px', ['text-align'] = 'left', ['font-weight'] = item.rank == 1 and '700' or '400' })
        if o.trophy and item.rank == 1 then
            literal(label:tag('span'):addClass('sc-trophy'):attr('aria-hidden', 'true'):css('margin-right', '6px'), '🏆')
        end
        literal(label:tag('span'):addClass('sc-ranking-label'), item.label)
        local track = div(label, 'sc-ranking-track', { height = '8px', background = o.track, ['border-radius'] = '4px', overflow = 'hidden', ['margin-top'] = '7px' }):attr('aria-hidden', 'true')
        div(track, 'sc-ranking-bar', { height = '100%', width = percent(o.largest > 0 and item.value / o.largest * 100 or 0), background = item.color })
        literal(row:tag('td'):addClass('sc-ranking-value'):css({ padding = '12px 4px', ['text-align'] = 'right', ['vertical-align'] = 'top', ['font-variant-numeric'] = 'tabular-nums' }), o.format(item.value))
    end
end

local function stacked(root, o)
    local visual = div(root, 'sc-stacked', { display = 'flex', height = '28px', background = o.track, ['border-radius'] = '8px', overflow = 'hidden' }):attr('aria-hidden', 'true')
    for _, item in ipairs(o.series) do
        div(visual, 'sc-segment', { width = percent(o.total > 0 and item.value / o.total * 100 or 0), background = item.color })
    end
end

local function scrollBox(root, o, label)
    return div(root, 'sc-scroll', { ['overflow-x'] = 'auto', ['max-width'] = '100%' })
        :attr('tabindex', '0'):attr('role', 'region'):attr('aria-label', label)
end

local function columns(root, o)
    literal(div(root, 'sc-axis', { color = o.muted, ['font-size'] = '0.8em' }), '0 – ' .. o.format(o.ceiling))
    local outer = scrollBox(root, o, o.title ~= '' and o.title or 'Columns')
    local grouped = o.kind == 'grouped'
    local rows = grouped and o.rows or o.series
    local plot = div(outer, 'sc-columns', { display = 'grid', ['grid-template-columns'] = 'repeat(' .. #rows .. ',minmax(0,1fr))', gap = '12px', ['min-width'] = (#rows * (grouped and math.max(72, #o.columns * 22) or 48)) .. 'px' }):attr('aria-hidden', 'true')
    for _, row in ipairs(rows) do
        local cell = div(plot, 'sc-column-cell', { ['min-width'] = '0' })
        local group = div(cell, 'sc-column-group', { display = 'flex', ['align-items'] = 'flex-end', gap = '3px', height = cssnum(o.height) .. 'px', ['border-bottom'] = '1px solid ' .. o.muted, background = 'repeating-linear-gradient(to top,transparent 0%,transparent 24.5%,' .. o.track .. ' 24.5%,' .. o.track .. ' 25%)' })
        for j, value in ipairs(grouped and row.values or { row.value }) do
            div(group, 'sc-column', { flex = '1 1 0', height = percent(value / o.ceiling * 100), background = grouped and o.columns[j].color or row.color, ['border-radius'] = '3px 3px 0 0' })
        end
        literal(div(cell, 'sc-column-label', { ['text-align'] = 'center', ['font-size'] = '0.75em', ['overflow-wrap'] = 'anywhere', ['margin-top'] = '6px' }), row.label)
    end
end

local function heatColor(hex, ratio)
    if #hex == 4 then hex = '#' .. hex:sub(2,2):rep(2) .. hex:sub(3,3):rep(2) .. hex:sub(4,4):rep(2) end
    local rgb = {}
    for i = 1, 3 do
        local channel = tonumber(hex:sub(i * 2, i * 2 + 1), 16)
        rgb[i] = math.floor(255 + (channel - 255) * ratio + 0.5)
    end
    -- WCAG relative luminance: pick the higher-contrast black/white label.
    local linear = {}
    for i, value in ipairs(rgb) do
        local c = value / 255
        linear[i] = c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    local luminance = linear[1] * 0.2126 + linear[2] * 0.7152 + linear[3] * 0.0722
    return string.format('#%02x%02x%02x', rgb[1], rgb[2], rgb[3]), luminance > 0.179 and '#000000' or '#ffffff'
end

local function matrixTable(root, o)
    local heat = o.kind == 'heatmap'
    if heat then literal(div(root, 'sc-axis', { ['font-size'] = '0.85em', ['margin-bottom'] = '8px' }), '0 – ' .. o.format(o.ceiling)) end
    local box = scrollBox(root, o, o.title ~= '' and o.title or 'Chart data')
    local tableNode = box:tag('table'):addClass('sc-matrix'):css({ width = '100%', ['min-width'] = (110 + #o.columns * 64) .. 'px', ['table-layout'] = 'fixed', ['border-collapse'] = 'separate', ['border-spacing'] = '3px', ['font-size'] = '0.85em', ['margin-top'] = '12px', ['overflow-wrap'] = 'anywhere' })
    local header = tableNode:tag('tr')
    literal(header:tag('th'):attr('scope', 'col'), o.messages.label)
    for _, column in ipairs(o.columns) do
        local th = header:tag('th'):attr('scope', 'col'):css({ padding = '6px', ['font-weight'] = '500' })
        if not heat then th:tag('span'):attr('aria-hidden', 'true'):css({ display = 'inline-block', width = '9px', height = '9px', background = column.color, ['margin-right'] = '5px' }) end
        literal(th, column.label)
    end
    for _, row in ipairs(o.rows) do
        local tr = tableNode:tag('tr')
        literal(tr:tag('th'):attr('scope', 'row'):css({ ['text-align'] = 'left', ['font-weight'] = '400', padding = '6px' }), row.label)
        for _, value in ipairs(row.values) do
            local td = tr:tag('td'):css({ padding = '10px 6px', ['text-align'] = 'center', ['border-radius'] = '4px' })
            if heat then
                local bg, ink = heatColor(o.color, value / o.ceiling)
                td:addClass('sc-heat-cell'):css({ background = bg, color = ink })
            end
            literal(td, o.format(value))
        end
    end
    if o.largest == 0 then literal(div(root, 'sc-empty'), o.messages.empty) end
end

local function gantt(root, o)
    local scale = div(root, 'sc-gantt-scale', { display = 'flex', ['justify-content'] = 'space-between', gap = '8px', ['font-size'] = '0.8em', color = o.muted })
    literal(scale:tag('span'), o.from)
    literal(scale:tag('span'), o.to)
    for _, task in ipairs(o.tasks) do
        local row = div(root, 'sc-task', { ['margin-top'] = '16px', ['overflow-wrap'] = 'anywhere' })
        literal(div(row, 'sc-task-label', { ['font-weight'] = '600', ['font-size'] = '0.9em' }), task.label)
        literal(div(row, 'sc-task-dates', { ['font-size'] = '0.8em', color = o.muted, ['margin-bottom'] = '5px' }), task.start .. ' – ' .. task.finish .. ' · ' .. display(task.progress, 1) .. '%')
        local track = div(row, 'sc-gantt-track', { position = 'relative', height = '18px', background = o.track, ['border-radius'] = '4px' }):attr('aria-hidden', 'true')
        local bar = div(track, 'sc-task-bar', { position = 'absolute', top = '0', bottom = '0', left = percent((task.a - o.first) / o.days * 100), width = percent((task.b - task.a + 1) / o.days * 100), background = task.color, ['border-radius'] = '4px', overflow = 'hidden' })
        div(bar, 'sc-task-progress', { width = percent(task.progress), height = '100%', background = 'rgba(0,0,0,0.28)' })
    end
end

local function scalar(root, o)
    if o.kind == 'gauge' then
        local a = (o.warning - o.min) / (o.max - o.min) * 180
        local b = (o.danger - o.min) / (o.max - o.min) * 180
        local gradient = 'conic-gradient(from 270deg,' .. o.lowcolor .. ' 0deg ' .. cssnum(a) .. 'deg,' .. o.warncolor .. ' ' .. cssnum(a) .. 'deg ' .. cssnum(b) .. 'deg,' .. o.highcolor .. ' ' .. cssnum(b) .. 'deg 180deg,transparent 180deg 360deg)'
        local visual = div(root, 'sc-gauge', { position = 'relative', width = '100%', ['aspect-ratio'] = '2 / 1', overflow = 'hidden' }):attr('aria-hidden', 'true')
        local arc = div(visual, 'sc-gauge-arc', { position = 'absolute', top = '0', left = '0', width = '100%', ['aspect-ratio'] = '1', ['border-radius'] = '50%', background = gradient })
        div(arc, 'sc-gauge-hole', { position = 'absolute', inset = '14%', ['border-radius'] = '50%', background = o.bg })
        div(visual, 'sc-needle', { position = 'absolute', left = '5%', top = '100%', width = '45%', height = '4px', ['margin-top'] = '-2px', background = o.ink, ['border-radius'] = '2px', ['transform-origin'] = '100% 50%', transform = 'rotate(' .. cssnum(o.ratio * 180) .. 'deg)' })
        div(visual, 'sc-pivot', { position = 'absolute', left = '50%', bottom = '-7px', width = '14px', height = '14px', ['margin-left'] = '-7px', ['border-radius'] = '50%', background = o.ink })
    elseif o.kind == 'bullet' then
        local a = (o.warning - o.min) / (o.max - o.min) * 100
        local b = (o.danger - o.min) / (o.max - o.min) * 100
        local track = div(root, 'sc-bullet', { position = 'relative', height = '34px', background = 'linear-gradient(to right,' .. o.lowcolor .. ' 0% ' .. percent(a) .. ',' .. o.warncolor .. ' ' .. percent(a) .. ' ' .. percent(b) .. ',' .. o.highcolor .. ' ' .. percent(b) .. ' 100%)' }):attr('aria-hidden', 'true')
        div(track, 'sc-bullet-value', { position = 'absolute', top = '11px', height = '12px', width = percent(o.ratio * 100), background = o.ink, ['box-shadow'] = '0 0 0 1px ' .. o.bg })
        div(track, 'sc-target', { position = 'absolute', top = '2px', bottom = '2px', left = percent((o.target - o.min) / (o.max - o.min) * 100), width = '3px', transform = 'translateX(-50%)', background = o.ink, ['box-shadow'] = '0 0 0 1px ' .. o.bg })
    else
        local track = div(root, 'sc-progress', { background = o.track, height = '16px', ['border-radius'] = '8px', overflow = 'hidden' }):attr('aria-hidden', 'true')
        div(track, 'sc-fill', { width = percent(o.ratio * 100), height = '100%', background = o.color })
    end
    local scale = div(root, 'sc-scale', { display = 'flex', ['justify-content'] = 'space-between', gap = '12px', color = o.muted, ['font-size'] = '0.8em', ['margin-top'] = '8px' })
    literal(scale:tag('span'), o.format(o.min))
    literal(scale:tag('span'), o.format(o.max))
    literal(div(root, 'sc-value', { ['text-align'] = 'center', ['font-size'] = '1.8em', ['font-weight'] = '700', ['line-height'] = '1.4', ['overflow-wrap'] = 'anywhere' }), o.format(o.value))
    if o.kind == 'bullet' then
        literal(div(root, 'sc-target-label', { ['text-align'] = 'center', ['font-size'] = '0.9em' }), (o.lang == 'ru' and 'Цель: ' or 'Target: ') .. o.format(o.target))
    end
    if o.kind == 'gauge' or o.kind == 'bullet' then
        literal(div(root, 'sc-thresholds', { ['font-size'] = '0.8em', color = o.muted, ['text-align'] = 'center' }), o.messages.warning .. ' ≥ ' .. o.format(o.warning) .. ' · ' .. o.messages.danger .. ' ≥ ' .. o.format(o.danger))
    end
    if o.outside then
        literal(div(root, 'sc-notice', { ['margin-top'] = '8px', ['font-size'] = '0.85em' }), o.messages.outside)
    end
end

local function render(config)
    local o = options(config)
    local root = mw.html.create('div'):addClass('scribunto-chart sc-chart-' .. o.kind):css({ width = '100%', ['max-width'] = cssnum(o.size + 40) .. 'px', ['box-sizing'] = 'border-box', padding = '20px', margin = '1em 0', background = o.bg, color = o.ink, border = '1px solid ' .. o.track, ['border-radius'] = '16px', ['font-family'] = 'inherit', ['line-height'] = '1.5' })
    if o.title ~= '' then literal(div(root, 'sc-title', { ['font-size'] = '1.05em', ['font-weight'] = '700', ['margin-bottom'] = '18px', ['overflow-wrap'] = 'anywhere' }), o.title) end
    if o.kind == 'donut' or o.kind == 'pie' then roundChart(root, o)
    elseif o.kind == 'bars' then bars(root, o)
    elseif o.kind == 'leaderboard' then leaderboard(root, o)
    elseif o.kind == 'stacked' then stacked(root, o)
    elseif o.kind == 'columns' or o.kind == 'grouped' then columns(root, o)
    elseif o.kind == 'gantt' then gantt(root, o)
    elseif o.kind == 'heatmap' then -- the colored data table is the visualization
    else scalar(root, o) end
    if o.rows then matrixTable(root, o) end
    if o.series and o.kind ~= 'leaderboard' then
        if o.total == 0 then literal(div(root, 'sc-empty', { ['margin-top'] = '10px' }), o.messages.empty) end
        literal(div(root, 'sc-summary', { ['margin-top'] = '12px', color = o.muted, ['font-size'] = '0.85em' }), o.centerlabel .. ': ' .. o.format(o.total))
        legend(root, o)
    end
    if o.caption ~= '' then literal(div(root, 'sc-caption', { ['margin-top'] = '14px', ['font-size'] = '0.85em', color = o.muted, ['overflow-wrap'] = 'anywhere' }), o.caption) end
    return tostring(root)
end

-- Public Lua API; validation errors are readable, escaped output, not tracebacks.
function p.render(config)
    local ok, result = pcall(render, config)
    if ok then return result end
    return tostring(literal(mw.html.create('div'):addClass('scribunto-chart-error'):attr('role', 'alert'), 'Charts: ' .. tostring(result)))
end

local function fromFrame(frame, kind)
    local config = {}
    for key, value in pairs(frame.args) do
        if type(value) == 'string' then value = mw.text.trim(value) end
        if value ~= '' then config[key] = value end
    end
    config.type = kind or config.type
    return p.render(config)
end
function p.chart(frame) return fromFrame(frame) end
for kind in pairs(kinds) do
    local name = kind
    p[name] = function(frame) return fromFrame(frame, name) end
end
return p
