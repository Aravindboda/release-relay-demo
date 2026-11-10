import { LightningElement, api } from 'lwc';

/**
 * A wait without timers (build 57): an invisible element whose CSS animation lasts `ms` milliseconds; when it ends the
 * component fires `done` once. Render it to start the wait, remove it to cancel; a new key starts a new wait.
 */
export default class RlyWait extends LightningElement {
    /** How long to wait, in milliseconds. */
    @api ms = 1000;

    get waitStyle() {
        const ms = Math.max(1, Math.round(Number(this.ms) || 0));
        return 'animation-duration: ' + ms + 'ms;';
    }

    handleEnd(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('done'));
    }
}
