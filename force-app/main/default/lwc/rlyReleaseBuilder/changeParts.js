/**
 * New Release step 2 in parts (build 36): which types get a call of their own, how a failed part is tried again, and
 * Find deleted components' comparison of the branch with the org. Pure functions: rlyReleaseBuilder makes the calls.
 */

/** Light types per listChanges call. */
export const TYPES_PER_CALL = 24;
/** Parts running at once. */
export const PARALLEL = 4;
/** Find deleted components: parts running at once. */
export const DELETION_PARALLEL = 3;
/** Most deletion candidates shown (RlyChangeFinder.MAX_ITEMS). */
export const MAX_ITEMS = 3000;
/** Names per detectTests call. */
export const TEST_NAMES_PER_CALL = 25;
/** Names per flowVersions call. */
export const FLOW_NAMES_PER_CALL = 100;

/**
 * Types whose listMetadata answers can be large (one row per field, view, rule…): each gets its own call, so one of
 * them failing or running long never takes other types with it.
 */
export const HEAVY_TYPES = new Set([
    'CustomField', 'ListView', 'RecordType', 'CompactLayout', 'WebLink', 'ValidationRule', 'FieldSet', 'BusinessProcess',
    'Index', 'SharingReason', 'CustomLabel', 'Layout', 'Profile', 'PermissionSet', 'EmailTemplate', 'Report', 'Dashboard',
    'StaticResource', 'Translations', 'CustomObjectTranslation', 'QuickAction', 'FlexiPage', 'Flow', 'ApexClass'
]);

/** Kinds of listing part. */
export const KIND_TYPES = 'types';
export const KIND_FOLDER = 'folder';
export const KIND_FIELDS = 'fields';

function chunked(list, size) {
    const out = [];
    for (let i = 0; i < list.length; i += size) {
        out.push(list.slice(i, i + size));
    }
    return out;
}

/** The listing parts for an org's types: heavy types alone, light ones in chunks, each folder type on its own. */
export function listingParts(types, folderTypes) {
    const heavy = types.filter((t) => HEAVY_TYPES.has(t));
    const light = types.filter((t) => !HEAVY_TYPES.has(t));
    const parts = heavy.map((t) => typesPart([t], 0));
    chunked(light, TYPES_PER_CALL).forEach((c) => parts.push(typesPart(c, 0)));
    folderTypes.forEach((t) => parts.push({ key: 'folder:' + t, kind: KIND_FOLDER, types: [t], label: t, attempt: 0 }));
    return parts;
}

/** A part of one or more types. */
export function typesPart(types, attempt) {
    return {
        key: 'types:' + types.join(','), kind: KIND_TYPES, types, attempt,
        label: types.length === 1 ? types[0] : types.length + ' types (' + types[0] + ' … ' + types[types.length - 1] + ')'
    };
}

/**
 * What to do after a part failed: split a part of several types into single types, try a single type once more,
 * read custom fields through the Tooling API after listMetadata failed twice, or give up (null: list it on the screen).
 */
export function afterFailure(part) {
    if (part.kind === KIND_TYPES && part.types.length > 1) {
        return part.types.map((t) => typesPart([t], 0));
    }
    if (part.attempt < 1) {
        return [{ ...part, attempt: part.attempt + 1 }];
    }
    if (part.kind === KIND_TYPES && part.types[0] === 'CustomField') {
        return [{ key: 'fields:CustomField', kind: KIND_FIELDS, types: ['CustomField'], label: 'CustomField (one page at a time)', attempt: 0 }];
    }
    return null;
}

/** Adds changes to a list, each key once. */
export function mergeChanges(current, found) {
    const known = new Set(current.map((c) => c.key));
    const fresh = found.filter((c) => !known.has(c.key));
    return fresh.length ? [...current, ...fresh] : current;
}

// ---------- Find deleted components ----------

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

/** A standard object (Account) or field (Account.Industry): it can't be deleted. */
export function isStandard(type, name) {
    const own = type === 'CustomField' ? name.substring(name.indexOf('.') + 1) : name;
    return (type === 'CustomObject' || type === 'CustomField') && !own.includes('__');
}

/**
 * The comparison key of a component in the org or on the branch, lower case. A field's object is compared without its
 * suffix (__c, __mdt, __e, __b, __x), as custom fields read through the Tooling API may only know the object's base name.
 */
export function presenceKey(type, name) {
    let n = name.toLowerCase();
    if (type === 'CustomField' && n.includes('.')) {
        const dot = n.indexOf('.');
        n = n.substring(0, dot).replace(/__(c|mdt|e|b|x)$/, '') + n.substring(dot);
    }
    return type + ':' + n;
}

/**
 * The deletion candidates: components on the branch (Type:Name keys) the org doesn't have, for the types the org was
 * read for (presence: type => Set of presenceKey). Standard objects and fields are left out.
 */
export function deletionCandidates(branchKeys, presence) {
    const out = [];
    branchKeys.forEach((k) => {
        const type = k.substring(0, k.indexOf(':'));
        const name = decodeName(k.substring(k.indexOf(':') + 1));
        const inOrg = presence.get(type);
        if (inOrg && !isStandard(type, name) && !inOrg.has(presenceKey(type, name))) {
            out.push({ key: type + ':' + name, type, name, standard: false, deleted: true });
        }
    });
    return out;
}

/**
 * Runs jobs (functions returning a promise that handles its own errors) a few at a time. Jobs added to the list while
 * it runs are picked up too (a failed part's retries).
 */
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
