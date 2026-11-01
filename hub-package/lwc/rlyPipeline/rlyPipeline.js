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
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';

const LOGIN_OPTIONS = [
    { label: 'Production or Developer Edition', value: 'Production' },
    { label: 'Sandbox', value: 'Sandbox' }
];
const LOGIN_LABELS = LOGIN_OPTIONS.reduce((m, o) => ({ ...m, [o.value]: o.label }), {});
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
/** The org's own fields saveOrg takes (the consumer key is sent only when one is typed). */
const ORG_FIELDS = ['Name', 'Role__c', 'Environment__c', 'My_Domain__c', 'Login_Type__c', 'Username__c', 'Certificate__c', 'Git_Environment__c', 'Branch__c'];
/** A change to any of these (or a new consumer key) tests the sign-in again after Save. */
const SIGN_IN_FIELDS = ['My_Domain__c', 'Login_Type__c', 'Username__c', 'Certificate__c'];
const GIT_STATUS_CLS = { Connected: 'rr-pill rr-pill-ok', Failed: 'rr-pill rr-pill-bad', 'Not checked': 'rr-pill rr-pill-none' };
const READONLY_CLS = 'slds-form-element slds-form-element_readonly rr-ro-item';
/** RLY_Org__c.Approval_Rule__c: when a release into the org needs a person to approve it. */
const RULE_ALWAYS = 'Always';
const RULE_SELECTED = 'Selected_Types';
const RULE_NEVER = 'Never';
const APPROVAL_RULES = [
    { value: RULE_ALWAYS, label: 'Always' },
    { value: RULE_SELECTED, label: 'Only when the release contains…' },
    { value: RULE_NEVER, label: 'Never: deploy when the checks pass' }
];
/** RLY_Org__c.Approval_Types__c: the kinds of change that need approval under Selected_Types. */
const APPROVAL_TYPES = [
    { value: 'Apex', label: 'Apex classes and triggers' },
    { value: 'Flows', label: 'Flows' },
    { value: 'Profiles_Permissions', label: 'Profiles and permission sets' },
    { value: 'Objects_Fields', label: 'Objects and fields' },
    { value: 'Deletions', label: 'Deletions' },
    { value: 'Manual_Steps', label: 'Manual steps' },
    { value: 'Hotfix', label: 'Hotfixes' },
    { value: 'Other', label: 'Anything else' }
];
const HUB_NEVER_TEXT = 'Production always needs approval: pick Always or Only when…';
const NO_TYPE_TEXT = 'Tick at least one kind of change.';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function blankForm() {
    return {
        Id: null, Name: '', Role__c: 'Developer', Environment__c: 'Developer', My_Domain__c: '', Login_Type__c: 'Production',
        Username__c: '', Consumer_Key__c: '', Certificate__c: 'release_relay', Git_Environment__c: '', Branch__c: '',
        Approve_In_Salesforce__c: true, Approve_In_Slack__c: false, Require_Git_Review__c: false, Slack_Channel__c: '', Slack_Post__c: false,
        Hotfix_Two_Approvers__c: false, Approval_Rule__c: RULE_ALWAYS, approvalTypes: []
    };
}

/** The org's approval rule; an org saved before rules existed always needs approval. */
function ruleOf(o) {
    const v = o && o.Approval_Rule__c;
    return v === RULE_SELECTED || v === RULE_NEVER ? v : RULE_ALWAYS;
}

/** The ticked kinds of change (multi-select picklist "Apex;Flows") as a list, in the picklist's order. */
function typesOf(o) {
    const raw = (o && o.Approval_Types__c) || '';
    const picked = String(raw).split(';').map((t) => t.trim());
    return APPROVAL_TYPES.map((t) => t.value).filter((v) => picked.includes(v));
}

