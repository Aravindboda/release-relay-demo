import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import listReleases from '@salesforce/apex/RlyReleasesController.listReleases';
import listReleasesFor from '@salesforce/apex/RlyReleasesController.listReleasesFor';
import countReleases from '@salesforce/apex/RlyReleasesController.countReleases';
import refreshRelease from '@salesforce/apex/RlyReleasesController.refreshRelease';
import exportCsv from '@salesforce/apex/RlyEvidenceController.exportCsv';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';

/** Modes of RlyHubGuard.getHubStatus in which the tab shows only the org gate. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];

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
    { id: 'checks', label: 'Checks failed', title: 'The code scan or the check-only deploy failed, or there are merge conflicts to resolve' },
    { id: 'deployed', label: 'Deployed', title: 'Deployed to the target org' },
    { id: 'rolledback', label: 'Rolled back', title: 'Rolled back in an org from its snapshot (Git is not changed)' },
    { id: 'failed', label: 'Failed', title: 'The run or the deploy failed' },
    { id: 'closed', label: 'Rejected', title: 'Rejected or closed without deploying' },
    { id: 'all', label: 'All', title: 'Every status' }
];
const EMPTY_STATE = {
    open: 'No open releases',
    checks: 'No releases with failed checks',
    deployed: 'No deployed releases',
    rolledback: 'No rolled back releases',
    failed: 'No failed releases',
    closed: 'No rejected or closed releases',
    all: 'No releases'
};
/**
 * Page state c__filter (from the Home tab's tiles, or a shared link) → the Releases tab's chip. "mine" is the open chip
 * with Raised by = you; any other value lists everyone's releases. Unknown values keep the default chip.
 */
const PAGE_FILTERS = {
    open: 'open', mine: 'open', checks: 'checks', checksfailed: 'checks', failed: 'failed', deployed: 'deployed',
    rolledback: 'rolledback', rejected: 'closed', closed: 'closed', all: 'all'
};
/** The server lists at most this many releases per chip (RlyReleaseQuery); the search narrows the loaded ones. */
const SERVER_ROWS = 200;
/** At most this many running releases are read per check, the least recently checked first. */
const PER_CYCLE = 5;
/** The list checks again every 60 s (while the tab is visible), and only reads running releases checked longer ago. */
const CHECK_SECONDS = 60;
const TIME = { hour: 'numeric', minute: '2-digit', second: '2-digit' };
const TAB = 'RLY_My_Releases';
const TYPE_LABEL = { Promotion: 'Promotion', Back_Promote: 'Back promote' };
const NEW_RELEASE_TAB = 'RLY_New_Release';
/** Row.rollbackStatus (RLY_Release__c.Rollback_Status__c): what the list shows (board HubRollbackValuesGates 3). */
const ROLLBACK_SHOWN = { Rolled_Back: { status: 'Rolled back', tone: 'wait' }, Running: { status: 'Rolling back', tone: 'run' } };

/** The list's pill text and tone: "Rolled back" (the org is in the meta line), "Rolling back", else the status. */
function shownStatus(r) {
    const rb = r && ROLLBACK_SHOWN[r.rollbackStatus];
    return rb ? rb : { status: r ? r.status : '', tone: tone(r ? r.status : '') };
}

/** "rolled back in PROD by Ana Admin", for the meta line. */
function rollbackMeta(r) {
    if (r.rollbackStatus !== 'Rolled_Back') {
        return '';
    }
    return 'rolled back in ' + (r.rolledBackIn || 'an org') + (r.rolledBackBy ? ' by ' + r.rolledBackBy : '');
}

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
/** A release with only manual steps has no Git or pipeline steps: only these segments show. */
const MANUAL_ONLY_STEPS = ['Raised', 'Approval', 'Deploy'];

function rowSteps(r) {
    const steps = stepStates(r);
    return r.manualOnly === true ? steps.filter((st) => MANUAL_ONLY_STEPS.includes(st.label)) : steps;
}

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
    const before = Date.now() - CHECK_SECONDS * 1000;
    return rows.filter((r) => RUNNING.includes(r.status) && r.id !== skipId && stamp(r) < before)
        .sort((a, b) => stamp(a) - stamp(b))
        .slice(0, PER_CYCLE);
}

