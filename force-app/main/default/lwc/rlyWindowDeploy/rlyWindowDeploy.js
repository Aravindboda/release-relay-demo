import { LightningElement, api } from 'lwc';
import releaseNotice from '@salesforce/apex/RlyWindowController.releaseNotice';
import deployNow from '@salesforce/apex/RlyWindowController.deployNow';
import { errorText } from 'c/rlyShared';

/**
 * On a release Waiting for the window (build 39): for holders of the Release Window Bypass add-on (build 49), Deploy now anyway with a reason (History, evidence PDF and
 * the Slack card record it). Fires "deployed" so the release page reads the release again.
 */
export default class RlyWindowDeploy extends LightningElement {
    /** The release. */
    @api releaseId;

    canDeploy = false;
    asking = false;
    reason = '';
    busy = false;
    error;

    connectedCallback() {
        releaseNotice({ releaseId: this.releaseId })
            .then((n) => {
                this.canDeploy = !!n && n.canDeployNow === true && n.kind !== 'none';
            })
            .catch(() => {
                this.canDeploy = false;
            });
    }

    get cantSend() { return this.busy || (this.reason || '').trim().length < 5; }

    ask() {
        this.asking = true;
        this.error = undefined;
    }

    cancel() {
        this.asking = false;
        this.reason = '';
    }

    handleReason(event) {
        this.reason = event.detail.value || '';
    }

    async send() {
        this.busy = true;
        this.error = undefined;
        try {
            await deployNow({ releaseId: this.releaseId, reason: this.reason });
            this.asking = false;
            this.dispatchEvent(new CustomEvent('deployed'));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
