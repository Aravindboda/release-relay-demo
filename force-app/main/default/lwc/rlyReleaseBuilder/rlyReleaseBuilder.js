import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import getStart from '@salesforce/apex/RlyChangesController.getStart';
import describeTypes from '@salesforce/apex/RlyChangesController.describeTypes';
import listChanges from '@salesforce/apex/RlyChangesController.listChanges';
import listFolderChanges from '@salesforce/apex/RlyChangesController.listFolderChanges';
import listTracked from '@salesforce/apex/RlyChangesController.listTracked';
import detectTests from '@salesforce/apex/RlyChangesController.detectTests';
import findDeletions from '@salesforce/apex/RlyChangesController.findDeletions';
import raiseRelease from '@salesforce/apex/RlyReleasesController.raiseRelease';
import flowVersions from '@salesforce/apex/RlyChangesController.flowVersions';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';

const TYPES_PER_CALL = 24;
const PARALLEL = 4;
const PAGE = 200;
const WINDOWS = [
    { label: 'Last 7 days', value: '7' },
    { label: 'Last 30 days', value: '30' },
    { label: 'Any time', value: 'any' },
    { label: 'Since a date…', value: 'date' }
];
const SHOW = [
    { label: 'Custom + standard', value: 'both' },
    { label: 'Custom', value: 'custom' },
    { label: 'Standard', value: 'standard' }
];
const TYPE_GROUPS = [
    ['Code', ['ApexClass', 'ApexTrigger', 'ApexPage', 'ApexComponent', 'LightningComponentBundle', 'AuraDefinitionBundle', 'StaticResource']],
    ['Automation', ['Flow', 'FlowDefinition', 'WorkflowRule', 'ApprovalProcess', 'AssignmentRules', 'AutoResponseRules', 'EscalationRules']],
    ['Data model', ['CustomObject', 'CustomField', 'StandardValueSet', 'GlobalValueSet', 'RecordType', 'ValidationRule', 'BusinessProcess', 'CustomMetadata']],
    ['Access and UI', ['Layout', 'FlexiPage', 'PermissionSet', 'PermissionSetGroup', 'Profile', 'CustomTab', 'CustomApplication', 'ListView', 'QuickAction', 'CompactLayout']]
];

/** RaiseRequest.flowChoices[].choice: what happens to a flow after it's deployed into each org. */
const FLOW_KEEP = 'Keep';
const FLOW_ACTIVATE = 'Activate';
const FLOW_INACTIVE = 'Inactive';
const FLOW_STATUS_CLS = { Active: 'rr-pill rr-pill-info', Draft: 'rr-pill rr-pill-wait', InvalidDraft: 'rr-pill rr-pill-bad', Obsolete: 'rr-pill rr-pill-none' };
const FLOW_STATUS_LABEL = { Active: 'Active', Draft: 'Draft', InvalidDraft: 'Invalid draft', Obsolete: 'Obsolete' };
/**
 * Approval preview on Review (board HubApprovalFlowsEvidence 2). The hub decides with RlyApprovalRules when the checks
 * pass; this mirrors its buckets only to tell the user early. Anything not listed is "Other".
 */
const TYPE_BUCKETS = {
    ApexClass: 'Apex', ApexTrigger: 'Apex', Flow: 'Flows', FlowDefinition: 'Flows',
    Profile: 'Profiles_Permissions', PermissionSet: 'Profiles_Permissions', PermissionSetGroup: 'Profiles_Permissions',
    CustomPermission: 'Profiles_Permissions', MutingPermissionSet: 'Profiles_Permissions',
    CustomObject: 'Objects_Fields', CustomField: 'Objects_Fields', RecordType: 'Objects_Fields', ValidationRule: 'Objects_Fields'
};
const BUCKET_WORDS = {
    Apex: 'an Apex class', Flows: 'a Flow', Profiles_Permissions: 'a Profile or permission set', Objects_Fields: 'an object or field',
    Deletions: 'deletions', Manual_Steps: 'manual steps', Hotfix: 'a hotfix', Other: 'other changes'
};

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function chunks(list, size) {
    const out = [];
    for (let i = 0; i < list.length; i += size) {
        out.push(list.slice(i, i + size));
    }
    return out;
}

function groupOf(type) {
    const g = TYPE_GROUPS.find(([, types]) => types.includes(type));
    return g ? g[0] : 'Other';
}

function words(type) {
    return type.replace(/([a-z])([A-Z])/g, '$1 $2');
}

/** A deletion's selection key: never the same as the key of the component it removes, so both can't be one row. */
function deletionKey(type, name) {
    return 'del|' + type + ':' + name;
}

/** Deletions from the org get their own keys and are never ticked for the user. */
function asDeletion(c) {
    return { ...c, key: deletionKey(c.type, c.name), deleted: true };
}

function marked(c) {
    return c.deleted ? asDeletion(c) : c;
}

// Orgs listed at once on step 2; search narrows the rest.
const ORG_LIMIT = 50;
// Salesforce's sandbox types, smallest first. Production is the hub, where releases end, so it isn't a source.
const ENVIRONMENTS = [
    { value: 'Developer', label: 'Developer sandbox', hint: 'Metadata only · refresh every day' },
    { value: 'Developer_Pro', label: 'Developer Pro sandbox', hint: 'Metadata, more storage · refresh every day' },
    { value: 'Partial_Copy', label: 'Partial Copy sandbox', hint: 'Metadata and sample data · refresh every 5 days' },
    { value: 'Full_Copy', label: 'Full Copy sandbox', hint: 'Copy of production · refresh every 29 days' }
];