export default class RlyReleaseTracker extends NavigationMixin(LightningElement) {
    /**
     * RlyHubGuard.getHubStatus: the org's mode (hub, setup, sandbox, copy). In a sandbox, a sandbox copy of the hub or a
     * production org not set up yet this tab shows only rlyOrgGate, and nothing else is loaded.
     */
    hubStatus;
    /** The status has been read, or failed to read (then the tab works as on the hub: the server refuses actions anyway). */
    statusRead = false;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    get gated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    get showPage() { return this.statusRead && !this.gated; }

    /** Reads the hub status once, then loads the page only on the hub. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            })
            .finally(() => {
                this.statusRead = true;
                if (!this.gated) {
                    this.loadPage();
                }
            });
    }

    /** mine (Releases tab) or approvals (Approvals tab). */
    @api view = 'mine';
    rows = [];
    /** Approvals: all or mine. Releases: open, deployed, failed, closed or all (sent to the server). */
    filter;
    /** The search box's text, normalised: narrows the loaded rows as you type (client-side). */
    search = '';
    /** Releases tab: who raised the releases (the current user by default; cleared: everyone). */
    raisedById = USER_ID;
    counts = {};
    selectedId;
    wide = false;
    loading = false;
    loaded = false;
    error;
    /** Each load gets a number; an answer to an older load is ignored. */
    loadSeq = 0;
    // live check (Releases tab): a CSS countdown, as on the release page, then a check
    cycle = 0;
    nextAt;
    checking = false;
    lastChecked;
    /** The tab was hidden when a check was due: it checks as soon as the tab is visible again. */
    paused = false;
    /** The visibilitychange listener, kept so it can be removed. */
    visibilityHandler;

    /** A link such as /lightning/n/RLY_My_Releases?c__release=<Id> (from Slack) opens with that release selected. */
    @wire(CurrentPageReference)
    setPageReference(ref) {
        const state = (ref && ref.state) || {};
        const releaseId = state.c__release;
        if (releaseId) {
            this.selectedId = releaseId;
        }
        const pageFilter = state.c__filter ? String(state.c__filter).toLowerCase() : '';
        if (pageFilter && pageFilter !== this.pageFilter) {
            this.pageFilter = pageFilter;
            this.applyPageFilter(pageFilter);
        }
    }

    /** The c__filter last applied, so the same link doesn't reset a chip picked since. */
    pageFilter;

    /**
     * Picks the chip a link asks for (c__filter). Releases: open, mine, checks, failed, deployed, rolledback, rejected or all;
     * Approvals: mine or all. Reloads when the list is already showing.
     * @param {string} pageFilter the c__filter value, lower case
     */
    applyPageFilter(pageFilter) {
        if (this.isApprovals) {
            this.filter = pageFilter === 'mine' ? 'mine' : 'all';
            return;
        }
        const chipId = PAGE_FILTERS[pageFilter];
        if (!chipId) {
            return;
        }
        this.filter = chipId;
        this.raisedById = pageFilter === 'mine' ? USER_ID : null;
        if (this.statusRead && !this.gated) {
            this.load();
        }
    }

    connectedCallback() {
        if (!this.filter) {
            this.filter = this.isApprovals ? 'all' : 'open';
        }
        this.visibilityHandler = () => this.handleVisibility();
        document.addEventListener('visibilitychange', this.visibilityHandler);
        this.readHubStatus();
    }

    /** The release list and its live check (on the hub only). */
    loadPage() {
        this.load().then(() => this.firstCheck());
    }

    disconnectedCallback() {
        this.stop();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
    }

    /** Hidden tab: no checks (the countdown stops). Visible again: checks straight away, then counts down as before. */
    handleVisibility() {
        if (document.hidden) {
            if (this.nextAt) {
                this.stop();
                this.paused = true;
            }
        } else if (this.paused) {
            this.paused = false;
            this.checkNow();
        }
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
        if (this.isReleases) {
            this.schedule();
        }
    }

    async fetchApprovals() {
        return { rows: await listReleases({ view: 'approvals' }) };
    }

