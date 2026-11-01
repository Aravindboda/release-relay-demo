import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import listReleases from '@salesforce/apex/RlyReleasesController.listReleases';
import listReleasesFor from '@salesforce/apex/RlyReleasesController.listReleasesFor';
import countReleases from '@salesforce/apex/RlyReleasesController.countReleases';
import refreshRelease from '@salesforce/apex/RlyReleasesController.refreshRelease';

const APPROVAL = ['Ready for approval'];
const DONE = ['Deployed'];
const BAD = ['Checks failed', 'Deploy failed', 'Failed', 'Rejected'];
/** Something is running (RlyStatusReader.OPEN_STATUSES): the list reads these releases' latest status. */
const RUNNING = ['Submitted', 'Retrieving', 'Workflow running', 'Validating', 'Deploying'];
/** Still needs something (RlyReleaseQuery open state): running, or waiting for the developer or an approver. */
const OPEN = [...RUNNING, 'PR open', 'Checks failed', 'Ready for approval', 'Approved', 'Merging', 'Merged'];
const SCAN_BAD = ['Failed', 'Error'];
const STEPS = ['Raised', 'Pull request', 'Scan', 'Validate', 'Approval', 'Merge', 'Deploy'];
const FAILED_STEP = ['Raise', 'Pull request', 'Code scan', 'Validation', 'Approval', 'Merge', 'Deploy'];
/** Approvals tab chips, filtered on the page. */
const APPROVAL_CHIPS = [
    { id: 'all', label: 'All' },
    { id: 'mine', label: 'Mine' }
];
/** Releases tab chips: states filtered on the server (RlyReleaseQuery.STATE_STATUSES), open first and by default. */
const STATE_CHIPS = [
    { id: 'open', label: 'Open', title: 'Running, checks failed or waiting for approval' },
    { id: 'deployed', label: 'Deployed', title: 'Deployed to the target org' },
    { id: 'failed', label: 'Failed', title: 'The run or the deploy failed' },
    { id: 'closed', label: 'Rejected', title: 'Rejected or closed without deploying' },
    { id: 'all', label: 'All', title: 'Every status' }
];
const EMPTY_STATE = {
    open: 'No open releases',
    deployed: 'No deployed releases',
    failed: 'No failed releases',
    closed: 'No rejected or closed releases',
    all: 'No releases'
};
/** At most this many running releases are read per check, the least recently checked first. */
const PER_CYCLE = 5;
const TIME = { hour: 'numeric', minute: '2-digit', second: '2-digit' };
const TAB = 'RLY_My_Releases';
const TYPE_LABEL = { Promotion: 'Promotion', Back_Promote: 'Back promote' };
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

/** Running releases to read, the least recently checked first (never checked first), at most PER_CYCLE. */
function dueForCheck(rows, skipId) {
    const stamp = (r) => (r.lastChecked ? new Date(r.lastChecked).getTime() : 0);
    return rows.filter((r) => RUNNING.includes(r.status) && r.id !== skipId)
        .sort((a, b) => stamp(a) - stamp(b))
        .slice(0, PER_CYCLE);
}

export default class RlyReleaseTracker extends NavigationMixin(LightningElement) {
    /** mine (Releases tab) or approvals (Approvals tab). */
    @api view = 'mine';
    rows = [];
    /** Approvals: all or mine. Releases: open, deployed, failed, closed or all (sent to the server). */
    filter;
    /** What the search box shows (narrows the loaded rows as you type). */
    search = '';
    /** What the server last searched for (Enter or clearing the box sends it). */
    searchSent = '';
    /** Releases tab: who raised the releases (the current user by default; cleared: everyone). */
    raisedById = USER_ID;
    counts = {};
    selectedId;
    wide = false;
    loading = false;
    loaded = false;
    catchingUp = false;
    error;
    /** Each load gets a number; an answer to an older load is ignored. */
    loadSeq = 0;
    // live check (Releases tab): a CSS countdown, as on the release page, then a check
    cycle = 0;
    nextAt;
    checking = false;
    lastChecked;

    /** A link such as /lightning/n/RLY_My_Releases?c__release=<Id> (from Slack) opens with that release selected. */
    @wire(CurrentPageReference)
    setPageReference(ref) {
        const releaseId = ref && ref.state ? ref.state.c__release : undefined;
        if (releaseId) {
            this.selectedId = releaseId;
        }
    }

    connectedCallback() {
        this.filter = this.isApprovals ? 'all' : 'open';
        this.load().then(() => this.firstCheck());
    }

