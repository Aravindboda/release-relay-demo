/** Helpers for rlySyncStatus: chips and package statuses (the developer org listing and parts are in c/rlyPartSending). */

/** The status chip of a difference. */
export function statusChip(status, lowerName, higherName, lowerChangedToo) {
    if (status === 'onlyInOrg') {
        return { label: 'Only in org', cls: 'rr-pill rr-pill-violet' };
    }
    if (status === 'onlyOnBranch') {
        return { label: 'Only on branch', cls: 'rr-pill rr-pill-none' };
    }
    if (status === 'onlyInHigher') {
        return lowerChangedToo ? { label: 'Different in ' + lowerName + ' too', cls: 'rr-pill rr-pill-bad' }
            : { label: 'Only in ' + higherName, cls: 'rr-pill rr-pill-warn' };
    }
    if (status === 'different' && lowerChangedToo) {
        return { label: 'Different in ' + lowerName + ' too', cls: 'rr-pill rr-pill-bad' };
    }
    return { label: 'Different', cls: 'rr-pill rr-pill-warn' };
}

/** A pair's key by its branches. */
export function pairKey(higher, lower) {
    return String(higher || '').trim() + '>' + String(lower || '').trim();
}

/** Each org's version of a package ('—' when it isn't installed). */
export function versionList(pkg, orgs) {
    return (orgs || []).map((o) => ({ key: o, org: o, version: (pkg.versions || {})[o] || '—' }));
}

/** Same everywhere, Not in X, or X is older (with the upgrade step offered). */
export function packageStatus(pkg, orgs) {
    const versions = versionList(pkg, orgs);
    const missing = versions.filter((v) => v.version === '—').map((v) => v.org);
    const present = versions.filter((v) => v.version !== '—');
    const distinct = [...new Set(present.map((v) => v.version))];
    if (missing.length && present.length) {
        return { label: 'Not in ' + missing.join(', '), cls: 'rr-pill rr-pill-none', upgrade: true };
    }
    if (distinct.length > 1) {
        const newest = distinct.slice().sort(compareVersions).pop();
        const older = present.filter((v) => v.version !== newest).map((v) => v.org);
        return { label: older.join(', ') + (older.length === 1 ? ' is' : ' are') + ' older', cls: 'rr-pill rr-pill-warn', upgrade: true };
    }
    return { label: 'Same everywhere', cls: 'rr-pill rr-pill-ok', upgrade: false };
}

/** Compares versions like 252.4.1 by number. */
export function compareVersions(a, b) {
    const x = String(a).split('.').map(Number);
    const y = String(b).split('.').map(Number);
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
        const d = (x[i] || 0) - (y[i] || 0);
        if (d) {
            return d;
        }
    }
    return 0;
}
