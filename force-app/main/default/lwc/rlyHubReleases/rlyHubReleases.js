import { LightningElement, api } from 'lwc';
import listReleases from '@salesforce/apex/RlyReleasesController.listReleases';
import getRelease from '@salesforce/apex/RlyReleasesController.getRelease';

const GOOD = ['Deployed', 'Ready for approval'];
const BAD = ['Checks failed', 'Deploy failed', 'Failed', 'Rejected'];
const RUNNING = ['Retrieving', 'Workflow running', 'Validating', 'Deploying'];
const VIEWS = [
    { label: 'My releases', value: 'mine' },
    { label: 'All releases', value: 'all' }
];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function pill(status) {
    if (GOOD.includes(status)) {
        return 'rr-pill rr-pill-ok';
    }
    if (BAD.includes(status)) {
        return 'rr-pill rr-pill-bad';
    }
    if (RUNNING.includes(status)) {
        return 'rr-pill rr-pill-wait';
    }
    return 'rr-pill rr-pill-none';
}

export default class RlyHubReleases extends LightningElement {
    /** mine (Releases tab) or approvals (Approvals tab). */
    @api view = 'mine';
    current;
    rows = [];
    selectedId;
    loading = false;
    catchingUp = false;
    error;

    connectedCallback() {
        this.current = this.view === 'approvals' ? 'approvals' : 'mine';
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.rows = await listReleases({ view: this.current });
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
        this.catchUp();
    }

    /** Reads the latest status of releases that are still running (one call each), then shows the list again. */
    async catchUp() {
        const open = this.rows.filter((r) => RUNNING.includes(r.status)).slice(0, 10);
        if (!open.length || this.catchingUp) {
            return;
        }
        this.catchingUp = true;
        try {
            for (const r of open) {
                // eslint-disable-next-line no-await-in-loop
                await getRelease({ releaseId: r.id, refresh: true });
            }
            this.rows = await listReleases({ view: this.current });
        } catch (e) {
            // the list still shows the last known status
        } finally {
            this.catchingUp = false;
        }
    }

    get isApprovals() { return this.view === 'approvals'; }
    get heading() { return this.isApprovals ? 'Approvals' : 'Releases'; }
    get intro() {
        return this.isApprovals
            ? 'Releases whose checks finished. Approve to merge and deploy, bypass a blocking code scan, or reject with a comment.'
            : 'Every release raised from a developer org, and where it is now.';
    }
    get viewButtons() {
        return VIEWS.map((v) => ({ ...v, cls: 'rr-seg' + (v.value === this.current ? ' rr-seg-on' : ''), pressed: v.value === this.current ? 'true' : 'false' }));
    }

    handleView(event) {
        this.current = event.currentTarget.dataset.value;
        this.load();
    }

    get tableRows() {
        return this.rows.map((r) => ({
            ...r,
            statusCls: pill(r.status),
            when: r.raisedOn ? new Date(r.raisedOn).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '',
            openLabel: 'Open ' + r.name
        }));
    }
    get isEmpty() { return !this.loading && this.rows.length === 0; }
    get emptyText() {
        return this.isApprovals ? 'Nothing waiting for approval.' : 'No releases yet. Raise one on the New Release tab.';
    }

    open(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    back() {
        this.selectedId = undefined;
        this.load();
    }

    get showDetail() { return !!this.selectedId; }
    get notApprovals() { return !this.isApprovals; }
    get icon() { return this.isApprovals ? 'utility:approval' : 'utility:list'; }
}
