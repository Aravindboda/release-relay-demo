import { LightningElement, api } from 'lwc';
import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import getSetupStatus from '@salesforce/apex/RlySetupStatus.getSetupStatus';
import getHubDefaults from '@salesforce/apex/RlyOrgController.getHubDefaults';
import saveOrg from '@salesforce/apex/RlyOrgController.saveOrg';
import checkOrg from '@salesforce/apex/RlyOrgController.checkOrg';
import getSetup from '@salesforce/apex/RlyRouteController.getSetup';
import saveGit from '@salesforce/apex/RlyRouteController.saveGit';
import checkGit from '@salesforce/apex/RlyRouteController.checkGit';
import getPipelineFiles from '@salesforce/apex/RlyRouteController.getPipelineFiles';
import updatePipelineFiles from '@salesforce/apex/RlyRouteController.updatePipelineFiles';

const STEPS = [
    { n: 1, label: 'This org is the hub' },
    { n: 2, label: 'Git connection' },
    { n: 3, label: 'Pipeline files' },
    { n: 4, label: 'Add orgs' },
    { n: 5, label: 'Slack (optional)' }
];
const PROVIDERS = [
    { label: 'GitHub', value: 'GitHub', how: 'Actions workflow', repo: 'owner/repository', pipeLabel: 'Workflow file', pipe: 'release-relay.yml', cred: 'RLY_GitHub' },
    { label: 'GitLab', value: 'GitLab', how: 'CI pipeline', repo: 'group/project', pipeLabel: 'CI file', pipe: '.gitlab-ci.yml', cred: 'RLY_GitLab' },
    { label: 'Bitbucket', value: 'Bitbucket', how: 'Custom pipeline', repo: 'workspace/repository', pipeLabel: 'Custom pipeline', pipe: 'release-relay', cred: 'RLY_Bitbucket' },
    { label: 'Azure DevOps', value: 'AzureDevOps', how: 'Azure Pipeline', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '12', cred: 'RLY_AzureDevOps' }
];
const STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function blankGit() {
    return { Provider__c: 'GitHub', Repository__c: '', Named_Credential__c: '', Pipeline__c: '', Pipeline_Branch__c: '', Source_Path__c: '', Code_Scan__c: true };
}

function trimmed(v) {
    return typeof v === 'string' ? v.trim() : '';
}

/**
 * First-run setup on the Pipeline tab: This org is the hub → Git connection → Pipeline files → Add orgs → Slack.
 * Each step is checked before going on ("Test and continue"); the admin can leave ("Do this later") and come back.
 * Events: changed (something was saved: the page reloads), registerorg, editslack, close.
 */
export default class RlySetupWizard extends LightningElement {
    /** The registered orgs as the Pipeline tab has them (for step 4 and the hub's name). */
    @api orgs = [];
    /** This org is a sandbox copy of the hub: nothing can be saved. */
    @api hubCopy = false;

    status;
    step = 1;
    busy = false;
    error;
    defaults;
    hubForm = { Name: '', Username__c: '', Consumer_Key__c: '', Certificate__c: '', Branch__c: '', Git_Environment__c: '' };
    hubResult;
    gitForm = blankGit();
    gitResult;
    files;
    filesHow = 'pullRequest';
    filesResult;
    focusStep = false;

    get appName() { return APP_NAME; }
    get title() { return 'Set up ' + APP_NAME; }

