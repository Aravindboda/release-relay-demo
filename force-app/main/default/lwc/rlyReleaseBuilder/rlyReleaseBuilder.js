import { LightningElement } from 'lwc';
import getStart from '@salesforce/apex/RlyChangesController.getStart';
import describeTypes from '@salesforce/apex/RlyChangesController.describeTypes';
import listChanges from '@salesforce/apex/RlyChangesController.listChanges';
import listFolderChanges from '@salesforce/apex/RlyChangesController.listFolderChanges';
import listTracked from '@salesforce/apex/RlyChangesController.listTracked';
import detectTests from '@salesforce/apex/RlyChangesController.detectTests';
import raiseRelease from '@salesforce/apex/RlyReleasesController.raiseRelease';

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

export default class RlyReleaseBuilder extends LightningElement {
    windows = WINDOWS;
    showOptions = SHOW;

    step = 'source';
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
    manualType = 'ApexClass';
    manualName = '';
    manualError;
    allTypes = [];

    connectedCallback() {
        this.loading = true;
        getStart()
            .then((s) => {
                this.start = s;
                const ready = (s.developers || []).filter((d) => d.Status__c === 'Connected');
                if (ready.length === 1) {
                    this.orgId = ready[0].Id;
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

    get isSource() { return this.step === 'source'; }
    get isSelect() { return this.step === 'select'; }
    get isReview() { return this.step === 'review'; }

    get pathSteps() {
        const order = ['source', 'select', 'review', 'raise'];
        const labels = { source: 'Source', select: 'Select', review: 'Review', raise: 'Raise' };
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

    get orgCards() {
        return ((this.start && this.start.developers) || []).map((d) => {
            const ready = d.Status__c === 'Connected';
            const on = d.Id === this.orgId;
            return {
                id: d.Id,
                name: d.Name,
                branch: d.Branch__c,
                note: ready ? (d.Source_Tracking__c === 'Available' ? 'Fast: source tracking' : 'Metadata API') : 'Not connected: check it on the Pipeline tab',
                cls: 'rr-src' + (on ? ' rr-src-on' : '') + (ready ? '' : ' rr-src-off'),
                pressed: on ? 'true' : 'false',
                disabled: ready ? null : true
            };
        });
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
    handleBy(event) { this.changedBy = event.currentTarget.dataset.value; }

    get cantScan() {
        return !this.orgId || this.hasProblems || (this.isSinceDate && !this.sinceDate);
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
            this.changes = found;
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
        return (c) => this.changedBy === 'anyone' || !me || c.modifiedBy === me;
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
            cls: 'rr-type' + (this.typeFilter === 'all' ? ' rr-type-on' : '') }];
        order.filter((g) => groups[g]).forEach((g) => {
            nav.push({ key: 'g-' + g, isGroup: true, label: g });
            groups[g].sort().forEach((t) => nav.push({ key: 't-' + t, isGroup: false, value: t, label: words(t), count: counts[t],
                cls: 'rr-type' + (this.typeFilter === t ? ' rr-type-on' : '') }));
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
        return this.pool.filter((c) => (this.typeFilter === 'all' || c.type === this.typeFilter)
            && (!q || c.name.toLowerCase().includes(q) || c.type.toLowerCase().includes(q)));
    }

    get rows() {
        return this.filtered.slice(0, this.shown).map((c) => {
            const on = this.selected.has(c.key);
            const isTest = c.type === 'ApexClass' && this.tests.has(c.name);
            return {
                ...c,
                checked: on,
                rowCls: on ? 'rr-row-on' : '',
                typeLabel: isTest ? 'Apex test class' : words(c.type),
                kind: c.standard ? 'Standard' : 'Custom',
                kindCls: 'rr-pill ' + (c.standard ? 'rr-pill-std' : 'rr-pill-custom'),
                when: c.modifiedOn ? new Date(c.modifiedOn).toLocaleDateString([], { month: 'short', day: 'numeric' }) : '',
                by: c.modifiedBy || '',
                selLabel: 'Select ' + c.name
            };
        });
    }

    get noRows() { return !this.scanning && this.filtered.length === 0; }
    get emptyText() {
        if (this.changes.length === 0) {
            return 'No changes found in ' + this.sourceName + ' for this period. Try Any time, or add a component by name.';
        }
        return this.changedBy === 'me' ? 'Nothing here changed by you. Switch Changed by to Anyone.' : 'Nothing matches.';
    }
    get hasMore() { return this.filtered.length > this.shown; }
    get moreLabel() { return 'Show ' + Math.min(PAGE, this.filtered.length - this.shown) + ' more'; }
    showMore() { this.shown += PAGE; }

    get allShownChecked() {
        const rows = this.rows;
        return rows.length > 0 && rows.every((r) => r.checked);
    }

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
        this.rows.forEach((r) => (event.target.checked ? next.add(r.key) : next.delete(r.key)));
        this.selected = next;
    }

    // ---------- add by name ----------

    get typeOptions() {
        const types = this.allTypes.length ? this.allTypes : ['ApexClass', 'ApexTrigger', 'CustomField', 'CustomObject', 'Layout', 'PermissionSet', 'Flow'];
        return types.map((t) => ({ label: words(t), value: t }));
    }

    handleManualType(event) { this.manualType = event.detail.value; }
    handleManualName(event) { this.manualName = event.target.value; this.manualError = undefined; }

    async addManual() {
        const name = (this.manualName || '').trim();
        if (!name || /[,:\r\n]/.test(name)) {
            this.manualError = 'Enter the API name, for example AccountServiceTest or Account.Region__c.';
            return;
        }
        const key = this.manualType + ':' + name;
        if (!this.changes.some((c) => c.key === key)) {
            const isStd = (this.manualType === 'CustomObject' && !name.includes('__'))
                || (this.manualType === 'CustomField' && name.includes('.') && !name.split('.')[1].includes('__'))
                || this.manualType === 'StandardValueSet';
            this.changes = [{ key, type: this.manualType, name, standard: isStd, deleted: false, modifiedBy: '(added by name)', modifiedOn: null }, ...this.changes];
        }
        if (this.manualType === 'ApexClass') {
            try {
                const found = await detectTests({ orgId: this.orgId, classNames: [name] });
                if (found.length) {
                    this.tests = new Set([...this.tests, ...found]);
                }
            } catch (e) {
                this.manualError = errorText(e);
            }
        }
        this.selected = new Set([...this.selected, key]);
        this.manualName = '';
    }

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

    get ruleBlocked() { return this.apexItems.length > 0 && this.testItems.length === 0; }
    get ruleOk() { return this.apexItems.length > 0 && this.testItems.length > 0; }
    get selectedCount() { return this.selected.size; }
    get noneSelected() { return this.selected.size === 0; }
    get cantReview() { return this.noneSelected || this.ruleBlocked || this.scanning; }

    get barCls() { return 'rr-bar' + (this.ruleBlocked ? ' rr-bar-bad' : ''); }
    get barText() {
        const n = this.selected.size;
        const parts = [n + (n === 1 ? ' selected' : ' selected')];
        if (this.apexItems.length) {
            parts.push(this.apexItems.length + ' Apex');
            parts.push(this.testItems.length + (this.testItems.length === 1 ? ' test class' : ' test classes') + (this.ruleOk ? ' ✓' : ''));
        }
        return parts.join(' · ');
    }
    get ruleText() {
        return 'Apex selected without a test class. Tick the test class that covers it (or add it by name): the release runs it in every org it deploys to.';
    }
    get suggestions() {
        if (!this.ruleBlocked) {
            return [];
        }
        const names = this.apexItems.map((c) => c.name.toLowerCase());
        return this.changes
            .filter((c) => c.type === 'ApexClass' && this.tests.has(c.name) && !this.selected.has(c.key)
                && names.some((n) => c.name.toLowerCase().includes(n)))
            .slice(0, 3)
            .map((c) => ({ key: c.key, name: c.name }));
    }
    get hasSuggestions() { return this.suggestions.length > 0; }

    addSuggestion(event) {
        this.selected = new Set([...this.selected, event.currentTarget.dataset.key]);
    }

    toggleDrawer() { this.drawerOpen = !this.drawerOpen; }
    get drawerLabel() { return this.drawerOpen ? 'Hide selection' : 'Show selection'; }

    get grouped() {
        const groups = {};
        this.selectedItems.forEach((c) => {
            const label = c.type === 'ApexClass' && this.tests.has(c.name) ? 'Apex test class' : words(c.type);
            (groups[label] = groups[label] || []).push(c);
        });
        return Object.keys(groups).sort().map((g) => ({
            key: g,
            label: g + ' · ' + groups[g].length,
            items: groups[g].map((c) => ({ key: c.key, name: c.name, removeLabel: 'Remove ' + c.name, deleted: c.deleted }))
        }));
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
        return this.selectedItems
            .map((c) => {
                const isTest = c.type === 'ApexClass' && this.tests.has(c.name);
                return {
                    key: c.key, name: c.name, typeLabel: isTest ? 'Apex test class' : words(c.type),
                    kind: c.standard ? 'Standard' : 'Custom', kindCls: 'rr-pill ' + (c.standard ? 'rr-pill-std' : 'rr-pill-custom'),
                    removeLabel: 'Remove ' + c.name
                };
            })
            .sort((a, b) => (a.typeLabel + a.name).localeCompare(b.typeLabel + b.name));
    }

    get reviewSummary() {
        const n = this.selected.size;
        const types = new Set(this.selectedItems.map((c) => c.type)).size;
        return n + (n === 1 ? ' component' : ' components') + ' of ' + types + (types === 1 ? ' type' : ' types');
    }

    title = '';
    description = '';
    raising = false;
    raiseError;
    raisedId;

    get isRaised() { return this.step === 'raise'; }
    get raiseLabel() { return this.raising ? 'Raising…' : 'Raise pull request'; }
    get cantRaise() { return this.raising || this.noneSelected || this.ruleBlocked || !(this.title || '').trim(); }
    get testRunCls() { return 'rr-msg ' + (this.ruleBlocked ? 'rr-msg-bad' : 'rr-msg-info'); }

    handleTitle(event) { this.title = event.target.value; }
    handleDescription(event) { this.description = event.target.value; }

    get testRunText() {
        if (this.ruleBlocked) {
            return this.ruleText;
        }
        if (!this.apexItems.length) {
            return 'No Apex in this release: deploys run without tests (NoTestRun).';
        }
        return 'Runs ' + this.testItems.map((t) => t.name).join(', ') + ' (RunSpecifiedTests) in every org it deploys to. Each Apex class and trigger needs 75% coverage.';
    }

    async raise() {
        this.raising = true;
        this.raiseError = undefined;
        try {
            const items = this.selectedItems.map((c) => ({ type: c.type, name: c.name, deleted: !!c.deleted, standard: !!c.standard }));
            const request = {
                sourceOrgId: this.orgId,
                title: this.title.trim(),
                description: this.description,
                items,
                testClasses: this.testItems.map((t) => t.name)
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
        this.raisedId = undefined;
        this.step = 'source';
    }
}
