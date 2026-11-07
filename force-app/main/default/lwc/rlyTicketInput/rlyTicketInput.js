import { LightningElement, api } from 'lwc';
import settings from '@salesforce/apex/RlyWorkItemsController.settings';
import { routeTicket } from 'c/rlyWorkRoute';

/**
 * Ticket entry (build 40): chips for the tickets, a box to add one (Enter or comma), each ticket matched to its tracker
 * as you add it (build 47: the first active tracker whose pattern matches; the chip names it), the hub checks again on
 * save. Fires "change" with detail { value: [tickets] }.
 */
export default class RlyTicketInput extends LightningElement {
    @api label = 'Work items';
    @api disabled = false;
    /** Tickets already saved (Add tickets on a release): not matched again. */
    @api knownTickets = [];
    _value = [];
    text = '';
    problem;
    config;

    @api
    get value() { return this._value; }
    set value(v) { this._value = Array.isArray(v) ? [...v] : []; }

    connectedCallback() {
        settings().then((s) => { this.config = s; }).catch(() => { this.config = undefined; });
    }

    get required() { return !!this.config && this.config.required; }
    get labelText() { return this.label + (this.required ? '' : ' (optional)'); }
    get hint() { return 'PROJ-123, CHG0012345'; }
    get help() {
        if (this.required) {
            return 'Your admin made tickets required: add at least one.';
        }
        return 'The tickets this release delivers. Promotions carry them on; ' + (this.config ? this.config.trackerLabel : 'Release Relay') + ' shows where each one is.';
    }
    get trackers() { return this.config && this.config.trackers ? this.config.trackers : []; }
    get chips() {
        return this._value.map((t) => {
            const r = routeTicket(this.trackers, t);
            return { key: t, label: t, tracker: r.tracker ? r.tracker.name : undefined };
        });
    }

    handleText(event) { this.text = event.target.value; }

    handleKey(event) {
        if (event.key === 'Enter' || event.key === ',') {
            event.preventDefault();
            this.add();
        } else if (event.key === 'Backspace' && !this.text && this._value.length) {
            this.remove({ currentTarget: { dataset: { key: this._value[this._value.length - 1] } } });
        }
    }

    add() {
        const parts = (this.text || '').split(/[\s,;]+/).map((p) => p.trim().toUpperCase()).filter((p) => p);
        this.problem = undefined;
        const next = [...this._value];
        for (const p of parts) {
            const problem = this.problemOf(p);
            if (problem) {
                this.problem = problem;
                return;
            }
            if (!next.includes(p)) {
                next.push(p);
            }
        }
        this.text = '';
        this.setValue(next);
    }

    /** Why a ticket can't be added, or undefined. */
    problemOf(ticket) {
        if (!/^[A-Za-z0-9][A-Za-z0-9#._:/-]{0,79}$/.test(ticket)) {
            return '"' + ticket + '" isn’t a ticket number.';
        }
        if ((this.knownTickets || []).includes(ticket)) {
            return undefined;
        }
        const r = routeTicket(this.trackers, ticket);
        return r.ok ? undefined : r.problem;
    }

    remove(event) {
        const key = event.currentTarget.dataset.key;
        this.setValue(this._value.filter((t) => t !== key));
    }

    setValue(next) {
        this._value = next;
        this.dispatchEvent(new CustomEvent('change', { detail: { value: [...next] } }));
    }
}
