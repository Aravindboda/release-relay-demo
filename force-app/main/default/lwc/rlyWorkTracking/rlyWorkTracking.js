import { LightningElement } from 'lwc';
import settings from '@salesforce/apex/RlyWorkItemsController.settings';
import saveSettings from '@salesforce/apex/RlyWorkItemsController.saveSettings';
import saveTracker from '@salesforce/apex/RlyWorkTrackersController.saveTracker';
import setTrackerActive from '@salesforce/apex/RlyWorkTrackersController.setTrackerActive';
import moveTracker from '@salesforce/apex/RlyWorkTrackersController.moveTracker';
import testTracker from '@salesforce/apex/RlyWorkTrackersController.testTracker';
import { routeTicket } from 'c/rlyWorkRoute';

const KINDS = [
    { value: 'Jira', label: 'Jira', help: 'Comment and transition' },
    { value: 'Azure_Boards', label: 'Azure Boards', help: 'History and state' },
    { value: 'ServiceNow', label: 'ServiceNow', help: 'Work note and state; change gate' },
    { value: 'None', label: 'No integration', help: 'Tracked in Release Relay' },
    { value: 'Other', label: 'Other (link)', help: 'Link, optional web call' }
];
/** Grey hints per kind (never defaults). */
const HINTS = {
    Jira: { name: 'Claims stories', pattern: 'CLAIMS-\\d+', link: 'https://acme.atlassian.net/browse/{id}', credential: 'RLY_Work_Jira' },
    Azure_Boards: { name: 'Azure work items', pattern: 'AB#\\d+', link: 'https://dev.azure.com/acme/claims/_workitems/edit/{id}', credential: 'RLY_Work_AzureBoards' },
    ServiceNow: { name: 'Change requests', pattern: 'CHG\\d{7}', link: 'https://acme.service-now.com/change_request.do?sysparm_query=number={id}', credential: 'RLY_Work_ServiceNow' },
    None: { name: 'Ops tasks', pattern: 'OPS-\\d+', link: 'https://tracker.example.com/browse/{id}', credential: '' },
    Other: { name: 'Other tickets', pattern: 'TASK-\\d+', link: 'https://tracker.example.com/browse/{id}', credential: 'RLY_Work_Webhook' }
};
const KIND_PILL = { Jira: 'rr-pill rr-pill-run', Azure_Boards: 'rr-pill rr-pill-run', ServiceNow: 'rr-pill rr-pill-vio', None: 'rr-pill rr-pill-none', Other: 'rr-pill rr-pill-none' };
const SWITCHES = [
    { value: 'required', label: 'Tickets required to raise' },
    { value: 'requireChange', label: 'Approved ServiceNow change before production' }
];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * Pipeline tab: Work tracking (build 40; several trackers in build 47). Everyone reads the list; admins add a tracker
 * (kind tiles, grey hints, toggle chips), edit it, turn it on or off, move it in the routing order and Test its
 * sign-in (the Named Credential's API name only: the tracker's sign-in stays in Salesforce Setup), and set the switches
 * for every tracker: tickets required, and an approved ServiceNow change before production with its format.
 * "Try a ticket" shows which tracker a ticket goes to.
 */
export default class RlyWorkTracking extends LightningElement {
    data;
    form;
    switches;
    busy = false;
    error;
    saved;
    tests = {};
    tryText = '';

    connectedCallback() {
        settings().then((s) => { this.apply(s); }).catch((e) => { this.error = errorText(e); });
    }

    apply(s) {
        this.data = s;
        this.switches = { required: s.required, requireChange: s.requireChange, changePattern: s.changePattern || '' };
    }

    get isAdmin() { return !!this.data && this.data.isAdmin; }
    get trackers() { return this.data ? this.data.trackers : []; }
    get hasTrackers() { return this.trackers.length > 0; }
    get noTrackers() { return !!this.data && this.trackers.length === 0; }
    get summary() {
        if (!this.data) {
            return '';
        }
        const active = this.trackers.filter((t) => t.active).length;
        const bits = [this.trackers.length === 0 ? 'No trackers: every ticket is tracked in Release Relay'
            : active + (active === 1 ? ' active tracker' : ' active trackers') + (active < this.trackers.length ? ' of ' + this.trackers.length : '')];
        bits.push(this.data.required ? 'tickets required' : 'tickets optional');
        if (this.data.requireChange) {
            bits.push('approved change before production');
        }
        return bits.join(' · ');
    }
    get rows() {
        const last = this.trackers.length - 1;
        return this.trackers.map((t, i) => ({
            ...t,
            kindCls: KIND_PILL[t.kind] || KIND_PILL.None,
            patternText: t.ticketPattern || 'any ticket the others don’t take',
            credentialText: t.namedCredential || '—',
            postsText: t.postUpdates ? 'Posts' : (t.kind === 'None' ? 'Tracked here' : 'Links only'),
            postsCls: t.postUpdates ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none',
            rowCls: 'rr-tr' + (t.active ? '' : ' rr-tr-off'),
            activeValue: t.active ? ['active'] : [],
            activeText: t.active ? 'Active' : 'Off',
            activeCls: t.active ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none',
            activeOptions: [{ value: 'active', label: 'Active' }],
            upDisabled: this.busy || i === 0,
            downDisabled: this.busy || i === last,
            test: this.tests[t.id],
            testCls: this.tests[t.id] && this.tests[t.id].ok ? 'rr-msg rr-msg-ok rr-small' : 'rr-msg rr-msg-bad rr-small'
        }));
    }
    get showAdd() { return this.isAdmin && !this.form; }
    get switchOptions() { return SWITCHES; }
    get switchValue() {
        const s = this.switches || {};
        return SWITCHES.map((o) => o.value).filter((v) => s[v]);
    }
    get switchesDisabled() { return !this.isAdmin || this.busy; }
    get showChangePattern() { return !!this.switches && this.switches.requireChange; }
    get switchesDirty() {
        if (!this.data || !this.switches) {
            return false;
        }
        return this.switches.required !== this.data.required || this.switches.requireChange !== this.data.requireChange
            || (this.switches.changePattern || '') !== (this.data.changePattern || '');
    }
    get changeHint() { return 'CHG\\d{7}'; }

