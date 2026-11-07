/** Run directions the page offers (Refill is started from an org refreshed since its last load). */
export const DIRECTIONS = [
    { value: 'Up', label: 'Send up' },
    { value: 'Down', label: 'Copy down' },
    { value: 'Refill', label: 'Refill' }
];

const PILLS = {
    Exporting: 'rr-pill rr-pill-run', 'Dry run': 'rr-pill rr-pill-run', Loading: 'rr-pill rr-pill-run',
    Ready: 'rr-pill rr-pill-warn', Blocked: 'rr-pill rr-pill-bad', Failed: 'rr-pill rr-pill-bad', Loaded: 'rr-pill rr-pill-ok'
};
const LABELS = { Ready: 'Ready to load', Exporting: 'Sending records', 'Dry run': 'Dry run…', Loading: 'Loading…' };

/** A status's pill. */
export function statusPill(status) {
    return { label: LABELS[status] || status || 'Unknown', cls: PILLS[status] || 'rr-pill rr-pill-none' };
}

/** The totals JSON as one line. */
export function countsText(counts) {
    let c;
    try {
        c = counts ? JSON.parse(counts) : null;
    } catch (e) {
        c = null;
    }
    if (!c) {
        return '';
    }
    const bits = [c.insert + ' insert', c.update + ' update', c.unchanged + ' unchanged'];
    if (c.failed) {
        bits.push(c.failed + ' failed');
    }
    if (c.duplicates) {
        bits.push(c.duplicates + ' duplicate keys');
    }
    return bits.join(' · ');
}

/** A definition JSON, or null. */
export function definitionOf(text) {
    try {
        const d = text ? JSON.parse(text) : null;
        return d && Array.isArray(d.objects) ? d : null;
    } catch (e) {
        return null;
    }
}

function splitList(text) {
    return String(text || '').split(',').map((s) => s.trim()).filter(Boolean);
}

/** "Field:Value, Field:Value" as a map. */
function splitPairs(text) {
    const out = {};
    splitList(text).forEach((pair) => {
        const at = pair.indexOf(':');
        if (at > 0) {
            out[pair.slice(0, at).trim()] = pair.slice(at + 1).trim();
        }
    });
    return out;
}

function joinPairs(map) {
    return Object.keys(map || {}).map((k) => k + ':' + map[k]).join(', ');
}

/** The editor's state for a data set (null: a new one), with toDefinition() building the JSON back. */
export function editorOf(set) {
    const d = set ? definitionOf(set.definition) : null;
    const objects = (d ? d.objects : [{}]).map((o) => ({
        objectName: o.objectName || '', fields: (o.fields || []).join(', '), filter: o.filter || '',
        matchKey: (o.matchKey || []).join(', '), parents: joinPairs(o.parents), masks: joinPairs(o.masks)
    }));
    const bypass = d && d.bypass ? d.bypass : {};
    return {
        id: set ? set.id : null, title: set ? set.title : '', description: set ? set.description || '' : '', objects,
        bypassKind: bypass.kind || '', bypassName: bypass.name || '', bypassField: bypass.field || '', error: undefined,
        heading: set ? 'Edit ' + set.title : 'New data set',
        toDefinition() {
            return {
                objects: this.objects.map((o) => ({ objectName: o.objectName.trim(), fields: splitList(o.fields), filter: o.filter.trim(),
                    matchKey: splitList(o.matchKey), parents: splitPairs(o.parents), masks: splitPairs(o.masks) })),
                bypass: this.bypassKind ? { kind: this.bypassKind, name: this.bypassName.trim(), field: this.bypassField.trim() } : null
            };
        }
    };
}
