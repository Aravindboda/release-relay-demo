/**
 * Build 60: the items of a metadata XML file that Release Relay keeps or merges one by one (the same ids as the
 * pipeline, version 34): a layout's fields, related lists and actions, a permission set's accesses, a field's picklist
 * values, labels, value set values. An item's id is element:key, for example layoutItems:Fax or
 * fieldPermissions:Account.Industry (a layout assignment: layoutAssignments:<layout>|<recordType>).
 *
 * missingItems  what the target branch's copy has and the developer org's lacks (D40: Review keeps them)
 * keepBoth      both sides' items in one file when the two copies differ only by whole items (D39: Keep both)
 */

const KEY_CHILDREN = {
    layoutItems: ['field', 'customLink', 'page', 'scontrol', 'canvas', 'component', 'reportChartComponent'],
    relatedLists: ['relatedList'],
    quickActionListItems: ['quickActionName'],
    platformActionListItems: ['actionName'],
    fieldPermissions: ['field'],
    objectPermissions: ['object'],
    classAccesses: ['apexClass'],
    pageAccesses: ['apexPage'],
    tabSettings: ['tab'],
    recordTypeVisibilities: ['recordType'],
    applicationVisibilities: ['application'],
    customPermissions: ['name'],
    userPermissions: ['name'],
    customMetadataTypeAccesses: ['name'],
    customSettingAccesses: ['name'],
    flowAccesses: ['flow'],
    externalDataSourceAccesses: ['externalDataSource'],
    value: ['fullName'],
    labels: ['fullName'],
    customValue: ['fullName'],
    standardValue: ['fullName']
};

const ELEMENTS_OF = {
    Layout: ['layoutItems', 'relatedLists', 'quickActionListItems', 'platformActionListItems'],
    PermissionSet: ['fieldPermissions', 'objectPermissions', 'classAccesses', 'pageAccesses', 'tabSettings', 'recordTypeVisibilities',
        'applicationVisibilities', 'customPermissions', 'userPermissions', 'customMetadataTypeAccesses', 'customSettingAccesses',
        'flowAccesses', 'externalDataSourceAccesses'],
    CustomField: ['value'],
    CustomLabels: ['labels'],
    GlobalValueSet: ['customValue'],
    StandardValueSet: ['standardValue']
};

/** Words for an element in a line of the Review list. */
const ELEMENT_WORDS = {
    layoutItems: 'field', relatedLists: 'related list', quickActionListItems: 'action', platformActionListItems: 'action',
    fieldPermissions: 'field access', objectPermissions: 'object access', classAccesses: 'class access', pageAccesses: 'page access',
    tabSettings: 'tab', recordTypeVisibilities: 'record type', applicationVisibilities: 'app', customPermissions: 'custom permission',
    userPermissions: 'permission', customMetadataTypeAccesses: 'custom metadata type', customSettingAccesses: 'custom setting',
    flowAccesses: 'flow access', externalDataSourceAccesses: 'external data source', layoutAssignments: 'layout assignment',
    value: 'picklist value', labels: 'label', customValue: 'value', standardValue: 'value'
};

/** The types whose lines Review lists and the pipeline keeps (profiles go through Profile access). */
export const KEEP_TYPES = Object.keys(ELEMENTS_OF);

/** The type of a source-format path, for the types above, or null. */
export function typeOfPath(path) {
    const p = String(path || '');
    if (/(^|\/)layouts\/[^/]+\.layout-meta\.xml$/.test(p)) {
        return 'Layout';
    }
    if (/(^|\/)permissionsets\/[^/]+\.permissionset-meta\.xml$/.test(p)) {
        return 'PermissionSet';
    }
    if (/(^|\/)objects\/[^/]+\/fields\/[^/]+\.field-meta\.xml$/.test(p)) {
        return 'CustomField';
    }
    if (/(^|\/)labels\/[^/]+\.labels-meta\.xml$/.test(p)) {
        return 'CustomLabels';
    }
    if (/(^|\/)globalValueSets\/[^/]+\.globalValueSet-meta\.xml$/.test(p)) {
        return 'GlobalValueSet';
    }
    if (/(^|\/)standardValueSets\/[^/]+\.standardValueSet-meta\.xml$/.test(p)) {
        return 'StandardValueSet';
    }
    return null;
}

function childText(block, name) {
    const m = new RegExp('<' + name + '>([^<]*)</' + name + '>').exec(block);
    return m ? m[1].trim() : '';
}

