import { LightningElement, api } from 'lwc';
import syncRelease from '@salesforce/apex/RlyWorkItemsController.syncRelease';
import setReleaseTickets from '@salesforce/apex/RlyWorkItemsController.setReleaseTickets';
import addReleaseTickets from '@salesforce/apex/RlyWorkItemsController.addReleaseTickets';

const STATUS_PILL = { Posted: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Tracked here': 'rr-pill rr-pill-none' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * A release's tickets (build 40; its own Work items card with Add tickets in build 47). Each time the release's status
 * changes it asks the hub to post the new moment to the tickets, each through its own tracker
 * (RlyWorkItemsController.syncRelease: callouts, then one save) and shows what was posted; Try again posts again.
 * Until the release is deployed, rejected or closed: Add tickets (the same ticket input as New Release; the release's
 * history records it and the new tickets get the release's current moment) and Remove. Fires "changed" after a change
 * or when a release that waited for an approved change starts deploying.
 */
export default class RlyReleaseTickets extends LightningElement {
    @api releaseId;
    /** Kept for older callers: the card always has its heading. */
    @api compact = false;
    _status;
    data;
    busy = false;
    adding = false;
    draft = [];
    error;
    notice;

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

    get tickets() { return this.data ? this.data.tickets : []; }
    get hasTickets() { return this.tickets.length > 0; }
    get showEmpty() { return !!this.data && this.tickets.length === 0 && !this.adding; }
    get canEdit() { return !!this.data && this.data.canEdit; }
    get showAdd() { return this.canEdit && !this.adding; }
    get knownTickets() { return this.tickets.map((t) => t.ticket); }
    get summary() {
        if (!this.data) {
            return '';
        }
        const n = this.tickets.length;
        const names = [...new Set(this.tickets.map((t) => t.tracker).filter((x) => x))];
        const count = n === 0 ? 'No tickets' : n + (n === 1 ? ' ticket' : ' tickets');
        return names.length ? count + ' · ' + names.join(', ') : count + ' · ' + this.data.trackerLabel;
    }
    get rows() {
        return this.tickets.map((t) => ({
            ...t,
            pillCls: STATUS_PILL[t.status] || 'rr-pill rr-pill-none',
            statusText: t.status || 'Not posted yet',
            failed: t.status === 'Failed',
            trackerText: t.tracker || 'Untracked',
            detail: [t.posted, t.message && t.message !== t.posted ? t.message : null].filter((x) => x).join(' · ')
        }));
    }
    get emptyText() {
        return this.canEdit ? 'No tickets on this release yet: Add tickets links it to its stories or change request.' : 'No tickets on this release.';
    }

    startAdd() {
        this.draft = [];
        this.adding = true;
        this.notice = undefined;
    }
    cancelAdd() { this.adding = false; }
    handleDraft(event) { this.draft = event.detail.value; }

    async saveAdd() {
        this.busy = true;
        this.error = undefined;
        try {
            this.data = await addReleaseTickets({ releaseId: this.releaseId, tickets: this.draft });
            this.adding = false;
            this.notice = 'Added. They start at the release’s current stage; History records it.';
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
        if (!this.error) {
            await this.sync();
            this.dispatchEvent(new CustomEvent('changed'));
        }
    }

    async removeTicket(event) {
        const ticket = event.currentTarget.dataset.ticket;
        this.busy = true;
        this.error = undefined;
        this.notice = undefined;
        try {
            this.data = await setReleaseTickets({ releaseId: this.releaseId, tickets: this.knownTickets.filter((t) => t !== ticket) });
            this.notice = ticket + ' removed; History records it.';
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
