import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listReleases from '@salesforce/apex/RlyReleasesController.listReleases';
import refreshRelease from '@salesforce/apex/RlyReleasesController.refreshRelease';

const APPROVAL = ['Ready for approval'];
const DONE = ['Deployed'];
const BAD = ['Checks failed', 'Deploy failed', 'Failed', 'Rejected'];
const RUNNING = ['Retrieving', 'Workflow running', 'Validating', 'Deploying'];
const SCAN_BAD = ['Failed', 'Error'];
const STEPS = ['Raised', 'Pull request', 'Scan', 'Validate', 'Approval', 'Merge', 'Deploy'];
const FAILED_STEP = ['Raise', 'Pull request', 'Code scan', 'Validation', 'Approval', 'Merge', 'Deploy'];
const CHIPS = [
    { id: 'all', label: 'All' },
    { id: 'mine', label: 'Mine' },
    { id: 'approval', label: 'Awaiting approval' },
    { id: 'progress', label: 'In progress' },
    { id: 'failed', label: 'Failed' },
    { id: 'deployed', label: 'Deployed' }
];
const APPROVAL_CHIPS = ['all', 'mine'];
const TAB = 'RLY_My_Releases';
const NEW_RELEASE_TAB = 'RLY_New_Release';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/** The status pill's tone, as on the board: running blue, deployed green, waiting amber, failed red. */
function tone(status) {
    if (DONE.includes(status)) {
        return 'ok';
    }
    if (APPROVAL.includes(status)) {
        return 'wait';
    }
    if (BAD.includes(status)) {
        return 'bad';
    }
    if (RUNNING.includes(status)) {
        return 'run';
    }
    return 'none';
}

/** Which chip a release counts under. */
function group(status) {
    if (APPROVAL.includes(status)) {
        return 'approval';
    }
    if (RUNNING.includes(status)) {
        return 'progress';
    }
    if (BAD.includes(status)) {
        return 'failed';
    }
    if (DONE.includes(status)) {
        return 'deployed';
    }
    return 'other';
}

/** Where the release is on Raised, Pull request, Scan, Validate, Approval, Merge, Deploy: the current step and the failed one (or -1). */
function position(r) {
    const s = r.status;
    const scanBad = SCAN_BAD.includes(r.scan);
    const scanDone = !!r.scan && r.scan !== 'Pending';
    switch (s) {
        case 'Deployed':
            return { at: STEPS.length, fail: -1 };
        case 'Deploying':
            return { at: 6, fail: -1 };
        case 'Deploy failed':
            return { at: 6, fail: 6 };
        case 'Ready for approval':
            return { at: 4, fail: -1 };
        case 'Rejected':
            return { at: 4, fail: 4 };
        case 'Checks failed':
            return scanBad ? { at: 2, fail: 2 } : { at: 3, fail: 3 };
        case 'Validating':
        case 'Workflow running':
            return { at: scanDone ? 3 : 2, fail: -1 };
        case 'Failed':
            return scanDone ? { at: 1, fail: 1 } : { at: 0, fail: 0 };
        default:
            return { at: 0, fail: -1 };
    }
}

function stepStates(r) {
    const p = position(r);
    return STEPS.map((label, i) => {
        let state = 'todo';
        if (p.fail === i) {
            state = 'fail';
        } else if (i < p.at) {
            state = 'done';
        } else if (i === p.at) {
            state = 'now';
        }
        return { label, state, key: label, cls: 'rr-seg rr-seg-' + state };
    });
}

const STATE_TEXT = { done: 'done', now: 'in progress', fail: 'failed', todo: 'not started' };