    connectedCallback() {
        this.busy = true;
        Promise.all([getSetupStatus(), getHubDefaults().catch(() => null), getSetup().catch(() => null)])
            .then(([status, defaults, setup]) => {
                this.status = status || {};
                this.defaults = defaults || {};
                if (setup && setup.git) {
                    this.gitForm = { ...blankGit(), ...setup.git };
                    this.gitResult = setup.git;
                }
                this.step = this.firstOpenStep();
                if (this.step === 3) {
                    this.readFiles();
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    renderedCallback() {
        if (this.focusStep) {
            const first = this.template.querySelector('.rr-first');
            if (first) {
                first.focus();
                this.focusStep = false;
            }
        }
    }

    firstOpenStep() {
        const s = this.status || {};
        if (!s.hubRegistered) {
            return 1;
        }
        if (!s.gitSaved || !s.gitConnected) {
            return 2;
        }
        if (!s.pipelineFilesFound) {
            return 3;
        }
        return (s.orgCount || 0) < 1 ? 4 : 5;
    }

    // ---------- steps ----------

    get steps() {
        return STEPS.map((s) => {
            let cls = 'rr-step';
            if (s.n < this.step) {
                cls += ' rr-step-done';
            } else if (s.n === this.step) {
                cls += ' rr-step-now';
            }
            return { ...s, cls, done: s.n < this.step, current: s.n === this.step ? 'step' : 'false' };
        });
    }
    get stepText() { return 'Step ' + this.step + ' of ' + STEPS.length; }
    get isHubStep() { return this.step === 1; }
    get isGitStep() { return this.step === 2; }
    get isFilesStep() { return this.step === 3; }
    get isOrgsStep() { return this.step === 4; }
    get isSlackStep() { return this.step === 5; }
    get cantBack() { return this.step === 1 || this.busy; }
    get cantGo() { return this.busy || this.hubCopy; }
    get goLabel() {
        if (this.busy) {
            return 'Checking…';
        }
        return this.isSlackStep ? 'Finish' : 'Test and continue';
    }

    goTo(n) {
        this.step = n;
        this.error = undefined;
        this.focusStep = true;
        if (n === 3 && !this.files) {
            this.readFiles();
        }
    }

    handleBack() {
        if (this.step > 1) {
            this.goTo(this.step - 1);
        }
    }

    handleLater() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleGo() {
        this.error = undefined;
        if (this.isHubStep) {
            this.continueHub();
        } else if (this.isGitStep) {
            this.continueGit();
        } else if (this.isFilesStep) {
            this.continueFiles();
        } else if (this.isOrgsStep) {
            this.continueOrgs();
        } else {
            this.dispatchEvent(new CustomEvent('close'));
        }
    }

    changed() {
        this.dispatchEvent(new CustomEvent('changed'));
    }

    // ---------- 1 · This org is the hub ----------

    get hubOrg() { return (this.orgs || []).find((o) => o.Role__c === 'Hub'); }
    get hubRegistered() { return !!this.hubOrg; }
    get hubNotRegistered() { return !this.hubOrg; }
    get hubStatusText() { return (this.hubOrg && this.hubOrg.Status__c) || 'Not checked'; }
    get hubStatusCls() { return STATUS_CLS[this.hubStatusText] || 'rr-pill rr-pill-none'; }
    get hubDomain() { return (this.defaults && this.defaults.myDomain) || ''; }
    get hubOrgId() { return (this.defaults && this.defaults.orgId) || ''; }
    get hubMessage() { return this.hubOrg && this.hubOrg.Status__c === 'Failed' ? this.hubOrg.Status_Message__c : ''; }

    handleHubField(event) {
        this.hubForm = { ...this.hubForm, [event.target.dataset.field]: event.target.value };
        this.error = undefined;
    }

    stepValid() {
        const fields = [...this.template.querySelectorAll('.rr-step-body lightning-input')];
        return fields.reduce((ok, f) => f.reportValidity() && ok, true);
    }

    continueHub() {
        const hub = this.hubOrg;
        if (hub) {
            if (hub.Status__c === 'Connected') {
                this.goTo(2);
                return;
            }
            this.checkHub(hub.Id);
            return;
        }
        if (!this.stepValid()) {
            return;
        }
        const f = this.hubForm;
        const domain = this.hubDomain;
        const payload = {
            Name: trimmed(f.Name), Role__c: 'Hub', Environment__c: 'Production', My_Domain__c: domain,
            Login_Type__c: /\.sandbox\.my\.salesforce\.com/i.test(domain) ? 'Sandbox' : 'Production',
            Username__c: trimmed(f.Username__c), Consumer_Key__c: trimmed(f.Consumer_Key__c), Certificate__c: trimmed(f.Certificate__c),
            Branch__c: trimmed(f.Branch__c) || null, Git_Environment__c: trimmed(f.Git_Environment__c) || null,
            Approve_In_Salesforce__c: true, Approve_In_Slack__c: false, Require_Git_Review__c: false, Slack_Post__c: false,
            Hotfix_Two_Approvers__c: false, Approval_Rule__c: 'Always', Approval_Types__c: null
        };
        this.busy = true;
        saveOrg({ orgJson: JSON.stringify(payload) })
            .then((id) => {
                this.changed();
                return this.checkHub(id);
            })
            .catch((e) => {
                this.error = errorText(e);
                this.busy = false;
            });
    }

    checkHub(orgId) {
        this.busy = true;
        return checkOrg({ orgId })
            .then((o) => {
                this.hubResult = o;
                this.changed();
                if (o.Status__c === 'Connected') {
                    this.goTo(2);
                } else {
                    this.error = 'Sign-in failed: ' + (o.Status_Message__c || 'check the integration user and the consumer key.') + ' Fix it on the hub\'s card (Sign-in → Edit), then Test and continue.';
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    // ---------- 2 · Git connection ----------

    get provider() { return PROVIDERS.find((p) => p.value === this.gitForm.Provider__c) || PROVIDERS[0]; }
    get providerTiles() {
        const current = this.provider.value;
        return PROVIDERS.map((p, i) => ({
            ...p,
            pressed: p.value === current ? 'true' : 'false',
            cls: (p.value === current ? 'rr-prov rr-prov-on' : 'rr-prov') + (i === 0 ? ' rr-first' : '')
        }));
    }
    get repoHint() { return 'e.g. ' + this.provider.repo; }
    get credHint() { return 'e.g. ' + this.provider.cred; }
    get pipeHint() { return 'e.g. ' + this.provider.pipe; }
    get scanLabel() { return 'Code scan on every ' + (this.provider.value === 'GitLab' ? 'merge request' : 'pull request'); }
    get gitStatusText() { return (this.gitResult && this.gitResult.Status__c) || ''; }
    get gitStatusCls() { return STATUS_CLS[this.gitStatusText] || 'rr-pill rr-pill-none'; }
    get gitMessage() { return (this.gitResult && this.gitResult.Status_Message__c) || ''; }
    get hasGitResult() { return !!this.gitStatusText; }

    pickProvider(event) {
        const value = event.currentTarget.dataset.value;
        const before = this.provider;
        const next = { ...this.gitForm, Provider__c: value };
        // A value that was the old provider's usual one goes, so the new provider's hint shows.
        if (next.Named_Credential__c === before.cred) {
            next.Named_Credential__c = '';
        }
        if (next.Pipeline__c === before.pipe) {
            next.Pipeline__c = '';
        }
        this.gitForm = next;
        this.gitResult = undefined;
    }

    handleGitField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' ? event.target.checked : event.target.value;
        this.gitForm = { ...this.gitForm, [field]: value };
        this.error = undefined;
    }

    continueGit() {
        if (!this.stepValid()) {
            return;
        }
        const f = this.gitForm;
        const payload = {
            Provider__c: f.Provider__c, Repository__c: trimmed(f.Repository__c), Named_Credential__c: trimmed(f.Named_Credential__c),
            Pipeline__c: trimmed(f.Pipeline__c), Pipeline_Branch__c: trimmed(f.Pipeline_Branch__c),
            Source_Path__c: trimmed(f.Source_Path__c), Code_Scan__c: f.Code_Scan__c !== false
        };
        this.busy = true;
        saveGit({ gitJson: JSON.stringify(payload) })
            .then(() => checkGit())
            .then((g) => {
                this.gitResult = g;
                this.files = undefined;
                this.changed();
                if (g.Status__c === 'Connected') {
                    this.goTo(3);
                } else {
                    this.error = 'The connection didn\'t work yet. Check the repository and the Named Credential, then try again.';
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    // ---------- 3 · Pipeline files ----------

    readFiles() {
        this.busy = true;
        return getPipelineFiles()
            .then((st) => {
                this.files = st;
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    get filesMissing() { return !!this.files && (this.files.repoVersion === null || this.files.repoVersion === undefined); }
    get filesUpToDate() { return !!this.files && this.files.upToDate === true; }
    get filesNeedUpdate() { return !!this.files && !this.files.upToDate && !this.filesDone; }
    get filesDone() { return !!this.filesResult && this.filesResult.ok === true; }
    get filesWord() { return (this.files && this.files.provider) === 'GitLab' ? 'merge request' : 'pull request'; }
    get filesBranch() { return (this.files && this.files.branch) || trimmed(this.gitForm.Pipeline_Branch__c) || 'main'; }
    get filesText() {
        const st = this.files;
        if (!st) {
            return 'Pipeline files: checking your repository…';
        }
        if (st.upToDate) {
            return 'Pipeline files: up to date (version ' + st.packagedVersion + ')';
        }
        if (this.filesMissing) {
            return 'Pipeline files: not found on ' + this.filesBranch + ' · version ' + st.packagedVersion + ' available';
        }
        return 'Pipeline files: version ' + st.repoVersion + ' in your repository · version ' + st.packagedVersion + ' available';
    }
    get filesPill() {
        if (!this.files) {
            return 'Checking';
        }
        if (this.files.upToDate) {
            return 'Up to date';
        }
        return this.filesMissing ? 'Not found' : 'Update available';
    }
    get filesPillCls() { return this.filesUpToDate ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-wait'; }
    get filesHowOptions() {
        return [
            { value: 'pullRequest', label: 'Open a ' + this.filesWord, help: 'Recommended. Merge it in your Git provider to start using the files.' },
            { value: 'commit', label: 'Commit to ' + this.filesBranch, help: 'The files are committed at once.' }
        ];
    }
    get filesResultLabel() { return this.filesResult && this.filesResult.how === 'commit' ? 'Open the commit' : 'Open the ' + this.filesWord; }
    get filesCantUpdate() { return this.busy || this.hubCopy; }

    handleFilesHow(event) {
        this.filesHow = event.detail.value;
    }

    handleFilesUpdate() {
        const how = this.filesHow;
        this.busy = true;
        this.error = undefined;
        updatePipelineFiles({ how })
            .then((r) => {
                if (r && r.ok) {
                    this.filesResult = { ...r, how };
                    this.changed();
                    return this.readFiles();
                }
                this.error = (r && r.message) || 'The pipeline files were not updated.';
                return null;
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    continueFiles() {
        this.readFiles().then(() => {
            if (this.filesUpToDate || this.filesDone) {
                this.goTo(4);
            } else if (!this.error) {
                this.error = 'Add the pipeline files first: press Update pipeline files.';
            }
        });
    }

    // ---------- 4 · Add orgs ----------

    get orgRows() {
        return (this.orgs || []).map((o) => ({
            id: o.Id,
            name: o.Name,
            role: o.Role__c === 'Back_Promote' ? 'Back promote' : o.Role__c,
            status: o.Status__c || 'Not checked',
            statusCls: STATUS_CLS[o.Status__c] || 'rr-pill rr-pill-none'
        }));
    }
    get hasOrgRows() { return this.orgRows.length > 0; }

    handleRegister() {
        this.dispatchEvent(new CustomEvent('registerorg'));
    }

    continueOrgs() {
        this.busy = true;
        getSetupStatus()
            .then((s) => {
                this.status = s || {};
                if ((this.status.orgCount || 0) >= 1) {
                    this.goTo(5);
                } else {
                    this.error = 'Register at least one developer org or stage besides the hub, then Test and continue.';
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.busy = false;
            });
    }

    // ---------- 5 · Slack (optional) ----------

    get slackConnected() { return !!(this.status && this.status.slackConnected); }

    handleSlack() {
        this.dispatchEvent(new CustomEvent('editslack'));
    }
}
