/**
 * Release Relay list search helpers, shared by every list with a search box (c/rlySearchBox): the trimmed search term,
 * whether a row matches, and a text split into parts to highlight the matches as plain text parts.
 */
/**
 * The search text as the lists compare it: trimmed and lower case.
 * @param {string} value what was typed
 * @returns {string} the normalised text
 */
export function searchTerm(value) {
    return String(value || '').trim().toLowerCase();
}

/**
 * Whether any of the values contains the (normalised) search text. A blank search matches everything.
 * @param {Array} values the row's searchable texts
 * @param {string} term the normalised search text
 * @returns {boolean} true when the row matches
 */
export function matchesSearch(values, term) {
    if (!term) {
        return true;
    }
    return (values || []).some((v) => v !== undefined && v !== null && String(v).toLowerCase().includes(term));
}

/**
 * A text split into parts for the template, the matches flagged so they render in <mark> (plain text nodes only).
 * @param {string} text the full text
 * @param {string} term the normalised search text
 * @returns {Array} parts { key, text, hit }
 */
export function highlightParts(text, term) {
    const full = text === undefined || text === null ? '' : String(text);
    if (!term || !full) {
        return [{ key: 'p0', text: full, hit: false }];
    }
    const lower = full.toLowerCase();
    const parts = [];
    let at = 0;
    let found = lower.indexOf(term);
    while (found >= 0 && parts.length < 40) {
        if (found > at) {
            parts.push({ key: 'p' + parts.length, text: full.slice(at, found), hit: false });
        }
        parts.push({ key: 'p' + parts.length, text: full.slice(found, found + term.length), hit: true });
        at = found + term.length;
        found = lower.indexOf(term, at);
    }
    if (at < full.length) {
        parts.push({ key: 'p' + parts.length, text: full.slice(at), hit: false });
    }
    return parts;
}