/** One line on why it failed, from what the list knows. The release page has the full detail. */
function failReason(r) {
    switch (r.status) {
        case 'Checks failed':
            return SCAN_BAD.includes(r.scan)
                ? 'The code scan found blocking issues. Open it to see the findings.'
                : 'The check-only deploy in the target org failed. Open it to see the errors.';
        case 'Rejected':
            return 'An approver rejected it. Open it to read the comment.';
        case 'Deploy failed':
            return 'Open it to see the deployment errors.';
        default:
            return 'Open it to see what went wrong.';
    }
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** 4 min ago, 1 h ago, Today, 6:12 PM, Yesterday, Oct 28. */
function relative(value) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    const now = new Date();
    const minutes = Math.floor((now.getTime() - d.getTime()) / 60000);
    if (minutes < 1) {
        return 'Just now';
    }
    if (minutes < 60) {
        return minutes + ' min ago';
    }
    if (minutes < 180) {
        return Math.floor(minutes / 60) + ' h ago';
    }
    if (sameDay(d, now)) {
        return 'Today, ' + d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    }
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    if (sameDay(d, yesterday)) {
        return 'Yesterday';
    }
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

export default class RlyReleaseTracker extends NavigationMixin(LightningElement) {
    /** mine (Releases tab) or approvals (Approvals tab). */
    @api view = 'mine';
    rows = [];
    mineIds = [];
    filter = 'all';
    search = '';
    selectedId;
    wide = false;
    loading = false;
    loaded = false;
    catchingUp = false;
    error;

    /** A link such as /lightning/n/RLY_My_Releases?c__release=<Id> (from Slack) opens with that release selected. */
    @wire(CurrentPageReference)
    setPageReference(ref) {
        const releaseId = ref && ref.state ? ref.state.c__release : undefined;
        if (releaseId) {
            this.selectedId = releaseId;
        }
    }

    connectedCallback() {
        this.load();
    }

    get isApprovals() {
        return this.view === 'approvals';
    }

    async load() {
        this.loading = true;
        try {
            const [rows, mine] = await Promise.all([
                listReleases({ view: this.isApprovals ? 'approvals' : 'all' }),
                listReleases({ view: 'mine' })
            ]);
            this.rows = rows || [];
            this.mineIds = (mine || []).map((r) => r.id);
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
            this.loaded = true;
        }
        if (!this.selectedId && this.shown.length) {
            this.selectedId = this.shown[0].id;
        }
        this.catchUp();
    }

    /** Reads the latest status of releases that are still running (one call each, in turn), then shows the list again. */
    async catchUp() {
        const open = this.rows.filter((r) => RUNNING.includes(r.status) && r.id !== this.selectedId).slice(0, 10);
        if (!open.length || this.catchingUp) {
            return;
        }
        this.catchingUp = true;
        try {
            await open.reduce((previous, r) => previous.then(() => refreshRelease({ releaseId: r.id })), Promise.resolve());
            this.rows = (await listReleases({ view: this.isApprovals ? 'approvals' : 'all' })) || [];
        } catch {
            // the list still shows the last known status
        } finally {
            this.catchingUp = false;
        }
    }

    // ---------- header ----------
    get heading() {
        return this.isApprovals ? 'Approvals' : 'My Releases';
    }
    get icon() {
        return this.isApprovals ? 'utility:approval' : 'utility:list';
    }
    get showNewRelease() {
        return !this.isApprovals;
    }

    newRelease() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: NEW_RELEASE_TAB } });
    }

    // ---------- filters ----------
    matches(r, id) {
        if (id === 'all') {
            return true;
        }
        if (id === 'mine') {
            return this.mineIds.includes(r.id);
        }
        return group(r.status) === id;
    }

    get chips() {
        const ids = this.isApprovals ? APPROVAL_CHIPS : CHIPS.map((c) => c.id);
        return CHIPS.filter((c) => ids.includes(c.id)).map((c) => {
            const on = c.id === this.filter;
            return {
                ...c,
                on: on ? 'true' : 'false',
                cls: on ? 'rr-chip rr-chip-on' : 'rr-chip',
                count: this.rows.filter((r) => this.matches(r, c.id)).length
            };
        });
    }

    pickChip(event) {
        this.filter = event.currentTarget.dataset.id;
    }

    handleSearch(event) {
        this.search = (event.target.value || '').trim().toLowerCase();
    }

    get shown() {
        const q = this.search;
        return this.rows.filter((r) => this.matches(r, this.filter))
            .filter((r) => !q || [r.name, r.title, r.source, r.target].some((v) => (v || '').toLowerCase().includes(q)));
    }

    // ---------- list ----------
    get cards() {
        return this.shown.map((r) => {
            const steps = stepStates(r);
            const p = position(r);
            const on = r.id === this.selectedId;
            const count = r.components || 0;
            const meta = [r.hotfix ? 'Hotfix' : null, count + (count === 1 ? ' component' : ' components'),
                this.mineIds.includes(r.id) ? 'You' : r.raisedBy].filter((x) => x);
            return {
                id: r.id,
                name: r.name,
                title: r.title,
                status: r.status,
                pillCls: 'rr-pill rr-pill-' + tone(r.status),
                when: relative(r.raisedOn),
                steps,
                pathLabel: 'Progress: ' + steps.map((s) => s.label + ' ' + STATE_TEXT[s.state]).join(', '),
                route: (r.source || '') + ' → ' + (r.target || ''),
                meta: meta.join(' · '),
                failed: p.fail >= 0,
                failStep: FAILED_STEP[p.fail] || '',
                failReason: failReason(r),
                cls: on ? 'rr-card rr-card-on' : 'rr-card',
                on: on ? 'true' : 'false'
            };
        });
    }

    get hasCards() {
        return this.shown.length > 0;
    }
    get isEmpty() {
        return this.loaded && !this.loading && this.shown.length === 0;
    }
    get emptyText() {
        if (this.rows.length) {
            return 'No releases match this filter.';
        }
        return this.isApprovals ? 'Nothing waiting for approval.' : 'No releases yet. Raise one on the New Release tab.';
    }

    pick(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    // ---------- detail pane ----------
    get hasSelection() {
        return !!this.selectedId;
    }
    get selected() {
        return this.rows.find((r) => r.id === this.selectedId);
    }
    get selectedName() {
        return this.selected ? this.selected.name : '';
    }
    get selectedStatus() {
        return this.selected ? this.selected.status : '';
    }
    get selectedPillCls() {
        return 'rr-pill rr-pill-' + tone(this.selectedStatus);
    }
    get showList() {
        return !this.wide;
    }
    get bodyCls() {
        return this.wide ? 'rr-body rr-body-wide' : 'rr-body';
    }
    get expandIcon() {
        return this.wide ? 'utility:contract_alt' : 'utility:expand_alt';
    }
    get expandLabel() {
        return this.wide ? 'Show the list' : 'Widen the detail';
    }

    toggleWide() {
        this.wide = !this.wide;
    }

    /** The release page tells us its latest status: show it on the card, and reload the list when it moved on. */
    handleChanged(event) {
        const status = event.detail;
        const row = this.selected;
        if (!row || !status || row.status === status) {
            return;
        }
        this.rows = this.rows.map((r) => (r.id === row.id ? { ...r, status } : r));
        this.load();
    }

    async copyLink() {
        try {
            const url = await this[NavigationMixin.GenerateUrl]({
                type: 'standard__navItemPage',
                attributes: { apiName: TAB },
                state: { c__release: this.selectedId }
            });
            const full = url && url.startsWith('/') ? window.location.origin + url : url;
            await navigator.clipboard.writeText(full);
            this.dispatchEvent(new ShowToastEvent({ title: 'Link copied', message: full, variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: "Couldn't copy the link", message: errorText(e), variant: 'error' }));
        }
    }
}
