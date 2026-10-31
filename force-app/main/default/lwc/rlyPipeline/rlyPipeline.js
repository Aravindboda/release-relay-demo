import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrgs from '@salesforce/apex/RlyOrgController.getOrgs';
import saveOrg from '@salesforce/apex/RlyOrgController.saveOrg';
import checkOrg from '@salesforce/apex/RlyOrgController.checkOrg';
import getSetup from '@salesforce/apex/RlyRouteController.getSetup';
import saveGit from '@salesforce/apex/RlyRouteController.saveGit';
import checkGit from '@salesforce/apex/RlyRouteController.checkGit';
import createBranches from '@salesforce/apex/RlyRouteController.createBranches';
import saveRoute from '@salesforce/apex/RlyRouteController.saveRoute';

const ROLE_OPTIONS = [
    { label: 'Developer org (raises releases)', value: 'Developer' },
    { label: 'Stage (SIT, UAT…)', value: 'Stage' },
    { label: 'Hub (this org, production)', value: 'Hub' }
];
const LOGIN_OPTIONS = [
    { label: 'Production or Developer Edition', value: 'Production' },
    { label: 'Sandbox', value: 'Sandbox' }
];
const STATUS_CLS = {
    Connected: 'rr-pill rr-pill-ok',
    Failed: 'rr-pill rr-pill-bad',
    Refreshed: 'rr-pill rr-pill-wait',
    'Not checked': 'rr-pill rr-pill-none'
};
const ROLE_ORDER = { Developer: 0, Stage: 1, Hub: 2 };
const PROVIDERS = [
    { label: 'GitHub', value: 'GitHub', repo: 'owner/repository', pipeLabel: 'Workflow file', pipe: 'release-relay.yml', cred: 'RLY_GitHub' },
    { label: 'GitLab', value: 'GitLab', repo: 'group/project', pipeLabel: 'CI file', pipe: '.gitlab-ci.yml', cred: 'RLY_GitLab' },
    { label: 'Bitbucket', value: 'Bitbucket', repo: 'workspace/repository', pipeLabel: 'Custom pipeline', pipe: 'release-relay', cred: 'RLY_Bitbucket' },
    { label: 'Azure DevOps', value: 'AzureDevOps', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '', cred: 'RLY_AzureDevOps' }
];
const GIT_STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Not checked': 'rr-pill rr-pill-none' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function blankForm() {
    return {
        Id: null, Name: '', Role__c: 'Developer', My_Domain__c: '', Login_Type__c: 'Production',
        Username__c: '', Consumer_Key__c: '', Certificate__c: 'release_relay', Git_Environment__c: '', Branch__c: ''
    };
}

function blankGit() {
    return {
        Provider__c: 'GitHub', Repository__c: '', Named_Credential__c: 'RLY_GitHub', Pipeline__c: 'release-relay.yml',
        Pipeline_Branch__c: 'main', Source_Path__c: 'force-app/main/default', Code_Scan__c: true
    };
}

export default class RlyPipeline extends LightningElement {
    roleOptions = ROLE_OPTIONS;
    loginOptions = LOGIN_OPTIONS;
    orgs = [];
    keyHints = {};
    hubDomain = '';
    isAdmin = false;
    loading = false;
    error;
    editing = false;
    form = blankForm();
    formError;
    saving = false;
    checkingId;
    showSetup = false;
    providerOptions = PROVIDERS.map((p) => ({ label: p.label, value: p.value }));
    git;
    gitForm = blankGit();
    editingGit = false;
    gitError;
    gitBusy = false;
    developers = [];
    stages = [];
    warnings = [];
    routeDirty = false;
    routeBusy = false;

    connectedCallback() {
        this.load();
    }

