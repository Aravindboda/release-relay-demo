import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement, api } from 'lwc';
import getSteps from '@salesforce/apex/RlyManualStepController.getSteps';
import saveStep from '@salesforce/apex/RlyManualStepController.saveStep';
import deleteStep from '@salesforce/apex/RlyManualStepController.deleteStep';
import markRun from '@salesforce/apex/RlyManualStepController.markRun';
import getStart from '@salesforce/apex/RlyChangesController.getStart';

const CATEGORIES = [
    { value: 'Permissions', label: 'Profile or permission access' },
    { value: 'Data', label: 'Data' },
    { value: 'Setup', label: 'Setup configuration' },
    { value: 'Other', label: 'Other' }
];
const TIMINGS = [
    { value: 'Before_Deploy', label: 'Before deploy' },
    { value: 'After_Deploy', label: 'After deploy' }
];
const SCOPES = [
    { value: 'all', label: 'All orgs on the route' },
    { value: 'pick', label: 'Pick orgs' }
];
const BEFORE = 'Before_Deploy';
const DONE = 'Done';
const NOT_NEEDED = 'Not_Needed';
const TO_DO = 'To_Do';
const MAX_STEPS = 50;
const MAX_TITLE = 120;

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function when(value) {
    return value ? new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
}

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

function labelOf(options, value) {
    const o = options.find((x) => x.value === value);
    return o ? o.label : (value || '');
}

function timingCls(timing) {
    return 'rr-pill ' + (timing === BEFORE ? 'rr-pill-wait' : 'rr-pill-info');
}

function scopeNames(scope) {
    return (scope || '').split(',').map((s) => s.trim()).filter((s) => s);
}

/** Where a step applies, as the board words it: "All orgs on the route · also in back promote orgs". */
function whereText(step) {
    const names = scopeNames(step.orgScope);
    const orgs = names.length ? names.join(', ') + ' only' : 'All orgs on the route';
    return orgs + (step.backPromote ? ' · also in back promote orgs' : ' · not in back promote orgs');
}

function blankForm() {
    return { id: null, key: null, title: '', category: 'Permissions', timing: 'After_Deploy', instructions: '', backPromote: true, scopeMode: 'all', scopeOrgs: [] };
}

/**
 * Manual steps (board HubManualSteps): changes that can't be deployed as metadata. They follow the release through every
 * org on the route, in order, and the deployment team checks each one off per org.
 * Two uses:
 *  - draft (New Release → Review): the steps are kept here and sent up in a stepschange event ({ steps }) as StepInput rows;
 *  - a release (release-id): RlyManualStepController.getSteps, per org tabs with the checklist; canEdit users add, edit and
 *    reorder steps until the first deploy; canCheck users (deployment team, admin) tick them with markRun.
 */
export default class RlyManualSteps extends LightningElement {
    @api draft = false;
    /** The release's number (REL-…), to tell its own steps from the ones a promotion carries. */
    @api releaseName;
    /** Org names offered under Pick orgs (New Release passes the route; a release reads it when needed). */
    @api orgOptions;
    @api disabled = false;

    /** New Release: the steps so far (StepInput rows), so they survive going back to the select step. */
    @api
    get value() {
        return this._emitted;
    }
    set value(list) {
        // The parent hands back what this component sent (as a read-only copy): only a different list replaces the drafts.
        if (JSON.stringify(list || []) === JSON.stringify(this._emitted || [])) {
            return;
        }
        this._emitted = list;
        this.drafts = (Array.isArray(list) ? list : []).map((s, i) => ({ ...s, sequence: i + 1, key: 'd' + this.nextKey++ }));
    }

    _releaseId;
    _status;
    board;
    error;
    loading = false;
    busy = false;
    /** Draft steps: StepInput plus a key. */
    drafts = [];
    formOpen = false;
    form = blankForm();
    formError;
    selectedOrgId;
    /** Run ids whose instructions were opened or closed by hand (open runs start opened). */
    toggled = new Set();
    /** The run whose Not needed note is being typed, and the note. */
    notingId;
    noteText = '';
    routeNames;
    nextKey = 1;
    _emitted;

    @api
    get releaseId() {
        return this._releaseId;
    }
    set releaseId(value) {
        const changed = value !== this._releaseId;
        this._releaseId = value;
        if (changed) {
            this.board = undefined;
            this.selectedOrgId = undefined;
            this.formOpen = false;
            if (value) {
                this.load();
            }
        }
    }

