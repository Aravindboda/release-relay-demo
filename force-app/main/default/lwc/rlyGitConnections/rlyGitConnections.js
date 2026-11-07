import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConnections from '@salesforce/apex/RlyConnectionController.getConnections';
import saveConnection from '@salesforce/apex/RlyConnectionController.saveConnection';
import checkConnection from '@salesforce/apex/RlyConnectionController.checkConnection';
import createBranchesFor from '@salesforce/apex/RlyConnectionController.createBranchesFor';
import pipelineFilesFor from '@salesforce/apex/RlyConnectionController.pipelineFilesFor';
import updatePipelineFilesFor from '@salesforce/apex/RlyConnectionController.updatePipelineFilesFor';

const APP_NAME = 'Release Relay';
/** One connection per provider (build 45). Grey hints only: nothing is filled in for the admin. */
const PROVIDERS = [
    { label: 'GitHub', value: 'GitHub', how: 'Actions workflow', repo: 'owner/repository', pipeLabel: 'Pipeline file', pipe: 'release-relay.yml', cred: 'RLY_GitHub' },
    { label: 'GitLab', value: 'GitLab', how: 'CI pipeline', repo: 'group/project', pipeLabel: 'Pipeline file', pipe: '.gitlab-ci.yml', cred: 'RLY_GitLab' },
    { label: 'Bitbucket', value: 'Bitbucket', how: 'Custom pipeline', repo: 'workspace/repository', pipeLabel: 'Custom pipeline', pipe: 'release-relay', cred: 'RLY_Bitbucket' },
    { label: 'Azure DevOps', value: 'AzureDevOps', how: 'Azure Pipeline', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '12', cred: 'RLY_AzureDevOps' }
];
const STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Not checked': 'rr-pill rr-pill-none' };
const HOW_OPTIONS = [
    { value: 'pullRequest', label: 'By pull request', help: 'A branch and a pull request into the pipeline branch.' },
    { value: 'commit', label: 'Commit', help: 'Straight to the pipeline branch.' }
];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function providerOf(value) {
    return PROVIDERS.find((p) => p.value === value) || PROVIDERS[0];
}

/**
 * Pipeline tab, Git connections (build 45): one card per connection (provider, repository, Named Credential, pipeline
 * version, orgs) with Check, Edit, Create missing branches and Update pipeline files, a "Not set up" card with Add for
 * each provider not used yet, and the add / edit form. Fires "changed" after a save or check (the page reloads its
 * route) and "filesstatus" with { connectionId: { older, text } } once the pipeline files are read (the route lanes
 * warn when a connection's file is older than the hub's).
 */
export default class RlyGitConnections extends LightningElement {
    /** A sandbox copy of the hub: nothing can be changed. */
    @api hubCopy = false;
    /** Another section is being edited: Edit and Add wait. */
    @api locked = false;

    data;
    files = {};
    error;
    busyId;
    editing;
    form = {};
    formError;
    saving = false;
    filesForId;
    filesHow = 'pullRequest';
    filesResult;
    loaded = false;

    connectedCallback() {
        this.load();
    }

    /** Reads the cards again (the page calls it after an org moves). */
    @api
    reload() {
        return this.load();
    }

    load() {
        return getConnections()
            .then((d) => {
                this.data = d;
                this.error = undefined;
                this.loaded = true;
                this.readFiles();
            })
            .catch((e) => {
                this.error = errorText(e);
                this.loaded = true;
            });
    }

    readFiles() {
        const cards = (this.data && this.data.cards) || [];
        Promise.all(cards.map((c) => pipelineFilesFor({ connectionId: c.id })
            .then((s) => ({ id: c.id, s }))
            .catch((e) => ({ id: c.id, s: { message: errorText(e) } }))))
            .then((rows) => {
                const files = {};
                const status = {};
                rows.forEach((r) => {
                    files[r.id] = r.s || {};
                    const s = r.s || {};
                    const older = s.packagedVersion != null && s.repoVersion != null && s.repoVersion < s.packagedVersion;
                    status[r.id] = { older, missing: s.packagedVersion != null && s.repoVersion == null, text: s.message || '' };
                });
                this.files = files;
                this.dispatchEvent(new CustomEvent('filesstatus', { detail: status }));
            });
    }

    // ---------- cards ----------

