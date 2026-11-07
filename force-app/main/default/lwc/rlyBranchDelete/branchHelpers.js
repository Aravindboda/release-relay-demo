/**
 * Delete from the branch (build 37.1): pure helpers for rlyBranchDelete (the branch's components grouped and tagged).
 * The comparison keys match rlyReleaseBuilder's Find deleted components (changeParts.js).
 */

/** Branch parts and org types read at once. */
export const PARALLEL = 3;
/** Rows shown before Show more. */
export const PAGE = 200;
/** Most deletions one window adds (RlyReleaseSize allows 500 per release). */
export const MAX_CHOSEN = 500;

/** A component name from a file name (some are URL-encoded, like Account-Account %28Old%29 Layout). */
export function decodeName(name) {
    if (!name.includes('%')) {
        return name;
    }
    try {
        return decodeURIComponent(name.replace(/\+/g, '%2B'));
    } catch (e) {
        return name;
    }
}

/**
 * The comparison key of a component, lower case; a field's object without its suffix (the Tooling API may only know
 * the object's base name).
 */
export function presenceKey(type, name) {
    let n = name.toLowerCase();
    if (type === 'CustomField' && n.includes('.')) {
        const dot = n.indexOf('.');
        n = n.substring(0, dot).replace(/__(c|mdt|e|b|x)$/, '') + n.substring(dot);
    }
    return type + ':' + n;
}

/** A type's words: CustomField → Custom Field. */
export function words(type) {
    return type.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/([A-Z])([A-Z][a-z])/g, '$1 $2');
}

/** Runs jobs (functions returning a promise that handles its own errors) a few at a time. */
export function runPool(jobs, size) {
    let next = 0;
    const worker = () => {
        if (next >= jobs.length) {
            return Promise.resolve();
        }
        const job = jobs[next++];
        return Promise.resolve().then(job).then(worker);
    };
    return Promise.all(Array.from({ length: Math.min(size, Math.max(jobs.length, 1)) }, worker));
}

/** The types listMetadata can't list without a folder (rule kind folder). */
export function folderTypesOf(rules) {
    return new Set((rules || []).filter((r) => r.kind === 'folder').map((r) => r.type));
}

/**
 * The components from the parts read: { key (Type:Name, the name decoded), type, name, blocked (reason or null) }, each
 * once, sorted by type then name.
 */
export function componentsOf(keyLists, blockedList) {
    const blocked = new Map((blockedList || []).map((b) => [b.key, b.reason]));
    const out = new Map();
    keyLists.forEach((keys) => keys.forEach((k) => {
        const type = k.substring(0, k.indexOf(':'));
        const name = decodeName(k.substring(k.indexOf(':') + 1));
        const key = type + ':' + name;
        if (!out.has(key)) {
            out.set(key, { key, type, name, blocked: blocked.get(k) || null });
        }
    }));
    return [...out.values()].sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type.localeCompare(b.type)));
}

/** The types with their counts, in order. */
export function typeCounts(components) {
    const counts = new Map();
    components.forEach((c) => counts.set(c.type, (counts.get(c.type) || 0) + 1));
    return [...counts.entries()].map(([type, count]) => ({ type, count }));
}
