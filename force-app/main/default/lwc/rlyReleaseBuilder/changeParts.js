/**
 * New Release step 2 in parts (build 36): which types get a call of their own and how a failed part is tried again
 * (build 50: Find deleted components is retired; deletions are picked with Delete from the branch). Pure functions:
 * rlyReleaseBuilder makes the calls.
 */

/** Light types per listChanges call. */
export const TYPES_PER_CALL = 24;
/** Parts running at once. */
export const PARALLEL = 4;
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