    get isAdmin() { return !!(this.data && this.data.isAdmin); }
    get hasCards() { return this.cardList.length > 0; }
    get cardList() {
        const cards = (this.data && this.data.cards) || [];
        return cards.map((c) => {
            const f = this.files[c.id] || {};
            const busy = this.busyId === c.id;
            const rec = c.record || {};
            return {
                ...c,
                key: c.id,
                namedCredential: rec.Named_Credential__c,
                title: c.providerLabel || c.provider,
                statusText: c.status || 'Not checked',
                statusCls: STATUS_CLS[c.status] || STATUS_CLS['Not checked'],
                inactive: c.active !== true,
                orgsText: c.orgNames && c.orgNames.length ? c.orgNames.join(', ') : 'No orgs yet',
                orgCount: (c.orgNames || []).length + ((c.orgNames || []).length === 1 ? ' org' : ' orgs'),
                versionText: this.versionText(f),
                versionCls: f.upToDate ? 'rr-pill rr-pill-ok' : (f.repoVersion == null && f.packagedVersion == null ? 'rr-pill rr-pill-none' : 'rr-pill rr-pill-wait'),
                versionPill: this.versionPill(f),
                pipelineText: rec.Pipeline__c || providerOf(c.provider).pipe,
                messageText: rec.Status_Message__c,
                checkLabel: busy ? 'Checking…' : 'Check',
                cantAct: busy || this.hubCopy || !this.isAdmin,
                cantEdit: this.locked || this.hubCopy || !!this.editing || !this.isAdmin,
                filesOpen: this.filesForId === c.id,
                canUpdate: this.isAdmin && f.upToDate !== true && f.packagedVersion != null
            };
        });
    }

    versionText(f) {
        if (f.packagedVersion == null && !f.message) {
            return 'Reading…';
        }
        return f.message || '';
    }

    versionPill(f) {
        if (f.upToDate) {
            return 'Version ' + f.repoVersion;
        }
        if (f.repoVersion != null) {
            return 'Version ' + f.repoVersion + ' · ' + f.packagedVersion + ' available';
        }
        return f.packagedVersion != null ? 'Not in the repository' : '…';
    }

    get notSetUpList() {
        return ((this.data && this.data.notSetUp) || []).map((v) => {
            const p = providerOf(v);
            return { key: v, value: v, label: p.label, how: p.how, cantAdd: this.locked || this.hubCopy || !!this.editing || !this.isAdmin };
        });
    }
    get hasNotSetUp() { return this.notSetUpList.length > 0; }
    get showEmpty() { return this.loaded && !this.hasCards; }
    get showAddButton() { return this.isAdmin && this.hasNotSetUp && !this.isEditing; }
    get addLocked() { return this.locked || this.hubCopy; }

    handleCheck(event) {
        const id = event.currentTarget.dataset.id;
        this.busyId = id;
        checkConnection({ connectionId: id })
            .then((card) => {
                this.toast(card.status === 'Connected' ? card.providerLabel + ': connection checked' : card.providerLabel + ': check failed',
                    card.status === 'Connected' ? 'success' : 'warning');
                this.fireChanged();
                return this.load();
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.busyId = undefined;
            });
    }