    load() {
        this.loading = true;
        this.error = undefined;
        return Promise.all([getOrgs(), getSetup()])
            .then(([h, s]) => {
                this.orgs = h.orgs || [];
                this.keyHints = h.keyHints || {};
                this.hubDomain = h.hubDomain;
                this.isAdmin = h.isAdmin;
                this.showSetup = this.orgs.length === 0;
                this.applySetup(s);
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    // ---------- cards ----------

    get hasOrgs() { return this.orgs.length > 0; }
    get noOrgs() { return !this.loading && this.orgs.length === 0; }

    get cards() {
        return [...this.orgs]
            .sort((a, b) => (ROLE_ORDER[a.Role__c] - ROLE_ORDER[b.Role__c]) || a.Name.localeCompare(b.Name))
            .map((o) => {
                const tracking = o.Source_Tracking__c === 'Available' ? 'Fast: source tracking'
                    : o.Source_Tracking__c === 'Not available' ? 'Metadata API' : null;
                return {
                    ...o,
                    statusCls: STATUS_CLS[o.Status__c] || STATUS_CLS['Not checked'],
                    roleLabel: o.Role__c === 'Developer' ? 'Developer org' : o.Role__c,
                    tracking,
                    trackingCls: o.Source_Tracking__c === 'Available' ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none',
                    identity: [o.Org_Type__c, o.Is_Sandbox__c ? 'Sandbox' : null, o.Api_Version__c ? 'API ' + o.Api_Version__c : null]
                        .filter(Boolean).join(' · '),
                    checkedText: o.Last_Checked__c ? 'Checked ' + new Date(o.Last_Checked__c).toLocaleString([], {
                        month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not checked yet',
                    messageCls: o.Status__c === 'Failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-info',
                    keyHint: this.keyHints[o.Id],
                    checking: this.checkingId === o.Id,
                    checkLabel: this.checkingId === o.Id ? 'Signing in…' : 'Test sign-in'
                };
            });
    }

    applySetup(s) {
        this.git = s.git;
        this.developers = s.developers || [];
        this.stages = s.stages || [];
        this.warnings = s.warnings || [];
        this.routeDirty = false;
        if (!this.git) {
            this.gitForm = blankGit();
        }
    }

    // ---------- Git connection ----------

    get hasGit() { return !!this.git; }
    get notEditingGit() { return !this.editingGit; }
    get noGit() { return !this.git && !this.editingGit; }
    get gitStatusCls() { return GIT_STATUS_CLS[(this.git && this.git.Status__c) || 'Not checked']; }
    get gitMessageCls() { return this.git && this.git.Status__c === 'Failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-info'; }
    get gitProvider() { return PROVIDERS.find((p) => p.value === (this.gitForm.Provider__c || 'GitHub')) || PROVIDERS[0]; }
    get gitProviderLabel() {
        const p = this.git && PROVIDERS.find((x) => x.value === this.git.Provider__c);
        return p ? p.label : '';
    }
    get gitCheckLabel() { return this.gitBusy ? 'Checking…' : 'Check connection'; }
    get scanText() { return this.git && this.git.Code_Scan__c ? 'On' : 'Off'; }

    startGitEdit() {
        this.gitForm = this.git ? { ...blankGit(), ...this.git } : blankGit();
        this.gitError = undefined;
        this.editingGit = true;
    }

    cancelGitEdit() {
        this.editingGit = false;
    }

    handleGitField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }
        const next = { ...this.gitForm, [field]: value };
        if (field === 'Provider__c') {
            const p = PROVIDERS.find((x) => x.value === value);
            next.Named_Credential__c = p.cred;
            next.Pipeline__c = p.pipe;
        }
        this.gitForm = next;
        this.gitError = undefined;
    }

    handleGitSave() {
        const f = this.gitForm;
        const payload = {
            Provider__c: f.Provider__c, Repository__c: (f.Repository__c || '').trim(), Named_Credential__c: (f.Named_Credential__c || '').trim(),
            Pipeline__c: (f.Pipeline__c || '').trim(), Pipeline_Branch__c: (f.Pipeline_Branch__c || '').trim(),
            Source_Path__c: (f.Source_Path__c || '').trim(), Code_Scan__c: f.Code_Scan__c !== false
        };
        this.gitBusy = true;
        this.gitError = undefined;
        saveGit({ gitJson: JSON.stringify(payload) })
            .then(() => {
                this.editingGit = false;
                return this.load().then(() => this.runGitCheck());
            })
            .catch((e) => {
                this.gitError = errorText(e);
            })
            .finally(() => {
                this.gitBusy = false;
            });
    }

    handleGitCheck() {
        this.runGitCheck();
    }

    runGitCheck() {
        this.gitBusy = true;
        return checkGit()
            .then((g) => {
                this.git = g;
                this.toast(g.Status__c === 'Connected' ? 'Git connection checked' : 'Git connection: check failed',
                    g.Status__c === 'Connected' ? 'success' : 'error');
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.gitBusy = false;
            });
    }

    handleCreateBranches() {
        this.gitBusy = true;
        createBranches()
            .then((made) => {
                this.toast(made.length ? 'Created ' + made.join(', ') : 'Every route branch already exists.', 'success');
                return this.runGitCheck();
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.gitBusy = false;
            });
    }

    // ---------- route ----------

    get hasRoute() { return this.developers.length > 0 || this.stages.length > 0; }
    get hasWarnings() { return this.warnings.length > 0; }
    get developerChips() {
        return this.developers.map((d) => ({ id: d.Id, name: d.Name, branch: d.Branch__c || 'no branch' }));
    }
    get stageChips() {
        const last = this.stages.length - 1;
        return this.stages.map((s, i) => ({
            id: s.Id,
            name: s.Name,
            branch: s.Branch__c || 'no branch',
            isHub: s.Role__c === 'Hub',
            label: s.Role__c === 'Hub' ? 'Production (hub)' : 'Stage ' + (i + 1),
            cantUp: i === 0 || s.Role__c === 'Hub' || !this.isAdmin,
            cantDown: i >= last || s.Role__c === 'Hub' || (this.stages[i + 1] && this.stages[i + 1].Role__c === 'Hub') || !this.isAdmin,
            upLabel: 'Move ' + s.Name + ' earlier',
            downLabel: 'Move ' + s.Name + ' later'
        }));
    }

    moveStage(event) {
        const id = event.currentTarget.dataset.id;
        const dir = event.currentTarget.dataset.dir === 'up' ? -1 : 1;
        const list = [...this.stages];
        const i = list.findIndex((s) => s.Id === id);
        const j = i + dir;
        if (j < 0 || j >= list.length) {
            return;
        }
        [list[i], list[j]] = [list[j], list[i]];
        this.stages = list;
        this.routeDirty = true;
    }

    handleSaveRoute() {
        this.routeBusy = true;
        saveRoute({ stageIds: this.stages.map((s) => s.Id) })
            .then(() => {
                this.toast('Route saved', 'success');
                return this.load();
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.routeBusy = false;
            });
    }

    // ---------- org checks ----------

    handleCheck(event) {
        this.runCheck(event.currentTarget.dataset.id);
    }

    runCheck(orgId) {
        this.checkingId = orgId;
        return checkOrg({ orgId })
            .then((o) => {
                this.orgs = this.orgs.map((x) => (x.Id === o.Id ? o : x));
                this.toast(o.Name + (o.Status__c === 'Failed' ? ': sign-in failed' : ': signed in'),
                    o.Status__c === 'Failed' ? 'error' : 'success');
            })
            .catch((e) => {
                this.toast(errorText(e), 'error');
            })
            .finally(() => {
                this.checkingId = undefined;
            });
    }

    // ---------- form ----------

    startAdd() {
        this.form = blankForm();
        this.formError = undefined;
        this.editing = true;
    }

    handleEdit(event) {
        const o = this.orgs.find((x) => x.Id === event.currentTarget.dataset.id);
        this.form = { ...blankForm(), ...o };
        this.formError = undefined;
        this.editing = true;
    }

    cancelEdit() {
        this.editing = false;
    }

    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        const next = { ...this.form, [field]: value };
        // A sandbox My Domain means a sandbox login.
        if (field === 'My_Domain__c' && /\.sandbox\.my\.salesforce\.com/i.test(value || '')) {
            next.Login_Type__c = 'Sandbox';
        }
        this.form = next;
        this.formError = undefined;
    }

    get formTitle() { return this.form.Id ? 'Edit ' + this.form.Name : 'Register an org'; }

    /** The masked hint of the saved consumer key (the key itself never comes to the page). */
    get savedKeyHint() { return this.form.Id ? this.keyHints[this.form.Id] : null; }
    get keyRequired() { return !this.savedKeyHint; }
    get keyPlaceholder() {
        const saved = this.savedKeyHint;
        return saved ? 'Saved (ends ••••' + saved.slice(-4) + '). Leave blank to keep it.' : '';
    }
    get saveLabel() { return this.saving ? 'Saving…' : 'Save and test sign-in'; }

    handleSave() {
        // A blank consumer key isn't sent, so an edit keeps the saved one.
        const keys = ['Id', 'Name', 'Role__c', 'My_Domain__c', 'Login_Type__c', 'Username__c', 'Consumer_Key__c',
            'Certificate__c', 'Git_Environment__c', 'Branch__c'];
        const payload = {};
        keys.forEach((k) => {
            if (this.form[k] !== null && this.form[k] !== undefined && this.form[k] !== '') {
                payload[k] = typeof this.form[k] === 'string' ? this.form[k].trim() : this.form[k];
            }
        });
        this.saving = true;
        this.formError = undefined;
        saveOrg({ orgJson: JSON.stringify(payload) })
            .then((id) => {
                this.editing = false;
                return this.load().then(() => this.runCheck(id));
            })
            .catch((e) => {
                this.formError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ---------- setup help ----------

    toggleSetup() {
        this.showSetup = !this.showSetup;
    }

    get setupLabel() { return this.showSetup ? 'Hide setup steps' : 'Setup steps for a new org'; }
    get remoteSite() { return (this.form && this.form.My_Domain__c) || 'https://<that org>.my.salesforce.com'; }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Release Relay', message, variant }));
    }
}
