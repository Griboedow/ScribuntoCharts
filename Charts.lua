-- Module:Charts — CSS-only charts for MediaWiki Scribunto. MIT license.
local p = {}
local palettes = {
    ocean = { '#2563eb', '#0d9488', '#f59e0b', '#8b5cf6', '#e11d48', '#64748b' },
    sunset = { '#ea580c', '#e11d48', '#9333ea', '#f59e0b', '#be185d', '#475569' },
    forest = { '#047857', '#65a30d', '#0e7490', '#ca8a04', '#7c3aed', '#475569' },
    mono = { '#172554', '#1e40af', '#2563eb', '#60a5fa', '#93c5fd', '#bfdbfe' }
}
local kinds = { donut = true, pie = true, gauge = true, bars = true, stacked = true, progress = true }
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
    o.size = bounded(config.size, (o.kind == 'bars' or o.kind == 'stacked' or o.kind == 'progress') and 420 or 260, 120, 640, 'Size')
    o.decimals = bounded(config.decimals, 1, 0, 4, 'Decimals')
    if o.decimals % 1 ~= 0 then fail('Decimals must be an integer.') end
    o.hole = bounded(config.hole, 64, 35, 85, 'Hole')
    o.palette = palettes[text(config.palette, 'ocean')]
    if not o.palette then fail('Unknown palette. Use ocean, sunset, forest or mono.') end
    o.color = color(config.color, o.palette[1])
    o.format = function(n) return display(n, o.decimals) .. (o.unit ~= '' and ' ' .. o.unit or '') end
    if o.kind == 'gauge' or o.kind == 'progress' then
        o.min = number(config.min, 0, 'Minimum')
        o.max = number(config.max, 100, 'Maximum')
        if o.max <= o.min then fail('Maximum must be greater than minimum.') end
        o.value = number(config.value, nil, 'Value')
        o.ratio = math.max(0, math.min(1, (o.value - o.min) / (o.max - o.min)))
        o.outside = o.value < o.min or o.value > o.max
        if o.kind == 'gauge' then
            o.warning = number(config.warning, o.min + (o.max - o.min) * 0.6, 'Warning threshold')
            o.danger = number(config.danger, o.min + (o.max - o.min) * 0.85, 'Danger threshold')
            if not (o.min < o.warning and o.warning < o.danger and o.danger < o.max) then
                fail('Thresholds must satisfy min < warning < danger < max.')
            end
            o.lowcolor = color(config.lowcolor, '#0d9488')
            o.warncolor = color(config.warncolor, '#f59e0b')
            o.highcolor = color(config.highcolor, '#ef4444')
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

local function stacked(root, o)
    local visual = div(root, 'sc-stacked', { display = 'flex', height = '28px', background = o.track, ['border-radius'] = '8px', overflow = 'hidden' }):attr('aria-hidden', 'true')
    for _, item in ipairs(o.series) do
        div(visual, 'sc-segment', { width = percent(o.total > 0 and item.value / o.total * 100 or 0), background = item.color })
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
    else
        local track = div(root, 'sc-progress', { background = o.track, height = '16px', ['border-radius'] = '8px', overflow = 'hidden' }):attr('aria-hidden', 'true')
        div(track, 'sc-fill', { width = percent(o.ratio * 100), height = '100%', background = o.color })
    end
    local scale = div(root, 'sc-scale', { display = 'flex', ['justify-content'] = 'space-between', gap = '12px', color = o.muted, ['font-size'] = '0.8em', ['margin-top'] = '8px' })
    literal(scale:tag('span'), o.format(o.min))
    literal(scale:tag('span'), o.format(o.max))
    literal(div(root, 'sc-value', { ['text-align'] = 'center', ['font-size'] = '1.8em', ['font-weight'] = '700', ['line-height'] = '1.4', ['overflow-wrap'] = 'anywhere' }), o.format(o.value))
    if o.kind == 'gauge' then
        literal(div(root, 'sc-thresholds', { ['font-size'] = '0.8em', color = o.muted, ['text-align'] = 'center' }), o.messages.warning .. ' ≥ ' .. o.format(o.warning) .. ' · ' .. o.messages.danger .. ' ≥ ' .. o.format(o.danger))
    end
    if o.outside then
        literal(div(root, 'sc-notice', { ['margin-top'] = '8px', ['font-size'] = '0.85em' }), o.messages.outside)
    end
end

local function render(config)
    local o = options(config)
    local root = mw.html.create('div'):addClass('scribunto-chart sc-' .. o.kind):css({ width = '100%', ['max-width'] = cssnum(o.size + 40) .. 'px', ['box-sizing'] = 'border-box', padding = '20px', margin = '1em 0', background = o.bg, color = o.ink, border = '1px solid ' .. o.track, ['border-radius'] = '16px', ['font-family'] = 'inherit', ['line-height'] = '1.5' })
    if o.title ~= '' then literal(div(root, 'sc-title', { ['font-size'] = '1.05em', ['font-weight'] = '700', ['margin-bottom'] = '18px', ['overflow-wrap'] = 'anywhere' }), o.title) end
    if o.kind == 'donut' or o.kind == 'pie' then roundChart(root, o)
    elseif o.kind == 'bars' then bars(root, o)
    elseif o.kind == 'stacked' then stacked(root, o)
    else scalar(root, o) end
    if o.series then
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