    /** The list and the chip counts for the current Raised by, state and search, filtered on the server. */
    async fetchReleases() {
        const filterJson = this.filterJson;
        const [rows, counts] = await Promise.all([
            listReleasesFor({ filterJson }),
            countReleases({ raisedById: this.raisedById || null })
        ]);
        return { rows, counts };
    }

    /** build 13's listReleasesFor filter: Raised by and state chip (the search box filters the loaded rows on the page). */
    get filterJson() {
        return JSON.stringify({ raisedById: this.raisedById || null, state: this.filter, searchText: null });
    }

    /** Export CSV: the same filter plus the search text (the server matches it on the release number or title). */
    get exportJson() {
        return JSON.stringify({ raisedById: this.raisedById || null, state: this.filter, searchText: this.search || null });
    }

    // ---------- Export CSV (board HubApprovalFlowsEvidence 4) ----------

    exporting = false;
    /** The last export as a data: URL for the <a download> link, and its file name. */
    csvHref;
    csvName;
    clickCsv = false;

    get exportLabel() { return this.exporting ? 'Exporting…' : 'Export CSV'; }

    /** RlyEvidenceController.exportCsv: the releases matching the filters as CSV text, downloaded as a file. */
    async exportReleases() {
        this.exporting = true;
        try {
            const csv = await exportCsv({ filterJson: this.exportJson });
            const today = new Date();
            const pad = (n) => String(n).padStart(2, '0');
            this.csvName = 'releases-' + today.getFullYear() + '-' + pad(today.getMonth() + 1) + '-' + pad(today.getDate()) + '.csv';
            this.csvHref = 'data:text/csv;charset=utf-8,' + encodeURIComponent('\uFEFF' + (csv || ''));
            this.clickCsv = true;
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Export CSV', message: errorText(e), variant: 'error' }));
        } finally {
            this.exporting = false;
        }
    }

    /** Starts the download once the link is drawn; the link stays, in case the browser asks first. */
    renderedCallback() {
        if (!this.clickCsv) {
            return;
        }
        const link = this.template.querySelector('a.rr-csv');
        if (link) {
            this.clickCsv = false;
            link.click();
        }
    }

    /**
     * Releases tab, first load: shows the saved statuses, and reads straight away only the running releases nobody
     * checked in the last 60 s. Approvals reads records only (no Git calls); the release opened beside the list keeps
     * its own checks.
     */
    firstCheck() {
        if (this.isReleases && dueForCheck(this.rows, this.selectedId).length) {
            this.checkNow();
        }
    }

    // ---------- live check (Releases tab) ----------

    /** Counts down to the next check while the list shows an open release and the tab is visible; stops otherwise. */
    schedule() {
        if (this.checking || !this.rows.some((r) => OPEN.includes(r.status))) {
            this.stop();
        } else if (document.hidden) {
            this.stop();
            this.paused = true;
        } else {
            this.startCountdown();
        }
    }

    /** Stops the countdown: the bar is removed, so its animation can't end and trigger a check. */
    stop() {
        this.nextAt = undefined;
    }

    /**
     * Starts the next countdown. The bar is a CSS animation of CHECK_SECONDS (no JavaScript timers);
     * when it ends, handleCountdownEnd checks again.
     */
    startCountdown() {
        this.cycle += 1;
        this.nextAt = new Date(Date.now() + CHECK_SECONDS * 1000);
    }

    handleCountdownEnd() {
        if (!this.nextAt) {
            return;
        }
        if (document.hidden) {
            this.stop();
            this.paused = true;
        } else {
            this.checkNow();
        }
    }

