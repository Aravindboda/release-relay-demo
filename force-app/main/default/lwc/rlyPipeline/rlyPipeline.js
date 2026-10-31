import APP_NAME from '@salesforce/label/c.RLY_App_Name';
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
import getSlack from '@salesforce/apex/RlySlackController.getSlack';
import saveSlack from '@salesforce/apex/RlySlackController.saveSlack';
import sendSlackTest from '@salesforce/apex/RlySlackController.sendSlackTest';
import testSlack from '@salesforce/apex/RlySlackController.testSlack';
import saveSlackMember from '@salesforce/apex/RlySlackController.saveSlackMember';

const ROLE_OPTIONS = [
    { label: 'Developer org (raises releases)', value: 'Developer' },
    { label: 'Stage (an org on the route)', value: 'Stage' },
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
const DEFAULT_APPROVAL = [{ value: 'Salesforce', label: 'In Salesforce' }];
const SLACK_FIELDS = ['Id', 'Name', 'Role__c', 'My_Domain__c', 'Login_Type__c', 'Username__c', 'Certificate__c', 'Git_Environment__c', 'Branch__c'];
const GIT_STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Not checked': 'rr-pill rr-pill-none' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function blankForm() {
    return {
        Id: null, Name: '', Role__c: 'Developer', My_Domain__c: '', Login_Type__c: 'Production',
        Username__c: '', Consumer_Key__c: '', Certificate__c: 'release_relay', Git_Environment__c: '', Branch__c: '',
        Approval_In__c: 'Salesforce', Slack_Channel__c: '', Slack_Post__c: false
    };
}

function blankGit() {
    return {
        Provider__c: 'GitHub', Repository__c: '', Named_Credential__c: 'RLY_GitHub', Pipeline__c: 'release-relay.yml',
        Pipeline_Branch__c: 'main', Source_Path__c: 'force-app/main/default', Code_Scan__c: true
    };
}

export default class RlyPipeline extends LightningElement {
    /** The app's name, from Custom Label RLY_App_Name, so each owner can rename it. */
    get appName() { return APP_NAME; }
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
    approvalOptions = DEFAULT_APPROVAL;
    slack = { isAdmin: false, events: [], allEvents: [], approvers: [] };
    slackForm = { enabled: false, signingSecret: '', events: [] };
    slackBusy = false;
    slackTesting = false;
    slackError;
    slackEditing = false;
    showApprovers = false;
    memberEdits = {};
    memberSavingId;
    orgSlackBusyId;

    connectedCallback() {
        this.load();
    }

