/**
 * Pipeline tab layout (build 50): the status strip's tiles, the seven sections down the left (a select on narrow
 * screens), their status dots, and the Recent changes to settings list. Pure helpers: the component passes in what it
 * has (RlyPipelineSummary.summary, the page's own pipeline-files check) and renders what these return.
 */

/** The sections in list order. Each tile opens one of them. */
export const SECTIONS = [
    { key: 'connection', label: 'Connection & route', sub: '' },
    { key: 'orgs', label: 'Orgs', sub: '' },
    { key: 'approvals', label: 'Approvals & Slack', sub: '' },
    { key: 'tracking', label: 'Work tracking', sub: '' },
    { key: 'security', label: 'Security & credentials', sub: '' },
    { key: 'retention', label: 'Retention & archive', sub: '' },
    { key: 'advanced', label: 'Advanced', sub: 'values · gates · lock' }
];
export const DEFAULT_SECTION = 'connection';
/** Where this browser remembers the open section (per viewer, best effort). */
const SECTION_STORE = 'rly.pipeline.section';
const TONE_WORDS = { ok: 'OK', warn: 'Needs a look', bad: 'Needs fixing', none: 'Not set up' };
const DAY = 86400000;

function known(key) {
    return SECTIONS.some((s) => s.key === key);
}

/** The section this browser last opened; Connection & route when none, unknown or storage is blocked. */
export function readSection() {
    try {
        const v = window.localStorage.getItem(SECTION_STORE);
        return known(v) ? v : DEFAULT_SECTION;
    } catch {
        return DEFAULT_SECTION;
    }
}

export function writeSection(key) {
    try {
        window.localStorage.setItem(SECTION_STORE, key);
    } catch {
        // Storage blocked (private window, previews): the section is remembered for this page only.
    }
}

export function sectionKnown(key) {
    return known(key);
}

export function sectionLabel(key) {
    const s = SECTIONS.find((x) => x.key === key);
    return s ? s.label : '';
}

function dotCls(tone) {
    return 'rr-sd rr-sd-' + (TONE_WORDS[tone] ? tone : 'none');
}

/**
 * The list down the left: label, dot (with its meaning for screen readers), the Orgs count, aria-current on the open one,
 * and "Editing" on the section whose form is open.
 */
export function navItems(current, dots, orgCount, editingKey) {
    const d = dots || {};
    return SECTIONS.map((s) => {
        const tone = d[s.key] || 'none';
        const on = s.key === current;
        return {
            key: s.key,
            label: s.label,
            sub: s.sub,
            hasSub: !!s.sub,
            current: on ? 'true' : undefined,
            selected: on,
            cls: 'rr-nav-btn' + (on ? ' rr-nav-on' : ''),
            dotCls: dotCls(tone),
            toneText: TONE_WORDS[tone] || TONE_WORDS.none,
            count: s.key === 'orgs' ? String(orgCount || 0) : '',
            hasCount: s.key === 'orgs',
            editing: s.key === editingKey
        };
    });
}

/**
 * The five tiles. The Git tile's grey line becomes the pipeline-files version (with an "update to vN" chip) once the
 * page's own files check has answered; everything else comes from the stored summary.
 */
export function tileViews(summary, files, activeTile) {
    const tiles = (summary && summary.tiles) || [];
    return tiles.map((t) => {
        let detail = t.detail || '';
        let chip = '';
        if (t.key === 'git' && files && files.state && t.tone !== 'bad') {
            detail = files.state.repoVersion === null || files.state.repoVersion === undefined
                ? 'pipeline files not found' : 'pipeline files v' + files.state.repoVersion;
            chip = files.state.upToDate ? '' : 'update to v' + files.state.packagedVersion;
        } else if (t.key === 'git' && files && files.loading && t.tone !== 'bad') {
            detail = 'checking pipeline files…';
        }
        const on = t.key === activeTile;
        return {
            key: t.key,
            label: t.label,
            value: t.value,
            detail,
            chip,
            hasChip: !!chip,
            section: t.section,
            cls: 'rr-tile' + (on ? ' rr-tile-on' : ''),
            valueCls: 'rr-tile-v rr-tone-' + (t.tone || 'none'),
            title: 'Open ' + sectionLabel(t.section)
        };
    });
}

/** The first tile of a section (highlighted when the section is opened from the list). */
export function firstTileOf(summary, section) {
    const t = ((summary && summary.tiles) || []).find((x) => x.section === section);
    return t ? t.key : undefined;
}

function shortDate(value) {
    if (!value) {
        return '';
    }
    try {
        return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' }).format(new Date(value));
    } catch {
        return String(value);
    }
}

/** "today", "yesterday" or "2 Nov". */
export function dayText(value, now) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    const today = new Date(now || Date.now());
    const start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    if (d.getTime() >= start) {
        return 'today';
    }
    return d.getTime() >= start - DAY ? 'yesterday' : shortDate(value);
}

/** Recent changes to settings: what, old → new, when and who. */
export function changeViews(summary, now) {
    return ((summary && summary.changes) || []).map((c, i) => {
        let change = '';
        if (c.oldValue && c.newValue) {
            change = c.oldValue + ' → ' + c.newValue;
        } else if (c.newValue) {
            change = '→ ' + c.newValue;
        } else if (c.oldValue) {
            change = c.oldValue + ' → (empty)';
        }
        return {
            key: 'c' + i,
            what: c.what,
            change,
            hasChange: !!change,
            meta: [dayText(c.changedOn, now), c.who].filter((x) => !!x).join(' · '),
            section: c.section || ''
        };
    });
}

/** Security & credentials: what to fix, worst first ("Fix", "25 days", "Off"…). */
export function problemViews(summary) {
    return ((summary && summary.problems) || []).map((p, i) => ({
        key: 'p' + i,
        tag: p.tag,
        tagCls: 'rr-pill ' + (p.tone === 'bad' ? 'rr-pill-bad' : 'rr-pill-wait'),
        text: p.expiresOn ? p.text + ' · expires ' + shortDate(p.expiresOn) : p.text
    }));
}

/** The pill beside a section's title: the dot's meaning in words. */
export function tonePill(tone) {
    const cls = { ok: 'rr-pill rr-pill-ok', warn: 'rr-pill rr-pill-wait', bad: 'rr-pill rr-pill-bad' };
    return { text: TONE_WORDS[tone] || TONE_WORDS.none, cls: cls[tone] || 'rr-pill rr-pill-none' };
}
