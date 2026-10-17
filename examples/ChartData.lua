-- Optional: save as Module:ChartData, invoke {{#invoke:ChartData|budget}}.
local charts = require('Module:Charts')
local p = {}
function p.budget()
    return charts.render({
        type = 'donut', title = 'Project budget', unit = 'EUR',
        caption = 'Planned spending, not actual expenses.',
        series = {
            { label = 'Development', value = 5400, color = '#2563eb' },
            { label = 'Design', value = 2100, color = '#0d9488' },
            { label = 'Testing', value = 1500, color = '#f59e0b' },
            { label = 'Reserve', value = 1000, color = '#8b5cf6' }
        }
    })
end
return p
