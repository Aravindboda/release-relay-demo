import { LightningElement, api } from 'lwc';
import saveWindow from '@salesforce/apex/RlyWindowController.saveWindow';

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const ZONES = ['America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles', 'America/Phoenix',
    'America/Anchorage', 'Pacific/Honolulu', 'America/Toronto', 'America/Sao_Paulo', 'Europe/London', 'Europe/Dublin',
    'Europe/Paris', 'Europe/Berlin', 'Europe/Zurich', 'Europe/Madrid', 'Europe/Amsterdam', 'Asia/Kolkata', 'Asia/Dubai',
    'Asia/Singapore', 'Asia/Tokyo', 'Australia/Sydney', 'GMT'];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

let seq = 0;

/**
 * An org's release window (build 39) in the Pipeline tab's org window: the summary and what happens now, and for admins
 * Edit: the days (chips), From / To (blank for the whole day; To earlier than From runs past midnight), the time zone and
 * the freezes (start, end, reason). Saving fires "saved" with the window as saved (RlyWindowController.WindowView).
 */
export default class RlyReleaseWindow extends LightningElement {
    /** The window (RlyWindowController.WindowView). */
    @api view;

    editing = false;
    saving = false;
    error;
    form = { days: [], fromTime: '', toTime: '', timeZone: '', freezes: [] };

    get summary() { return (this.view && this.view.summary) || 'No window: deploys run any time.'; }
    get stateText() { return this.view ? this.view.stateText : ''; }
    get stateCls() {
        if (!this.view || !this.view.isSet) {
            return 'rr-pill rr-pill-none';
        }
        return this.view.openNow ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-wait';
    }
    get stateLabel() {
        if (!this.view || !this.view.isSet) {
            return 'Not set';
        }
        return this.view.openNow ? 'Open now' : 'Closed now';
    }
    get canEdit() { return !!this.view && this.view.canEdit === true; }
    get showEdit() { return this.canEdit && !this.editing; }
    get freezeRows() {
        return ((this.view && this.view.freezes) || []).map((f, i) => ({
            key: 'f' + i, text: f.fromDate + ' → ' + f.toDate + (f.reason ? ' · ' + f.reason : '')
        }));
    }
    get hasFreezes() { return this.freezeRows.length > 0; }

    get dayOptions() { return DAYS.map((d) => ({ value: d, label: d })); }
    get zoneOptions() {
        const list = ZONES.includes(this.form.timeZone) || !this.form.timeZone ? ZONES : [this.form.timeZone, ...ZONES];
        return list.map((z) => ({ value: z, label: z }));
    }
    get formFreezes() { return this.form.freezes; }
    get hasFormFreezes() { return this.form.freezes.length > 0; }
    get overnight() {
        return !!this.form.fromTime && !!this.form.toTime && this.form.toTime.slice(0, 5) < this.form.fromTime.slice(0, 5);
    }

    startEdit() {
        const v = this.view || {};
        this.form = {
            days: [...(v.days || [])],
            fromTime: v.fromTime || '',
            toTime: v.toTime || '',
            timeZone: v.timeZone || 'America/Chicago',
            freezes: (v.freezes || []).map((f) => ({ key: 'k' + (seq++), fromDate: f.fromDate, toDate: f.toDate, reason: f.reason || '' }))
        };
        this.error = undefined;
        this.editing = true;
    }

    cancelEdit() {
        this.editing = false;
        this.error = undefined;
    }

    handleDays(event) {
        this.form = { ...this.form, days: event.detail.value || [] };
    }

    handleField(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.detail.value || '' };
    }

    addFreeze() {
        this.form = { ...this.form, freezes: [...this.form.freezes, { key: 'k' + (seq++), fromDate: '', toDate: '', reason: '' }] };
    }

    removeFreeze(event) {
        const key = event.currentTarget.dataset.key;
        this.form = { ...this.form, freezes: this.form.freezes.filter((f) => f.key !== key) };
    }

    handleFreeze(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        const value = event.detail.value || '';
        this.form = { ...this.form, freezes: this.form.freezes.map((f) => (f.key === key ? { ...f, [field]: value } : f)) };
    }

    clearWindow() {
        this.form = { ...this.form, days: [], fromTime: '', toTime: '' };
    }

    async save() {
        this.saving = true;
        this.error = undefined;
        try {
            const input = {
                orgId: this.view.orgId,
                days: this.form.days,
                fromTime: (this.form.fromTime || '').slice(0, 5),
                toTime: (this.form.toTime || '').slice(0, 5),
                timeZone: this.form.timeZone,
                freezes: this.form.freezes.map((f) => ({ fromDate: f.fromDate || null, toDate: f.toDate || null, reason: f.reason }))
            };
            const saved = await saveWindow({ inputJson: JSON.stringify(input) });
            this.editing = false;
            this.dispatchEvent(new CustomEvent('saved', { detail: saved }));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.saving = false;
        }
    }
}