    /**
     * Reads the latest status of up to PER_CYCLE running releases not checked in the last CHECK_SECONDS (in turn, least
     * recently checked first), then reloads the list with the statuses as saved (other viewers' checks included).
     */
    async checkNow() {
        if (this.checking) {
            return;
        }
        this.stop();
        this.paused = false;
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

    /** rlySearchBox: filters the loaded rows as you type. */
    handleSearch(event) {
        this.search = searchTerm(event.detail && event.detail.value);
    }

    /** "Clear search" in the empty list. */
    clearSearch() {
        const box = this.template.querySelector('c-rly-search-box');
        if (box) {
            box.clear();
        }
        this.search = '';
    }

    get searchLabel() {
        return this.isApprovals ? 'Search approvals' : 'Search releases';
    }

    get searchPlaceholder() {
        return 'Search by release, title, org or person';
    }

    /** The rows under the chip, before the search box. */
    get chipRows() {
        if (this.isReleases) {
            return this.rows;
        }
        const list = this.rows.filter((r) => this.matches(r, this.filter));
        // Approvals: hotfixes first (the server sends them first; a sort keeps it so after a status change).
        return [...list].sort((a, b) => Number(!!b.isHotfix) - Number(!!a.isHotfix));
    }

    get shown() {
        const q = this.search;
        return this.chipRows.filter((r) => matchesSearch([r.name, r.title, r.source, r.target, r.raisedBy, r.status, r.hotfixReason], q));
    }

    get shownCount() { return this.shown.length; }
    get totalCount() { return this.chipRows.length; }

    /** The server sent its maximum: older releases are under another chip or Raised by, or in the CSV. */
    get atServerMax() {
        return this.isReleases && this.rows.length >= SERVER_ROWS;
    }
    get serverMaxText() {
        return 'Showing the newest ' + SERVER_ROWS + '. Pick a person in Raised by or another chip to see older releases.';
    }

    get isSearchEmpty() {
        return this.isEmpty && !!this.search && this.chipRows.length > 0;
    }
    get searchEmptyText() {
        return 'No releases match \u2018' + this.search + '\u2019.';
    }
    get isPlainEmpty() {
        return this.isEmpty && !this.isSearchEmpty;
    }

    // ---------- list ----------
    get cards() {
        return this.shown.map((r) => {
            const steps = rowSteps(r);
            const p = position(r);
            const on = r.id === this.selectedId;
            const count = r.components || 0;
            const isHotfix = r.isHotfix === true;
            const carried = Array.isArray(r.carried) ? r.carried : [];
            const deletions = Number(r.deletionCount) || 0;
            const manual = Number(r.manualOpen) || 0;
            const manualOnly = r.manualOnly === true;
            const meta = [manualOnly ? '' : count + (count === 1 ? ' component' : ' components')
                + (deletions ? ' · ' + deletions + (deletions === 1 ? ' deletion' : ' deletions') : ''),
                this.isMine(r) ? 'You' : r.raisedBy, rollbackMeta(r)].filter((x) => x);
            const shown = shownStatus(r);
            const rolledBack = r.rollbackStatus === 'Rolled_Back';
            if (rolledBack && steps.length) {
                steps[steps.length - 1] = { ...steps[steps.length - 1], cls: 'rr-seg rr-seg-rb' };
            }
            return {
                id: r.id,
                name: r.name,
                title: r.title,
                nameParts: highlightParts(r.name, this.search),
                titleParts: highlightParts(r.title, this.search),
                isHotfix,
                manualOnly,
                hotfixReason: isHotfix ? r.hotfixReason : '',
                deletesText: this.isApprovals && deletions ? 'Deletes ' + deletions : '',
                manualText: manual ? manual + (manual === 1 ? ' manual step' : ' manual steps') : '',
                typeLabel: TYPE_LABEL[r.releaseType] || '',
                carriesText: r.releaseType === 'Promotion' && carried.length ? 'Carries ' + carried.join(', ') : '',
                status: shown.status,
                pillCls: 'rr-pill rr-pill-' + shown.tone,
                rollbackFailed: r.rollbackStatus === 'Failed',
                when: relative(rolledBack && r.rolledBackOn ? r.rolledBackOn : r.raisedOn),
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
            return 'No releases match this filter.';
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
        const hint = this.filter === 'open' ? ' Deployed, failed and rejected releases are under their chips.' : '';
        return EMPTY_STATE[this.filter] + who + '.' + hint;
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
        return this.selected ? shownStatus(this.selected).status : '';
    }
    get selectedPillCls() {
        return 'rr-pill rr-pill-' + (this.selected ? shownStatus(this.selected).tone : tone(''));
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

    /** A rollback of the selected release started or ended: the rows (pill, chip counts) are read again. */
    handleRollbackChanged() {
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
