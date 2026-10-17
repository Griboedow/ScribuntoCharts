# ScribuntoCharts

**CSS-only charts for MediaWiki. One Lua module, eleven chart types, no JavaScript.**

Donut and pie charts, a semicircular gauge with a needle and threshold bands,
horizontal and vertical bars, grouped columns, a stacked bar, a progress indicator,
a bullet chart, a heatmap and Gantt timelines. Charts are rendered by
Scribunto as HTML and inline CSS. No TemplateStyles, API extension, external
service, images, canvas, or client-side chart library is required.

![Gauge and bars rendered on MediaWiki 1.43](docs/gauge-bars.jpg)

[View the full gallery screenshot](docs/gallery.jpg) · [Copy the gallery wikitext](examples/Gallery.wikitext)

## Install

1. Enable **Scribunto** on your MediaWiki installation.
2. Create **Module:Charts** and copy the contents of [Charts.lua](Charts.lua).
3. Paste an invocation below into a normal wiki page.

The module targets MediaWiki **1.43+**. CI runs the actual Lua module and MediaWiki
parser on the 1.43, 1.44, 1.45 and 1.46 release lines. Use a modern browser with
CSS `conic-gradient` and `aspect-ratio` support. Data is also available as ordinary
text and semantic tables if graphics are unavailable. A skin or site policy that
removes inline styles will affect the graphics.

**По-русски:** скопируйте `Charts.lua` на страницу `Module:Charts`, затем вставьте
пример на вики-страницу. Параметр `lang=ru` включает русские служебные подписи.
Модуль работает без JavaScript и без установки дополнительных расширений, кроме
Scribunto. [Полная галерея для копирования](examples/Gallery.wikitext).

## Quick start: a donut

```wikitext
{{#invoke:Charts|donut
 |title=Бюджет проекта
 |lang=ru |unit=EUR
 |label1=Разработка |value1=5400 |color1=#2563eb
 |label2=Дизайн |value2=2100 |color2=#0d9488
 |label3=Тестирование |value3=1500 |color3=#f59e0b
 |label4=Резерв |value4=1000 |color4=#8b5cf6
 |caption=Плановые расходы по направлениям.
}}
```

Values are normalized into slices automatically. The center shows the total;
the table contains every label, value and percentage. Change `donut` to `pie`
for a solid circular chart. Use `hole=72` for a thinner ring.

## Gauge: a speedometer for a bounded metric

```wikitext
{{#invoke:Charts|gauge
 |title=Storage used |value=72 |unit=%
 |min=0 |max=100 |warning=60 |danger=85
 |caption=Warning at 60%, danger at 85%.
}}
```

The needle moves from left (minimum), through the top (midpoint), to right
(maximum). Thresholds are **values in the same units as the metric**, not
percentages of the scale. For temperature, for example:

```wikitext
{{#invoke:Charts|gauge|title=Temperature|value=-5|min=-40|max=40
 |warning=10|danger=25|unit=°C|theme=dark}}
```

An out-of-range value is still displayed accurately. Only the needle is clamped,
and a visible notice explains it. These default bands model **higher is worse**;
choose colors and thresholds appropriate for your metric.

## Bars, stacked shares and progress

```wikitext
{{#invoke:Charts|bars|title=Documentation coverage|unit=pages
 |label1=Getting started|value1=38
 |label2=API reference|value2=64
 |label3=Tutorials|value3=27}}

{{#invoke:Charts|stacked|title=Release pipeline|theme=dark
 |label1=Ready|value1=42|color1=#2dd4bf
 |label2=In review|value2=18|color2=#60a5fa
 |label3=Blocked|value3=6|color3=#fb7185}}

{{#invoke:Charts|progress|title=Translation goal
 |value=840|max=1200|unit=pages|color=#0d9488}}
```

Bars compare against the **largest value** in the series. The stacked bar compares
each value against the **total**. Progress fills `(value - min) / (max - min)`;
its default range is 0–100. For a percentage, use `unit=%` explicitly.

The generic entry point also works: `{{#invoke:Charts|chart|type=pie|value1=3|value2=7}}`.
Arguments are read from the invocation itself. In a template wrapper, forward
parameters explicitly, for example `|value={{{value|0}}}`.

## Use from another Lua module

See also [the five advanced chart examples](examples/Advanced.wikitext).

```lua
local charts = require('Module:Charts')
local p = {}

function p.workload()
    return charts.render({
        type = 'bars', title = 'Open work', size = 420,
        series = {
            { label = 'Documentation', value = 12 },
            { label = 'Bugs', value = 7, color = '#e11d48' },
            { label = 'Features', value = 18 }
        }
    })
end

return p
```

