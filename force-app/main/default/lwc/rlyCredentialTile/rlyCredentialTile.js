import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import readTile from '@salesforce/apex/RlyCredentialController.tile';

const PILL = {
    Expiring: 'rr-pill rr-pill-wait',
    Critical: 'rr-pill rr-pill-bad',
    Expired: 'rr-pill rr-pill-bad',
    Failed: 'rr-pill rr-pill-bad'
};

function when(value) {
    if (!value) {
        return '';
    }
    try {
        return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }).format(new Date(value));
    } catch (e) {
        return String(value);
    }
}

/**
 * Home tab (build 49): the Credentials tile. Lists the certificates, tokens, integration users and sign-ins that are
 * Expiring, Critical, Expired or Failed (RlyCredentialController.tile), or "All credentials OK · checked <time>".
 * Admins get a link to the Pipeline tab's Credentials card. Reads saved rows only: no callouts.
 */
export default class RlyCredentialTile extends NavigationMixin(LightningElement) {
    tile;

    connectedCallback() {
        readTile().then((t) => { this.tile = t; }).catch(() => { this.tile = undefined; });
    }

    get loaded() { return !!this.tile; }
    get isAdmin() { return !!this.tile && this.tile.isAdmin === true; }
    get notChecked() { return !!this.tile && this.tile.total === 0; }
    get hasProblems() { return !!this.tile && (this.tile.problems || []).length > 0; }
    get allOk() { return !!this.tile && this.tile.total > 0 && !this.hasProblems; }
    get checkedText() { return this.tile && this.tile.checkedOn ? '· checked ' + when(this.tile.checkedOn) : ''; }
    get problems() {
        return ((this.tile && this.tile.problems) || []).map((p) => {
            let detail = '';
            if (p.daysLeft !== null && p.daysLeft !== undefined && p.status !== 'Failed') {
                detail = p.daysLeft < 0 ? ' · expired' : ' · ' + p.daysLeft + (p.daysLeft === 1 ? ' day left' : ' days left');
            } else if (p.status === 'Failed' && p.message) {
                detail = ' · ' + p.message;
            }
            return { key: p.key, status: p.status, pillCls: PILL[p.status] || 'rr-pill rr-pill-none', text: p.kind + ' · ' + p.name + detail };
        });
    }

    openPipeline() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'RLY_Pipeline' } });
    }
}
