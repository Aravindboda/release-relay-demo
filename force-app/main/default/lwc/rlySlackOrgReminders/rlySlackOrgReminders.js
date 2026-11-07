import { LightningElement, api } from 'lwc';
import orgSettings from '@salesforce/apex/RlySlackReminderController.orgSettings';
import saveOrgSettings from '@salesforce/apex/RlySlackReminderController.saveOrgSettings';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function hourLabel(h) {
    const n = Number(h);
    if (n === 0) {
        return '12:00 AM';
    }
    if (n === 12) {
        return '12:00 PM';
    }
    return (n % 12) + ':00 ' + (n < 12 ? 'AM' : 'PM');
}

const HOURS = Array.from({ length: 24 }, (v, i) => ({ label: hourLabel(i), value: String(i) }));

/**
 * One org's Slack reminders (Pipeline tab → org window → Slack): reminders and their hours, the daily digest and its
 * hour, mentions, hotfix alerts. Read for everyone with the tab; Edit and Save for Release Relay Admins
 * (RlySlackReminderController). An org with reminders and the digest off is never read by the hourly call.
 */
export default class RlySlackOrgReminders extends LightningElement {
    /** The org (RLY_Org__c Id). */
    @api orgId;

    s;
    form;
    editing = false;
    busy = false;
    error;
    loadedFor;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.orgId && this.loadedFor !== this.orgId && !this.busy) {
            this.load();
        }
    }

    async load() {
        if (!this.orgId) {
            return;
        }
        this.loadedFor = this.orgId;
        this.busy = true;
        this.error = undefined;
        try {
            this.s = await orgSettings({ orgId: this.orgId });
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    get ready() { return !!this.s; }
    get canEdit() { return !!this.s && this.s.canEdit && !this.editing; }
    get noChannel() { return !!this.s && !this.s.channel; }
    get slackOff() { return !!this.s && !this.s.slackOn; }
    get hourOptions() { return HOURS; }
    get digestHourValue() { return this.form ? String(this.form.digestHour) : ''; }

    get facts() {
        const s = this.s;
        if (!s) {
            return [];
        }
        const on = (b) => (b ? 'On' : 'Off');
        return [
            { key: 'rem', label: 'Reminders', value: s.reminders ? 'On · after ' + s.hours + ' h waiting, again every ' + s.hours + ' h' : 'Off' },
            { key: 'dig', label: 'Daily digest', value: s.digest ? 'On · ' + hourLabel(s.digestHour) + ' (' + s.timeZone + ')' : 'Off' },
            { key: 'men', label: 'Mentions', value: on(s.mentions) },
            { key: 'hot', label: 'Hotfix alerts', value: on(s.hotfixAlerts) + (s.hotfixAlerts ? ' · even when reminders are off' : '') }
        ];
    }

    startEdit() {
        const s = this.s;
        this.form = { reminders: s.reminders, hours: s.hours, digest: s.digest, digestHour: s.digestHour, mentions: s.mentions,
            hotfixAlerts: s.hotfixAlerts };
        this.editing = true;
        this.error = undefined;
    }

    cancel() {
        this.editing = false;
        this.form = undefined;
        this.error = undefined;
    }

    handleToggle(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.checked };
    }

    handleNumber(event) {
        const v = event.detail.value;
        this.form = { ...this.form, [event.target.dataset.field]: v === '' || v === null ? null : Number(v) };
    }

    async save() {
        this.busy = true;
        this.error = undefined;
        try {
            this.s = await saveOrgSettings({ orgId: this.orgId, inputJson: JSON.stringify(this.form) });
            this.editing = false;
            this.form = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    get remindersOff() { return !this.form || !this.form.reminders; }
    get digestOff() { return !this.form || !this.form.digest; }
}