function keyOf(element, block) {
    const names = KEY_CHILDREN[element] || [];
    for (const n of names) {
        const v = childText(block, n);
        if (v) {
            return v;
        }
    }
    return '';
}

/** The keyed items of a file, in file order: { id, element, key, start, end, text }. Blank layout spaces are left out. */
export function itemsOf(type, text) {
    const source = String(text || '');
    const out = [];
    (ELEMENTS_OF[type] || []).forEach((element) => {
        const re = new RegExp('<' + element + '>[\\s\\S]*?</' + element + '>', 'g');
        let m = re.exec(source);
        while (m) {
            const key = keyOf(element, m[0]);
            if (key) {
                out.push({ id: element + ':' + key, element, key, start: m.index, end: m.index + m[0].length, text: m[0] });
            }
            m = re.exec(source);
        }
    });
    return out.sort((a, b) => a.start - b.start);
}

/** The words a line shows: "field External_ID__c", "field access Account.Active__c". */
export function itemWords(id) {
    const element = String(id).substring(0, String(id).indexOf(':'));
    return (ELEMENT_WORDS[element] || element) + ' ' + String(id).substring(element.length + 1);
}

/** Items the branch's copy has and the developer org's copy lacks: [{ id, element, key }]. */
export function missingItems(type, branchText, sourceText) {
    if (branchText === null || branchText === undefined || sourceText === null || sourceText === undefined) {
        return [];
    }
    const have = new Set(itemsOf(type, sourceText).map((i) => i.id));
    const seen = new Set();
    return itemsOf(type, branchText).filter((i) => {
        const keep = !have.has(i.id) && !seen.has(i.id);
        seen.add(i.id);
        return keep;
    }).map((i) => ({ id: i.id, element: i.element, key: i.key }));
}

const squash = (s) => String(s || '').replace(/\r\n/g, '\n').replace(/\n[ \t]*(?=\n)/g, '').replace(/[ \t]+\n/g, '\n').trim();

/** A file with its keyed items taken out, for comparing what's left. */
function skeleton(text, items) {
    let out = '';
    let at = 0;
    items.forEach((i) => {
        out += text.substring(at, i.start);
        at = i.end;
    });
    return squash(out + text.substring(at));
}

/** The whitespace before an item on its line. */
function indentOf(text, start) {
    const lineStart = text.lastIndexOf('\n', start - 1) + 1;
    const lead = text.substring(lineStart, start);
    return /^[ \t]*$/.test(lead) ? lead : '';
}

/** Where a mine-only item goes in the result: after the item before it in mine and the target's own items that follow. */
function insertAt(result, type, mineIds, before) {
    const ordered = itemsOf(type, result);
    let at = -1;
    let idx = before ? ordered.findIndex((i) => i.id === before) : -1;
    if (idx >= 0) {
        at = ordered[idx].end;
        idx += 1;
        while (idx < ordered.length && !mineIds.has(ordered[idx].id)) {
            at = ordered[idx].end;
            idx += 1;
        }
    }
    return at;
}

/**
 * Both sides' items in one file (D39), or null when the copies differ by more than whole items (then the developer
 * keeps one side or edits). The target's copy stays as it is; each item only mine has goes in after the item before it
 * in mine (and after the target's own items that follow that one).
 * @param type the metadata type (typeOfPath)
 * @param theirs the target branch's copy
 * @param mine the release's copy
 */
export function keepBoth(type, theirs, mine) {
    if (!ELEMENTS_OF[type] || theirs === null || theirs === undefined || mine === null || mine === undefined) {
        return null;
    }
    const theirItems = itemsOf(type, theirs);
    const mineItems = itemsOf(type, mine);
    if (skeleton(theirs, theirItems) !== skeleton(mine, mineItems)) {
        return null;
    }
    const theirsById = new Map(theirItems.map((i) => [i.id, i]));
    if (mineItems.some((i) => theirsById.has(i.id) && squash(theirsById.get(i.id).text) !== squash(i.text))) {
        return null;
    }
    const mineIds = new Set(mineItems.map((i) => i.id));
    let result = theirs;
    let previous = null;
    let added = 0;
    for (const item of mineItems) {
        if (!theirsById.has(item.id)) {
            const at = insertAt(result, type, mineIds, previous);
            if (at < 0) {
                return null;
            }
            result = result.substring(0, at) + '\n' + indentOf(mine, item.start) + item.text + result.substring(at);
            added += 1;
        }
        previous = item.id;
    }
    return added ? result : null;
}
