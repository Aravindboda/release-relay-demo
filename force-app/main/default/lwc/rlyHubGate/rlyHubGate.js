import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import { isGated } from 'c/rlyShared';

/**
 * The hub gate for a tab (build 57: one copy instead of one per tab). RlyHubGuard.getHubStatus tells the org's mode
 * (hub, setup, sandbox, copy); in a sandbox, a sandbox copy of the hub or a production org not set up yet the tab shows
 * only rlyOrgGate. The component keeps hubStatus and statusRead as its own fields and implements loadPage().
 * @param {Function} Base the component's base class
 * @returns {Function} the class with the gate
 */
export const HubGate = (Base) => class extends Base {
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    get gated() { return isGated(this.hubStatus); }
    get showPage() { return this.statusRead && !this.gated; }

    /** Reads the hub status once, then loads the page only on the hub. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            })
            .finally(() => {
                this.statusRead = true;
                if (!this.gated) {
                    this.loadPage();
                }
            });
    }
};
