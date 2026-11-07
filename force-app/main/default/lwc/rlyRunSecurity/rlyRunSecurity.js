import { LightningElement } from 'lwc';
import readStatus from '@salesforce/apex/RlyRunSigningController.status';
import generateKey from '@salesforce/apex/RlyRunSigningController.generateKey';
import saveKey from '@salesforce/apex/RlyRunSigningController.saveKey';
import checkRepository from '@salesforce/apex/RlyRunSigningController.checkRepository';

const ICONS = {
    ok: { icon: '✓', cls: 'rr-ic rr-ic-ok', label: 'In place' },
    missing: { icon: '!', cls: 'rr-ic rr-ic-missing', label: 'Missing' },
    unknown: { icon: '?', cls: 'rr-ic rr-ic-unknown', label: "Couldn't read" }
};
const GITLAB_WHERE = 'In GitLab: Settings → CI/CD → Variables → Add variable RELAY_RUN_KEY, paste the key, Masked and Protected, environments *.';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function when(value) {
    if (!value) {
        return '';
    }
    try {
        return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit' })
            .format(new Date(value));
    } catch (e) {
        return String(value);
    }
}

/**
 * Pipeline tab (build 48): Run signing and Repository security. Everyone reads whether the hub signs its runs; admins
 * Generate a key (shown once here, to copy into the repository as RELAY_RUN_KEY) and Save it, after which it is never
 * shown again; Replace does the same for a new key. Admins also run the read-only repository check: branch protection,
 * each org environment's deployment branches and the RELAY_RUN_KEY secret, with how to fix each gap.
 */
export default class RlyRunSecurity extends LightningElement {
    status;
    newKey;
    report;
    busy = false;
    error;
    saved;
    checkError;
    copied = false;

    connectedCallback() {
        readStatus().then((s) => { this.status = s; }).catch((e) => { this.error = errorText(e); });
    }

    get canEdit() { return !!this.status && this.status.canEdit === true; }
    get readOnly() { return !!this.status && !this.canEdit; }
    get keySet() { return !!this.status && this.status.keySet === true; }
    get replacing() { return this.keySet; }
    get showGenerate() { return this.canEdit && !this.newKey; }
    get generateLabel() { return this.keySet ? 'Replace key' : 'Generate key'; }
    get signPill() { return this.keySet ? 'On' : 'Off'; }
    get signPillCls() { return this.keySet ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none'; }
    get keyText() {
        if (!this.keySet) {
            return 'Not set';
        }
        const bits = ['Set'];
        if (this.status.setOn) {
            bits.push(when(this.status.setOn));
        }
        return bits.join(' · ') + (this.status.setBy ? ' by ' + this.status.setBy : '');
    }
    get runsText() { return this.keySet ? 'Every run the hub starts is signed' : 'Not signed yet'; }
    get resultsText() { return this.keySet ? 'Only signed results are trusted' : 'Unsigned results are accepted'; }
    get whereText() {
        const p = this.status && this.status.provider;
        if (p === 'GitLab') {
            return GITLAB_WHERE;
        }
        const envs = (this.status && this.status.environments) || [];
        const list = envs.length ? envs.join(', ') : 'each org environment';
        return 'In GitHub: Settings → Environments → add it to each environment (' + list + ') as the environment secret RELAY_RUN_KEY, '
            + 'each environment limited to the pipeline branch. Not as a repository secret: a workflow on any branch can read those.';
    }
    get copyLabel() { return this.copied ? 'Copied' : 'Copy'; }

    async generate() {
        this.busy = true;
        this.error = undefined;
        this.saved = undefined;
        try {
            this.newKey = await generateKey();
            this.copied = false;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    async copyKey() {
        try {
            await navigator.clipboard.writeText(this.newKey);
            this.copied = true;
        } catch (e) {
            this.error = "Copying was blocked by the browser: select the key and copy it.";
        }
    }

    cancelKey() {
        this.newKey = undefined;
        this.copied = false;
    }

    async saveNewKey() {
        this.busy = true;
        this.error = undefined;
        try {
            this.status = await saveKey({ key: this.newKey });
            this.newKey = undefined;
            this.saved = 'Saved. Every run the hub starts is signed now; the key won\'t be shown again.';
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    // ---- Repository security ----
    get checkLabel() { return this.report ? 'Check again' : 'Check'; }
    get noReport() { return !this.report; }
    get noReportText() {
        return this.canEdit ? 'Check reads the repository through the Git connection: branch protection, each org environment and RELAY_RUN_KEY.'
            : 'Only Release Relay admins can run the repository check.';
    }
    get reportSubtitle() {
        if (!this.report) {
            return 'Branch protection, environments and the run-signing key in the repository';
        }
        const r = this.report;
        return [r.provider, r.repository, 'checked ' + when(r.checkedOn)].filter((x) => !!x).join(' · ');
    }
    get reportPill() {
        const r = this.report;
        if (r.missing > 0) {
            return r.missing + ' to fix';
        }
        return r.unknown > 0 ? r.unknown + " couldn't be read" : 'All in place';
    }
    get reportPillCls() {
        const r = this.report;
        if (r.missing > 0) {
            return 'rr-pill rr-pill-bad';
        }
        return r.unknown > 0 ? 'rr-pill rr-pill-wait' : 'rr-pill rr-pill-ok';
    }
    get rows() {
        return (this.report ? this.report.items : []).map((i) => {
            const look = ICONS[i.state] || ICONS.unknown;
            return { ...i, icon: look.icon, iconCls: look.cls, stateLabel: look.label };
        });
    }

    async checkRepository() {
        this.busy = true;
        this.checkError = undefined;
        try {
            this.report = await checkRepository();
        } catch (e) {
            this.checkError = errorText(e);
        } finally {
            this.busy = false;
        }
    }
}