    handleBranches(event) {
        const id = event.currentTarget.dataset.id;
        this.busyId = id;
        const created = [];
        const step = (from) => createBranchesFor({ connectionId: id, fromIndex: from }).then((r) => {
            created.push(...((r && r.created) || []));
            return r && r.nextIndex != null ? step(r.nextIndex) : null;
        });
        step(0)
            .then(() => this.toast(created.length ? 'Created ' + created.join(', ') : 'Every branch of this route exists', 'success'))
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.busyId = undefined;
            });
    }

    // ---------- Update pipeline files (per connection) ----------

    get howOptions() { return HOW_OPTIONS; }
    get filesBusy() { return !!this.busyId && this.busyId === this.filesForId; }
    get filesUpdateLabel() { return this.filesBusy ? 'Updating…' : 'Update'; }
    get filesResultUrl() { return this.filesResult && this.filesResult.url; }
    get filesResultText() { return this.filesResult && this.filesResult.message; }

    openFiles(event) {
        this.filesForId = event.currentTarget.dataset.id;
        this.filesHow = 'pullRequest';
        this.filesResult = undefined;
    }

    closeFiles() {
        this.filesForId = undefined;
        this.filesResult = undefined;
    }

    handleHow(event) {
        this.filesHow = event.detail.value;
    }

    handleFilesUpdate() {
        const id = this.filesForId;
        this.busyId = id;
        updatePipelineFilesFor({ connectionId: id, how: this.filesHow })
            .then((r) => {
                this.filesResult = r;
                this.toast((r && r.message) || 'Pipeline files updated', r && r.ok ? 'success' : 'warning');
                this.readFiles();
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.busyId = undefined;
            });
    }

    // ---------- add / edit ----------

    get isEditing() { return !!this.editing; }
    get isAdding() { return this.editing === 'new'; }
    get formTitle() { return this.isAdding ? 'Add a Git connection' : 'Edit ' + providerOf(this.form.Provider__c).label + ' connection'; }
    get formProvider() { return providerOf(this.form.Provider__c); }
    get providerTiles() {
        const unused = (this.data && this.data.notSetUp) || [];
        const list = this.isAdding ? PROVIDERS.filter((p) => unused.includes(p.value)) : PROVIDERS.filter((p) => p.value === this.form.Provider__c);
        return list.map((p) => ({
            ...p,
            pressed: p.value === this.form.Provider__c ? 'true' : 'false',
            cls: p.value === this.form.Provider__c ? 'rr-prov rr-prov-on' : 'rr-prov',
            off: !this.isAdding
        }));
    }
    get repoHint() { return 'e.g. ' + this.formProvider.repo; }
    get credHint() { return 'e.g. ' + this.formProvider.cred; }
    get pipeHint() { return 'e.g. ' + this.formProvider.pipe; }
    get saveLabel() { return this.saving ? 'Saving…' : 'Save'; }
    get cantSave() { return this.saving || this.hubCopy || !this.form.Provider__c; }
    get showActive() { return !this.isAdding; }

    openAdd(event) {
        const v = event && event.currentTarget && event.currentTarget.dataset ? event.currentTarget.dataset.value : undefined;
        if (this.editing) {
            return;
        }
        const unused = (this.data && this.data.notSetUp) || [];
        this.form = { Id: null, Provider__c: v || unused[0], Repository__c: '', Named_Credential__c: '', Pipeline__c: '',
            Pipeline_Branch__c: '', Source_Path__c: '', Code_Scan__c: true, Active__c: true };
        this.formError = undefined;
        this.editing = 'new';
    }

    openEdit(event) {
        const c = ((this.data && this.data.cards) || []).find((x) => x.id === event.currentTarget.dataset.id);
        if (!c) {
            return;
        }
        const rec = c.record || {};
        this.form = { Id: c.id, Provider__c: c.provider, Repository__c: c.repository || '', Named_Credential__c: rec.Named_Credential__c || '',
            Pipeline__c: rec.Pipeline__c || '', Pipeline_Branch__c: rec.Pipeline_Branch__c || '', Source_Path__c: rec.Source_Path__c || '',
            Code_Scan__c: rec.Code_Scan__c === true, Active__c: c.active === true };
        this.formError = undefined;
        this.editing = c.id;
    }

    pickProvider(event) {
        if (this.isAdding) {
            this.form = { ...this.form, Provider__c: event.currentTarget.dataset.value };
        }
    }

    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' ? event.target.checked : event.target.value;
        this.form = { ...this.form, [field]: value };
    }

    handleKey(event) {
        if (event.key === 'Escape') {
            this.cancelEdit();
        }
    }

    cancelEdit() {
        if (!this.saving) {
            this.editing = undefined;
            this.formError = undefined;
        }
    }

    handleSave() {
        this.saving = true;
        this.formError = undefined;
        const payload = { ...this.form };
        if (!payload.Id) {
            delete payload.Id;
        }
        saveConnection({ connectionJson: JSON.stringify(payload) })
            .then((id) => {
                this.editing = undefined;
                this.toast('Git connection saved. Checking it…', 'success');
                this.fireChanged();
                return this.load().then(() => checkConnection({ connectionId: id }).then(() => this.load()).catch(() => this.load()));
            })
            .catch((e) => {
                this.formError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    fireChanged() {
        this.dispatchEvent(new CustomEvent('changed'));
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: APP_NAME, message, variant }));
    }
}
