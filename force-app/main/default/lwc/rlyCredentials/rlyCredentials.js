import { LightningElement } from 'lwc';
import readBoard from '@salesforce/apex/RlyCredentialController.board';
import checkNow from '@salesforce/apex/RlyCredentialController.checkNow';
import { errorText } from 'c/rlyShared';

const PILL = {
    OK: 'rr-pill rr-pill-ok',
    Expiring: 'rr-pill rr-pill-wait',
    Critical: 'rr-pill rr-pill-bad',
    Expired: 'rr-pill rr-pill-bad',
    Failed: 'rr-pill rr-pill-bad',
    Unknown: 'rr-pill rr-pill-none'
};
const COUNTED = ['Failed', 'Expired', 'Critical', 'Expiring', 'Unknown'];

function when(value, withTime) {
    if (!value) {
        return '';
    }
    try {
        const opts = withTime ? { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' } : { day: 'numeric', month: 'short', year: 'numeric' };
        return new Intl.DateTimeFormat(undefined, opts).format(new Date(value));
    } catch (e) {
        return String(value);
    }
}

/**
 * Pipeline tab (build 49): the Credentials card. Every certificate, Git token, Slack app, integration user and org
 * sign-in the hub depends on (RLY_Credential_Status__c, saved by the nightly check), with its status, expiry, days left,
 * last check, message and how to renew it. Admins press Check now: the same pass, callouts first, then saved.
 */
export default class RlyCredentials extends LightningElement {
    board;
    busy = false;
    error;
    message;

    connectedCallback() {
        readBoard().then((b) => { this.board = b; }).catch((e) => { this.error = errorText(e); });
    }

    get canCheck() { return !!this.board && this.board.canCheck === true; }
    get checkLabel() { return this.busy ? 'Checking…' : 'Check now'; }
    get hasRows() { return !!this.board && (this.board.rows || []).length > 0; }
    get noRows() { return !!this.board && !this.hasRows; }
    get noRowsText() {
        return this.canCheck ? 'Not checked yet. Check now reads every credential, or wait for the nightly check.'
            : 'Not checked yet: credentials are checked nightly.';
    }
    get subtitle() {
        const at = this.board && this.board.checkedOn;
        return at ? 'Certificates, tokens and sign-ins · checked ' + when(at, true) : 'Certificates, tokens and sign-ins the hub depends on';
    }
    get pills() {
        const counts = (this.board && this.board.counts) || {};
        const out = COUNTED.filter((s) => counts[s] > 0).map((s) => ({ key: s, cls: PILL[s], text: counts[s] + ' ' + s.toLowerCase() }));
        if (this.hasRows && out.length === 0) {
            out.push({ key: 'ok', cls: PILL.OK, text: 'All OK' });
        }
        return out;
    }
    get rows() {
        return ((this.board && this.board.rows) || []).map((r) => ({
            ...r,
            pillCls: PILL[r.status] || PILL.Unknown,
            expiresText: r.expiresOn ? when(r.expiresOn + 'T12:00:00', false) : '—',
            daysText: r.daysLeft === null || r.daysLeft === undefined ? '—' : String(r.daysLeft),
            checkedText: when(r.lastChecked, true),
            lastOkText: r.lastOk ? 'Last OK ' + when(r.lastOk, true) : 'Not OK yet',
            showRenew: r.status !== 'OK' && !!r.renew
        }));
    }

    async checkNow() {
        this.busy = true;
        this.error = undefined;
        this.message = undefined;
        try {
            this.board = await checkNow();
            this.message = this.board.message;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
