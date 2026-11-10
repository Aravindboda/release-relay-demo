/**
 * Profile access rows (build 58): the sections a profile file holds, the rows a release's components need, and the
 * rules between values (Edit needs Read; Modify all needs everything). Shared by c/rlyProfileAccess.
 */

const ON = 'true';
const OFF = 'false';

/** The sections the step offers, in page order, with the values each sends. */
export const SECTIONS = [
    { section: 'fieldPermissions', label: 'Fields', values: [{ name: 'readable', label: 'Read' }, { name: 'editable', label: 'Edit' }] },
    { section: 'objectPermissions', label: 'Objects', values: [{ name: 'allowCreate', label: 'Create' }, { name: 'allowRead', label: 'Read' },
        { name: 'allowEdit', label: 'Edit' }, { name: 'allowDelete', label: 'Delete' }, { name: 'viewAllRecords', label: 'View all' },
        { name: 'modifyAllRecords', label: 'Modify all' }] },
    { section: 'classAccesses', label: 'Apex classes', values: [{ name: 'enabled', label: 'Enabled' }] },
    { section: 'pageAccesses', label: 'Visualforce pages', values: [{ name: 'enabled', label: 'Enabled' }] },
    { section: 'tabVisibilities', label: 'Tabs', choice: 'visibility',
        values: [{ name: 'DefaultOn', label: 'Default on' }, { name: 'DefaultOff', label: 'Default off' }, { name: 'Hidden', label: 'Hidden' }] },
    { section: 'recordTypeVisibilities', label: 'Record types', values: [{ name: 'visible', label: 'Visible' }, { name: 'default', label: 'Default' }] },
    { section: 'layoutAssignments', label: 'Page layouts', text: 'layout', values: [] },
    { section: 'applicationVisibilities', label: 'Apps', values: [{ name: 'visible', label: 'Visible' }, { name: 'default', label: 'Default' }] },
    { section: 'customPermissions', label: 'Custom permissions', values: [{ name: 'enabled', label: 'Enabled' }] },
    { section: 'customMetadataTypeAccesses', label: 'Custom metadata types', values: [{ name: 'enabled', label: 'Enabled' }] },
    { section: 'customSettingAccesses', label: 'Custom settings', values: [{ name: 'enabled', label: 'Enabled' }] },
    { section: 'userPermissions', label: 'System permissions', values: [{ name: 'enabled', label: 'Enabled' }] }
];

const BY_SECTION = new Map(SECTIONS.map((s) => [s.section, s]));
const NAME = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;
const DOTTED = /^[A-Za-z][A-Za-z0-9_]{0,79}\.[A-Za-z][A-Za-z0-9_]{0,79}$/;
const TAB = /^[A-Za-z][A-Za-z0-9_-]{0,79}$/;

/** A section's settings. */
export function sectionOf(section) {
    return BY_SECTION.get(section);
}

/** The id of a row: section|key. */
export function rowId(section, key) {
    return section + '|' + key;
}

/** The key the server answers a row's values under: profile|section|key in lower case. */
export function valueKey(profile, section, key) {
    return profile + '|' + section + '|' + String(key).toLowerCase();
}

function objectRows(name) {
    if (name.endsWith('__mdt')) {
        return [{ section: 'customMetadataTypeAccesses', key: name }];
    }
    return name.endsWith('__e') || name.endsWith('__b') ? [] : [{ section: 'objectPermissions', key: name }];
}

/** The rows the components of a release need: fields, objects, classes, pages, tabs, record types, layouts… */
export function rowsFor(components) {
    const out = new Map();
    const add = (section, key) => out.set(rowId(section, key), { section, key });
    (components || []).forEach((c) => {
        const name = String(c.name || '');
        const object = name.split('.')[0];
        if (c.type === 'CustomField' && DOTTED.test(name) && !object.endsWith('__mdt') && !object.endsWith('__e')) {
            add('fieldPermissions', name);
        } else if (c.type === 'CustomObject' && NAME.test(name)) {
            objectRows(name).forEach((r) => add(r.section, r.key));
        } else if (c.type === 'RecordType' && DOTTED.test(name)) {
            add('recordTypeVisibilities', name);
            add('layoutAssignments', name);
        } else if (c.type === 'Layout' && name.includes('-') && NAME.test(name.split('-')[0])) {
            add('layoutAssignments', name.split('-')[0]);
        } else {
            const section = { ApexClass: 'classAccesses', ApexPage: 'pageAccesses', CustomTab: 'tabVisibilities',
                CustomPermission: 'customPermissions', CustomApplication: 'applicationVisibilities' }[c.type];
            if (section && (section === 'tabVisibilities' ? TAB : NAME).test(name)) {
                add(section, name);
            }
        }
    });
    return [...out.values()];
}

/** Why a name can't be added under a section, or ''. */
export function nameProblem(section, key) {
    const s = sectionOf(section);
    if (!s) {
        return 'Pick what kind of access it is.';
    }
    const pattern = ['fieldPermissions', 'recordTypeVisibilities'].includes(section) ? DOTTED
        : section === 'tabVisibilities' ? TAB : section === 'layoutAssignments' ? /^[A-Za-z][A-Za-z0-9_]{0,79}(\.[A-Za-z][A-Za-z0-9_]{0,79})?$/ : NAME;
    if (pattern.test(key)) {
        return '';
    }
    return ['fieldPermissions', 'recordTypeVisibilities'].includes(section)
        ? 'Use Object.Name, for example Account.Region__c.' : 'Use the API name, for example Order__c or ApiEnabled.';
}

// Edit needs Read; Delete needs Edit; Modify all needs every other; turning one off turns off what needs it.
const NEEDS = {
    fieldPermissions: { editable: ['readable'] },
    objectPermissions: { allowCreate: ['allowRead'], allowEdit: ['allowRead'], allowDelete: ['allowEdit', 'allowRead'],
        viewAllRecords: ['allowRead'], modifyAllRecords: ['allowDelete', 'allowEdit', 'allowRead', 'viewAllRecords'] }
};

/** Values after one was switched: what it needs goes on, what needs it goes off. */
export function switched(section, values, name) {
    const out = { ...values, [name]: values[name] === ON ? OFF : ON };
    const needs = NEEDS[section] || {};
    if (out[name] === ON) {
        (needs[name] || []).forEach((n) => { out[n] = ON; });
    } else {
        Object.keys(needs).filter((n) => needs[n].includes(name)).forEach((n) => { out[n] = OFF; });
    }
    return out;
}

/** The values a row starts with when it's first set: the developer org's, else nothing on. */
export function startValues(section, known) {
    const s = sectionOf(section);
    const out = {};
    if (s.text) {
        if (known && known[s.text]) {
            out[s.text] = known[s.text];
        }
        return out;
    }
    if (s.choice) {
        out[s.choice] = known && known[s.choice] ? known[s.choice] : 'Hidden';
        return out;
    }
    s.values.forEach((v) => { out[v.name] = known && known[v.name] === ON ? ON : OFF; });
    return out;
}

/** Words for an org's values: "Read, Edit", "No access", a tab's setting or a layout; '–' when unread. */
export function describe(section, known) {
    if (!known) {
        return '–';
    }
    const s = sectionOf(section);
    if (s.text) {
        return known[s.text] || 'Not assigned';
    }
    if (s.choice) {
        const v = s.values.find((x) => x.name === known[s.choice]);
        return v ? v.label : '–';
    }
    const on = s.values.filter((v) => known[v.name] === ON).map((v) => v.label);
    return on.length ? on.join(', ') : 'No access';
}
