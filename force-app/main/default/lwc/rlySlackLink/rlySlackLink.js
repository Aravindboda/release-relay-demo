import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import readLink from '@salesforce/apex/RlySlackLink.readLink';
import confirmLink from '@salesforce/apex/RlySlackLink.confirmLink';

function errorText(e) {
    if (e && e.body && e.body.message) {
        return e.body.message;
    }
    return (e && e.message) || 'Something went wrong.';
}

/**
 * Link your Slack account (board HubSlackApprovers 6b): opened from the private "Link my account" button in Slack with
 * ?c__t=<signed token>&c__release=<release Id>. Shows the Slack account and the signed-in user side by side; Link saves
 * the Slack member ID on the user with Linked by Self (RlySlackLink.confirmLink). The token carries only the Slack ID,
 * so the page names both accounts and "Not me" cancels.
 */
export default class RlySlackLink extends NavigationMixin(LightningElement) {
    token;
    releaseId;
    view;
    loading = true;
    saving = false;
    error;
    cancelled = false;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        const state = (ref && ref.state) || {};
        const token = state.c__t;
        if (token === this.token) {
            return;
        }
        this.token = token;
        this.releaseId = state.c__release;
        this.cancelled = false;
        this.read();
    }

    read() {
        this.loading = true;
        this.error = undefined;
        if (!this.token) {
            this.view = { state: 'invalid', message: 'Open this page from the Link my account button in Slack.' };
            this.loading = false;
            return;
        }
        readLink({ token: this.token })
            .then((v) => {
                this.view = v;
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get state() { return this.view ? this.view.state : ''; }
    get isReady() { return this.state === 'ready' && !this.cancelled; }
    get isLinked() { return this.state === 'linked'; }
    get isCancelled() { return this.cancelled; }
    get isRefused() { return !!this.view && !this.isReady && !this.isLinked && !this.cancelled; }
    get refusedText() { return this.view ? this.view.message : ''; }
    get linkedText() { return this.view ? this.view.message : ''; }
    get hasRelease() { return !!this.releaseId; }
    get question() { return this.view ? 'Link Slack account ' + this.view.memberId + ' to you, ' + this.view.meName + '?' : ''; }
    get slackName() { return (this.view && this.view.slackName) || 'Slack account'; }
    get slackEmail() { return (this.view && this.view.slackEmail) || 'email not shared by Slack'; }
    get memberId() { return this.view ? this.view.memberId : ''; }
    get meLine() { return this.view ? this.view.meName + ' · ' + (this.view.meAccess || '') : ''; }
    get meLogin() { return (this.view && this.view.meLogin) || ''; }
    get emailMatches() { return !!(this.view && this.view.emailMatches); }
    get matchNote() {
        return this.emailMatches ? 'Federation ID matches your email'
            : 'Slack\'s email differs from your Federation ID, which is why it wasn\'t linked automatically.';
    }
    get matchCls() { return this.emailMatches ? 'rr-ok rr-small' : 'rr-weak rr-small'; }
    get replacesText() {
        return this.view && this.view.replaces ? 'You\'re linked to ' + this.view.replaces + '; linking replaces it.' : '';
    }
    get expiresText() {
        if (!this.view || !this.view.expiresAt) {
            return '';
        }
        return 'Link expires ' + new Date(this.view.expiresAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    }
    get linkLabel() { return this.saving ? 'Linking…' : 'Link'; }

    handleNotMe() {
        this.cancelled = true;
    }

    handleLink() {
        this.saving = true;
        this.error = undefined;
        confirmLink({ token: this.token })
            .then((v) => {
                this.view = v;
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    openRelease() {
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.releaseId, actionName: 'view' } });
    }
}