    disconnectedCallback() {
        this.stop();
    }

    get isApprovals() {
        return this.view === 'approvals';
    }
    get isReleases() {
        return !this.isApprovals;
    }

    async load() {
        const seq = ++this.loadSeq;
        this.loading = true;
        try {
            const result = this.isApprovals ? await this.fetchApprovals() : await this.fetchReleases();
            if (seq !== this.loadSeq) {
                return;
            }
            this.rows = result.rows || [];
            this.counts = result.counts || {};
            this.error = undefined;
            if (this.isReleases) {
                this.lastChecked = new Date();
            }
        } catch (e) {
            if (seq === this.loadSeq) {
                this.error = errorText(e);
            }
        } finally {
            if (seq === this.loadSeq) {
                this.loading = false;
                this.loaded = true;
            }
        }
        if (seq !== this.loadSeq) {
            return;
        }
        if (!this.selectedId && this.shown.length) {
            this.selectedId = this.shown[0].id;
        }
        if (this.isApprovals) {
            this.catchUpApprovals();
        } else {
            this.schedule();
        }
    }

    async fetchApprovals() {
        return { rows: await listReleases({ view: 'approvals' }) };
    }

    /** The list and the chip counts for the current Raised by, state and search, filtered on the server. */
    async fetchReleases() {
        const filterJson = JSON.stringify({ raisedById: this.raisedById || null, state: this.filter, searchText: this.searchSent });
        const [rows, counts] = await Promise.all([
            listReleasesFor({ filterJson }),
            countReleases({ raisedById: this.raisedById || null })
        ]);
        return { rows, counts };
    }

    /** Releases tab, first load: reads the latest status of running releases straight away instead of in 30 s. */
    firstCheck() {
        if (this.isReleases && dueForCheck(this.rows, this.selectedId).length) {
            this.checkNow();
        }
    }

    /** Approvals: reads the latest status of releases that are still running (one call each, in turn), then shows the list again. */
    async catchUpApprovals() {
        const open = this.rows.filter((r) => RUNNING.includes(r.status) && r.id !== this.selectedId).slice(0, 10);
        if (!open.length || this.catchingUp) {
            return;
        }
        this.catchingUp = true;
        try {
            await open.reduce((previous, r) => previous.then(() => refreshRelease({ releaseId: r.id })), Promise.resolve());
            this.rows = (await listReleases({ view: 'approvals' })) || [];
        } catch {
            // the list still shows the last known status
        } finally {
            this.catchingUp = false;
        }
    }

    // ---------- live check (Releases tab) ----------

    /** Counts down to the next check while the list shows an open release; stops otherwise. */
    schedule() {
        if (!this.checking && this.rows.some((r) => OPEN.includes(r.status))) {
            this.startCountdown();
        } else {
            this.stop();
        }
    }

    /** Stops the countdown: the bar is removed, so its animation can't end and trigger a check. */
    stop() {
        this.nextAt = undefined;
    }

    /**
     * Starts the next countdown. The bar is a CSS animation of 30 s (no JavaScript timers);
     * when it ends, handleCountdownEnd checks again.
     */
    startCountdown() {
        this.cycle += 1;
        this.nextAt = new Date(Date.now() + 30000);
    }

    handleCountdownEnd() {
        if (this.nextAt) {
            this.checkNow();
        }
    }

    /** Reads the latest status of up to PER_CYCLE running releases (in turn, least recently checked first), then reloads the list. */
    async checkNow() {
        if (this.checking) {
            return;
        }
        this.stop();
        this.checking = true;
        try {
            const due = dueForCheck(this.rows, this.selectedId);
            await due.reduce((previous, r) => previous.then(() => refreshRelease({ releaseId: r.id }).catch(() => null)), Promise.resolve());
        } finally {
            this.checking = false;
        }
        await this.load();
    }

    get syncedText() {
        if (this.checking) {
            return 'Checking now…';
        }
        const last = this.lastChecked ? 'Last checked ' + this.lastChecked.toLocaleTimeString([], TIME) : '';
        if (this.counting) {
            return last ? last + ' · next check in' : 'Next check in';
        }
        return last;
    }
    get counting() {
        return !!this.nextAt && !this.checking;
    }
    /** One key per countdown, so a fresh bar (and a fresh animation) is drawn each time. */
    get cycles() {
        return [{ key: 'c' + this.cycle }];
    }
    get showLive() {
        return this.isReleases && (this.counting || this.checking);
    }
    get checkDisabled() {
        return this.checking || this.loading;
    }

