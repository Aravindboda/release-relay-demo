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
import getPipelineFiles from '@salesforce/apex/RlyRouteController.getPipelineFiles';
import updatePipelineFiles from '@salesforce/apex/RlyRouteController.updatePipelineFiles';
import getSlack from '@salesforce/apex/RlySlackController.getSlack';
import saveSlack from '@salesforce/apex/RlySlackController.saveSlack';
import sendSlackTest from '@salesforce/apex/RlySlackController.sendSlackTest';
import testSlack from '@salesforce/apex/RlySlackController.testSlack';
import saveSlackMember from '@salesforce/apex/RlySlackController.saveSlackMember';
import getBackPromote from '@salesforce/apex/RlyRouteController.getBackPromote';
import setBackPromote from '@salesforce/apex/RlyRouteController.setBackPromote';
import saveBackPromoteOrg from '@salesforce/apex/RlyRouteController.saveBackPromoteOrg';
import syncNow from '@salesforce/apex/RlyRouteController.syncNow';

const LOGIN_OPTIONS = [
    { label: 'Production or Developer Edition', value: 'Production' },
    { label: 'Sandbox', value: 'Sandbox' }
];
const ENVIRONMENT_OPTIONS = [
    { label: 'Developer sandbox', value: 'Developer' },
    { label: 'Developer Pro sandbox', value: 'Developer_Pro' },
    { label: 'Partial Copy sandbox', value: 'Partial_Copy' },
    { label: 'Full Copy sandbox', value: 'Full_Copy' },
    { label: 'Production', value: 'Production' }
];
const ENVIRONMENT_LABELS = ENVIRONMENT_OPTIONS.reduce((m, o) => ({ ...m, [o.value]: o.label }), {});
const STATUS_CLS = {
    Connected: 'rr-pill rr-pill-ok',
    Failed: 'rr-pill rr-pill-bad',
    Refreshed: 'rr-pill rr-pill-wait',
    'Not checked': 'rr-pill rr-pill-none'
};
const ROLE_ORDER = { Stage: 0, Hub: 1, Developer: 2, Back_Promote: 3 };
const BACK_PROMOTE = 'Back_Promote';
const SYNC_STATUS_CLS = { Deployed: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', Conflict: 'rr-pill rr-pill-wait', Running: 'rr-pill rr-pill-info' };
const PROVIDERS = [
    { label: 'GitHub', value: 'GitHub', how: 'Actions workflow', repo: 'owner/repository', pipeLabel: 'Workflow file', pipe: 'release-relay.yml', cred: 'RLY_GitHub' },
    { label: 'GitLab', value: 'GitLab', how: 'CI pipeline', repo: 'group/project', pipeLabel: 'CI file', pipe: '.gitlab-ci.yml', cred: 'RLY_GitLab' },
    { label: 'Bitbucket', value: 'Bitbucket', how: 'Custom pipeline', repo: 'workspace/repository', pipeLabel: 'Custom pipeline', pipe: 'release-relay', cred: 'RLY_Bitbucket' },
    { label: 'Azure DevOps', value: 'AzureDevOps', how: 'Azure Pipeline', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '', cred: 'RLY_AzureDevOps' }
];
const ORG_FIELDS = ['Id', 'Name', 'Role__c', 'Environment__c', 'My_Domain__c', 'Login_Type__c', 'Username__c', 'Certificate__c', 'Git_Environment__c', 'Branch__c'];
const GIT_STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Not checked': 'rr-pill rr-pill-none' };
const APPROVE_FIELDS = ['Approve_In_Salesforce__c', 'Approve_In_Slack__c'];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function blankForm() {
    return {
        Id: null, Name: '', Role__c: 'Developer', Environment__c: 'Developer', My_Domain__c: '', Login_Type__c: 'Production',
        Username__c: '', Consumer_Key__c: '', Certificate__c: 'release_relay', Git_Environment__c: '', Branch__c: '',
        Approve_In_Salesforce__c: true, Approve_In_Slack__c: false, Require_Git_Review__c: false, Slack_Channel__c: '', Slack_Post__c: false,
        Hotfix_Two_Approvers__c: false
    };
}

/** The approval toggles as the org has them; an org saved before the toggles existed approves in Salesforce. */
function approvals(o) {
    const sf = o.Approve_In_Salesforce__c === true;
    const slack = o.Approve_In_Slack__c === true;
    return { sf: sf || !slack, slack, git: o.Require_Git_Review__c === true };
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
    loginOptions = LOGIN_OPTIONS;
    environmentOptions = ENVIRONMENT_OPTIONS;
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
    gitError;
    gitBusy = false;
    developers = [];
    stages = [];
    warnings = [];
    routeDirty = false;
    routeBusy = false;
    gitDirty = false;
    editingRoute = false;
    slackAvailable = false;
    gitProviderName;
    bouncedId;
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
    /** RlyRouteController.getPipelineFiles: the pipeline files' versions in the repository and packaged. */
    pipeFiles;
    pipeFilesLoading = false;
    pipeFilesError;
    filesOpen = false;
    filesHow = 'pullRequest';
    filesBusy = false;
    filesResult;
    filesUpdateError;
    focusFiles = false;
    /** RlyRouteController.getBackPromote: the back promote switch and its orgs (null when this user can't read it). */
    backPromote;
    bpBusy = false;
    bpBusyId;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.focusFiles) {
            const close = this.template.querySelector('.rr-files-close');
            if (close) {
                close.focus();
                this.focusFiles = false;
            }
        }
    }

    load() {
        this.loading = true;
        this.error = undefined;
        return Promise.all([getOrgs(), getSetup(), getSlack(), this.readBackPromote()])
            .then(([h, s, sl, bp]) => {
                this.applySlack(sl);
                this.backPromote = bp;
                this.orgs = h.orgs || [];
                this.keyHints = h.keyHints || {};
                this.hubDomain = h.hubDomain;
                this.isAdmin = h.isAdmin;
                this.slackAvailable = h.slackAvailable === true;
                this.gitProviderName = h.gitProvider;
                this.showSetup = this.orgs.length === 0;
                this.applySetup(s);
                if (this.git && !this.pipeFiles && !this.pipeFilesLoading) {
                    this.loadPipeFiles();
                }
                if (this.orgs.length === 0 && this.isAdmin && !this.editing) {
                    this.startAdd();
                }
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    /** Back promote is for admins: anyone else gets no board, and the page shows no back promote settings. */
    readBackPromote() {
        return getBackPromote().catch(() => null);
    }

    // ---------- cards ----------

    get hasOrgs() { return this.orgs.length > 0; }
    get noOrgs() { return !this.loading && this.orgs.length === 0; }

    get cards() {
        return [...this.orgs]
            .sort((a, b) => (ROLE_ORDER[a.Role__c] - ROLE_ORDER[b.Role__c]) || (this.routeIndex(a) - this.routeIndex(b)) || a.Name.localeCompare(b.Name))
            .map((o) => {
                const isDeveloper = o.Role__c === 'Developer';
                const isHub = o.Role__c === 'Hub';
                const isBackPromote = o.Role__c === BACK_PROMOTE;
                const ap = approvals(o);
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
                    isTarget: !isDeveloper && !isBackPromote,
                    isBackPromote,
                    isOrg: true,
                    Hotfix_Two_Approvers__c: o.Hotfix_Two_Approvers__c === true,
                    twoApproverLabel: 'Hotfixes into ' + o.Name + ' need 2 approvers',
                    showTwoApproverHelp: o.Hotfix_Two_Approvers__c === true,
                    bp: isBackPromote ? this.bpCard(o) : null,
                    Approve_In_Salesforce__c: ap.sf || !(this.slackAvailable && ap.slack),
                    Approve_In_Slack__c: ap.slack,
                    Require_Git_Review__c: ap.git,
                    approveGroupLabel: 'Where releases into ' + o.Name + ' are approved',
                    showApproveHelp: this.slackAvailable || this.bouncedId === o.Id,
                    approveHelpCls: this.bouncedId === o.Id ? 'rr-msg rr-msg-wait' : 'rr-kicker',
                    slackTitle: this.sectTitle(o, isDeveloper),
                    channelPlaceholder: '#channel-name',
                    postLabel: isDeveloper ? 'Also post here' : 'Post to Slack',
                    cantEdit: !this.isAdmin || busy,
                    cantTest: !this.isAdmin || busy || this.slackBusy || !(o.Slack_Channel__c || '').trim(),
                    showHubNote: !isDeveloper && !isBackPromote && !ap.slack && !!o.Slack_Post__c,
                    showEvents: !isDeveloper && (!!o.Slack_Post__c || ap.slack),
                    showSect: !isDeveloper || this.slackSetUp
                };
            });
    }

    /** The org cards, with the Back promote card just before the back promote orgs (board HubHotfixBackPromote). */
    get gridCards() {
        const cards = this.cards;
        if (!this.backPromote) {
            return cards;
        }
        const at = cards.findIndex((c) => c.isBackPromote);
        const settings = { Id: 'rr-back-promote', isSettings: true };
        return at < 0 ? [...cards, settings] : [...cards.slice(0, at), settings, ...cards.slice(at)];
    }

    /** The org's place on the route (stages in route order), so the cards follow the route. */
    routeIndex(o) {
        const i = this.stages.findIndex((s) => s.Id === o.Id);
        return i >= 0 ? i : this.stages.length;
    }

    sectTitle(o, isDeveloper) {
        if (isDeveloper) {
            return 'Slack for ' + o.Name + '\'s developers (optional)';
        }
        if (o.Role__c === BACK_PROMOTE) {
            return 'Back promote from ' + this.hubName;
        }
        return (this.slackSetUp || this.slackAvailable ? 'Approval and Slack for releases into ' : 'Approval for releases into ') + o.Name;
    }

    get showGitReview() { return !!(this.gitProviderName || '').trim(); }
    get gitReviewLabel() { return 'Also require ' + (this.gitProviderName || '').trim() + ' reviewers before deploying'; }

    get roleOptions() {
        const first = this.stages.find((s) => s.Role__c !== 'Hub');
        const into = first && first.Branch__c ? ' (raises into ' + first.Branch__c + ')' : ' (raises releases)';
        return [
            { label: 'Developer org' + into, value: 'Developer' },
            { label: 'Stage (an org on the route)', value: 'Stage' },
            { label: 'Hub (this org, production)', value: 'Hub' },
            { label: 'Back promote (after production)', value: BACK_PROMOTE }
        ];
    }

    /** Developer, Hub, or the stage's place on the route (Stage 1, Stage 2…). */
    rolePill(o) {
        if (o.Role__c === 'Developer') {
            return 'Developer';
        }
        if (o.Role__c === 'Hub') {
            return 'Hub';
        }
        if (o.Role__c === BACK_PROMOTE) {
            return 'Back promote';
        }
        const i = this.stages.findIndex((s) => s.Id === o.Id);
        return i >= 0 ? 'Stage ' + (i + 1) : 'Stage';
    }

    /** branch · env · source tracking or Metadata API · API version (or "this org" for the hub). */
    summary(o) {
        const parts = [];
        if (o.Environment__c && ENVIRONMENT_LABELS[o.Environment__c]) {
            parts.push({ key: 'v', label: ENVIRONMENT_LABELS[o.Environment__c] });
        }
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

    /** Approve in Salesforce / in Slack: either is enough, and the last one on can't be switched off. */
    handleApproveToggle(event) {
        const orgId = event.target.dataset.id;
        const field = event.target.dataset.field;
        const on = event.target.checked;
        const o = this.orgs.find((x) => x.Id === orgId);
        const ap = approvals(o);
        const slack = this.slackAvailable && ap.slack;
        const current = { Approve_In_Salesforce__c: ap.sf || !slack, Approve_In_Slack__c: slack };
        const next = { ...current, [field]: on };
        if (!APPROVE_FIELDS.some((k) => next[k])) {
            event.target.checked = true;
            this.bouncedId = orgId;
            this.updateOrg(orgId, { [field]: true }, false);
            return;
        }
        this.bouncedId = undefined;
        this.updateOrg(orgId, { [field]: on }, true);
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
        ORG_FIELDS.forEach((k) => {
            payload[k] = o[k] === undefined ? null : o[k];
        });
        const ap = approvals(o);
        payload.Approve_In_Salesforce__c = ap.sf;
        payload.Approve_In_Slack__c = ap.slack;
        payload.Require_Git_Review__c = ap.git;
        payload.Slack_Channel__c = (o.Slack_Channel__c || '').trim() || null;
        payload.Slack_Post__c = !!o.Slack_Post__c;
        payload.Hotfix_Two_Approvers__c = o.Hotfix_Two_Approvers__c === true;
        this.orgSlackBusyId = o.Id;
        return saveOrg({ orgJson: JSON.stringify(payload) })
            .then(() => getOrgs())
            .then((h) => {
                this.orgs = h.orgs || this.orgs;
                this.toast(o.Name + ': settings saved', 'success');
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
        // Back promote orgs are drawn after the hub (backPromoteNodes); they aren't stages or developer orgs.
        this.developers = (s.developers || []).filter((o) => o.Role__c !== BACK_PROMOTE);
        this.stages = (s.stages || []).filter((o) => o.Role__c !== BACK_PROMOTE);
        this.warnings = s.warnings || [];
        this.routeDirty = false;
        this.editingRoute = false;
        if (!this.gitDirty) {
            this.gitForm = this.git ? { ...blankGit(), ...this.git } : blankGit();
        }
    }

    // ---------- Git connection ----------

    get hasGit() { return !!this.git; }
    get gitLocked() { return !this.isAdmin || this.gitBusy; }
    get gitCantCheck() { return this.gitBusy || this.gitDirty; }
    get showGitSave() { return this.isAdmin && (this.gitDirty || !this.git); }
    get gitSaveLabel() { return this.gitBusy ? 'Saving…' : 'Save and check'; }
    get gitStatus() { return (this.git && this.git.Status__c) || 'Not checked'; }
    /** A short one-line result goes in the pill, as on the board; anything longer stays in the message below. */
    get gitShortMessage() {
        const m = (this.git && this.git.Status_Message__c) || '';
        return this.gitStatus === 'Connected' && m && m.length <= 80 && !m.includes('\n') ? m : '';
    }
    get gitStatusText() { return this.gitShortMessage || this.gitStatus; }
    get gitStatusCls() { return GIT_STATUS_CLS[this.gitStatus] || GIT_STATUS_CLS['Not checked']; }
    get gitMessage() { return this.git && !this.gitDirty && !this.gitShortMessage ? this.git.Status_Message__c : null; }
    get gitMessageCls() { return this.git && this.git.Status__c === 'Failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-info'; }
    get providerTiles() {
        const current = this.gitForm.Provider__c || 'GitHub';
        return PROVIDERS.map((p) => ({
            ...p,
            pressed: p.value === current ? 'true' : 'false',
            cls: p.value === current ? 'rr-prov rr-prov-on' : 'rr-prov'
        }));
    }
    get gitProvider() { return PROVIDERS.find((p) => p.value === (this.gitForm.Provider__c || 'GitHub')) || PROVIDERS[0]; }
    get gitProviderLabel() {
        const p = this.git && PROVIDERS.find((x) => x.value === this.git.Provider__c);
        return p ? p.label : '';
    }
    get gitCheckLabel() { return this.gitBusy ? 'Testing…' : 'Test connection'; }
    get scanOnText() { return 'On for every ' + (this.gitForm.Provider__c === 'GitLab' ? 'merge request' : 'pull request'); }

    pickProvider(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.gitForm.Provider__c) {
            return;
        }
        const p = PROVIDERS.find((x) => x.value === value);
        this.gitForm = { ...this.gitForm, Provider__c: value, Named_Credential__c: p.cred, Pipeline__c: p.pipe };
        this.gitDirty = true;
        this.gitError = undefined;
    }

    cancelGitEdit() {
        this.gitDirty = false;
        this.gitError = undefined;
        this.gitForm = this.git ? { ...blankGit(), ...this.git } : blankGit();
    }

    handleGitField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }
        this.gitForm = { ...this.gitForm, [field]: value };
        this.gitDirty = true;
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
                this.gitDirty = false;
                // The provider or branch may have changed: read the pipeline files' versions again.
                this.pipeFiles = undefined;
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

    // ---------- pipeline files ----------

    loadPipeFiles() {
        this.pipeFilesLoading = true;
        this.pipeFilesError = undefined;
        return getPipelineFiles()
            .then((st) => {
                this.pipeFiles = st;
            })
            .catch((e) => {
                this.pipeFilesError = errorText(e);
            })
            .finally(() => {
                this.pipeFilesLoading = false;
            });
    }

    get showFilesLine() { return this.hasGit && (this.pipeFilesLoading || !!this.pipeFiles || !!this.pipeFilesError); }
    get filesRepoMissing() { return !!this.pipeFiles && (this.pipeFiles.repoVersion === null || this.pipeFiles.repoVersion === undefined); }

    /** Pipeline files: up to date (version N) · version R in your repository · version N available · not found in your repository. */
    get filesText() {
        const st = this.pipeFiles;
        if (this.pipeFilesLoading) {
            return 'Pipeline files: checking your repository…';
        }
        if (!st) {
            return 'Pipeline files: ' + (this.pipeFilesError || 'not checked');
        }
        if (this.filesRepoMissing) {
            return 'Pipeline files: not found in your repository · version ' + st.packagedVersion + ' available';
        }
        if (st.upToDate) {
            return 'Pipeline files: up to date (version ' + st.packagedVersion + ')';
        }
        return 'Pipeline files: version ' + st.repoVersion + ' in your repository · version ' + st.packagedVersion + ' available';
    }
    get filesPill() {
        const st = this.pipeFiles;
        if (!st) {
            return this.pipeFilesLoading ? 'Checking' : 'Not checked';
        }
        if (st.upToDate) {
            return 'Up to date';
        }
        return this.filesRepoMissing ? 'Not found' : 'Update available';
    }
    get filesPillCls() {
        const st = this.pipeFiles;
        if (!st) {
            return this.pipeFilesError ? 'rr-pill rr-pill-bad' : 'rr-pill rr-pill-none';
        }
        return st.upToDate ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-wait';
    }
    get filesNote() { return this.pipeFiles && this.pipeFiles.message ? this.pipeFiles.message : ''; }
    get canUpdateFiles() { return this.isAdmin && !!this.pipeFiles && this.pipeFiles.isAdmin === true && !this.pipeFiles.upToDate; }
    get filesGitLab() { return (this.pipeFiles && this.pipeFiles.provider) === 'GitLab'; }
    get filesRequestWord() { return this.filesGitLab ? 'merge request' : 'pull request'; }
    get filesBranch() { return (this.pipeFiles && this.pipeFiles.branch) || (this.git && this.git.Pipeline_Branch__c) || 'main'; }
    get filesHowOptions() {
        return [
            { label: 'Open a ' + this.filesRequestWord + ' (recommended)', value: 'pullRequest' },
            { label: 'Commit directly to ' + this.filesBranch, value: 'commit' }
        ];
    }
    get filesHowHelp() {
        return this.filesHow === 'commit'
            ? 'The files are committed to ' + this.filesBranch + ' at once. The next release uses them.'
            : 'A branch with the new files and a ' + this.filesRequestWord + ' into ' + this.filesBranch + '. Merge it in your Git provider to start using them.';
    }
    get filesTitle() { return 'Update pipeline files to version ' + ((this.pipeFiles && this.pipeFiles.packagedVersion) || ''); }

    /** The files this hub's pipeline uses (its provider's file and the script), with what changes in each. */
    get filesToChange() {
        const st = this.pipeFiles;
        const packaged = st && st.packagedVersion;
        return ((st && st.files) || []).filter((f) => f.forThisHub).map((f) => {
            let change;
            if (f.repoVersion === null || f.repoVersion === undefined) {
                change = 'New file · version ' + packaged;
            } else if (f.repoVersion < packaged) {
                change = 'Version ' + f.repoVersion + ' → ' + packaged;
            } else {
                change = 'Already version ' + f.repoVersion + ' · written again';
            }
            return { key: f.resourceName || f.repoPath, name: f.name, repoPath: f.repoPath, change };
        });
    }
    get hasFilesToChange() { return this.filesToChange.length > 0; }
    get filesDone() { return !!this.filesResult && this.filesResult.ok === true; }
    get filesNotDone() { return !this.filesDone; }
    get filesResultLabel() {
        if (!this.filesResult) {
            return '';
        }
        return this.filesResult.how === 'commit' ? 'Open the commit' : 'Open the ' + this.filesRequestWord;
    }
    get filesUpdateLabel() { return this.filesBusy ? 'Updating…' : 'Update'; }
    get filesCantUpdate() { return this.filesBusy || !this.hasFilesToChange; }
    get filesCancelLabel() { return this.filesDone ? 'Close' : 'Cancel'; }

    openFiles() {
        this.filesHow = 'pullRequest';
        this.filesResult = undefined;
        this.filesUpdateError = undefined;
        this.filesOpen = true;
        this.focusFiles = true;
    }

    closeFiles() {
        if (!this.filesBusy) {
            this.filesOpen = false;
        }
    }

    handleFilesKey(event) {
        if (event.key === 'Escape') {
            this.closeFiles();
        }
    }

    handleFilesHow(event) {
        this.filesHow = event.detail.value;
        this.filesUpdateError = undefined;
    }

    handleFilesUpdate() {
        const how = this.filesHow;
        this.filesBusy = true;
        this.filesUpdateError = undefined;
        updatePipelineFiles({ how })
            .then((r) => {
                if (r && r.ok) {
                    this.filesResult = { ...r, how };
                    this.toast(r.message || 'Pipeline files updated', 'success');
                    return this.loadPipeFiles();
                }
                this.filesUpdateError = (r && r.message) || 'The pipeline files were not updated.';
                return null;
            })
            .catch((e) => {
                this.filesUpdateError = errorText(e);
            })
            .finally(() => {
                this.filesBusy = false;
            });
    }

    // ---------- route ----------

    get hasRoute() { return this.developers.length > 0 || this.stages.length > 0; }
    get hasWarnings() { return this.warnings.length > 0; }
    get hasDevelopers() { return this.developers.length > 0; }
    get canEditRoute() { return this.stages.filter((s) => s.Role__c !== 'Hub').length > 1; }
    get routeCantSave() { return this.routeBusy || !this.routeDirty; }

    /** The org as getOrgs has it (sandbox, approval toggles), falling back to the route's copy. */
    orgFor(r) { return this.orgs.find((x) => x.Id === r.Id) || r; }

    get developerChips() {
        const first = this.stages[0];
        const into = first && first.Branch__c ? first.Branch__c : '';
        return this.developers.map((d) => {
            const o = this.orgFor(d);
            const facts = [];
            if (d.Git_Environment__c) {
                facts.push({ key: 'e', label: ' · env ', value: d.Git_Environment__c });
            } else if (d.Branch__c) {
                facts.push({ key: 'b', label: ' · branch ', value: d.Branch__c });
            }
            if (into) {
                facts.push({ key: 'i', label: ' → ', value: into });
            }
            return {
                id: d.Id,
                name: d.Name,
                status: d.Status__c || 'Not checked',
                statusCls: STATUS_CLS[d.Status__c] || STATUS_CLS['Not checked'],
                kind: o.Is_Sandbox__c ? 'Developer sandbox' : 'Developer org',
                facts
            };
        });
    }
    get stageChips() {
        const last = this.stages.length - 1;
        return this.stages.map((s, i) => ({
            id: s.Id,
            name: s.Name,
            branch: s.Branch__c || 'no branch',
            status: s.Status__c || 'Not checked',
            statusCls: STATUS_CLS[s.Status__c] || STATUS_CLS['Not checked'],
            kind: s.Role__c === 'Hub' ? 'Production (this hub)' : 'Stage ' + (i + 1),
            extra: this.approvalText(this.orgFor(s)),
            arrow: i < last,
            cantUp: i === 0 || s.Role__c === 'Hub' || !this.isAdmin,
            cantDown: i >= last || s.Role__c === 'Hub' || (this.stages[i + 1] && this.stages[i + 1].Role__c === 'Hub') || !this.isAdmin,
            upLabel: 'Move ' + s.Name + ' earlier',
            downLabel: 'Move ' + s.Name + ' later'
        }));
    }

    /** Where releases into the stage are approved, for its route card. */
    approvalText(o) {
        const ap = approvals(o);
        const where = [];
        if (ap.sf) {
            where.push('Salesforce');
        }
        if (ap.slack && this.slackAvailable) {
            where.push('Slack');
        }
        let text = 'Approved in ' + (where.length ? where.join(' or ') : 'Salesforce');
        if (ap.git && this.showGitReview) {
            text += ' · ' + this.gitProviderName.trim() + ' reviewers';
        }
        if (o.Hotfix_Two_Approvers__c === true) {
            text += ' · hotfixes: 2 approvers';
        }
        return text;
    }

    // ---------- back promote (optional, off by default) ----------

    /** The hub's name (production), for the back promote wording. */
    get hubName() {
        const hub = this.stages.find((s) => s.Role__c === 'Hub') || this.orgs.find((o) => o.Role__c === 'Hub');
        return hub ? hub.Name : 'production';
    }
    get bpOrgs() { return (this.backPromote && this.backPromote.orgs) || []; }
    get bpEnabled() { return !!(this.backPromote && this.backPromote.enabled); }
    get bpIsAdmin() { return !!(this.backPromote && this.backPromote.isAdmin) && this.isAdmin; }
    get bpCantToggle() { return !this.bpIsAdmin || this.bpBusy; }
    get bpPill() { return this.bpEnabled ? 'On' : 'Off by default'; }
    get bpPillCls() { return this.bpEnabled ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none'; }
    get bpToggleLabel() { return 'Send ' + this.hubName + '\'s changes to other orgs after a deploy'; }
    get bpHelpLead() { return 'Register an org with the role '; }
    get bpHelpTail() {
        return ', then choose when it gets ' + this.hubName + '\'s changes. Metadata only: users and records in that org stay as they are.';
    }
    get bpNoOrgs() { return this.bpOrgs.length === 0; }

    /** Dashed nodes after the hub on the route: "Back promote · matches <hub>" or "· n releases behind". */
    get backPromoteNodes() {
        return this.bpOrgs.map((b) => ({ key: 'bp-' + b.orgId, name: b.name, text: 'Back promote · ' + this.behindText(b) }));
    }
    get hasBackPromoteNodes() { return this.backPromoteNodes.length > 0; }
    get bpRouteNote() {
        return 'Dashed: orgs that receive ' + this.hubName + '\'s changes after a deploy. They never send changes up the route.';
    }

    behindText(b) {
        const n = b.behind || 0;
        return n ? n + (n === 1 ? ' release behind' : ' releases behind') : 'matches ' + this.hubName;
    }

    get bpWhenOptions() {
        return [
            { label: 'After every ' + this.hubName + ' deploy', value: 'After_Deploy' },
            { label: 'When an admin clicks Sync now', value: 'Manual' }
        ];
    }

    /** What the Back promote org card shows: When, Approve before syncing, how far behind, Sync now. */
    bpCard(o) {
        const b = this.bpOrgs.find((x) => x.orgId === o.Id) || { orgId: o.Id, whenValue: o.Back_Promote_When__c, approval: o.Back_Promote_Approval__c === true, behind: 0 };
        const busy = this.bpBusyId === o.Id;
        const behind = b.behind || 0;
        const approval = b.approval === true;
        let lastText = '';
        if (b.syncedOn || b.syncStatus) {
            lastText = 'Last sync' + (b.syncedOn ? ' ' + new Date(b.syncedOn).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '');
        }
        return {
            whenValue: b.whenValue || 'Manual',
            approval,
            approvalText: approval ? 'On: an approver approves each sync first' : 'Off: ' + this.hubName + '\'s approval is enough',
            behindPill: behind ? this.behindText(b) : 'Matches ' + this.hubName,
            behindCls: behind ? 'rr-pill rr-pill-wait' : 'rr-pill rr-pill-ok',
            behindNames: (b.behindNames || []).join(', '),
            lastText,
            syncStatus: b.syncStatus || '',
            syncCls: SYNC_STATUS_CLS[b.syncStatus] || 'rr-pill rr-pill-none',
            offNote: this.bpEnabled ? '' : 'Back promote is off. Switch it on in the Back promote card to sync this org.',
            cantEdit: !this.bpIsAdmin || busy,
            cantSync: !this.bpIsAdmin || busy || !this.bpEnabled,
            syncLabel: busy ? 'Starting…' : 'Sync now',
            groupLabel: 'When ' + o.Name + ' gets ' + this.hubName + '\'s changes'
        };
    }

    handleBackPromoteToggle(event) {
        const state = event.target.checked ? 'on' : 'off';
        this.bpBusy = true;
        setBackPromote({ state })
            .then((bp) => {
                this.backPromote = bp;
                this.toast('Back promote ' + (bp && bp.enabled ? 'on' : 'off'), 'success');
            })
            .catch((e) => {
                this.toast(errorText(e), 'error');
                return this.readBackPromote().then((bp) => {
                    this.backPromote = bp;
                });
            })
            .finally(() => {
                this.bpBusy = false;
            });
    }

    handleBpWhen(event) {
        this.saveBp(event.target.dataset.id, { whenValue: event.detail.value });
    }

    handleBpApproval(event) {
        this.saveBp(event.target.dataset.id, { approval: event.target.checked });
    }

    /** Saves one back promote org's When and Approve before syncing (saveBackPromoteOrg returns the board again). */
    saveBp(orgId, changes) {
        const b = this.bpOrgs.find((x) => x.orgId === orgId) || {};
        const settings = { orgId, whenValue: b.whenValue || 'Manual', approval: b.approval === true, ...changes };
        this.backPromote = { ...this.backPromote, orgs: this.bpOrgs.map((x) => (x.orgId === orgId ? { ...x, ...changes } : x)) };
        this.bpBusyId = orgId;
        saveBackPromoteOrg({ settingsJson: JSON.stringify(settings) })
            .then((bp) => {
                this.backPromote = bp;
                this.toast((b.name || 'Org') + ': back promote saved', 'success');
            })
            .catch((e) => {
                this.toast(errorText(e), 'error');
                return this.readBackPromote().then((bp) => {
                    this.backPromote = bp;
                });
            })
            .finally(() => {
                this.bpBusyId = undefined;
            });
    }

    handleSyncNow(event) {
        const orgId = event.currentTarget.dataset.id;
        const b = this.bpOrgs.find((x) => x.orgId === orgId) || {};
        this.bpBusyId = orgId;
        syncNow({ orgId })
            .then(() => {
                this.toast((b.name || 'Org') + (b.approval ? ': sync waiting for approval' : ': sync started'), 'success');
                return this.readBackPromote().then((bp) => {
                    this.backPromote = bp;
                });
            })
            .catch((e) => this.toast(errorText(e), 'error'))
            .finally(() => {
                this.bpBusyId = undefined;
            });
    }

    startRouteEdit() {
        this.editingRoute = true;
    }

    cancelRouteEdit() {
        this.load();
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
        const ap = approvals(o);
        // An org saved before environments existed has none: show the picker empty rather than the new-org default.
        this.form = { ...blankForm(), Environment__c: null, ...o, Approve_In_Salesforce__c: ap.sf, Approve_In_Slack__c: ap.slack, Require_Git_Review__c: ap.git };
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
        // The hub is the production org.
        if (field === 'Role__c' && value === 'Hub') {
            next.Environment__c = 'Production';
        }
        this.form = next;
        this.formError = undefined;
    }

    get formTitle() { return this.form.Id ? '2 · Edit ' + this.form.Name : '2 · Register an org'; }

    /** The masked hint of the saved consumer key (the key itself never comes to the page). */
    get savedKeyHint() { return this.form.Id ? this.keyHints[this.form.Id] : null; }
    get keyRequired() { return !this.savedKeyHint; }
    get keyPlaceholder() {
        const saved = this.savedKeyHint;
        return saved ? 'Saved (ends ••••' + saved.slice(-4) + '). Leave blank to keep it.' : '';
    }
    get saveLabel() { return this.saving ? 'Saving…' : 'Save org'; }

    handleSave() {
        // A blank consumer key isn't sent, so an edit keeps the saved one.
        const keys = ['Id', 'Name', 'Role__c', 'Environment__c', 'My_Domain__c', 'Login_Type__c', 'Username__c', 'Consumer_Key__c',
            'Certificate__c', 'Git_Environment__c', 'Branch__c', 'Approve_In_Salesforce__c', 'Approve_In_Slack__c',
            'Require_Git_Review__c', 'Slack_Channel__c', 'Slack_Post__c', 'Hotfix_Two_Approvers__c'];
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
