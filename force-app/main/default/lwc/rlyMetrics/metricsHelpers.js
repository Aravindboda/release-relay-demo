/**
 * Formatting, trends, chart geometry and CSV for the Metrics tab (rlyMetrics). Plain functions, no Salesforce imports.
 */

/** Chart size in SVG units (the SVG scales to its card). */
export const CHART = { width: 560, height: 190, left: 8, right: 8, top: 22, bottom: 30 };
const BAR_COLOR = { count: '#0b5cab', hours: '#0b5cab', percent: '#ba0517' };

function one(n) {
    return Math.round(n * 10) / 10;
}

/** A value in its unit: 24 · 5.2 h · 3.4 days · 8%; a dash when there's nothing to measure. */
export function formatValue(value, unit) {
    if (value === null || value === undefined) {
        return '—';
    }
    if (unit === 'percent') {
        return Math.round(value) + '%';
    }
    if (unit === 'hours') {
        return value >= 48 ? one(value / 24) + ' days' : one(value) + ' h';
    }
    return String(Math.round(value));
}

/** A difference in a unit's words: 6 · 1.1 days · 2 points. */
function formatDelta(delta, unit) {
    const d = Math.abs(delta);
    if (unit === 'percent') {
        return Math.round(d) + (Math.round(d) === 1 ? ' point' : ' points');
    }
    if (unit === 'hours') {
        return d >= 48 ? one(d / 24) + ' days' : one(d) + ' h';
    }
    return String(Math.round(d));
}

/**
 * The tile's trend against the period before: its words and whether it's better, worse or the same.
 * @param tile {value, previous, unit, higherIsBetter}
 * @param days the period's length
 */
export function trendOf(tile, days) {
    if (tile.value === null || tile.value === undefined || tile.previous === null || tile.previous === undefined) {
        return { text: 'nothing to compare with the ' + days + ' days before', tone: 'flat' };
    }
    const delta = tile.value - tile.previous;
    if (Math.abs(delta) < (tile.unit === 'hours' ? 0.05 : 0.5)) {
        return { text: 'same as the ' + days + ' days before', tone: 'flat' };
    }
    const better = tile.higherIsBetter ? delta > 0 : delta < 0;
    let words;
    if (tile.unit === 'hours') {
        words = formatDelta(delta, tile.unit) + (delta < 0 ? ' faster' : ' slower');
    } else {
        words = formatDelta(delta, tile.unit) + (delta > 0 ? ' more' : ' fewer');
    }
    return { text: (delta > 0 ? '▲ ' : '▼ ') + words + ' than the ' + days + ' days before', tone: better ? 'up' : 'down' };
}

/**
 * Bars for one chart: geometry, value labels above the bars, axis labels thinned so they never overlap, and a title
 * (the browser's tooltip) per bar.
 * @param series {label, unit, points: [{label, value, count}]}
 */
export function barsOf(series) {
    const points = series.points || [];
    const n = Math.max(points.length, 1);
    const inner = CHART.width - CHART.left - CHART.right;
    const slot = inner / n;
    const barWidth = Math.max(4, Math.min(48, slot * 0.7));
    const max = Math.max(...points.map((p) => p.value || 0), series.unit === 'percent' ? 10 : 1);
    const plotHeight = CHART.height - CHART.top - CHART.bottom;
    const every = Math.ceil(n / 8);
    return points.map((p, i) => {
        const v = p.value || 0;
        const h = p.value === null || p.value === undefined ? 0 : Math.max(2, (v / max) * plotHeight);
        const x = CHART.left + i * slot + (slot - barWidth) / 2;
        const y = CHART.top + plotHeight - h;
        const valueText = p.value === null || p.value === undefined ? '' : formatValue(p.value, series.unit);
        const made = series.unit === 'count' ? '' : ' (' + (p.count || 0) + ')';
        return {
            key: series.key + '-' + i,
            x: one(x), y: one(y), width: one(barWidth), height: one(h),
            cx: one(x + barWidth / 2), valueY: one(y - 5), labelY: CHART.height - 10,
            valueText,
            axisText: i % every === 0 ? p.label : '',
            title: p.label + ': ' + (valueText || 'nothing') + made,
            fill: BAR_COLOR[series.unit] || BAR_COLOR.count
        };
    });
}

/** Horizontal bars: the widest is 100%, sorted largest first, at most `top`. */
export function hbarsOf(bars, top) {
    const sorted = [...(bars || [])].filter((b) => b.value > 0).sort((a, b) => b.value - a.value || a.label.localeCompare(b.label)).slice(0, top);
    const max = Math.max(...sorted.map((b) => b.value), 1);
    return sorted.map((b) => ({ key: b.label, label: b.label, value: b.value, style: 'width:' + Math.round((b.value / max) * 100) + '%' }));
}

/** Adds one part's bars to the running totals. */
export function mergeBars(totals, part) {
    const byLabel = new Map((totals || []).map((b) => [b.label, { ...b }]));
    (part || []).forEach((b) => {
        const t = byLabel.get(b.label) || { label: b.label, value: 0 };
        t.value += b.value;
        byLabel.set(b.label, t);
    });
    return [...byLabel.values()];
}

function csvCell(v) {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

/** Every number on the page as CSV: tiles (this period and the one before), each chart's points, the reasons and files. */
export function csvOf(metrics, reasons, files, filterText) {
    const rows = [['Section', 'Measure', 'Period', 'Value', 'Unit', 'Made of'], ['Filters', filterText, '', '', '', '']];
    (metrics.tiles || []).forEach((t) => {
        rows.push(['Tile', t.label, 'This period', t.value, t.unit, t.detail]);
        rows.push(['Tile', t.label, 'Period before', t.previous, t.unit, '']);
    });
    (metrics.series || []).forEach((s) => (s.points || []).forEach((p) => rows.push(['Chart', s.label, p.day, p.value, s.unit, p.count])));
    (reasons || []).forEach((b) => rows.push(['Why checks fail', b.label, 'This period', b.value, 'count', '']));
    (files || []).forEach((b) => rows.push(['Files that conflict most', b.label, 'This period', b.value, 'count', '']));
    return rows.map((r) => r.map(csvCell).join(',')).join('\r\n');
}
