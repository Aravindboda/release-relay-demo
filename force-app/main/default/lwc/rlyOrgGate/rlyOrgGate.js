import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import allowInSandbox from '@salesforce/apex/RlySandboxSwitch.allowInSandbox';
import endSandboxAllowance from '@salesforce/apex/RlySandboxSwitch.endSandboxAllowance';

const GUIDE_TAB = 'RLY_Relay_Guide';
const PIPELINE_TAB = 'RLY_Pipeline';
const WARN_MODES = ['sandbox', 'copy'];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * RlyHubGuard.getHubStatus as a card (board HubOrgGate): in a sandbox or a sandbox copy of the hub, and in production
 * before setup, a tab shows only this card. While an admin's override turns Release Relay on in a sandbox, it is a small
 * info line instead (with Turn off where showSwitch is set). On the hub it shows nothing.
 * Event: statuschange (detail: the new status) after the override is turned on or off.
 */
export default class RlyOrgGate extends NavigationMixin(LightningElement) {
    /** The HubStatus from RlyHubGuard.getHubStatus. */
    @api status;
    /** The Guide shows the card without its own Open the Guide button. */
    @api hideGuideButton = false;
    /** Pipeline for users who can't run setup: no Open setup button. */
    @api hideSetupButton = false;
    /** Only the override's info line, never the card (Pipeline while it shows its own setup screen or the page). */
    @api bannerOnly = false;
    /** Pipeline, admins: the override switch (sandbox and copy) and Turn off (while on). */
    @api showSwitch = false;

    switchOn = false;
    days = '';
    busy = false;
    error;

    get mode() { return (this.status && this.status.mode) || ''; }
    get isOverride() { return !!(this.status && this.status.sandboxOverride); }
    get isWarn() { return WARN_MODES.includes(this.mode); }
    get isSetup() { return this.mode === 'setup'; }
    get showCard() { return !this.bannerOnly && (this.isWarn || this.isSetup); }
    get icon() { return this.isSetup ? 'utility:setup' : 'utility:warning'; }
    get iconCls() { return this.isSetup ? 'rr-gate-icon rr-gate-icon-setup' : 'rr-gate-icon rr-gate-icon-warn'; }
    get title() { return this.status ? this.status.title : ''; }
    get message() { return this.status ? this.status.message : ''; }
    get overrideNote() { return this.status ? this.status.overrideNote : ''; }
    get showGuide() { return !this.hideGuideButton; }
    get showSetupButton() { return this.isSetup && !this.hideSetupButton; }
    get guideVariant() { return this.showSetupButton ? 'neutral' : 'brand'; }
    get hasButtons() { return this.showGuide || this.showSetupButton; }
    get canSwitch() { return this.showSwitch && this.isWarn; }
    get canTurnOff() { return this.showSwitch && this.isOverride; }
    get cantTurnOn() { return this.busy; }

    openGuide() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: GUIDE_TAB } });
    }

    openSetup() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: PIPELINE_TAB } });
    }

    handleSwitch(event) {
        this.switchOn = event.target.checked === true;
        this.error = undefined;
    }

    handleDays(event) {
        this.days = event.target.value;
    }

    turnOn() {
        const raw = String(this.days || '').trim();
        const count = raw === '' ? null : Number(raw);
        if (count !== null && (!Number.isInteger(count) || count < 1 || count > 90)) {
            this.error = 'Pick 1 to 90 days.';
            return;
        }
        this.run(allowInSandbox({ days: count }));
    }

    turnOff() {
        this.run(endSandboxAllowance());
    }

    run(call) {
        this.busy = true;
        this.error = undefined;
        call.then((status) => {
            this.switchOn = false;
            this.days = '';
            this.dispatchEvent(new CustomEvent('statuschange', { detail: status }));
        }).catch((e) => {
            this.error = errorText(e);
        }).finally(() => {
            this.busy = false;
        });
    }
}
