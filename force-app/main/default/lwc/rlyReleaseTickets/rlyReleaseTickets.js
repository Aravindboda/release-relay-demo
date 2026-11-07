import { LightningElement, api } from 'lwc';
import syncRelease from '@salesforce/apex/RlyWorkItemsController.syncRelease';
import setReleaseTickets from '@salesforce/apex/RlyWorkItemsController.setReleaseTickets';

const STATUS_PILL = { Posted: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Tracked here': 'rr-pill rr-pill-none' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * A release's tickets (build 40). Each time the release's status changes it asks the hub to post the new moment to the
 * tickets (RlyWorkItemsController.syncRelease: callouts, then one save) and shows what was posted; Try again posts
 * again; Edit changes the tickets until the release is deployed, rejected or closed. Fires "changed" after an edit or
 * when a release that waited for an approved change starts deploying.
 */
export default class RlyReleaseTickets extends LightningElement {
    @api releaseId;
    /** Inside the release page's details list: no heading of its own. */
    @api compact = false;
    _status;
    data;
    busy = false;
    editing = false;
    draft = [];
    error;

    /** The release's status: a new status posts its moment. */
    @api
    get status() { return this._status; }
    set status(value) {
        const changed = value !== this._status;
        this._status = value;
        if (changed && this.releaseId) {
            this.sync();
        }
    }

    connectedCallback() {
        if (this.releaseId && !this.data) {
            this.sync();
        }
    }

    async sync() {
        if (this.busy) {
            return;
        }
        this.busy = true;
        this.error = undefined;
        try {
            const before = this.data;
            this.data = await syncRelease({ releaseId: this.releaseId });
            if (before && JSON.stringify(before.tickets) !== JSON.stringify(this.data.tickets)) {
                this.dispatchEvent(new CustomEvent('changed'));
            }
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    get showHeading() { return !this.compact; }
    get hasTickets() { return !!this.data && this.data.tickets.length > 0; }
    get showEmpty() { return !!this.data && this.data.tickets.length === 0 && !this.editing; }
    get canEdit() { return !!this.data && this.data.canEdit && !this.editing; }
    get trackerLabel() { return this.data ? this.data.trackerLabel : ''; }
    get rows() {
        return (this.data ? this.data.tickets : []).map((t) => ({
            ...t,
            pillCls: STATUS_PILL[t.status] || 'rr-pill rr-pill-none',
            statusText: t.status || 'Not posted yet',
            failed: t.status === 'Failed',
            detail: [t.posted, t.message && t.message !== t.posted ? t.message : null].filter((x) => x).join(' · ')
        }));
    }

    startEdit() {
        this.draft = (this.data ? this.data.tickets : []).map((t) => t.ticket);
        this.editing = true;
    }
    cancelEdit() { this.editing = false; }
    handleDraft(event) { this.draft = event.detail.value; }

    async saveEdit() {
        this.busy = true;
        this.error = undefined;
        try {
            this.data = await setReleaseTickets({ releaseId: this.releaseId, tickets: this.draft });
            this.editing = false;
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
