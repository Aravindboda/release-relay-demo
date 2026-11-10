/**
 * Delete from the branch (build 37.1): pure helpers for rlyBranchDelete (the branch's components grouped and tagged).
 * The comparison keys, the parts runner and the folder types come from c/rlyShared (build 50).
 */
import { decodeName } from 'c/rlyShared';

/** Branch parts and org types read at once. */
export const PARALLEL = 3;
/** Rows shown before Show more. */
export const PAGE = 200;
/** Most deletions one window adds (RlyReleaseSize allows 500 per release). */
export const MAX_CHOSEN = 500;

/** A type's words: CustomField → Custom Field. */
export function words(type) {
    return type.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/([A-Z])([A-Z][a-z])/g, '$1 $2');
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