`render(config)` returns a string ready for a module's return value. It accepts
the same options as the wikitext interface; `series` is a consecutive Lua array
of `{ label, value, color }` records, with `value` required. When present, `series`
supplies the items instead of the numbered arguments. There is also a complete
[Module:ChartData example](examples/ChartData.lua).

## Vertical columns and grouped comparisons

```wikitext
{{#invoke:Charts|columns|title=Monthly releases|max=40
 |label1=January|value1=10|label2=February|value2=20|label3=March|value3=40}}

{{#invoke:Charts|grouped|title=Plan and actual|max=100
 |column1=Plan|column2=Actual|seriescolor2=#0d9488
 |label1=January|row1=40,30
 |label2=February|row2=60,65
 |label3=March|row3=80,75}}
```

Both types start at zero and use **one common scale**. `max` defaults to the
largest value and must cover all values when specified. `height` sets the plot
height (80–400 px, default 180). `columns` uses the usual `valueN`/`labelN` or
`series` inputs. `grouped` uses category rows and series columns, as above.
Colors identify series consistently across groups. Wide plots scroll inside a
keyboard-focusable region; values are also listed in a table.

## Bullet chart: actual value, target and ranges

```wikitext
{{#invoke:Charts|bullet|title=Response time|value=72|target=85
 |min=0|max=100|warning=60|danger=90|unit=ms}}
```

The thick bar is the actual value, the thin vertical marker is the target.
Scale, threshold colors and out-of-range value handling follow `gauge`.
`target` is required and must lie within the scale; an invalid target is rejected.
The default bands mean higher is worse, so choose appropriate colors for
metrics where higher is better. The target and thresholds are also printed as text.

## Heatmap: compare a whole matrix

```wikitext
{{#invoke:Charts|heatmap|title=Support load|color=#0f766e|max=20
 |column1=Morning|column2=Afternoon|column3=Evening
 |label1=Monday|row1=3,12,1
 |label2=Tuesday|row2=8,20,5}}
```

Zero is white; `max` uses the full `color`. Intermediate shades use one linear
color interpolation across the entire matrix. The default maximum is the
largest cell (1 for an all-zero matrix); an explicit maximum cannot hide larger
values. Each cell includes its value, and its black/white text color is selected
from relative luminance for contrast. Dark theme still uses this white-to-color
scale. The matrix has semantic row/column headers and scrolls inside the card.

For `heatmap` and `grouped`, use consecutive `column1`…`column12` and
`row1`…`row30`, with optional `labelN` row labels. A row is a comma-separated
list of **non-negative numbers using a decimal point**, with exactly one value
per column. Blank cells, ragged rows, missing indexes and excess entries are
errors. `seriescolorN` overrides a grouped series color. The Lua equivalent is:

```lua
return charts.render({
    type = 'grouped', max = 100,
    columns = { 'Plan', { label = 'Actual', color = '#0d9488' } },
    rows = {
        { label = 'January', values = { 40, 30 } },
        { label = 'February', values = { 60, 65 } }
    }
})
```

Use this inside a function in a module that imports `charts`, as in the Lua
example above. Structured `columns` and `rows` arrays replace the corresponding
numbered arguments. Change `type` to `heatmap` to visualize the same data as cells.

## Gantt: dates and task completion

```wikitext
{{#invoke:Charts|gantt|title=Release schedule
 |from=2028-02-28|to=2028-03-08
 |label1=Build|start1=2028-02-28|finish1=2028-03-01|progress1=100
 |label2=Review|start2=2028-03-01|finish2=2028-03-06|progress2=50
 |label3=Release|start3=2028-03-08|finish3=2028-03-08}}
```

`startN` and `finishN` are required ISO dates (`YYYY-MM-DD`, Gregorian years
0001–9999). **Both endpoints are inclusive**: a same-day task has a one-day bar.
Leap days are handled without time zones or daylight-saving conversions.
Overlapping tasks are allowed; reversed/invalid dates are rejected.

The default timeline covers all tasks. Optional `from`/`to` must contain every
task; nothing is silently clipped. `progressN` is completion from 0–100,
default 0; the darker part of the bar shows it, with a text percentage alongside
the dates. There are up to 30 tasks, with optional `labelN` and `colorN`.
In Lua, pass a consecutive `tasks` array instead:

```lua
return charts.render({
    type = 'gantt',
    tasks = {
        { label = 'Build', start = '2028-02-28', finish = '2028-03-01', progress = 100 },
        { label = 'Review', start = '2028-03-01', finish = '2028-03-06', color = '#0d9488' }
    }
})
```

