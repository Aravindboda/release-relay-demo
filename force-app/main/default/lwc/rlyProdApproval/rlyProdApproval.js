import { LightningElement } from 'lwc';
import readView from '@salesforce/apex/RlyAccessController.prodApproval';
import saveView from '@salesforce/apex/RlyAccessController.saveProdApproval';
import { errorText } from 'c/rlyShared';

/**
 * Pipeline tab (build 49): Approvals. The hub setting "Production approval needs the add-on" as a toggle (admins), with
 * who holds the Production Approver add-on. While it is off, admins see "Turn on once you've assigned the Production
 * Approver add-on": a hub upgraded with existing approvers isn't locked out until they choose.
 */
export default class RlyProdApproval extends LightningElement {
    view;
    busy = false;
    error;

    connectedCallback() {
        readView().then((v) => { this.view = v; }).catch((e) => { this.error = errorText(e); });
    }

    get isOn() { return !!this.view && this.view.isOn === true; }
    get canEdit() { return !!this.view && this.view.canEdit === true; }
    get readOnly() { return !!this.view && !this.canEdit; }
    get toggleDisabled() { return !this.canEdit || this.busy; }
    get banner() { return (this.view && this.view.banner) || ''; }
    get pillText() { return this.isOn ? 'On' : 'Off'; }
    get pillCls() { return this.isOn ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none'; }
    get showHolders() { return !!this.view && !this.banner; }
    get holdersText() {
        const v = this.view;
        if (!v) {
            return '';
        }
        if (!v.holderCount) {
            return 'Nobody holds the Production Approver add-on yet.';
        }
        const names = (v.holderNames || []).join(', ');
        const more = v.holderCount > (v.holderNames || []).length ? ' and ' + (v.holderCount - v.holderNames.length) + ' more' : '';
        return v.holderCount + (v.holderCount === 1 ? ' person holds' : ' people hold') + ' the add-on: ' + names + more + '.';
    }

    async handleToggle(event) {
        const turnOn = event.target.checked;
        this.busy = true;
        this.error = undefined;
        try {
            this.view = await saveView({ state: turnOn ? 'On' : 'Off' });
        } catch (e) {
            this.error = errorText(e);
            event.target.checked = !turnOn;
        } finally {
            this.busy = false;
        }
    }
}