    /** The release's status: when it moves (raised, deployed…) the runs change, so the steps are read again. */
    @api
    get status() {
        return this._status;
    }
    set status(value) {
        const changed = this._status !== undefined && value !== this._status;
        this._status = value;
        if (changed && this._releaseId) {
            this.load();
        }
    }

    async load() {
        this.loading = !this.board;
        try {
            this.apply(await getSteps({ releaseId: this._releaseId }));
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
    }

    apply(board) {
        this.board = board;
        const orgs = this.orgs;
        if (!orgs.some((o) => o.orgId === this.selectedOrgId)) {
            const open = orgs.find((o) => o.open > 0);
            this.selectedOrgId = open ? open.orgId : (orgs[0] && orgs[0].orgId);
        }
    }

    /** Calls the server, shows its answer, and tells the release page (header pill, notice, a deploy that started). */
    async call(fn, args) {
        this.busy = true;
        this.error = undefined;
        try {
            this.apply(await fn(args));
            this.dispatchEvent(new CustomEvent('stepschange', { detail: { open: this.openCount } }));
            return true;
        } catch (e) {
            this.error = errorText(e);
            return false;
        } finally {
            this.busy = false;
        }
    }

    // ---------- header ----------

    get cardCls() { return this.draft ? 'rr-ms-flat' : 'rr-card'; }
    get headCls() { return this.draft ? 'rr-hd rr-hd-flat' : 'rr-hd rr-hd-line'; }
    get orgs() { return (this.board && this.board.orgs) || []; }
    get hasOrgs() { return this.orgs.length > 0; }
    get canEdit() { return this.draft ? !this.disabled : !!(this.board && this.board.canEdit) && !this.disabled; }
    get canCheck() { return !!(this.board && this.board.canCheck); }
    get openCount() { return this.orgs.reduce((n, o) => n + (Number(o.open) || 0), 0); }
    get definitions() { return this.draft ? this.drafts : ((this.board && this.board.steps) || []); }
    get headPill() {
        if (!this.draft && this.hasOrgs) {
            const open = this.openCount;
            return open ? plural(open, 'manual step', 'manual steps') + ' open' : 'All done';
        }
        return plural(this.definitions.length, 'step', 'steps');
    }
    get headPillCls() {
        if (!this.draft && this.hasOrgs) {
            return 'rr-pill ' + (this.openCount ? 'rr-pill-wait' : 'rr-pill-ok');
        }
        return 'rr-pill rr-pill-none';
    }
    get showHeadPill() { return this.draft || this.hasOrgs || this.definitions.length > 0; }
    get introText() {
        return 'Things the deployment team does by hand in each org, in this order: profile or permission access, data, setup. '
            + 'They follow the release to every org on the route and to back promote orgs.';
    }
    get showIntro() { return this.draft || (!this.hasOrgs && this.canEdit); }
    /** A release with no manual steps shows no card, unless its raiser can still add some. */
    get visible() {
        return this.draft || !!this.error || this.canEdit || this.definitions.length > 0 || this.orgs.some((o) => (o.runs || []).length > 0);
    }

    // ---------- org tabs and the checklist ----------

    get tabs() {
        return this.orgs.map((o) => {
            const on = o.orgId === this.selectedOrgId;
            const open = Number(o.open) || 0;
            const total = (o.runs || []).length;
            return {
                key: o.orgId,
                orgId: o.orgId,
                name: o.orgName,
                cls: 'slds-tabs_default__item' + (on ? ' slds-is-active' : ''),
                selected: on ? 'true' : 'false',
                tabIndex: on ? '0' : '-1',
                count: open ? open + ' open' : String(total),
                countCls: 'rr-pill rr-sp ' + (open ? 'rr-pill-wait' : 'rr-pill-none')
            };
        });
    }
    get selectedOrg() { return this.orgs.find((o) => o.orgId === this.selectedOrgId); }
    get panelLabel() { return this.selectedOrg ? 'Manual steps in ' + this.selectedOrg.orgName : 'Manual steps'; }

    /** The deploy gate: the deploy into this org waits for its open before deploy steps. */
    get gateText() {
        const o = this.selectedOrg;
        const n = o ? Number(o.beforeOpen) || 0 : 0;
        return n ? 'The deploy into ' + o.orgName + ' waits until the deployment team finishes ' + plural(n, 'manual step', 'manual steps') + ' before deploy.' : '';
    }

    get manyReleases() {
        return new Set(this.definitions.map((s) => s.fromRelease).filter((x) => x)).size > 1;
    }

    get runs() {
        const o = this.selectedOrg;
        if (!o) {
            return [];
        }
        const instructions = new Map(this.definitions.map((s) => [s.id, s.instructions]));
        const many = this.manyReleases;
        return [...(o.runs || [])]
            .sort((a, b) => (Number(a.orderNo) || 0) - (Number(b.orderNo) || 0))
            .map((r, i) => this.runView(r, i, instructions.get(r.stepId), many));
    }

    runView(r, i, text, many) {
        const status = r.status || TO_DO;
        const open = status === TO_DO;
        const expanded = !!text && (open !== this.toggled.has(r.id));
        const noting = this.notingId === r.id;
        return {
            key: r.id,
            id: r.id,
            no: i + 1,
            title: r.title,
            timingLabel: labelOf(TIMINGS, r.timing),
            timingCls: timingCls(r.timing),
            categoryLabel: labelOf(CATEGORIES, r.category),
            statusLabel: open ? '' : labelOf([{ value: DONE, label: 'Done' }, { value: NOT_NEEDED, label: 'Not needed' }], status),
            statusCls: 'rr-pill ' + (status === DONE ? 'rr-pill-ok' : 'rr-pill-none'),
            isDone: status === DONE,
            isNotNeeded: status === NOT_NEEDED,
            isOpen: open,
            tickable: this.canCheck && status !== NOT_NEEDED,
            tickLabel: (status === DONE ? 'Mark as not done: ' : 'Mark as done: ') + r.title,
            boxCls: 'rr-box' + (status === DONE ? ' rr-box-done' : '') + (status === NOT_NEEDED ? ' rr-box-na' : ''),
            boxGlyph: { [DONE]: '✓', [NOT_NEEDED]: '–' }[status] || '',
            boxLabel: open ? 'To do' : labelOf([{ value: DONE, label: 'Done' }, { value: NOT_NEEDED, label: 'Not needed' }], status),
            hasInstructions: !!text,
            instructions: text,
            expanded,
            ariaExpanded: expanded ? 'true' : 'false',
            toggleLabel: expanded ? 'Hide instructions' : 'Show instructions',
            metaText: this.metaText(r, status, many),
            showNotNeeded: this.canCheck && open && !noting,
            showReopen: this.canCheck && status === NOT_NEEDED,
            noting
        };
    }

    metaText(r, status, many) {
        const parts = [];
        if (status === DONE) {
            parts.push('Done by ' + (r.doneBy || 'someone') + (r.doneOn ? ' · ' + when(r.doneOn) : ''));
        } else if (status === NOT_NEEDED) {
            parts.push('Not needed: “' + (r.note || '') + '” · ' + (r.doneBy || '') + (r.doneOn ? ' · ' + when(r.doneOn) : ''));
        }
        if (many && r.fromRelease) {
            parts.push(r.fromRelease);
        }
        return parts.join(' · ');
    }

    get hasRuns() { return this.runs.length > 0; }
    get noRunsText() { return this.selectedOrg ? 'No manual steps in ' + this.selectedOrg.orgName + '.' : ''; }
    get checkNote() {
        if (this.canCheck) {
            return 'Tick each step when it is done in this org. Not needed asks for a note.';
        }
        return 'Only the deployment team (' + APP_NAME + ' Deployment Team, or an admin) ticks steps.'
            + (this.canEdit ? ' You can add, edit and reorder them until the first deploy.' : '');
    }

    pickOrg(event) {
        this.selectedOrgId = event.currentTarget.dataset.id;
        this.notingId = undefined;
    }

    /** Arrow keys move between the org tabs, as SLDS tabs do. */
    tabKey(event) {
        const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
        if (!step) {
            return;
        }
        const ids = this.orgs.map((o) => o.orgId);
        const at = ids.indexOf(this.selectedOrgId);
        this.selectedOrgId = ids[(at + step + ids.length) % ids.length];
        event.preventDefault();
    }

    toggleInstructions(event) {
        const id = event.currentTarget.dataset.id;
        const next = new Set(this.toggled);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this.toggled = next;
    }

    handleTick(event) {
        const id = event.target.dataset.id;
        this.mark(id, event.target.checked ? DONE : TO_DO, null);
    }

    startNote(event) {
        this.notingId = event.currentTarget.dataset.id;
        this.noteText = '';
    }
    handleNote(event) { this.noteText = event.target.value; }
    cancelNote() { this.notingId = undefined; }
    get noteMissing() { return this.actDisabled || !(this.noteText || '').trim(); }
    /** Busy, or disabled by the parent (a sandbox copy of the hub): tick, Not needed and Reopen are off. */
    get actDisabled() { return this.busy || this.disabled; }

    async saveNote() {
        const ok = await this.mark(this.notingId, NOT_NEEDED, this.noteText.trim());
        if (ok) {
            this.notingId = undefined;
        }
    }

    reopen(event) {
        this.mark(event.currentTarget.dataset.id, TO_DO, null);
    }

    mark(runId, status, note) {
        return this.call(markRun, { runJson: JSON.stringify({ runId, status, note, releaseId: this.releaseId }) });
    }

    // ---------- the steps themselves (add, edit, reorder) ----------

    /** A release's own steps can be edited; the ones a promotion carries belong to their release. */
    isOwn(step) {
        return this.draft || !step.fromRelease || !this.releaseName || step.fromRelease === this.releaseName;
    }

    /** The steps listed under the checklist: the release's own when they can be edited, else all of them. */
    get ownSteps() {
        return [...this.definitions].filter((s) => !this.canEdit || this.isOwn(s))
            .sort((a, b) => (Number(a.sequence) || 0) - (Number(b.sequence) || 0));
    }

    get showDefinitions() { return this.draft || this.canEdit || (!this.hasOrgs && this.definitions.length > 0); }
    get definitionsTitle() { return this.hasOrgs ? 'Steps in this release' : ''; }
    get stepRows() {
        const own = this.ownSteps;
        const edit = this.canEdit && !this.busy;
        return own.map((s, i) => {
            const key = this.draft ? s.key : s.id;
            return {
                key,
                no: i + 1,
                title: s.title,
                timingLabel: labelOf(TIMINGS, s.timing),
                timingCls: timingCls(s.timing),
                categoryLabel: labelOf(CATEGORIES, s.category),
                whereText: whereText(s),
                canEdit: this.canEdit,
                upDisabled: !edit || i === 0,
                downDisabled: !edit || i === own.length - 1,
                editDisabled: !edit,
                upLabel: 'Move up: ' + s.title,
                downLabel: 'Move down: ' + s.title,
                editLabel: 'Edit: ' + s.title,
                deleteLabel: 'Delete: ' + s.title
            };
        });
    }
    get hasStepRows() { return this.ownSteps.length > 0; }
    get canAdd() { return this.canEdit && !this.formOpen && this.ownSteps.length < MAX_STEPS; }
    get addDisabled() { return this.busy || this.disabled; }

    get categoryOptions() { return CATEGORIES; }
    get timingOptions() { return TIMINGS; }
    get scopeOptions() { return SCOPES; }
    get isPick() { return this.form.scopeMode === 'pick'; }
    get pickOptions() {
        const names = new Set([...(this.orgOptions || []), ...(this.routeNames || []), ...this.orgs.map((o) => o.orgName), ...this.form.scopeOrgs]);
        return [...names].filter((n) => n).map((n) => ({ value: n, label: n }));
    }
    get formTitle() { return this.form.id || this.form.key ? 'Edit the manual step' : 'Add a manual step'; }
    get formSaveLabel() { return this.form.id || this.form.key ? 'Save step' : 'Add step'; }
    get formCantSave() {
        const f = this.form;
        return this.busy || !(f.title || '').trim() || (f.title || '').trim().length > MAX_TITLE || (f.scopeMode === 'pick' && f.scopeOrgs.length === 0);
    }

    openForm() {
        this.form = blankForm();
        this.formError = undefined;
        this.formOpen = true;
    }

    editStep(event) {
        const key = event.currentTarget.dataset.key;
        const s = this.ownSteps.find((x) => (this.draft ? x.key : x.id) === key);
        if (!s) {
            return;
        }
        const names = scopeNames(s.orgScope);
        this.form = {
            id: this.draft ? null : s.id,
            key: this.draft ? s.key : null,
            title: s.title || '',
            category: s.category || 'Permissions',
            timing: s.timing || 'After_Deploy',
            instructions: s.instructions || '',
            backPromote: s.backPromote !== false,
            scopeMode: names.length ? 'pick' : 'all',
            scopeOrgs: names
        };
        this.formError = undefined;
        this.formOpen = true;
        this.loadRoute();
    }

    cancelForm() {
        this.formOpen = false;
        this.formError = undefined;
    }

    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' || event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.form = { ...this.form, [field]: value };
        if (field === 'scopeMode' && value === 'pick') {
            this.loadRoute();
        }
    }