This is a static day-based timeline. Very short tasks in a long date range can
be subpixel-wide; their full dates and completion remain visible in text.

## Options

| Option | Meaning / default |
|---|---|
| `type` | `donut` (default), `pie`, `gauge`, `bars`, `stacked`, `progress`, `columns`, `grouped`, `bullet`, `heatmap`, `gantt`. Named entry points fix the type. |
| `title`, `caption` | Optional plain-text title and description. |
| `lang` | `en` (default) or `ru` for built-in labels and notices. Validation messages are English. |
| `unit` | Plain-text suffix shown with values, e.g. `%`, `EUR`, `pages`, `°C`. |
| `size` | Maximum graphic width in pixels, 120–640. Default 260 for donut/pie/gauge, 420 for the other types. The card adds 40 px of padding and shrinks to its container. Wide matrices/column plots scroll inside it. |
| `decimals` | 0–4, default 1. Display rounding only; trailing zeroes are removed. Tiny nonzero values use three significant digits instead of becoming zero. Calculations use the original values. |
| `theme` | `light` (default) or `dark`; explicit, independent of the skin theme. |
| `background` | Optional hex card/hole background. Text color follows `theme`; choose compatible colors. |
| `palette` | `ocean` (default), `sunset`, `forest`, `mono`. Colors repeat after six items. |
| `label1` … `label30` | Plain-text item names; default `Item N`. |
| `value1` … `value30` | Required consecutive non-negative values for series charts. Decimal point, not comma. |
| `color1` … `color30` | Optional per-item hex colors, overriding the palette. |
| `hole` | Donut hole diameter as a percentage of the outer diameter, 35–85; default 64. |
| `centerlabel` | Label for the total, default `Total` / `Всего`. |
| `value`, `min`, `max` | Gauge/progress metric and scale. `value` is required, defaults for the scale are 0 and 100. Negative scale values are supported. |
| `warning`, `danger` | Gauge thresholds. Default 60% and 85% along the scale. Must satisfy `min < warning < danger < max`. |
| `lowcolor`, `warncolor`, `highcolor` | Gauge band colors. Defaults: teal, amber, red. |
| `color` | Progress fill or heatmap maximum color; default first palette color. |

## Data and rendering rules

- Series charts accept 1–30 items with finite, non-negative values. Each numeric
  input has magnitude at most `1e12`. Missing items, negative series values,
  invalid thresholds and invalid colors produce a readable error, rather than
  silently discarding data.
- Zero-valued items remain in the table. An all-zero series displays an empty
  track, a notice and `—` shares; it never invents equal-sized slices.
- Colors accept only `#RGB` / `#RRGGBB`. Text is escaped; labels and captions do
  not execute HTML or wikitext. When calling from wikitext, the normal parser
  expands arguments first; literal pipes still require normal template escaping.
- Diagrams are static and decorative for assistive technology. Series data is
  exposed in a table with row/column headers; gauge/progress values, endpoints
  and gauge thresholds remain visible text. Color is not the only way to read
  the data. Very small slices and rounded percentages can be visually tiny or
  be nearly invisible; their values and shares remain in the table.
- The module does not fetch data or install scripts. MediaWiki's own skin may
  use JavaScript, but these charts do not require it. There are no hover-only
  values, animation, or interactive controls.
- Pure CSS graphics depend on browser/print settings. Printing with background
  graphics disabled can hide the fills; the text and tables remain useful.
- Charts follow normal MediaWiki parser caching. Modules that obtain changing
  data must handle their own data freshness and cache dependencies.

## Tests

On a **disposable** MediaWiki installation with Scribunto and an `Admin` account:

```sh
MW_INSTALL_PATH=/path/to/wiki php tests/wiki.php --disposable-wiki
```

This overwrites `Module:Charts`, `Module:ChartsTests`, `Module:ChartData` and
`Charts demo` and `Charts advanced` on that test wiki. It tests calculations, needle endpoints,
clamping, zero totals, invalid data, literal labels, real parser sanitization
and the examples. [The workflow](.github/workflows/tests.yml) runs the same checks
in disposable MediaWiki containers. Browser checks additionally load the gallery
at 1366 px and 390 px with JavaScript **disabled**, verify the shapes and lack of
page-level horizontal overflow, and save screenshots as workflow artifacts.
Advanced checks verify column scales, target positions, inclusive Gantt dates,
heatmap colors and narrow-screen scrolling. Tables and plots may intentionally
scroll inside their own cards.
Production module code is [Charts.lua](Charts.lua);
test runners are not needed on your wiki.

## License

[MIT](LICENSE).