    get tryResult() {
        const ticket = (this.tryText || '').trim().toUpperCase();
        if (!ticket || !this.data) {
            return undefined;
        }
        const r = routeTicket(this.trackers, ticket);
        if (!r.ok) {
            return { cls: 'rr-small rr-bad', text: r.problem };
        }
        return { cls: 'rr-small rr-ok', text: r.tracker ? ticket + ' → ' + r.tracker.name + ' (' + r.tracker.kindLabel + ')' : ticket + ' → tracked in Release Relay' };
    }

    // ---- form ----
    get kindOptions() { return KINDS; }
    get hints() { return HINTS[this.form ? this.form.kind : 'Jira'] || HINTS.Jira; }
    get formTitle() { return this.form && this.form.id ? 'Edit ' + this.form.name : 'Add tracker'; }
    get integrates() { return !!this.form && this.form.kind !== 'None'; }
    get isServiceNow() { return !!this.form && this.form.kind === 'ServiceNow'; }
    get formChipOptions() {
        const out = [];
        if (this.integrates) {
            out.push({ value: 'postUpdates', label: 'Post each moment to the ticket' });
        }
        out.push({ value: 'active', label: 'Active' });
        return out;
    }
    get formChipValue() {
        if (!this.form) {
            return [];
        }
        return ['postUpdates', 'active'].filter((v) => this.form[v] && (v !== 'postUpdates' || this.integrates));
    }
    get stateHint() { return '{"Deployed to SIT":"In QA","Deployed to PROD":"Done"}'; }

    startAdd() {
        this.form = { id: null, kind: 'Jira', name: '', ticketPattern: '', linkPattern: '', namedCredential: '', postUpdates: false,
            stateMap: '', serviceNowTable: '', active: true };
        this.saved = undefined;
        this.error = undefined;
    }
    startEdit(event) {
        const t = this.trackers.find((x) => x.id === event.currentTarget.dataset.id);
        if (t) {
            this.form = { ...t };
            this.saved = undefined;
            this.error = undefined;
        }
    }
    cancel() { this.form = undefined; }
    handleKind(event) { this.form = { ...this.form, kind: event.detail.value }; }
    handleText(event) { this.form = { ...this.form, [event.target.dataset.field]: event.target.value }; }
    handleFormChips(event) {
        const v = event.detail.value;
        this.form = { ...this.form, postUpdates: v.includes('postUpdates'), active: v.includes('active') };
    }
    handleTry(event) { this.tryText = event.target.value; }

    async save() {
        await this.run(() => saveTracker({ trackerJson: JSON.stringify(this.form) }), 'Saved.');
        if (!this.error) {
            this.form = undefined;
        }
    }

    // ---- row actions ----
    handleActive(event) {
        const id = event.currentTarget.dataset.id;
        const on = event.detail.value.includes('active');
        this.run(() => setTrackerActive({ trackerId: id, state: on ? 'on' : 'off' }), on ? 'Turned on.' : 'Turned off: no new tickets go to it.');
    }
    moveUp(event) { this.run(() => moveTracker({ trackerId: event.currentTarget.dataset.id, direction: 'up' }), 'Order saved.'); }
    moveDown(event) { this.run(() => moveTracker({ trackerId: event.currentTarget.dataset.id, direction: 'down' }), 'Order saved.'); }

    async test(event) {
        const id = event.currentTarget.dataset.id;
        this.busy = true;
        try {
            const o = await testTracker({ trackerId: id });
            this.tests = { ...this.tests, [id]: o };
        } catch (e) {
            this.tests = { ...this.tests, [id]: { ok: false, message: errorText(e) } };
        } finally {
            this.busy = false;
        }
    }

    // ---- switches ----
    handleSwitches(event) {
        const v = event.detail.value;
        this.switches = { ...this.switches, required: v.includes('required'), requireChange: v.includes('requireChange') };
    }
    handleChangePattern(event) { this.switches = { ...this.switches, changePattern: event.target.value }; }
    resetSwitches() { this.apply(this.data); }
    saveSwitches() { this.run(() => saveSettings({ settingsJson: JSON.stringify(this.switches) }), 'Saved.'); }

    async run(call, okText) {
        this.busy = true;
        this.error = undefined;
        this.saved = undefined;
        try {
            this.apply(await call());
            this.saved = okText;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