export default class RlyReleaseBuilder extends LightningElement {
    /** RlyHubGuard.getHubStatus: whether this org is a sandbox copy of the hub (then a banner, and the actions are off). */
    hubStatus;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }

    /** Reads the hub status once. A failed read shows nothing: the server refuses the actions anyway. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            });
    }

    /** The app's name, from Custom Label RLY_App_Name, so each owner can rename it. */
    get appName() { return APP_NAME; }
    windows = WINDOWS;
    showOptions = SHOW;

    step = 'origin';
    envChoice;
    orgSearch = '';
    loading = false;
    start;
    error;

    // source
    orgId;
    windowChoice = '7';
    sinceDate;
    changedBy = 'me';

    // scan
    scanning = false;
    scanDone = 0;
    scanTotal = 0;
    scanErrors = [];
    cache = {};
    changes = [];
    tests = new Set();

    // select
    typeFilter = 'all';
    show = 'both';
    search = '';
    shown = PAGE;
    selected = new Set();
    drawerOpen = false;
    allTypes = [];

    // deletions found from the branch (orgs without source tracking)
    findingDeletions = false;
    deletionResult;
    deletionResultBad = false;

    connectedCallback() {
        this.readHubStatus();
        this.loading = true;
        getStart()
            .then((s) => {
                this.start = s;
                const usable = this.envGroups.filter((g) => g.pickable > 0);
                if (usable.length === 1) {
                    this.envChoice = usable[0].value;
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    // ---------- steps ----------

    get isOrigin() { return this.step === 'origin'; }
    get isSource() { return this.step === 'source'; }
    get originKicker() { return APP_NAME + ' hub · New release · step 1 of 5'; }
    /** The select step fits the screen: its lists scroll inside the card and the bar stays at the bottom. */
    get pageCls() { return 'rr-page slds-is-relative' + (this.isSelect ? ' rr-page-fit' : ''); }
    get sourceKicker() { return APP_NAME + ' hub · New release · step 2 of 5'; }
    get isSelect() { return this.step === 'select'; }
    get isReview() { return this.step === 'review'; }

    get pathSteps() {
        const order = ['origin', 'source', 'select', 'review', 'raise'];
        const labels = { origin: 'Where', source: 'Org', select: 'Select', review: 'Review', raise: 'Raise' };
        const at = order.indexOf(this.step);
        return order.map((v, i) => ({
            key: v,
            label: (i < at ? '✓ ' : i + 1 + ' ') + labels[v],
            cls: 'rr-step' + (i < at ? ' rr-step-done' : i === at ? ' rr-step-now' : ''),
            current: i === at ? 'step' : null
        }));
    }

    // ---------- step 1: source ----------

    get problems() { return this.start ? this.start.problems : []; }
    get hasProblems() { return this.problems.length > 0; }
    get targetText() {
        return this.start && this.start.targetName ? this.start.targetName + ' · ' + this.start.targetBranch : 'not set';
    }
    get targetNote() { return '(the first stage of the route)'; }
    get sourceBranch() { return this.sourceOrg ? this.sourceOrg.Branch__c : ''; }

    get orgCards() {
        return ((this.start && this.start.developers) || []).map((d) => {
            const ready = d.Status__c === 'Connected';
            const on = d.Id === this.orgId;
            return {
                id: d.Id,
                environment: d.Environment__c,
                name: d.Name,
                branch: d.Branch__c,
                note: ready
                    ? (d.Source_Tracking__c === 'Available' ? 'Fast: source tracking' : 'Metadata API') + (this.start.targetName ? ' · → ' + this.start.targetName : '')
                    : 'Not connected: check it on the Pipeline tab',
                showStatus: !ready,
                status: d.Status__c || 'Not checked',
                cls: 'rr-src' + (on ? ' rr-src-on' : '') + (ready ? '' : ' rr-src-off'),
                pressed: on ? 'true' : 'false',
                disabled: ready ? null : true
            };
        });
    }

    /** New Release groups the orgs by Salesforce environment, in Salesforce's own order. */
    get envGroups() {
        const cards = this.orgCards.map((c) => ({ ...c, selectable: true, statusCls: 'rr-pill rr-pill-wait' }));
        const picked = new Set(cards.map((c) => c.id));
        // The hub is production: releases end there, so it never shows as a place changes come from.
        // Back promote orgs only receive production's changes, so they aren't places changes come from either.
        ((this.start && this.start.routeStops) || []).filter((o) => !picked.has(o.Id) && o.Role__c !== 'Hub' && o.Role__c !== 'Back_Promote').forEach((o) => {
            cards.push({
                id: o.Id, name: o.Name, branch: o.Branch__c, environment: o.Environment__c, selectable: false, cls: 'rr-src rr-src-stop',
                note: 'Stage' + (o.Stage_Order__c ? ' ' + o.Stage_Order__c : '') + ' · releases arrive here'
            });
        });
        const groups = ENVIRONMENTS.map((e) => ({ ...e, cards: cards.filter((c) => c.environment === e.value) }));
        const unset = cards.filter((c) => !ENVIRONMENTS.some((e) => e.value === c.environment));
        if (unset.length) {
            groups.push({ value: 'none', label: 'Other orgs', hint: 'No sandbox type set. An admin sets it on the Pipeline tab (Edit org).', cards: unset });
        }
        return groups.map((g) => ({ ...g, key: 'env-' + g.value, empty: g.cards.length === 0,
            pickable: g.cards.filter((c) => c.selectable).length }));
    }

    /** Step 1: one tile per environment, with how many orgs changes can come from. */
    get envTiles() {
        return this.envGroups.map((g) => {
            const on = g.value === this.envChoice;
            const stops = g.cards.filter((c) => !c.selectable).map((c) => c.name);
            let count = g.pickable === 1 ? '1 org' : g.pickable + ' orgs';
            if (g.pickable === 0) {
                count = stops.length ? stops.join(', ') + ': releases arrive here' : 'None registered';
            }
            return { ...g, count, on: on ? 'true' : 'false', disabled: g.pickable === 0 ? true : null,
                cls: 'rr-tile' + (on ? ' rr-tile-on' : '') + (g.pickable === 0 ? ' rr-tile-off' : '') };
        });
    }
    get cantPickEnv() { return !this.envChoice || this.hasProblems; }
    handleEnv(event) {
        const next = event.currentTarget.dataset.value;
        if (next !== this.envChoice) {
            this.envChoice = next;
            this.orgId = undefined;
        }
    }
    goSource() {
        const g = this.envGroups.find((x) => x.value === this.envChoice);
        const ready = g ? g.cards.filter((c) => c.selectable && !c.disabled) : [];
        if (!this.orgId && ready.length === 1) {
            this.orgId = ready[0].id;
        }
        this.orgSearch = '';
        this.step = 'source';
    }
    backToOrigin() {
        this.step = 'origin';
    }

    /** Step 2: the chosen environment's orgs, searchable by name or branch. */
    get envLabel() {
        const g = this.envGroups.find((x) => x.value === this.envChoice);
        return g ? g.label : '';
    }
    get sourceTitle() { return 'Which ' + this.envLabel + ' org?'; }
    get envOrgs() {
        const g = this.envGroups.find((x) => x.value === this.envChoice);
        return g ? g.cards.filter((c) => c.selectable) : [];
    }
    get matchingOrgs() {
        const q = this.orgSearch.trim().toLowerCase();
        return this.envOrgs.filter((c) => !q || (c.name || '').toLowerCase().includes(q) || (c.branch || '').toLowerCase().includes(q));
    }
    get orgRows() {
        return this.matchingOrgs.slice(0, ORG_LIMIT).map((c) => ({ ...c,
            rowCls: 'rr-org' + (c.id === this.orgId ? ' rr-org-on' : '') + (c.disabled ? ' rr-org-off' : '') }));
    }
    get showOrgSearch() { return this.envOrgs.length > 6; }
    get noOrgMatch() { return this.matchingOrgs.length === 0; }
    get orgCountText() {
        const all = this.envOrgs.length;
        const hits = this.matchingOrgs.length;
        if (hits > ORG_LIMIT) {
            return 'Showing ' + ORG_LIMIT + ' of ' + hits + ' matches. Type more of the name to narrow it.';
        }
        return hits === all ? all + (all === 1 ? ' org' : ' orgs') : hits + ' of ' + all + ' orgs';
    }
    handleOrgSearch(event) {
        this.orgSearch = event.target.value || '';
    }

    get noDevelopers() { return this.start && (this.start.developers || []).length === 0; }

    handleOrg(event) {
        this.orgId = event.currentTarget.dataset.id;
    }

    get windowButtons() {
        return WINDOWS.map((w) => ({ ...w, cls: 'rr-seg' + (w.value === this.windowChoice ? ' rr-seg-on' : ''),
            pressed: w.value === this.windowChoice ? 'true' : 'false' }));
    }

    get byButtons() {
        return [{ label: 'Me', value: 'me' }, { label: 'Anyone', value: 'anyone' }].map((b) => ({
            ...b, cls: 'rr-seg' + (b.value === this.changedBy ? ' rr-seg-on' : ''), pressed: b.value === this.changedBy ? 'true' : 'false' }));
    }

    get isSinceDate() { return this.windowChoice === 'date'; }

    handleWindow(event) { this.windowChoice = event.currentTarget.dataset.value; }
    handleSince(event) { this.sinceDate = event.target.value; }
    /** Today as yyyy-mm-dd in the user's time zone: changes can't come from the future. */
    get today() {
        const d = new Date();
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    }
    get sinceInFuture() { return this.isSinceDate && !!this.sinceDate && this.sinceDate > this.today; }
    handleBy(event) { this.changedBy = event.currentTarget.dataset.value; }

    get cantScan() {
        return !this.orgId || this.hasProblems || (this.isSinceDate && !this.sinceDate) || this.sinceInFuture;
    }

    get sinceIso() {
        if (this.windowChoice === 'any') {
            return null;
        }
        if (this.windowChoice === 'date') {
            return this.sinceDate ? this.sinceDate + 'T00:00:00Z' : null;
        }
        const d = new Date(Date.now() - Number(this.windowChoice) * 86400000);
        return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
    }

    get sourceOrg() {
        return ((this.start && this.start.developers) || []).find((d) => d.Id === this.orgId);
    }

    goSelect() {
        this.step = 'select';
        this.scan(false);
    }

    backToSource() {
        this.step = 'source';
    }

    // ---------- scanning ----------

    get cacheKey() { return this.orgId + '|' + this.windowChoice + '|' + (this.sinceDate || ''); }

    refresh() {
        this.scan(true);
    }

    async scan(force) {
        const key = this.cacheKey;
        if (!force && this.cache[key]) {
            this.changes = this.cache[key].changes;
            this.tests = this.cache[key].tests;
            return;
        }
        this.scanning = true;
        this.scanErrors = [];
        this.changes = [];
        this.deletionResult = undefined;
        this.scanDone = 0;
        const orgId = this.orgId;
        const since = this.sinceIso;
        try {
            let found = [];
            if (this.sourceOrg && this.sourceOrg.Source_Tracking__c === 'Available') {
                this.scanTotal = 1;
                found = await listTracked({ orgId, sinceIso: since });
                this.scanDone = 1;
            } else {
                const types = await describeTypes({ orgId });
                this.allTypes = [...types.types, ...types.folderTypes].sort();
                const jobs = chunks(types.types, TYPES_PER_CALL).map((c) => () => listChanges({ orgId, types: c, sinceIso: since }));
                types.folderTypes.forEach((t) => jobs.push(() => listFolderChanges({ orgId, type: t, sinceIso: since })));
                this.scanTotal = jobs.length;
                found = await this.runAll(jobs);
            }
            this.changes = found.map(marked);
            this.tests = new Set(await this.findTests(found.filter((c) => c.type === 'ApexClass' && !c.deleted).map((c) => c.name)));
            this.cache[key] = { changes: this.changes, tests: this.tests };
        } catch (e) {
            this.scanErrors = [...this.scanErrors, errorText(e)];
        } finally {
            this.scanning = false;
        }
    }

    /** Runs the jobs PARALLEL at a time; a failed chunk is reported and the rest carry on. */
    async runAll(jobs) {
        const results = [];
        let next = 0;
        // Each worker takes the next job when its last one is done.
        const worker = () => {
            if (next >= jobs.length) {
                return Promise.resolve();
            }
            const job = jobs[next++];
            return job()
                .then((found) => {
                    results.push(...found);
                })
                .catch((e) => {
                    this.scanErrors = [...this.scanErrors, errorText(e)];
                })
                .then(() => {
                    this.scanDone += 1;
                    return worker();
                });
        };
        await Promise.all(Array.from({ length: Math.min(PARALLEL, jobs.length) }, worker));
        return results;
    }

    /** Which of these classes are tests, 100 names per call, one call after the other. */
    findTests(classNames) {
        const out = [];
        return chunks(classNames, 100)
            .reduce((previous, c) => previous
                .then(() => detectTests({ orgId: this.orgId, classNames: c }))
                .then((found) => {
                    out.push(...found);
                }), Promise.resolve())
            .then(() => out);
    }

    get scanPercent() { return this.scanTotal ? Math.round((this.scanDone / this.scanTotal) * 100) : 0; }
    get scanText() {
        return this.scanTotal > 1 ? 'Reading ' + this.sourceName + ': ' + this.scanDone + ' of ' + this.scanTotal + ' batches' : 'Reading ' + this.sourceName + '…';
    }
    get sourceName() { return this.sourceOrg ? this.sourceOrg.Name : ''; }
    get hasScanErrors() { return this.scanErrors.length > 0; }
    get scanErrorText() {
        return this.scanErrors.length + (this.scanErrors.length === 1 ? ' batch' : ' batches') + ' couldn\'t be read: ' + this.scanErrors.slice(0, 3).join(' · ');
    }

    // ---------- step 2: select ----------

    get byMe() {
        const me = this.start ? this.start.hubUserName : null;
        // Deletions found from the branch have no author in the org, so Changed by doesn't hide them.
        return (c) => this.changedBy === 'anyone' || !me || c.modifiedBy === me || (c.deleted && !c.modifiedBy);
    }

    get pool() {
        const mine = this.byMe;
        return this.changes.filter((c) => mine(c) && (this.show === 'both' || (this.show === 'standard') === c.standard));
    }

    get typeNav() {
        const pool = this.pool;
        const counts = {};
        pool.forEach((c) => {
            counts[c.type] = (counts[c.type] || 0) + 1;
        });
        const groups = {};
        Object.keys(counts).forEach((t) => {
            const g = groupOf(t);
            (groups[g] = groups[g] || []).push(t);
        });
        const order = ['Code', 'Automation', 'Data model', 'Access and UI', 'Other'];
        const nav = [{ key: 'g-all', isGroup: false, value: 'all', label: 'All changed', count: pool.length,
            cls: 'rr-type' + (this.typeFilter === 'all' ? ' rr-type-on' : ''), pressed: this.typeFilter === 'all' ? 'true' : 'false' }];
        const deletions = pool.filter((c) => c.deleted).length;
        if (deletions || this.typeFilter === 'deleted') {
            nav.push({ key: 'g-deleted', isGroup: false, value: 'deleted', label: 'Deleted', count: deletions,
                cls: 'rr-type rr-type-del' + (this.typeFilter === 'deleted' ? ' rr-type-on' : ''), pressed: this.typeFilter === 'deleted' ? 'true' : 'false' });
        }
        order.filter((g) => groups[g]).forEach((g) => {
            nav.push({ key: 'g-' + g, isGroup: true, label: g });
            groups[g].sort().forEach((t) => nav.push({ key: 't-' + t, isGroup: false, value: t, label: words(t), count: counts[t],
                cls: 'rr-type' + (this.typeFilter === t ? ' rr-type-on' : ''), pressed: this.typeFilter === t ? 'true' : 'false' }));
        });
        return nav;
    }

    handleType(event) {
        this.typeFilter = event.currentTarget.dataset.value;
        this.shown = PAGE;
    }

    get showButtons() {
        return SHOW.map((s) => ({ ...s, cls: 'rr-seg' + (s.value === this.show ? ' rr-seg-on' : ''), pressed: s.value === this.show ? 'true' : 'false' }));
    }

    handleShow(event) {
        this.show = event.currentTarget.dataset.value;
        this.shown = PAGE;
    }

    handleSearch(event) {
        this.search = (event.target.value || '').trim().toLowerCase();
        this.shown = PAGE;
    }

    get filtered() {
        const q = this.search;
        return this.pool.filter((c) => (this.typeFilter === 'all' || c.type === this.typeFilter || (this.typeFilter === 'deleted' && c.deleted))
            && (!q || c.name.toLowerCase().includes(q) || c.type.toLowerCase().includes(q)));
    }

    get rows() {
        return this.filtered.slice(0, this.shown).map((c) => {
            const on = this.selected.has(c.key);
            const isTest = !c.deleted && c.type === 'ApexClass' && this.tests.has(c.name);
            const changed = [c.modifiedOn ? new Date(c.modifiedOn).toLocaleDateString([], { month: 'short', day: 'numeric' }) : '', c.modifiedBy || ''].join(' ').trim();
            return {
                ...c,
                checked: on,
                rowCls: (on ? 'rr-row-on' : '') + (c.deleted ? ' rr-row-del' : ''),
                typeLabel: isTest ? 'Apex test class' : words(c.type),
                kind: c.standard ? 'Standard' : 'Custom',
                kindCls: 'rr-pill ' + (c.standard ? 'rr-pill-std' : 'rr-pill-custom'),
                when: c.modifiedOn ? new Date(c.modifiedOn).toLocaleDateString([], { month: 'short', day: 'numeric' }) : '',
                by: c.modifiedBy || '',
                changedText: changed,
                deleteText: c.deleted ? this.deleteFromText : '',
                selLabel: (c.deleted ? 'Delete ' : 'Select ') + c.name
            };
        });
    }

    get noRows() { return !this.scanning && this.filtered.length === 0; }
    get emptyText() {
        if (this.typeFilter === 'deleted') {
            return 'No deletions found in ' + this.sourceName + '.';
        }
        if (this.changes.length === 0) {
            return 'No changes found in ' + this.sourceName + ' for this period. Try Any time, or add a component by name.';
        }
        return this.changedBy === 'me' ? 'Nothing here changed by you. Switch Changed by to Anyone.' : 'Nothing matches.';
    }
    get hasMore() { return this.filtered.length > this.shown; }
    get moreLabel() { return 'Show ' + Math.min(PAGE, this.filtered.length - this.shown) + ' more'; }
    showMore() { this.shown += PAGE; }

    /** Select all ticks changes only: deletions are never ticked for the user, each one is ticked by hand. */
    get allShownChecked() {
        const rows = this.rows.filter((r) => !r.deleted);
        return rows.length > 0 && rows.every((r) => r.checked);
    }
    get noCheckAll() { return this.rows.every((r) => r.deleted); }

    handleCheck(event) {
        const key = event.target.dataset.key;
        const next = new Set(this.selected);
        if (event.target.checked) {
            next.add(key);
        } else {
            next.delete(key);
        }
        this.selected = next;
    }

    handleCheckAll(event) {
        const next = new Set(this.selected);
        this.rows.filter((r) => !r.deleted).forEach((r) => (event.target.checked ? next.add(r.key) : next.delete(r.key)));
        this.selected = next;
    }

    // ---------- deletions ----------

    get target() { return (this.start && this.start.targetName) || 'the target'; }
    get deleteFromText() { return 'Delete from ' + this.target; }
    get deletedGroupLabel() { return 'Deleted from ' + this.target; }
    /** Orgs without source tracking can't list their deletions: the hub compares the org with its branch. */
    get canFindDeletions() { return !!this.sourceOrg && this.sourceOrg.Source_Tracking__c !== 'Available'; }
    get cantFindDeletions() { return this.scanning || this.findingDeletions; }
    get findLabel() { return this.findingDeletions ? 'Finding deleted components…' : 'Find deleted components'; }
    /** The developer org's own branch, else the first stage's. */
    get ownBranch() { return this.sourceBranch || (this.start && this.start.targetBranch) || 'the branch'; }
    get deletionResultCls() { return 'rr-msg rr-msg-inset ' + (this.deletionResultBad ? 'rr-msg-bad' : 'rr-msg-info'); }

    async findDeleted() {
        this.findingDeletions = true;
        this.deletionResult = undefined;
        this.deletionResultBad = false;
        try {
            const found = (await findDeletions({ orgId: this.orgId })).map(asDeletion);
            const known = new Set(this.changes.map((c) => c.key));
            const fresh = found.filter((c) => !known.has(c.key));
            this.changes = [...this.changes, ...fresh];
            if (this.cache[this.cacheKey]) {
                this.cache[this.cacheKey] = { ...this.cache[this.cacheKey], changes: this.changes };
            }
            const branch = this.ownBranch;
            const org = this.sourceName;
            if (found.length === 0) {
                this.deletionResult = 'Everything in ' + branch + '\'s branch is in ' + org + '. Nothing to delete.';
            } else {
                this.deletionResult = 'In ' + branch + '\'s branch but not in ' + org
                    + '. They may have been deleted in ' + org + ', or came from another org through the branch and were never deployed to ' + org
                    + '. Tick only what you deleted.';
                this.typeFilter = 'deleted';
                this.shown = PAGE;
            }
        } catch (e) {
            this.deletionResult = errorText(e);
            this.deletionResultBad = true;
        } finally {
            this.findingDeletions = false;
        }
    }

    // ---------- add by name ----------

    /** The message when a component is picked to be added and to be deleted. */
    bothText(type, name) { return type + ' ' + name + ' is both added and deleted.'; }

    // ---------- the selection and the test rule ----------

    get selectedItems() {
        const byKey = new Map(this.changes.map((c) => [c.key, c]));
        return [...this.selected].map((k) => byKey.get(k)).filter(Boolean);
    }

    get apexItems() {
        return this.selectedItems.filter((c) => !c.deleted && (c.type === 'ApexTrigger' || (c.type === 'ApexClass' && !this.tests.has(c.name))));
    }

    get testItems() {
        return this.selectedItems.filter((c) => !c.deleted && c.type === 'ApexClass' && this.tests.has(c.name));
    }

    get addedItems() { return this.selectedItems.filter((c) => !c.deleted); }
    get deletionItems() { return this.selectedItems.filter((c) => c.deleted); }
    get hasDeletions() { return this.deletionItems.length > 0; }
    /** Picked to be added and to be deleted: the hub refuses it, so it is shown before raising. */
    get bothItems() {
        const added = new Set(this.addedItems.map((c) => c.type + ':' + c.name));
        return this.deletionItems.filter((c) => added.has(c.type + ':' + c.name));
    }
    get bothError() {
        const b = this.bothItems;
        return b.length ? b.map((c) => this.bothText(c.type, c.name)).join(' ') : '';
    }

    get ruleBlocked() { return this.apexItems.length > 0 && this.testItems.length === 0; }
    get ruleOk() { return this.apexItems.length > 0 && this.testItems.length > 0; }
    get selectedCount() { return this.selected.size; }
    get noneSelected() { return this.selected.size === 0; }
    get cantReview() { return this.noneSelected || this.ruleBlocked || this.scanning || this.bothItems.length > 0; }

    get barCls() { return 'rr-bar' + (this.ruleBlocked || this.bothItems.length ? ' rr-bar-bad' : ''); }
    get barText() {
        const n = this.selected.size;
        const parts = [n + ' selected'];
        const d = this.deletionItems.length;
        if (d) {
            parts.push(d + (d === 1 ? ' deletion' : ' deletions'));
        }
        if (this.apexItems.length) {
            parts.push(this.apexItems.length + ' Apex');
            parts.push(this.testItems.length + (this.testItems.length === 1 ? ' test class' : ' test classes') + (this.ruleOk ? ' ✓' : ''));
        }
        return parts.join(' · ');
    }
    get ruleText() {
        return 'Apex selected without a test class. Tick the test class that covers it (or add it by name).';
    }
    get suggestions() {
        if (!this.ruleBlocked) {
            return [];
        }
        const names = this.apexItems.map((c) => c.name.toLowerCase());
        return this.changes
            .filter((c) => !c.deleted && c.type === 'ApexClass' && this.tests.has(c.name) && !this.selected.has(c.key)
                && names.some((n) => c.name.toLowerCase().includes(n)))
            .slice(0, 3)
            .map((c) => ({ key: c.key, name: c.name, addLabel: 'Add ' + c.name }));
    }
    get hasSuggestions() { return this.suggestions.length > 0; }

    addSuggestion(event) {
        this.selected = new Set([...this.selected, event.currentTarget.dataset.key]);
    }

    toggleDrawer() { this.drawerOpen = !this.drawerOpen; }
    get drawerLabel() { return this.drawerOpen ? 'Hide selection' : 'Show selection'; }

    get grouped() {
        const groups = {};
        this.addedItems.forEach((c) => {
            const label = c.type === 'ApexClass' && this.tests.has(c.name) ? 'Apex test class' : words(c.type);
            (groups[label] = groups[label] || []).push(c);
        });
        const out = Object.keys(groups).sort().map((g) => ({
            key: g,
            label: g + ' · ' + groups[g].length,
            labelCls: 'rr-label',
            chipCls: 'rr-chip',
            items: groups[g].map((c) => ({ key: c.key, name: c.name, removeLabel: 'Remove ' + c.name }))
        }));
        const del = this.deletionItems;
        if (del.length) {
            out.unshift({
                key: 'deleted',
                label: this.deletedGroupLabel + ' · ' + del.length,
                labelCls: 'rr-label rr-del',
                chipCls: 'rr-chip rr-chip-del',
                items: del.map((c) => ({ key: c.key, name: words(c.type) + ' ' + c.name, removeLabel: 'Don\'t delete ' + c.name }))
            });
        }
        return out;
    }

    removeItem(event) {
        const next = new Set(this.selected);
        next.delete(event.currentTarget.dataset.key);
        this.selected = next;
    }

    clearSelection() {
        this.selected = new Set();
    }

    goReview() {
        this.drawerOpen = false;
        this.step = 'review';
        this.readFlows();
    }

    backToSelect() {
        this.step = 'select';
    }

    // ---------- step 3: review and raise ----------

    get scopeText() {
        const w = WINDOWS.find((x) => x.value === this.windowChoice);
        const when = this.windowChoice === 'date' ? 'changed since ' + (this.sinceDate || '…') : (w ? w.label.toLowerCase() : '');
        return when + ' · changed by ' + (this.changedBy === 'me' ? 'me' : 'anyone');
    }

    get reviewRows() {
        return this.addedItems
            .map((c) => {
                const isTest = c.type === 'ApexClass' && this.tests.has(c.name);
                return {
                    key: c.key, name: c.name, typeLabel: isTest ? 'Apex test class' : words(c.type),
                    kind: c.standard ? 'Standard' : 'Custom', kindCls: 'rr-pill ' + (c.standard ? 'rr-pill-std' : 'rr-pill-custom'),
                    removeLabel: 'Remove ' + c.name,
                    subText: (isTest ? 'Apex test class' : words(c.type)) + ' · ' + (c.standard ? 'Standard' : 'Custom')
                };
            })
            .sort((a, b) => (a.typeLabel + a.name).localeCompare(b.typeLabel + b.name));
    }

    get hasAdded() { return this.addedItems.length > 0; }
    get reviewDeletions() {
        return this.deletionItems
            .map((c) => ({ key: c.key, name: c.name, subText: words(c.type) + ' · ' + this.deleteFromText, removeLabel: 'Don\'t delete ' + c.name }))
            .sort((a, b) => (a.subText + a.name).localeCompare(b.subText + b.name));
    }

    get reviewSummary() {
        const added = this.addedItems;
        const n = added.length;
        const types = new Set(added.map((c) => c.type)).size;
        const d = this.deletionItems.length;
        const parts = [];
        if (n || !d) {
            parts.push(n + (n === 1 ? ' component' : ' components') + ' of ' + types + (types === 1 ? ' type' : ' types'));
        }
        if (d) {
            parts.push(d + (d === 1 ? ' deletion' : ' deletions'));
        }
        return parts.join(' · ');
    }

    title = '';
    description = '';
    hotfix = false;
    hotfixReason = '';
    /** Manual steps for the release (RaiseRequest.manualSteps), from c-rly-manual-steps. */
    manualSteps = [];
    raising = false;
    raiseError;
    raisedId;

    get isRaised() { return this.step === 'raise'; }
    /** The target's branch, as the compare board names it (for example: main branch). */
    get targetBranchLabel() {
        const branch = this.start && this.start.targetBranch;
        return branch ? branch + ' branch' : this.targetText;
    }
    /** The provider's word for a pull request (merge request in GitLab); neutral when the provider isn't known. */
    get crWord() {
        const p = this.start && this.start.provider;
        if (p === 'GitLab') {
            return 'merge request';
        }
        return ['GitHub', 'Bitbucket', 'AzureDevOps', 'Azure DevOps'].includes(p) ? 'pull request' : 'change request';
    }
    get intoText() {
        const w = this.crWord;
        return w.charAt(0).toUpperCase() + w.slice(1) + ' into ' + this.targetText;
    }
    get raiseLabel() {
        if (this.raising) {
            return 'Raising…';
        }
        return this.isHotfix ? 'Raise hotfix' : 'Raise ' + this.crWord;
    }
    get cantRaise() {
        return this.raising || this.hubCopy || this.noneSelected || this.ruleBlocked || this.bothItems.length > 0 || !(this.title || '').trim()
            || (this.isHotfix && !(this.hotfixReason || '').trim());
    }
    get reviewKicker() { return 'New release · step 4 of 5 · Review'; }

    // ---------- the hotfix flag ----------

    /** Only users with the Hotfix permission can flag a hotfix (Start.canHotfix). */
    get canHotfix() { return !!(this.start && this.start.canHotfix); }
    get isHotfix() { return this.canHotfix && this.hotfix; }
    /** The stop after the first stage (where a hotfix is promoted to next), from the route's stops. */
    get nextStopName() {
        const stops = ((this.start && this.start.routeStops) || []).filter((o) => o.Role__c === 'Stage' || o.Role__c === 'Hub')
            .map((o) => ({ name: o.Name, order: o.Role__c === 'Hub' ? Number.MAX_SAFE_INTEGER : Number(o.Stage_Order__c || 0) }))
            .sort((a, b) => a.order - b.order);
        const i = stops.findIndex((o) => o.name === (this.start && this.start.targetName));
        return i >= 0 && i + 1 < stops.length ? stops[i + 1].name : '';
    }
    get hotfixHelp() {
        const target = (this.start && this.start.targetName) || 'the first stage';
        const next = this.nextStopName;
        return 'Goes to ' + target + ' like any release (scan, check-only deploy, tests, approval). After approval it can be promoted to '
            + (next || 'the next stop') + ' on its own.';
    }
    handleHotfix(event) {
        this.hotfix = event.target.checked;
    }
    handleHotfixReason(event) {
        this.hotfixReason = event.target.value;
    }
    // ---------- manual steps ----------

    /** The route's orgs (stages and the hub), offered under Pick orgs for a manual step. */
    get routeOrgNames() {
        return ((this.start && this.start.routeStops) || []).map((o) => o.Name);
    }
    handleManualSteps(event) {
        this.manualSteps = event.detail.steps || [];
    }
    get testRunCls() { return 'rr-msg ' + (this.ruleBlocked || this.bothItems.length ? 'rr-msg-bad' : 'rr-msg-info'); }

    handleTitle(event) { this.title = event.target.value; }
    handleDescription(event) { this.description = event.target.value; }

    get testRunText() {
        if (this.bothItems.length) {
            return this.bothError;
        }
        if (this.ruleBlocked) {
            return this.ruleText;
        }
        if (!this.apexItems.length) {
            const apexGone = this.deletionItems.some((c) => c.type === 'ApexClass' || c.type === 'ApexTrigger');
            return apexGone
                ? 'No Apex added: deploys run without tests (NoTestRun). Deleting Apex from production runs the local tests (RunLocalTests), as Salesforce requires.'
                : 'No Apex in this release: deploys run without tests (NoTestRun).';
        }
        return 'Runs ' + this.testItems.map((t) => t.name).join(', ') + ' (RunSpecifiedTests) in every org it deploys to. Each Apex class and trigger needs 75% coverage.';
    }

    // ---------- flows: versions and the After deploy choice (board HubApprovalFlowsEvidence 2) ----------

    /** RlyChangesController.flowVersions: FlowInfo by flow name, read from the source org when Review opens. */
    flowInfo = {};
    flowsLoading = false;
    flowsError;
    /** The After deploy choice per flow name (Keep by default), sent as RaiseRequest.flowChoices. */
    flowPicks = {};

    get flowNames() {
        return [...new Set(this.addedItems.filter((c) => c.type === 'Flow').map((c) => c.name))].sort();
    }
    get hasFlows() { return this.flowNames.length > 0; }
    get flowCountText() { const n = this.flowNames.length; return n + (n === 1 ? ' flow' : ' flows'); }

    readFlows() {
        const names = this.flowNames;
        if (!names.length || !this.orgId) {
            return;
        }
        this.flowsLoading = true;
        this.flowsError = undefined;
        flowVersions({ orgId: this.orgId, names })
            .then((list) => {
                const next = {};
                (list || []).forEach((f) => {
                    next[f.name] = f;
                });
                this.flowInfo = next;
            })
            .catch((e) => {
                this.flowInfo = {};
                this.flowsError = 'Couldn\'t read the flow versions from ' + this.sourceName + ': ' + errorText(e);
            })
            .finally(() => {
                this.flowsLoading = false;
            });
    }

    /** The stages and the hub the release deploys to, in route order. */
    get routeTargets() {
        return ((this.start && this.start.routeStops) || []).filter((o) => o.Role__c === 'Stage' || o.Role__c === 'Hub')
            .map((o) => ({ name: o.Name, order: o.Role__c === 'Hub' ? Number.MAX_SAFE_INTEGER : Number(o.Stage_Order__c || 0) }))
            .sort((a, b) => a.order - b.order)
            .map((o) => o.name);
    }
    get routeTargetsText() {
        const names = this.routeTargets;
        if (names.length < 2) {
            return names[0] || 'each org';
        }
        return names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
    }
    get flowsKicker() {
        const from = this.flowsLoading ? 'Reading versions from ' + this.sourceName + '…' : 'Versions read from ' + this.sourceName + ' just now.';
        return from + ' Choose what happens to each flow after it\'s deployed to ' + this.routeTargetsText + '.';
    }
    get flowChoiceOptions() {
        const src = this.sourceName || 'the developer org';
        return [
            { label: 'Keep as in ' + src, value: FLOW_KEEP },
            { label: 'Activate in each org', value: FLOW_ACTIVATE },
            { label: 'Leave inactive: add a manual step to activate', value: FLOW_INACTIVE }
        ];
    }

    get flowRows() {
        return this.flowNames.map((name) => {
            const f = this.flowInfo[name];
            const choice = this.flowPicks[name] || FLOW_KEEP;
            const status = f && f.latestStatus;
            const draft = !!f && status !== 'Active';
            let where = 'in ' + this.sourceName;
            if (draft) {
                where += f.active ? ' · active: Version ' + f.active : ' · no active version';
            }
            return {
                name,
                choice,
                versionText: f ? 'Version ' + f.latest + ' · ' + (FLOW_STATUS_LABEL[status] || status || 'Unknown') : (this.flowsLoading ? 'Reading…' : 'Version unknown'),
                versionCls: (f && FLOW_STATUS_CLS[status]) || 'rr-pill rr-pill-none',
                where: f ? where : '',
                draftText: draft && choice !== FLOW_ACTIVATE
                    ? 'Version ' + f.latest + ' is a draft. It deploys inactive: ' + this.routeTargetsText + ' keep running their current version unless you choose Activate.'
                    : '',
                stepText: choice === FLOW_INACTIVE
                    ? 'Adds manual step “Activate flow ' + name + '” · Setup · After deploy · every org. It shows on the release\'s Manual steps once raised.'
                    : '',
                groupLabel: 'After deploy: ' + name
            };
        });
    }

    handleFlowChoice(event) {
        this.flowPicks = { ...this.flowPicks, [event.target.dataset.name]: event.detail.value };
    }

    /** RaiseRequest.flowChoices: one {name, choice} per selected flow. */
    get flowChoices() {
        return this.flowNames.map((name) => ({ name, choice: this.flowPicks[name] || FLOW_KEEP }));
    }

    // ---------- approval preview: the first stage's approval rule (RLY_Org__c.Approval_Rule__c / Approval_Types__c) ----------

    get targetStop() {
        const name = this.start && this.start.targetName;
        return ((this.start && this.start.routeStops) || []).find((o) => o.Name === name);
    }

    /** The release's kinds of change, as RlyApprovalRules buckets them. */
    get releaseBuckets() {
        const out = new Set(this.addedItems.map((c) => TYPE_BUCKETS[c.type] || 'Other'));
        if (this.deletionItems.length) {
            out.add('Deletions');
        }
        if ((this.manualSteps || []).length || this.flowChoices.some((f) => f.choice === FLOW_INACTIVE)) {
            out.add('Manual_Steps');
        }
        if (this.isHotfix) {
            out.add('Hotfix');
        }
        return out;
    }

    get approvalPreview() {
        const t = this.targetStop;
        if (!t || !t.Approval_Rule__c) {
            return '';
        }
        if (t.Approval_Rule__c === 'Never') {
            return 'Approved automatically when the checks pass (' + t.Name + '\'s rule: Never).';
        }
        if (t.Approval_Rule__c !== 'Selected_Types') {
            return 'Always needs approval in ' + t.Name + '.';
        }
        const ticked = String(t.Approval_Types__c || '').split(';');
        const hits = Object.keys(BUCKET_WORDS).filter((b) => ticked.includes(b) && this.releaseBuckets.has(b)).map((b) => BUCKET_WORDS[b]);
        if (!hits.length) {
            return 'Approved automatically when the checks pass: nothing in this release needs approval in ' + t.Name + '.';
        }
        const list = hits.length > 1 ? hits.slice(0, -1).join(', ') + ' and ' + hits[hits.length - 1] : hits[0];
        return 'Needs approval: contains ' + list + '.';
    }
    get approvalPreviewLead() { return 'Approval in ' + (this.targetStop ? this.targetStop.Name : '') + ': '; }
    get approvalPreviewRule() {
        const t = this.targetStop;
        const labels = { Always: 'Always', Selected_Types: 'Only when the release contains…', Never: 'Never' };
        return t ? ' (' + t.Name + '\'s rule: ' + (labels[t.Approval_Rule__c] || t.Approval_Rule__c) + ')' : '';
    }

    async raise() {
        this.raising = true;
        this.raiseError = undefined;
        try {
            const items = this.addedItems.map((c) => ({ type: c.type, name: c.name, deleted: false, standard: !!c.standard }));
            const deletions = this.deletionItems.map((c) => ({ type: c.type, name: c.name }));
            const request = {
                sourceOrgId: this.orgId,
                title: this.title.trim(),
                description: this.description,
                items,
                deletions,
                testClasses: this.testItems.map((t) => t.name),
                isHotfix: this.isHotfix,
                hotfixReason: this.isHotfix ? this.hotfixReason.trim() : null,
                manualSteps: this.manualSteps,
                flowChoices: this.flowChoices
            };
            this.raisedId = await raiseRelease({ requestJson: JSON.stringify(request) });
            this.step = 'raise';
        } catch (e) {
            this.raiseError = errorText(e);
        } finally {
            this.raising = false;
        }
    }

    startOver() {
        this.selected = new Set();
        this.title = '';
        this.description = '';
        this.hotfix = false;
        this.hotfixReason = '';
        this.manualSteps = [];
        this.flowPicks = {};
        this.flowInfo = {};
        this.raisedId = undefined;
        this.step = 'source';
    }
}
