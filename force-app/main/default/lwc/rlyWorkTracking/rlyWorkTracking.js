import { LightningElement } from 'lwc';
import settings from '@salesforce/apex/RlyWorkItemsController.settings';
import saveSettings from '@salesforce/apex/RlyWorkItemsController.saveSettings';

const TRACKERS = [
    { value: 'Jira', label: 'Jira' },
    { value: 'Azure_Boards', label: 'Azure Boards' },
    { value: 'ServiceNow', label: 'ServiceNow' },
    { value: 'None', label: 'No integration' },
    { value: 'Other', label: 'Other (link)' }
];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * Pipeline tab: Work tracking (build 40). Everyone reads the summary; admins edit the tracker, ticket formats, link,
 * required tickets, the Named Credential (its API name only: the tracker's sign-in stays in Salesforce Setup), posting
 * moments with an optional state map, and (ServiceNow) an approved change before production.
 */
export default class RlyWorkTracking extends LightningElement {
    data;
    form;
    editing = false;
    busy = false;
    error;
    saved;

    connectedCallback() {
        settings().then((s) => { this.data = s; }).catch((e) => { this.error = errorText(e); });
    }

    get isAdmin() { return !!this.data && this.data.isAdmin; }
    get summary() {
        if (!this.data) {
            return '';
        }
        const d = this.data;
        const bits = [d.trackerLabel, d.required ? 'tickets required' : 'tickets optional'];
        if (d.postUpdates) {
            bits.push('moments posted');
        }
        if (d.requireChange) {
            bits.push('approved change before production');
        }
        return bits.join(' · ');
    }
    get trackerChips() { return TRACKERS; }
    get trackerValue() { return this.form ? this.form.tracker : 'None'; }
    get isServiceNow() { return !!this.form && this.form.tracker === 'ServiceNow'; }
    get integrates() { return !!this.form && this.form.tracker !== 'None'; }
    get credentialHint() { return 'Jira_Cloud'; }
    get showEdit() { return !this.editing; }
    get ticketHint() { return '[A-Z][A-Z0-9]+-\\d+ CHG\\d{7}'; }
    get linkHint() { return 'https://tracker.example.com/browse/{id}'; }
    get stateHint() { return '{"Deployed to SIT":"In QA","Deployed to PROD":"Done"}'; }
    get changeHint() { return 'CHG\\d{7}'; }

    startEdit() {
        this.form = { ...this.data };
        this.editing = true;
        this.saved = undefined;
    }
    cancel() { this.editing = false; }

    handleTracker(event) { this.form = { ...this.form, tracker: event.detail.value }; }
    handleText(event) { this.form = { ...this.form, [event.target.dataset.field]: event.target.value }; }
    handleToggle(event) { this.form = { ...this.form, [event.target.dataset.field]: event.target.checked }; }

    async save() {
        this.busy = true;
        this.error = undefined;
        try {
            this.data = await saveSettings({ settingsJson: JSON.stringify(this.form) });
            this.editing = false;
            this.saved = 'Saved.';
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
