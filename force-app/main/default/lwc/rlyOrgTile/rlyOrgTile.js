import { LightningElement, api } from 'lwc';

/**
 * One compact org card under Connected orgs (rlyPipeline, board HubPipelineLayout A). The whole card is a button: a click,
 * Enter or Space fires "open" with detail { id }, and rlyPipeline opens the org's window.
 * tile: { id, name, domain, rolePill, roleCls, statusText, dotCls, branch, branchCls, approvalText, checkedText, openLabel, flash }
 */
export default class RlyOrgTile extends LightningElement {
    /** What the card shows (built by rlyPipeline). */
    @api tile;

    get t() { return this.tile || {}; }
    /** A card just registered or saved lights up once (a CSS animation, no timer). */
    get cardCls() { return this.t.flash ? 'rr-tile rr-tile-flash' : 'rr-tile'; }

    /** Puts the keyboard focus back on the card (after its window closes). */
    @api
    focus() {
        const btn = this.template.querySelector('button');
        if (btn) {
            btn.focus();
        }
    }

    handleOpen() {
        this.dispatchEvent(new CustomEvent('open', { detail: { id: this.t.id } }));
    }
}