/** The approval rule as one line on the org card. */
function ruleText(o) {
    const rule = ruleOf(o);
    if (rule === RULE_SELECTED) {
        const labels = typesOf(o).map((v) => APPROVAL_TYPES.find((t) => t.value === v).label);
        return 'Only when the release contains: ' + (labels.length ? labels.join(', ') : 'nothing ticked yet');
    }
    return APPROVAL_RULES.find((r) => r.value === rule).label;
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

/** One read-only label/value pair on a card (slds-form-element_readonly). */
function fact(key, label, value, opts) {
    const o = opts || {};
    const has = value !== null && value !== undefined && String(value).trim() !== '';
    return {
        key, label, isFlag: false,
        value: has ? value : (o.empty || 'Not set'),
        valueCls: (o.mono && has ? 'rr-mono rr-break' : 'rr-break') + (has ? '' : ' rr-weak'),
        cls: READONLY_CLS + (o.wide ? ' rr-ro-wide' : ''),
        hint: o.hint || ''
    };
}

/** One read-only switch on a card: a check and "On", or a dash and "Off". */
function flag(key, label, on, hint) {
    return { key, label, isFlag: true, on: on === true, value: on === true ? 'On' : 'Off', cls: READONLY_CLS, hint: hint || '' };
}

function trimOrNull(v) {
    if (typeof v !== 'string') {
        return v === undefined ? null : v;
    }
    const t = v.trim();
    return t === '' ? null : t;
}

export default class RlyPipeline extends LightningElement {
    /** RlyHubGuard.getHubStatus: whether this org is a sandbox copy of the hub (then a banner, and the actions are off). */
    hubStatus;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }

    /** Reads the hub status once. A failed read shows nothing: the server refuses the actions anyway. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            });
    }

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
    checkingId;
    showSetup = false;
    providerOptions = PROVIDERS.map((p) => ({ label: p.label, value: p.value }));
    git;
    gitBusy = false;
    developers = [];
    stages = [];
    warnings = [];
    routeDirty = false;
    routeBusy = false;
    editingRoute = false;
    slackAvailable = false;
    gitProviderName;
    slack = { isAdmin: false, events: [], allEvents: [], approvers: [] };
    slackBusy = false;
    slackTesting = false;
    showApprovers = false;
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
    bpBusyId;

    // The Edit modal: every card is read-only; Edit (or Register an org) opens one modal with that card's settings.
    /** Which modal is open: org, git, slack or backPromote (undefined when none). */
    modalKind;
    modalError;
    saving = false;
    focusModal = false;
    /** The org being edited as the page has it (undefined when registering a new one). */
    modalOrg;
    form = blankForm();
    bounced = false;
    /** The Approval rule's error under the radio group ("Tick at least one kind of change."). */
    ruleError;
    bpForm = { whenValue: 'Manual', approval: false };
    gitForm = blankGit();
    slackForm = { enabled: false, signingSecret: '', events: [] };
    memberEdits = {};
    bpSwitch = false;

    connectedCallback() {
        this.readHubStatus();
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
        if (this.focusModal) {
            const first = this.template.querySelector('.rr-modal .rr-first');
            if (first) {
                first.focus();
                this.focusModal = false;
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

    // ---------- cards (read-only) ----------

    get hasOrgs() { return this.orgs.length > 0; }
    get noOrgs() { return !this.loading && this.orgs.length === 0; }

    get cards() {
        return [...this.orgs]
            .sort((a, b) => (ROLE_ORDER[a.Role__c] - ROLE_ORDER[b.Role__c]) || (this.routeIndex(a) - this.routeIndex(b)) || a.Name.localeCompare(b.Name))
            .map((o) => {
                const isDeveloper = o.Role__c === 'Developer';
                const isHub = o.Role__c === 'Hub';
                const isBackPromote = o.Role__c === BACK_PROMOTE;
                const isTarget = !isDeveloper && !isBackPromote;
                const ap = approvals(o);
                const busy = this.orgSlackBusyId === o.Id;
                const bp = isBackPromote ? this.bpCard(o) : null;
                return {
                    ...o,
                    statusText: o.Status__c || 'Not checked',
                    statusCls: STATUS_CLS[o.Status__c] || STATUS_CLS['Not checked'],
                    rolePill: this.rolePill(o),
                    rolePillCls: isHub ? 'rr-pill rr-pill-info' : 'rr-pill rr-pill-none',
                    facts: this.orgFacts(o),
                    settings: this.orgSettings(o, { isDeveloper, isTarget, isBackPromote, ap, bp }),
                    checkedText: o.Last_Checked__c ? 'Checked ' + new Date(o.Last_Checked__c).toLocaleString([], {
                        month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not checked yet',
                    messageCls: o.Status__c === 'Failed' ? 'rr-msg rr-msg-bad rr-pad' : 'rr-msg rr-msg-info rr-pad',
                    checking: this.checkingId === o.Id,
                    cantCheck: this.checkingId === o.Id || this.hubCopy,
                    checkLabel: this.checkingId === o.Id ? 'Signing in…' : 'Test sign-in',
                    editLabel: 'Edit ' + o.Name,
                    isDeveloper,
                    isBackPromote,
                    isOrg: true,
                    bp,
                    sectTitle: this.sectTitle(o, isDeveloper),
                    cantTest: !this.isAdmin || busy || this.slackBusy || this.hubCopy || !(o.Slack_Channel__c || '').trim(),
                    showHubNote: isTarget && this.slackSetUp && !ap.slack && !!o.Slack_Post__c,
                    showEvents: this.slackSetUp && !isDeveloper && (!!o.Slack_Post__c || ap.slack),
                    showDevNote: this.slackSetUp && isDeveloper,
                    showSect: !isDeveloper || this.slackSetUp
                };
            });
    }

    /** Sign-in and environment facts for an org card. */
    orgFacts(o) {
        const facts = [
            fact('env', 'Salesforce environment', ENVIRONMENT_LABELS[o.Environment__c]),
            fact('branch', 'Branch', o.Branch__c, { mono: true }),
            fact('genv', 'Git environment', o.Git_Environment__c, { mono: true }),
            fact('login', 'Login type', LOGIN_LABELS[o.Login_Type__c]),
            fact('domain', 'My Domain', o.My_Domain__c, { mono: true, wide: true }),
            fact('user', 'Integration username', o.Username__c, { mono: true, wide: true })
        ];
        if (o.Role__c === 'Hub') {
            facts.push(fact('deploy', 'Deploys with', 'This org (the hub)'));
        } else {
            let how;
            if (o.Source_Tracking__c === 'Available') {
                how = 'Fast: source tracking';
            } else if (o.Source_Tracking__c === 'Not available') {
                how = 'Metadata API';
            }
            facts.push(fact('deploy', 'Deploys with', how, { empty: 'Known after a sign-in' }));
            facts.push(fact('api', 'API version', o.Api_Version__c, { empty: 'Known after a sign-in' }));
        }
        return facts;
    }

    /** Approval, Slack and back promote settings for an org card, as text. */
    orgSettings(o, c) {
        const list = [];
        if (c.isTarget) {
            list.push(fact('rule', 'Approval rule', ruleText(o), { wide: true }));
            list.push(flag('asf', 'Approve in Salesforce', c.ap.sf || !(this.slackAvailable && c.ap.slack)));
            if (this.slackAvailable) {
                list.push(flag('asl', 'Approve in Slack', c.ap.slack));
            }
            if (this.showGitReview) {
                list.push(flag('git', 'Also require ' + this.gitProviderName.trim() + ' reviewers', c.ap.git));
            }
            list.push(flag('two', 'Hotfixes need 2 approvers', o.Hotfix_Two_Approvers__c === true,
                o.Hotfix_Two_Approvers__c === true ? 'Two different approvers, and the person who raised the hotfix can\'t approve it.' : ''));
        }
        if (c.isBackPromote && c.bp) {
            const when = this.bpWhenOptions.find((w) => w.value === c.bp.whenValue);
            list.push(fact('bpw', 'When', when ? when.label : c.bp.whenValue));
            list.push(flag('bpa', 'Approve before syncing', c.bp.approval, c.bp.approvalText));
        }
        if (this.slackSetUp) {
            list.push(fact('ch', 'Slack channel', o.Slack_Channel__c, { mono: true, empty: 'None' }));
            list.push(flag('post', c.isDeveloper ? 'Also post here' : 'Post to Slack', !!o.Slack_Post__c));
        }
        return list;
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

    get eventsText() {
        if (!this.slack.enabled) {
            return 'Slack is off for the hub.';
        }
        const events = this.slack.events || [];
        return 'Events: ' + (events.length ? events.join(' · ') : 'none');
    }

    handleOrgSlackTest(event) {
        const o = this.orgs.find((x) => x.Id === event.currentTarget.dataset.id);
        this.orgSlackBusyId = o.Id;
        this.runSlack(sendSlackTest({ channel: (o.Slack_Channel__c || '').trim() }), 'test').finally(() => {
            this.orgSlackBusyId = undefined;
        });
    }

    applySetup(s) {
        this.git = s.git;
        // Back promote orgs are drawn after the hub (backPromoteNodes); they aren't stages or developer orgs.
        this.developers = (s.developers || []).filter((o) => o.Role__c !== BACK_PROMOTE);
        this.stages = (s.stages || []).filter((o) => o.Role__c !== BACK_PROMOTE);
        this.warnings = s.warnings || [];
        this.routeDirty = false;
        this.editingRoute = false;
    }

    // ---------- Git connection (read-only card) ----------

    get hasGit() { return !!this.git; }
    get noGit() { return !this.git; }
    get gitStatus() { return (this.git && this.git.Status__c) || 'Not checked'; }
    /** A short one-line result goes in the pill, as on the board; anything longer stays in the message below. */
    get gitShortMessage() {
        const m = (this.git && this.git.Status_Message__c) || '';
        return this.gitStatus === 'Connected' && m && m.length <= 80 && !m.includes('\n') ? m : '';
    }
    get gitStatusText() { return this.gitShortMessage || this.gitStatus; }
    get gitStatusCls() { return GIT_STATUS_CLS[this.gitStatus] || GIT_STATUS_CLS['Not checked']; }
    get gitMessage() { return this.git && !this.gitShortMessage ? this.git.Status_Message__c : null; }
    get gitMessageCls() { return this.git && this.git.Status__c === 'Failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-info'; }
    get gitCheckLabel() { return this.gitBusy ? 'Testing…' : 'Test connection'; }

    /** What the Git connection card shows, as text. */
    get gitFacts() {
        const g = this.git || {};
        const p = PROVIDERS.find((x) => x.value === g.Provider__c) || PROVIDERS[0];
        const scanOn = g.Code_Scan__c !== false;
        return [
            fact('prov', 'Provider', p.label + ' · ' + p.how),
            fact('repo', 'Repository', g.Repository__c, { mono: true }),
            fact('cred', 'Named Credential (token)', g.Named_Credential__c, { mono: true }),
            fact('pipe', p.pipeLabel, g.Pipeline__c, { mono: true }),
            fact('pb', 'Pipeline branch', g.Pipeline_Branch__c, { mono: true }),
            fact('src', 'Source path', g.Source_Path__c, { mono: true }),
            flag('scan', 'Code scan', scanOn, scanOn ? 'On for every ' + (g.Provider__c === 'GitLab' ? 'merge request' : 'pull request') : '')
        ];
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
    get filesCantUpdate() { return this.filesBusy || this.hubCopy || !this.hasFilesToChange; }
    get filesCantOpen() { return this.filesBusy || this.hubCopy; }
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
    get routeCantSave() { return this.routeBusy || this.hubCopy || !this.routeDirty; }
    /** Git sign-in check and Create missing branches: off while one runs, and on a sandbox copy of the hub. */
    get gitCantAct() { return this.gitBusy || this.hubCopy; }
    get slackCantTest() { return this.slackBusy || this.hubCopy; }
    get modalCantSave() { return this.saving || this.hubCopy; }

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
    get bpPill() { return this.bpEnabled ? 'On' : 'Off by default'; }
    get bpPillCls() { return this.bpEnabled ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none'; }
    get bpToggleLabel() { return 'Send ' + this.hubName + '\'s changes to other orgs after a deploy'; }
    get bpFacts() { return [flag('bp', this.bpToggleLabel, this.bpEnabled)]; }
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

    /** The org's back promote settings as getBackPromote has them. */
    bpFor(o) {
        return this.bpOrgs.find((x) => x.orgId === o.Id) || { orgId: o.Id, whenValue: o.Back_Promote_When__c, approval: o.Back_Promote_Approval__c === true, behind: 0 };
    }

    /** What the back promote org card shows: When, Approve before syncing, how far behind, Sync now. */
    bpCard(o) {
        const b = this.bpFor(o);
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
            approvalText: approval ? 'An approver approves each sync first.' : this.hubName + '\'s approval is enough.',
            behindPill: behind ? this.behindText(b) : 'Matches ' + this.hubName,
            behindCls: behind ? 'rr-pill rr-pill-wait' : 'rr-pill rr-pill-ok',
            behindNames: (b.behindNames || []).join(', '),
            lastText,
            syncStatus: b.syncStatus || '',
            syncCls: SYNC_STATUS_CLS[b.syncStatus] || 'rr-pill rr-pill-none',
            offNote: this.bpEnabled ? '' : 'Back promote is off. Switch it on in the Back promote card to sync this org.',
            cantSync: !this.bpIsAdmin || busy || !this.bpEnabled || this.hubCopy,
            syncLabel: busy ? 'Starting…' : 'Sync now'
        };
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

    // ---------- route ----------

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

    // ---------- Slack connection (read-only card) ----------

    applySlack(sl) {
        this.slack = sl || { isAdmin: false, events: [], allEvents: [], approvers: [] };
    }

    get showSlack() { return this.isAdmin && this.slack.isAdmin; }
    /** Slack is optional: until it's connected or switched on, the org cards show only Approved in. */
    get slackSetUp() { return !!(this.slack.connected || this.slack.enabled); }
    get slackNotSetUp() { return !this.slackSetUp; }
    get slackStatus() { return this.slack.status || 'Not set up'; }
    get slackStatusCls() {
        if (this.slackStatus === 'Connected') {
            return 'rr-pill rr-pill-ok';
        }
        return this.slackStatus.startsWith('Error') ? 'rr-pill rr-pill-bad' : 'rr-pill rr-pill-none';
    }
    get slackTestLabel() { return this.slackTesting ? 'Testing…' : 'Test'; }
    /** The secret itself never comes to the page: only a masked hint of the saved one. */
    get slackSecretText() {
        const hint = this.slack.signingSecretHint;
        return hint ? 'Signing secret ' + hint.charAt(0).toLowerCase() + hint.slice(1) : 'No signing secret saved yet';
    }
    get slackSecretPlaceholder() { return this.slack.signingSecretHint ? this.slack.signingSecretHint + '. Leave blank to keep it.' : ''; }
    get approversText() { return (this.slack.approversLinked || 0) + ' of ' + (this.slack.approversTotal || 0); }
    get approversToggleLabel() { return this.showApprovers ? 'Hide approvers' : 'Show approvers'; }

    /** What the Slack connection card shows, as text. */
    get slackFacts() {
        const events = this.slack.events || [];
        return [
            flag('on', 'Slack', !!this.slack.enabled),
            fact('ws', 'Workspace', this.slack.workspace, { empty: 'Not connected yet' }),
            fact('tok', 'Bot token', 'Named Credential RLY_Slack', { mono: true, hint: 'Token kept by Salesforce, never shown' }),
            fact('site', 'Approve in Slack', this.slack.actionsUrl ? 'Site: ' + this.slack.actionsUrl : '', { mono: true, empty: 'No Site set up yet', hint: this.slackSecretText }),
            fact('ev', 'Send a message when a release is', events.join(' · '), { empty: 'No events', wide: true }),
            fact('ap', 'Approvers linked', this.approversText)
        ];
    }

    get approverRows() {
        return (this.slack.approvers || []).map((a) => {
            const edited = this.memberEdits[a.userId];
            const memberId = edited !== undefined ? edited : (a.slackMemberId || '');
            return {
                ...a,
                memberId,
                memberText: a.slackMemberId || 'Not linked',
                linked: !!a.slackMemberId,
                inputLabel: 'Slack member ID for ' + a.name
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

    toggleApprovers() {
        this.showApprovers = !this.showApprovers;
    }

    handleSlackConnTest() {
        this.slackTesting = true;
        this.runSlack(testSlack(), 'check').finally(() => {
            this.slackTesting = false;
        });
    }

    /** Runs a Slack check or test message (kind check or test: which toast to show). Resolves true when it worked. */
    runSlack(call, kind) {
        this.slackBusy = true;
        return call
            .then((sl) => {
                this.applySlack(sl);
                if (kind === 'check') {
                    this.toast('Slack: ' + (sl.status || 'checked'), sl.status === 'Connected' ? 'success' : 'error');
                } else {
                    const failed = (sl.lastResult || '').startsWith('Failed');
                    this.toast(failed ? 'Slack: ' + sl.lastResult : 'Test message sent to Slack', failed ? 'error' : 'success');
                }
                return true;
            })
            .catch((e) => {
                this.toast(errorText(e), 'error');
                return false;
            })
            .finally(() => {
                this.slackBusy = false;
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

    // ---------- the Edit modal ----------

    get modalOpen() { return !!this.modalKind; }
    get isOrgModal() { return this.modalKind === 'org'; }
    get isGitModal() { return this.modalKind === 'git'; }
    get isSlackModal() { return this.modalKind === 'slack'; }
    get isBpModal() { return this.modalKind === 'backPromote'; }
    get modalCls() { return this.isOrgModal ? 'slds-modal slds-fade-in-open slds-modal_medium rr-modal' : 'slds-modal slds-fade-in-open rr-modal'; }
    get modalTitle() {
        if (this.isOrgModal) {
            return this.modalOrg ? 'Edit ' + this.modalOrg.Name : 'Register an org';
        }
        if (this.isGitModal) {
            return 'Edit Git connection';
        }
        if (this.isSlackModal) {
            return 'Edit Slack connection';
        }
        return 'Edit Back promote';
    }
    get modalSub() {
        if (this.isOrgModal) {
            return this.modalOrg ? 'Nothing changes until you press Save.' : 'Save signs in and reads the Org Id, sandbox name and Metadata API version.';
        }
        if (this.isGitModal) {
            return 'One Git connection for the whole pipeline. Save tests the connection.';
        }
        return 'Nothing changes until you press Save.';
    }
    get saveLabel() { return this.saving ? 'Saving…' : 'Save'; }

    openModal(kind) {
        this.modalKind = kind;
        this.modalError = undefined;
        this.focusModal = true;
    }

    closeModal() {
        if (!this.saving) {
            this.modalKind = undefined;
            this.modalError = undefined;
        }
    }

    handleModalKey(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.closeModal();
        }
    }

    /** Every required field in the modal filled in; shows the field errors when not. */
    modalValid() {
        const fields = [...this.template.querySelectorAll('.rr-modal lightning-input, .rr-modal lightning-combobox')];
        return fields.reduce((ok, f) => f.reportValidity() && ok, true);
    }

    finishSave(message, reload) {
        this.modalKind = undefined;
        this.modalError = undefined;
        this.toast(message, 'success');
        return reload ? this.load() : null;
    }

    // ----- org -----

    startAdd() {
        this.modalOrg = undefined;
        this.form = blankForm();
        this.bounced = false;
        this.ruleError = undefined;
        this.openModal('org');
    }

    handleEdit(event) {
        const o = this.orgs.find((x) => x.Id === event.currentTarget.dataset.id);
        if (!o) {
            return;
        }
        const ap = approvals(o);
        const b = this.bpFor(o);
        this.modalOrg = o;
        // An org saved before environments existed has none: show the picker empty rather than the new-org default.
        this.form = {
            ...blankForm(), Environment__c: null, ...o, Consumer_Key__c: '',
            Approve_In_Salesforce__c: ap.sf || !(this.slackAvailable && ap.slack), Approve_In_Slack__c: ap.slack, Require_Git_Review__c: ap.git,
            Slack_Channel__c: o.Slack_Channel__c || '', Slack_Post__c: !!o.Slack_Post__c, Hotfix_Two_Approvers__c: o.Hotfix_Two_Approvers__c === true,
            Approval_Rule__c: ruleOf(o), approvalTypes: typesOf(o)
        };
        this.ruleError = undefined;
        this.bpForm = { whenValue: b.whenValue || 'Manual', approval: b.approval === true };
        this.bounced = false;
        this.openModal('org');
    }

    get formIsDeveloper() { return this.form.Role__c === 'Developer'; }
    get formIsBackPromote() { return this.form.Role__c === BACK_PROMOTE; }
    get formIsTarget() { return !this.formIsDeveloper && !this.formIsBackPromote; }
    get formOrgName() { return (this.form.Name || '').trim() || 'this org'; }
    get formTwoApproverLabel() { return 'Hotfixes into ' + this.formOrgName + ' need 2 approvers'; }
    get formTwoApproverOn() { return this.form.Hotfix_Two_Approvers__c === true; }
    get formGitReviewLabel() { return 'Also require ' + (this.gitProviderName || '').trim() + ' reviewers before deploying'; }
    get formApproveGroupLabel() { return 'Where releases into ' + this.formOrgName + ' are approved'; }
    get formShowApproveHelp() { return this.slackAvailable || this.bounced; }
    get formApproveHelpCls() { return this.bounced ? 'rr-msg rr-msg-wait' : 'rr-kicker'; }
    get formPostLabel() { return this.formIsDeveloper ? 'Also post here' : 'Post to Slack'; }
    get formSlackHelp() {
        return this.formIsDeveloper
            ? 'A release posts its card in the target\'s channel. A developer org can also get a copy, so the people working in ' + this.formOrgName + ' see their own releases.'
            : 'Releases into ' + this.formOrgName + ' post their card in this channel.';
    }
    get formShowSlack() { return this.slackSetUp; }

    // Approval rule (board HubApprovalFlowsEvidence 1): Always / Only when the release contains… / Never.
    get formIsHub() { return this.form.Role__c === 'Hub'; }
    get formRuleSelected() { return this.form.Approval_Rule__c === RULE_SELECTED; }
    get formRuleOptions() {
        const org = this.formOrgName;
        const help = {
            [RULE_ALWAYS]: 'Every release into ' + org + ' waits for an approver.',
            [RULE_SELECTED]: 'Ask for approval only if the release has one of the ticked kinds of change.',
            [RULE_NEVER]: this.formIsHub ? HUB_NEVER_TEXT : 'The scan, check-only deploy and tests still have to pass.'
        };
        return APPROVAL_RULES.map((r) => {
            const disabled = r.value === RULE_NEVER && this.formIsHub;
            return {
                ...r,
                help: help[r.value],
                checked: this.form.Approval_Rule__c === r.value,
                disabled,
                cls: 'rr-opt' + (disabled ? ' rr-opt-off' : ''),
                helpCls: disabled ? 'rr-msg rr-msg-wait' : 'rr-kicker',
                showTypes: r.value === RULE_SELECTED && this.form.Approval_Rule__c === RULE_SELECTED
            };
        });
    }
    get formTypeOptions() {
        const picked = this.form.approvalTypes || [];
        return APPROVAL_TYPES.map((t) => ({ ...t, checked: picked.includes(t.value) }));
    }
    get formTypesLabel() { return 'Kinds of change that need approval in ' + this.formOrgName; }

    handleRule(event) {
        this.form = { ...this.form, Approval_Rule__c: event.target.value };
        this.ruleError = undefined;
    }

    handleRuleType(event) {
        const value = event.target.dataset.value;
        const rest = (this.form.approvalTypes || []).filter((v) => v !== value);
        const next = event.target.checked ? [...rest, value] : rest;
        this.form = { ...this.form, approvalTypes: APPROVAL_TYPES.map((t) => t.value).filter((v) => next.includes(v)) };
        this.ruleError = undefined;
    }

    /** Selected_Types needs a ticked kind; the hub (production) can't be Never. */
    ruleValid() {
        if (!this.formIsTarget) {
            return true;
        }
        if (this.formRuleSelected && !(this.form.approvalTypes || []).length) {
            this.ruleError = NO_TYPE_TEXT;
            return false;
        }
        if (this.formIsHub && this.form.Approval_Rule__c === RULE_NEVER) {
            this.ruleError = HUB_NEVER_TEXT;
            return false;
        }
        this.ruleError = undefined;
        return true;
    }
    /** Back promote settings belong to a registered back promote org (getBackPromote has it). */
    get formShowBp() { return this.formIsBackPromote && !!this.form.Id && this.bpIsAdmin; }
    get formBpNew() { return this.formIsBackPromote && !this.form.Id; }
    get formBpGroupLabel() { return 'When ' + this.formOrgName + ' gets ' + this.hubName + '\'s changes'; }

    /** The masked hint of the saved consumer key (the key itself never comes to the page). */
    get savedKeyHint() { return this.form.Id ? this.keyHints[this.form.Id] : null; }
    get keyRequired() { return !this.savedKeyHint; }
    get keyPlaceholder() {
        const saved = this.savedKeyHint;
        return saved ? 'Saved (ends ••••' + saved.slice(-4) + '). Leave blank to keep it.' : '';
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
            if (next.Approval_Rule__c === RULE_NEVER) {
                next.Approval_Rule__c = RULE_ALWAYS;
            }
        }
        this.form = next;
        this.modalError = undefined;
    }

    handleFormToggle(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.checked };
    }

    /** Approve in Salesforce / in Slack: either is enough, and the last one on can't be switched off. */
    handleApproveToggle(event) {
        const field = event.target.dataset.field;
        const next = { ...this.form, [field]: event.target.checked };
        if (!next.Approve_In_Salesforce__c && !(this.slackAvailable && next.Approve_In_Slack__c)) {
            event.target.checked = true;
            this.bounced = true;
            return;
        }
        this.bounced = false;
        this.form = next;
    }

    handleBpWhen(event) {
        this.bpForm = { ...this.bpForm, whenValue: event.detail.value };
    }

    handleBpApproval(event) {
        this.bpForm = { ...this.bpForm, approval: event.target.checked };
    }

    /** The org as saveOrg takes it: sign-in, approval, Slack and two-approver fields; a blank consumer key keeps the saved one. */
    orgPayload() {
        const f = this.form;
        const payload = {};
        if (f.Id) {
            payload.Id = f.Id;
        }
        ORG_FIELDS.forEach((k) => {
            payload[k] = trimOrNull(f[k]);
        });
        const key = (f.Consumer_Key__c || '').trim();
        if (key) {
            payload.Consumer_Key__c = key;
        }
        payload.Approve_In_Salesforce__c = f.Approve_In_Salesforce__c === true;
        payload.Approve_In_Slack__c = f.Approve_In_Slack__c === true;
        payload.Require_Git_Review__c = f.Require_Git_Review__c === true;
        payload.Slack_Channel__c = trimOrNull(f.Slack_Channel__c);
        payload.Slack_Post__c = f.Slack_Post__c === true;
        payload.Hotfix_Two_Approvers__c = f.Hotfix_Two_Approvers__c === true;
        if (this.formIsTarget) {
            const rule = f.Approval_Rule__c || RULE_ALWAYS;
            payload.Approval_Rule__c = rule;
            payload.Approval_Types__c = rule === RULE_SELECTED ? (f.approvalTypes || []).join(';') : null;
        }
        return payload;
    }

    /** A new org, a new consumer key or a changed sign-in field: test the sign-in after Save. */
    signInChanged(payload) {
        const before = this.modalOrg;
        return !before || !!payload.Consumer_Key__c || SIGN_IN_FIELDS.some((k) => (payload[k] || null) !== (before[k] || null));
    }

    bpChanged() {
        const b = this.bpFor(this.modalOrg);
        return (b.whenValue || 'Manual') !== this.bpForm.whenValue || (b.approval === true) !== this.bpForm.approval;
    }

    saveOrgModal() {
        const ruleOk = this.ruleValid();
        if (!this.modalValid() || !ruleOk) {
            return;
        }
        const payload = this.orgPayload();
        const check = this.signInChanged(payload);
        const saveBp = this.formShowBp && this.bpChanged();
        const name = payload.Name || 'Org';
        this.saving = true;
        this.modalError = undefined;
        saveOrg({ orgJson: JSON.stringify(payload) })
            .then((id) => {
                const orgId = payload.Id || id;
                if (!saveBp) {
                    return orgId;
                }
                const settings = { orgId, whenValue: this.bpForm.whenValue, approval: this.bpForm.approval };
                return saveBackPromoteOrg({ settingsJson: JSON.stringify(settings) }).then(() => orgId);
            })
            .then((orgId) => {
                this.saving = false;
                return this.finishSave(name + ': saved', true).then(() => (check && orgId ? this.runCheck(orgId) : null));
            })
            .catch((e) => {
                this.modalError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Git connection -----

    openGitEdit() {
        this.gitForm = this.git ? { ...blankGit(), ...this.git } : blankGit();
        this.openModal('git');
    }

    get providerTiles() {
        const current = this.gitForm.Provider__c || 'GitHub';
        return PROVIDERS.map((p, i) => ({
            ...p,
            pressed: p.value === current ? 'true' : 'false',
            cls: (p.value === current ? 'rr-prov rr-prov-on' : 'rr-prov') + (i === 0 ? ' rr-first' : '')
        }));
    }
    get gitProvider() { return PROVIDERS.find((p) => p.value === (this.gitForm.Provider__c || 'GitHub')) || PROVIDERS[0]; }
    get scanHelp() { return 'When on, every ' + (this.gitForm.Provider__c === 'GitLab' ? 'merge request' : 'pull request') + ' is scanned.'; }

    pickProvider(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.gitForm.Provider__c) {
            return;
        }
        const p = PROVIDERS.find((x) => x.value === value);
        this.gitForm = { ...this.gitForm, Provider__c: value, Named_Credential__c: p.cred, Pipeline__c: p.pipe };
        this.modalError = undefined;
    }

    handleGitField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }
        this.gitForm = { ...this.gitForm, [field]: value };
        this.modalError = undefined;
    }

    saveGitModal() {
        if (!this.modalValid()) {
            return;
        }
        const f = this.gitForm;
        const payload = {
            Provider__c: f.Provider__c, Repository__c: (f.Repository__c || '').trim(), Named_Credential__c: (f.Named_Credential__c || '').trim(),
            Pipeline__c: (f.Pipeline__c || '').trim(), Pipeline_Branch__c: (f.Pipeline_Branch__c || '').trim(),
            Source_Path__c: (f.Source_Path__c || '').trim(), Code_Scan__c: f.Code_Scan__c !== false
        };
        this.saving = true;
        this.modalError = undefined;
        saveGit({ gitJson: JSON.stringify(payload) })
            .then(() => {
                this.saving = false;
                // The provider or branch may have changed: read the pipeline files' versions again.
                this.pipeFiles = undefined;
                return this.finishSave('Git connection saved', true).then(() => this.runGitCheck());
            })
            .catch((e) => {
                this.modalError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Slack connection -----

    openSlackEdit() {
        this.slackForm = { enabled: !!this.slack.enabled, signingSecret: '', events: [...(this.slack.events || [])] };
        this.memberEdits = {};
        this.openModal('slack');
    }

    handleSlackEnabled(event) {
        const enabled = event.target.checked;
        // Switched on with no events chosen: every event, as the hub does.
        const events = enabled && this.slackForm.events.length === 0 ? [...(this.slack.allEvents || [])] : this.slackForm.events;
        this.slackForm = { ...this.slackForm, enabled, events };
        this.modalError = undefined;
    }

    handleSlackSecret(event) {
        this.slackForm = { ...this.slackForm, signingSecret: event.target.value };
        this.modalError = undefined;
    }

    handleSlackEvents(event) {
        this.slackForm = { ...this.slackForm, events: event.detail.value };
    }

    handleMemberInput(event) {
        this.memberEdits = { ...this.memberEdits, [event.target.dataset.id]: event.target.value };
    }

    /** Saves the Slack settings, then each approver whose member ID changed (saveSlackMember, one at a time). */
    saveSlackModal() {
        const secret = (this.slackForm.signingSecret || '').trim();
        if (/\s/.test(secret)) {
            this.modalError = 'The signing secret has no spaces: copy it again from the Slack app (Basic Information).';
            return;
        }
        const settings = { enabled: this.slackForm.enabled, events: this.slackForm.events, signingSecret: secret };
        const members = (this.slack.approvers || [])
            .filter((a) => this.memberEdits[a.userId] !== undefined && this.memberEdits[a.userId].trim() !== (a.slackMemberId || ''))
            .map((a) => ({ userId: a.userId, memberId: this.memberEdits[a.userId].trim() }));
        this.saving = true;
        this.modalError = undefined;
        saveSlack({ settingsJson: JSON.stringify(settings) })
            .then((sl) => {
                this.applySlack(sl);
                return members.reduce((p, m) => p.then(() => saveSlackMember(m)).then((s2) => this.applySlack(s2)), Promise.resolve());
            })
            .then(() => {
                this.saving = false;
                this.memberEdits = {};
                return this.finishSave('Slack settings saved', true);
            })
            .catch((e) => {
                this.modalError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Back promote switch -----

    openBpEdit() {
        this.bpSwitch = this.bpEnabled;
        this.openModal('backPromote');
    }

    handleBpSwitch(event) {
        this.bpSwitch = event.target.checked;
    }

    saveBpModal() {
        this.saving = true;
        this.modalError = undefined;
        setBackPromote({ state: this.bpSwitch ? 'on' : 'off' })
            .then((bp) => {
                this.backPromote = bp;
                this.saving = false;
                return this.finishSave('Back promote ' + (bp && bp.enabled ? 'on' : 'off'), true);
            })
            .catch((e) => {
                this.modalError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    handleModalSave() {
        if (this.isOrgModal) {
            this.saveOrgModal();
        } else if (this.isGitModal) {
            this.saveGitModal();
        } else if (this.isSlackModal) {
            this.saveSlackModal();
        } else if (this.isBpModal) {
            this.saveBpModal();
        }
    }

    // ---------- setup help ----------

    toggleSetup() {
        this.showSetup = !this.showSetup;
    }

    get setupLabel() { return this.showSetup ? 'Hide setup steps' : 'Setup steps for a new org'; }
    get remoteSite() { return (this.isOrgModal && this.form.My_Domain__c) || 'https://<that org>.my.salesforce.com'; }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: APP_NAME, message, variant }));
    }
}