    handleText(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
    }

    /** The route's orgs for Pick orgs, read once when a release (not New Release) needs them. */
    async loadRoute() {
        if (this.routeNames || (this.orgOptions && this.orgOptions.length)) {
            return;
        }
        try {
            const start = await getStart();
            this.routeNames = ((start && start.routeStops) || []).map((o) => o.Name);
        } catch {
            this.routeNames = [];
        }
    }

    formInput(sequence) {
        const f = this.form;
        return {
            title: f.title.trim(),
            instructions: f.instructions || '',
            category: f.category,
            timing: f.timing,
            sequence,
            backPromote: !!f.backPromote,
            orgScope: f.scopeMode === 'pick' ? f.scopeOrgs.join(',') : ''
        };
    }

    async saveForm() {
        if (this.formCantSave) {
            return;
        }
        const own = this.ownSteps;
        if (this.draft) {
            if (this.form.key) {
                this.drafts = this.drafts.map((s) => (s.key === this.form.key ? { ...this.formInput(s.sequence), key: s.key } : s));
            } else {
                this.drafts = [...this.drafts, { ...this.formInput(own.length + 1), key: 'd' + this.nextKey++ }];
            }
            this.formOpen = false;
            this.emitDrafts();
            return;
        }
        const existing = own.find((s) => s.id === this.form.id);
        const sequence = existing ? existing.sequence : own.reduce((m, s) => Math.max(m, Number(s.sequence) || 0), 0) + 1;
        const step = { ...this.formInput(sequence), id: this.form.id, releaseId: this._releaseId };
        if (await this.call(saveStep, { stepJson: JSON.stringify(step) })) {
            this.formOpen = false;
        } else {
            this.formError = this.error;
            this.error = undefined;
        }
    }