    // ---------- header ----------
    get heading() {
        if (this.isApprovals) {
            return 'Approvals';
        }
        return this.raisedById === USER_ID ? 'My Releases' : 'Releases';
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
    isMine(r) {
        return r.raisedById === USER_ID;
    }

    /** Approvals only: the chips filter the loaded rows. */
    matches(r, id) {
        return id !== 'mine' || this.isMine(r);
    }

    get chips() {
        if (this.isApprovals) {
            return APPROVAL_CHIPS.map((c) => this.chip(c, this.rows.filter((r) => this.matches(r, c.id)).length));
        }
        return STATE_CHIPS.map((c) => this.chip(c, this.counts[c.id] || 0));
    }

    chip(c, count) {
        const on = c.id === this.filter;
        return { ...c, on: on ? 'true' : 'false', cls: on ? 'rr-chip rr-chip-on' : 'rr-chip', count };
    }

    pickChip(event) {
        const id = event.currentTarget.dataset.id;
        if (id === this.filter) {
            return;
        }
        this.filter = id;
        if (this.isReleases) {
            this.load();
        }
    }

    /** Raised by: a user, or cleared for everyone. */
    handleRaisedBy(event) {
        this.raisedById = (event.detail && event.detail.recordId) || null;
        this.load();
    }

    handleSearch(event) {
        this.search = (event.target.value || '').trim().toLowerCase();
    }

    /** Enter or clearing the box: the Releases tab searches on the server. */
    handleSearchCommit(event) {
        this.search = (event.target.value || '').trim().toLowerCase();
        if (this.isReleases && this.search !== this.searchSent) {
            this.searchSent = this.search;
            this.load();
        }
    }

    get searchPlaceholder() {
        return this.isApprovals ? 'Search release number, title or org' : 'Search release number or title, then press Enter';
    }

    get shown() {
        const q = this.search;
        if (this.isReleases) {
            // The server filtered; the box narrows the loaded rows while you type.
            return this.rows.filter((r) => !q || [r.name, r.title].some((v) => (v || '').toLowerCase().includes(q)));
        }
        const list = this.rows.filter((r) => this.matches(r, this.filter))
            .filter((r) => !q || [r.name, r.title, r.source, r.target, r.hotfixReason].some((v) => (v || '').toLowerCase().includes(q)));
        // Approvals: hotfixes first (the server sends them first; a sort keeps it so after a status change).
        return [...list].sort((a, b) => Number(!!b.isHotfix) - Number(!!a.isHotfix));
    }

    // ---------- list ----------
    get cards() {
        return this.shown.map((r) => {
            const steps = stepStates(r);
            const p = position(r);
            const on = r.id === this.selectedId;
            const count = r.components || 0;
            const isHotfix = r.isHotfix === true;
            const carried = Array.isArray(r.carried) ? r.carried : [];
            const deletions = Number(r.deletionCount) || 0;
            const manual = Number(r.manualOpen) || 0;
            const meta = [count + (count === 1 ? ' component' : ' components')
                + (deletions ? ' · ' + deletions + (deletions === 1 ? ' deletion' : ' deletions') : ''),
                this.isMine(r) ? 'You' : r.raisedBy].filter((x) => x);
            return {
                id: r.id,
                name: r.name,
                title: r.title,
                isHotfix,
                hotfixReason: isHotfix ? r.hotfixReason : '',
                deletesText: this.isApprovals && deletions ? 'Deletes ' + deletions : '',
                manualText: manual ? manual + (manual === 1 ? ' manual step' : ' manual steps') : '',
                typeLabel: TYPE_LABEL[r.releaseType] || '',
                carriesText: r.releaseType === 'Promotion' && carried.length ? 'Carries ' + carried.join(', ') : '',
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
                cls: 'rr-card' + (on ? ' rr-card-on' : '') + (isHotfix ? ' rr-card-hot' : ''),
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
            return this.isApprovals ? 'No releases match this filter.' : 'No releases match this search.';
        }
        if (this.isApprovals) {
            return 'Nothing waiting for approval.';
        }
        let who = '';
        if (this.raisedById === USER_ID) {
            who = ' raised by you';
        } else if (this.raisedById) {
            who = ' raised by this user';
        }
        const searched = this.searchSent ? ' matching "' + this.searchSent + '"' : '';
        const hint = this.filter === 'open' ? ' Deployed, failed and rejected releases are under their chips.' : '';
        return EMPTY_STATE[this.filter] + who + searched + '.' + hint;
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
        if (!this.checking) {
            this.load();
        }
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