    load() {
        this.loading = true;
        this.error = undefined;
        return Promise.all([getOrgs(), getSetup(), getSlack()])
            .then(([h, s, sl]) => {
                this.applySlack(sl);
                this.orgs = h.orgs || [];
                this.keyHints = h.keyHints || {};
                this.hubDomain = h.hubDomain;
                this.isAdmin = h.isAdmin;
                this.approvalOptions = h.approvalOptions && h.approvalOptions.length ? h.approvalOptions : DEFAULT_APPROVAL;
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
                const isDeveloper = o.Role__c === 'Developer';
                const isHub = o.Role__c === 'Hub';
                const approvalIn = o.Approval_In__c || 'Salesforce';
                const busy = this.orgSlackBusyId === o.Id;
                return {
                    ...o,
                    statusCls: STATUS_CLS[o.Status__c] || STATUS_CLS['Not checked'],
                    rolePill: this.rolePill(o),
                    rolePillCls: isHub ? 'rr-pill rr-pill-info' : 'rr-pill rr-pill-none',
                    summary: this.summary(o),
                    checkedText: o.Last_Checked__c ? 'Checked ' + new Date(o.Last_Checked__c).toLocaleString([], {
                        month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not checked yet',
                    messageCls: o.Status__c === 'Failed' ? 'rr-msg rr-msg-bad rr-pad' : 'rr-msg rr-msg-info rr-pad',
                    checking: this.checkingId === o.Id,
                    checkLabel: this.checkingId === o.Id ? 'Signing in…' : 'Test sign-in',
                    isDeveloper,
                    isTarget: !isDeveloper,
                    approvalIn,
                    slackTitle: isDeveloper ? 'Slack for ' + o.Name + '\'s developers (optional)' : 'Approval and Slack for releases into ' + o.Name,
                    channelPlaceholder: '#channel-name',
                    postLabel: isDeveloper ? 'Also post here' : 'Post to Slack',
                    cantEdit: !this.isAdmin || busy,
                    cantTest: !this.isAdmin || busy || this.slackBusy || !(o.Slack_Channel__c || '').trim(),
                    showHubNote: isHub && approvalIn !== 'Slack' && !!o.Slack_Post__c,
                    showEvents: !isDeveloper && (!!o.Slack_Post__c || approvalIn === 'Slack'),
                    showSect: !isDeveloper || this.slackSetUp
                };
            });
    }

    /** Developer, Hub, or the stage's place on the route (Stage 1, Stage 2…). */
    rolePill(o) {
        if (o.Role__c === 'Developer') {
            return 'Developer';
        }
        if (o.Role__c === 'Hub') {
            return 'Hub';
        }
        const i = this.stages.findIndex((s) => s.Id === o.Id);
        return i >= 0 ? 'Stage ' + (i + 1) : 'Stage';
    }

    /** branch · env · source tracking or Metadata API · API version (or "this org" for the hub). */
    summary(o) {
        const parts = [];
        if (o.Branch__c) {
            parts.push({ key: 'b', label: 'branch ', value: o.Branch__c });
        }
        if (o.Git_Environment__c) {
            parts.push({ key: 'e', label: 'env ', value: o.Git_Environment__c });
        }
        if (o.Role__c === 'Hub') {
            parts.push({ key: 'h', label: 'this org' });
        } else if (o.Source_Tracking__c === 'Available') {
            parts.push({ key: 't', label: 'Fast: source tracking' });
        } else if (o.Source_Tracking__c === 'Not available') {
            parts.push({ key: 't', label: 'Metadata API' });
        }
        if (o.Api_Version__c && o.Role__c !== 'Hub') {
            parts.push({ key: 'a', label: 'API ' + o.Api_Version__c });
        }
        return parts;
    }

    get eventsText() {
        if (!this.slack.enabled) {
            return 'Slack is off for the hub.';
        }
        const events = this.slack.events || [];
        return 'Events: ' + (events.length ? events.join(' · ') : 'none');
    }

    // ---------- approval and Slack per org ----------

    handleOrgApproval(event) {
        this.updateOrg(event.target.dataset.id, { Approval_In__c: event.detail.value }, true);
    }

    handleOrgChannel(event) {
        this.updateOrg(event.target.dataset.id, { Slack_Channel__c: event.target.value }, false);
    }

    handleOrgChannelCommit(event) {
        this.updateOrg(event.target.dataset.id, { Slack_Channel__c: (event.target.value || '').trim() }, true);
    }

    handleOrgToggle(event) {
        this.updateOrg(event.target.dataset.id, { [event.target.dataset.field]: event.target.checked }, true);
    }

    /** Changes the org on the page at once; saves it through saveOrg (the sign-in fields as they are, the key kept). */
    updateOrg(orgId, changes, save) {
        this.orgs = this.orgs.map((x) => (x.Id === orgId ? { ...x, ...changes } : x));
        if (save) {
            this.saveOrgSlack(this.orgs.find((x) => x.Id === orgId));
        }
    }

    saveOrgSlack(o) {
        const payload = {};
        SLACK_FIELDS.forEach((k) => {
            payload[k] = o[k] === undefined ? null : o[k];
        });
        payload.Approval_In__c = o.Approval_In__c || 'Salesforce';
        payload.Slack_Channel__c = (o.Slack_Channel__c || '').trim() || null;
        payload.Slack_Post__c = !!o.Slack_Post__c;
        this.orgSlackBusyId = o.Id;
        return saveOrg({ orgJson: JSON.stringify(payload) })
            .then(() => getOrgs())
            .then((h) => {
                this.orgs = h.orgs || this.orgs;
                this.toast(o.Name + ': approval and Slack saved', 'success');
            })
            .catch((e) => {
                this.toast(errorText(e), 'error');
                return this.load();
            })
            .finally(() => {
                this.orgSlackBusyId = undefined;
            });
    }

    handleOrgSlackTest(event) {
        const o = this.orgs.find((x) => x.Id === event.currentTarget.dataset.id);
        this.runSlack(sendSlackTest({ channel: (o.Slack_Channel__c || '').trim() }), 'test');
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
    get scanToggleLabel() { return 'Code scan on every ' + (this.gitForm.Provider__c === 'GitLab' ? 'merge request' : 'pull request'); }
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

    // ---------- Slack connection ----------

    applySlack(sl) {
        this.slack = sl || { isAdmin: false, events: [], allEvents: [], approvers: [] };
        this.slackForm = { enabled: !!this.slack.enabled, signingSecret: '', events: [...(this.slack.events || [])] };
        this.slackError = undefined;
    }

    get showSlack() { return this.isAdmin && this.slack.isAdmin; }
    /** Slack is optional: until it's connected or switched on, the org cards show only Approved in. */
    get slackSetUp() { return !!(this.slack.connected || this.slack.enabled); }
    get slackNotSetUp() { return !this.slackSetUp; }
    get showSlackForm() { return this.slackEditing || this.slackNotSetUp; }
    get slackStatus() { return this.slack.status || 'Not set up'; }
    get slackStatusCls() {
        if (this.slackStatus === 'Connected') {
            return 'rr-pill rr-pill-ok';
        }
        return this.slackStatus.startsWith('Error') ? 'rr-pill rr-pill-bad' : 'rr-pill rr-pill-none';
    }
    get slackTestLabel() { return this.slackTesting ? 'Testing…' : 'Test'; }
    get slackEditLabel() { return this.slackEditing ? 'Close settings' : 'Settings'; }
    get slackWorkspace() { return this.slack.workspace || 'Not connected yet'; }
    get slackActionsText() { return this.slack.actionsUrl ? 'Site: ' + this.slack.actionsUrl : 'No Site set up yet'; }
    /** The secret itself never comes to the page: only a masked hint of the saved one. */
    get slackSecretText() {
        const hint = this.slack.signingSecretHint;
        return hint ? 'Signing secret ' + hint.charAt(0).toLowerCase() + hint.slice(1) : 'No signing secret saved yet';
    }
    get slackSecretPlaceholder() { return this.slack.signingSecretHint ? this.slack.signingSecretHint + '. Leave blank to keep it.' : ''; }
    get approversText() { return (this.slack.approversLinked || 0) + ' of ' + (this.slack.approversTotal || 0); }
    get approversToggleLabel() { return this.showApprovers ? 'Hide' : 'Show'; }
    get approverRows() {
        return (this.slack.approvers || []).map((a) => {
            const edited = this.memberEdits[a.userId];
            const memberId = edited !== undefined ? edited : (a.slackMemberId || '');
            return {
                ...a,
                memberId,
                linked: !!a.slackMemberId,
                inputLabel: 'Slack member ID for ' + a.name,
                cantSave: this.memberSavingId === a.userId || memberId.trim() === (a.slackMemberId || '')
            };
        });
    }
    get hasApprovers() { return this.approverRows.length > 0; }
    get noApprovers() { return this.approverRows.length === 0; }
    get slackEventOptions() { return (this.slack.allEvents || []).map((e) => ({ label: e, value: e })); }
    get slackLastText() {
        if (!this.slack.lastResult) {
            return '';
        }
        const when = this.slack.lastSent ? new Date(this.slack.lastSent).toLocaleString([], {
            month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) + ' · ' : '';
        return 'Last message: ' + when + this.slack.lastResult;
    }
    get slackLastCls() { return (this.slack.lastResult || '').startsWith('Failed') ? 'rr-msg rr-msg-bad rr-pad' : 'rr-msg rr-msg-info rr-pad'; }
    get slackSaveLabel() { return this.slackBusy ? 'Saving…' : 'Save'; }

    toggleSlackEdit() {
        this.slackEditing = !this.slackEditing;
        this.applySlack(this.slack);
    }

    openSlackEdit() {
        this.slackEditing = true;
    }

    toggleApprovers() {
        this.showApprovers = !this.showApprovers;
    }

    handleSlackEnabled(event) {
        const enabled = event.target.checked;
        // Switched on with no events chosen: every event, as the hub does.
        const events = enabled && this.slackForm.events.length === 0 ? [...(this.slack.allEvents || [])] : this.slackForm.events;
        this.slackForm = { ...this.slackForm, enabled, events };
        this.slackError = undefined;
    }

    handleSlackSecret(event) {
        this.slackForm = { ...this.slackForm, signingSecret: event.target.value };
        this.slackError = undefined;
    }

    handleSlackEvents(event) {
        this.slackForm = { ...this.slackForm, events: event.detail.value };
    }

    handleSlackSave() {
        const secret = (this.slackForm.signingSecret || '').trim();
        if (/\s/.test(secret)) {
            this.slackError = 'The signing secret has no spaces: copy it again from the Slack app (Basic Information).';
            return;
        }
        const settings = { enabled: this.slackForm.enabled, events: this.slackForm.events, signingSecret: secret };
        this.runSlack(saveSlack({ settingsJson: JSON.stringify(settings) }), 'save').then((ok) => {
            if (ok) {
                this.slackEditing = false;
            }
        });
    }

    handleSlackConnTest() {
        this.slackTesting = true;
        this.runSlack(testSlack(), 'check').finally(() => {
            this.slackTesting = false;
        });
    }

    /** Runs a Slack call; kind is save, check or test (which toast to show). Resolves true when it worked. */
    runSlack(call, kind) {
        this.slackBusy = true;
        this.slackError = undefined;
        return call
            .then((sl) => {
                this.applySlack(sl);
                if (kind === 'save') {
                    this.toast('Slack settings saved', 'success');
                } else if (kind === 'check') {
                    this.toast('Slack: ' + (sl.status || 'checked'), sl.status === 'Connected' ? 'success' : 'error');
                } else {
                    const failed = (sl.lastResult || '').startsWith('Failed');
                    this.toast(failed ? 'Slack: ' + sl.lastResult : 'Test message sent to Slack', failed ? 'error' : 'success');
                }
                return true;
            })
            .catch((e) => {
                this.slackError = errorText(e);
                this.toast(this.slackError, 'error');
                return false;
            })
            .finally(() => {
                this.slackBusy = false;
            });
    }

    handleMemberInput(event) {
        this.memberEdits = { ...this.memberEdits, [event.target.dataset.id]: event.target.value };
    }

    handleMemberSave(event) {
        const userId = event.currentTarget.dataset.id;
        const memberId = (this.memberEdits[userId] || '').trim();
        this.memberSavingId = userId;
        saveSlackMember({ userId, memberId })
            .then((sl) => {
                const edits = { ...this.memberEdits };
                delete edits[userId];
                this.memberEdits = edits;
                this.applySlack(sl);
                this.toast(memberId ? 'Slack member linked' : 'Slack member unlinked', 'success');
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.memberSavingId = undefined;
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
            'Certificate__c', 'Git_Environment__c', 'Branch__c', 'Approval_In__c', 'Slack_Channel__c', 'Slack_Post__c'];
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
        this.dispatchEvent(new ShowToastEvent({ title: APP_NAME, message, variant }));
    }
}