    async removeStep(event) {
        const key = event.currentTarget.dataset.key;
        if (this.draft) {
            this.drafts = this.drafts.filter((s) => s.key !== key).map((s, i) => ({ ...s, sequence: i + 1 }));
            this.emitDrafts();
            return;
        }
        await this.call(deleteStep, { stepId: key });
    }

    moveUp(event) { this.move(event.currentTarget.dataset.key, -1); }
    moveDown(event) { this.move(event.currentTarget.dataset.key, 1); }

    /** Swaps a step with its neighbour (Sequence__c), so the deployment team does them in the new order. */
    async move(key, by) {
        const own = this.ownSteps;
        const at = own.findIndex((s) => (this.draft ? s.key : s.id) === key);
        const other = own[at + by];
        if (at < 0 || !other) {
            return;
        }
        if (this.draft) {
            const next = [...own];
            next[at] = other;
            next[at + by] = own[at];
            this.drafts = next.map((s, i) => ({ ...s, sequence: i + 1 }));
            this.emitDrafts();
            return;
        }
        const a = own[at];
        const seqA = Number(a.sequence) || at + 1;
        const seqB = Number(other.sequence) || at + by + 1;
        const ok = await this.call(saveStep, { stepJson: JSON.stringify({ ...this.stepInput(a), sequence: seqB }) });
        if (ok) {
            await this.call(saveStep, { stepJson: JSON.stringify({ ...this.stepInput(other), sequence: seqA }) });
        }
    }

    stepInput(s) {
        return {
            id: s.id, releaseId: this._releaseId, title: s.title, instructions: s.instructions, category: s.category,
            timing: s.timing, sequence: s.sequence, backPromote: s.backPromote, orgScope: s.orgScope || ''
        };
    }

    /** New Release: the steps as RaiseRequest.manualSteps (StepInput), in order. */
    emitDrafts() {
        const steps = this.drafts.map((s, i) => ({
            title: s.title, instructions: s.instructions, category: s.category, timing: s.timing,
            sequence: i + 1, backPromote: s.backPromote, orgScope: s.orgScope
        }));
        this._emitted = steps;
        this.dispatchEvent(new CustomEvent('stepschange', { detail: { steps } }));
    }

}
