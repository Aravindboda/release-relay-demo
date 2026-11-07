import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import board from '@salesforce/apex/RlyWorkItemsController.board';
import syncRecent from '@salesforce/apex/RlyWorkItemsController.syncRecent';
import { searchTerm, matchesSearch } from 'c/rlyListSearch';

/** Modes of RlyHubGuard.getHubStatus in which the tab shows only the org gate. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];
const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'inprogress', label: 'In progress' },
    { value: 'inprod', label: 'In production' },
    { value: 'blocked', label: 'Blocked' }
];
const TONE_PILL = { ok: 'rr-pill rr-pill-ok', run: 'rr-pill rr-pill-run', wait: 'rr-pill rr-pill-warn', bad: 'rr-pill rr-pill-bad', none: 'rr-pill rr-pill-none' };
const KIND_PILL = { Jira: 'rr-pill rr-pill-run', 'Azure Boards': 'rr-pill rr-pill-run', ServiceNow: 'rr-pill rr-pill-vio' };
/** The Tracker filter's values for every tracker and for tickets without one. */
const ALL_TRACKERS = '__all';
const UNTRACKED = '__none';
const TONE_DOT = { ok: 'rr-dot rr-dot-ok', run: 'rr-dot rr-dot-run', wait: 'rr-dot rr-dot-warn', bad: 'rr-dot rr-dot-bad', none: 'rr-dot' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * Work items tab (build 40): one row per ticket, where it is on the route (a cell per stage and production) and its
 * status, worked out from the releases that carry it; how the tracker updates went. Search, filter, Sync now.
 * Build 47: each ticket's own tracker (column and filter).
 */
export default class RlyWorkItems extends NavigationMixin(LightningElement) {
    appName = APP_NAME;
    hubStatus;
    statusRead = false;
    data;
    loading = false;
    syncing = false;
    error;
    notice;
    term = '';
    filter = 'all';
    trackerFilter = ALL_TRACKERS;

    connectedCallback() {
        getHubStatus()
            .then((s) => { this.hubStatus = s; })
            .catch(() => { this.hubStatus = undefined; })
            .finally(() => {
                this.statusRead = true;
                if (!this.gated) {
                    this.load();
                }
            });
    }

    get gated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    get showPage() { return this.statusRead && !this.gated; }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.data = await board();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
    }

    async syncNow() {
        this.syncing = true;
        this.notice = undefined;
        try {
            const n = await syncRecent();
            this.notice = n === 0 ? 'Every ticket is up to date.' : n + (n === 1 ? ' ticket updated.' : ' tickets updated.');
            await this.load();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.syncing = false;
        }
    }

    get trackerLabel() { return this.data ? this.data.trackerLabel : ''; }
    get orgs() { return this.data ? this.data.orgs.map((o) => ({ key: o, label: o })) : []; }
    get filters() {
        return FILTERS.map((f) => ({ ...f, cls: 'rr-seg' + (f.value === this.filter ? ' rr-seg-on' : ''), pressed: f.value === this.filter ? 'true' : 'false' }));
    }
    get allRows() {
        return (this.data ? this.data.tickets : []).map((t) => ({
            ...t,
            pillCls: TONE_PILL[t.tone] || TONE_PILL.none,
            syncCls: TONE_PILL[t.syncTone] || TONE_PILL.none,
            kindCls: KIND_PILL[t.trackerType] || TONE_PILL.none,
            releaseRefs: t.releases.map((r) => ({ ...r, label: r.name + (r.kind ? ' (' + r.kind + ')' : '') })),
            cellRows: t.cells.map((c) => ({ ...c, key: t.ticket + c.org, dotCls: TONE_DOT[c.tone] || TONE_DOT.none, textCls: 'rr-cell rr-cell-' + c.tone })),
            raisedText: t.raisedOn ? new Date(t.raisedOn).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) : ''
        }));
    }
    get rows() {
        return this.allRows.filter((r) => (this.filter === 'all' || r.bucket === this.filter) && this.trackerMatches(r)
            && matchesSearch([r.searchText], this.term));
    }
    trackerMatches(r) {
        if (this.trackerFilter === ALL_TRACKERS) {
            return true;
        }
        return this.trackerFilter === UNTRACKED ? !r.tracker : r.tracker === this.trackerFilter;
    }
    get trackerOptions() {
        const names = this.data && this.data.trackers ? this.data.trackers : [];
        return [{ value: ALL_TRACKERS, label: 'All trackers' }, ...names.map((n) => ({ value: n, label: n })), { value: UNTRACKED, label: 'Untracked' }];
    }
    get noRows() { return this.rows.length === 0; }
    get emptyText() {
        if (!this.data || this.data.tickets.length === 0) {
            return 'No tickets yet. Add them when raising a release (New Release → Review → Work items) or on the release page (Add tickets).';
        }
        return 'No tickets match.';
    }
    get shown() { return this.rows.length; }
    get total() { return this.allRows.length; }
    get truncated() { return !!this.data && this.data.truncated; }

    handleSearch(event) { this.term = searchTerm(event.detail && event.detail.value); }
    handleFilter(event) { this.filter = event.currentTarget.dataset.value; }
    handleTrackerFilter(event) { this.trackerFilter = event.detail.value; }

    openRelease(event) {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.id, actionName: 'view' } });
    }
}
