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
import readRepoSettings from '@salesforce/apex/RlyRepoSettings.read';
import getSetupStatus from '@salesforce/apex/RlySetupStatus.getSetupStatus';
import saveBotToken from '@salesforce/apex/RlySlackController.saveBotToken';
import IS_ADMIN from '@salesforce/customPermission/RLY_Admin';
import LightningConfirm from 'lightning/confirm';

/** Modes of RlyHubGuard.getHubStatus in which this tab shows only the org gate. */
const SANDBOX_MODES = ['sandbox', 'copy'];

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
    { label: 'Azure DevOps', value: 'AzureDevOps', how: 'Azure Pipeline', repo: 'organization/project/repository', pipeLabel: 'Pipeline id', pipe: '12', cred: 'RLY_AzureDevOps' }
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
/** The approval rule as radio cards (short labels; the card's help says the rest). */
const RULE_CARD_LABELS = { [RULE_ALWAYS]: 'Always', [RULE_SELECTED]: 'Only when it contains…', [RULE_NEVER]: 'Never' };
const HUB_NEVER_TEXT = 'Production always needs approval: pick Always or Only when it contains…';
const NO_TYPE_TEXT = 'Pick at least one kind of change.';
/** RLY_Org__c.Code_Scan__c: follow the Git connection's switch (default), always scan, or don't scan. */
const SCAN_FOLLOW = 'Follow';
const SCAN_ALWAYS = 'On';
const SCAN_NEVER = 'Off';
const SCAN_CHOICES = [SCAN_FOLLOW, SCAN_ALWAYS, SCAN_NEVER];
const SCAN_ORG_HINT = 'Each org can follow this or set its own.';
/** The repository's per-org values and quality gates (read-only cards, edited in Git). */
const VALUES_PATH = '.relay/values.json';
const GATES_PATH = '.relay/gates.json';
/** Values longer than this show the first 12 and last 4 characters (the full value on hover). */
const VALUE_MAX = 24;
/** An org card's sections, in order; each has its own Edit. */
const SECTION_TITLES = { signin: 'Sign-in', approval: 'Approval', bp: 'Back promote', slack: 'Slack' };
const NEW_ORG = 'new';
/** The org window's Edit: every section of the org at once (editing = org:<Id>:all). */
const ALL_SECTIONS = 'all';
/** Sign-in status as a dot on the compact org cards. */
const DOT_CLS = { Connected: 'rr-dot rr-dot-ok', Failed: 'rr-dot rr-dot-bad', Refreshed: 'rr-dot rr-dot-wait' };
/** Connected orgs: one tab per Salesforce environment (RLY_Org__c.Environment__c); an org without one goes under Other. */
const OTHER_TAB = 'Not set';
/** The page's sections, in order; each folds open or closed. Section 1 and Connected orgs start open. */
const FOLD_DEFAULTS = { git: true, route: false, values: false, gates: false, slack: false, orgs: true };
/** Where this browser remembers which sections are open, and the last Connected orgs tab (per viewer, best effort). */
const FOLD_STORE = 'rly.pipeline.sections';
const TAB_STORE = 'rly.pipeline.orgTab';
const BOT_TOKEN_PREFIX = 'xoxb-';
/** Where an admin puts the Slack bot token when this org can't save it from the page. */
const TOKEN_SETUP_URL = '/lightning/setup/NamedCredential/home';
const TOKEN_SETUP_TEXT = 'Put the bot token in Setup → Named Credentials → External Credentials → RLY_Slack → Principals → Bot → Token.';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/** A new org: every text field empty (the inputs show grey hints); the approval settings start as Always, in Salesforce. */
function blankForm() {
    return {
        Id: null, Name: '', Role__c: null, Environment__c: null, My_Domain__c: '', Login_Type__c: null,
        Username__c: '', Consumer_Key__c: '', Certificate__c: '', Git_Environment__c: '', Branch__c: '',
        Approve_In_Salesforce__c: true, Approve_In_Slack__c: false, Require_Git_Review__c: false, Slack_Channel__c: '', Slack_Post__c: false,
        Hotfix_Two_Approvers__c: false, Approval_Rule__c: RULE_ALWAYS, approvalTypes: [], Code_Scan__c: SCAN_FOLLOW
    };
}

/** The org's code scan choice; an org saved before the choice existed follows the Git connection. */
function scanChoiceOf(o) {
    const v = o && o.Code_Scan__c;
    return SCAN_CHOICES.includes(v) ? v : SCAN_FOLLOW;
}

/** A long value as its first 12 and last 4 characters. */
function shortValue(v) {
    return v.length > VALUE_MAX ? v.slice(0, 12) + '…' + v.slice(-4) : v;
}

/** A file's page on the Git provider (the pipeline branch), from the connection's provider and repository. */
function repoFileUrl(git, branch, filePath) {
    const repo = ((git && git.Repository__c) || '').trim();
    if (!repo || !branch) {
        return null;
    }
    const enc = (p) => p.split('/').map(encodeURIComponent).join('/');
    const parts = repo.split('/');
    switch (git.Provider__c) {
        case 'GitLab':
            return 'https://gitlab.com/' + enc(repo) + '/-/blob/' + enc(branch) + '/' + enc(filePath);
        case 'Bitbucket':
            return 'https://bitbucket.org/' + enc(repo) + '/src/' + enc(branch) + '/' + enc(filePath);
        case 'AzureDevOps':
            return parts.length === 3
                ? 'https://dev.azure.com/' + enc(parts[0]) + '/' + enc(parts[1]) + '/_git/' + encodeURIComponent(parts[2])
                    + '?path=/' + enc(filePath) + '&version=GB' + encodeURIComponent(branch)
                : null;
        default:
            return 'https://github.com/' + enc(repo) + '/blob/' + enc(branch) + '/' + enc(filePath);
    }
}

/** Production or Sandbox, read from the My Domain when no login type was chosen. */
function loginFor(domain) {
    return /\.sandbox\.my\.salesforce\.com/i.test(domain || '') ? 'Sandbox' : 'Production';
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

/** A new Git connection: empty fields with grey hints; the code scan starts on. */
function blankGit() {
    return {
        Provider__c: 'GitHub', Repository__c: '', Named_Credential__c: '', Pipeline__c: '',
        Pipeline_Branch__c: '', Source_Path__c: '', Code_Scan__c: true
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

/** The sections' open / closed choice this browser remembers; the defaults when it has none or storage is blocked. */
function readFolds() {
    try {
        const raw = window.localStorage.getItem(FOLD_STORE);
        const saved = raw ? JSON.parse(raw) : {};
        const folds = { ...FOLD_DEFAULTS };
        Object.keys(FOLD_DEFAULTS).forEach((k) => {
            if (saved && typeof saved[k] === 'boolean') {
                folds[k] = saved[k];
            }
        });
        return folds;
    } catch {
        return { ...FOLD_DEFAULTS };
    }
}

function writeFolds(folds) {
    try {
        window.localStorage.setItem(FOLD_STORE, JSON.stringify(folds));
    } catch {
        // Storage blocked (private window, previews): the choice then lasts for this page only.
    }
}

/** The Connected orgs tab this browser last used (undefined when none or storage is blocked). */
function readTab() {
    try {
        return window.localStorage.getItem(TAB_STORE) || undefined;
    } catch {
        return undefined;
    }
}

function writeTab(value) {
    try {
        window.localStorage.setItem(TAB_STORE, value);
    } catch {
        // Storage blocked: the tab is remembered for this page only.
    }
}

/** "1 value", "2 values". */
function countText(n, word) {
    return n + ' ' + word + (n === 1 ? '' : 's');
}

function trimOrNull(v) {
    if (typeof v !== 'string') {
        return v === undefined ? null : v;
    }
    const t = v.trim();
    return t === '' ? null : t;
}

export default class RlyPipeline extends LightningElement {
    /**
     * RlyHubGuard.getHubStatus: the org's mode. In a sandbox or a sandbox copy of the hub this tab shows only rlyOrgGate
     * (admins also get the override switch on it) and loads nothing else. In production not set up yet, admins get the
     * first-run setup (rlySetupWizard) with the rest of the page hidden while it's needed; other users get the gate.
     */
    hubStatus;
    /** The status has been read, or failed to read (then the tab works as on the hub: the server refuses actions anyway). */
    statusRead = false;
    /** The page's data has been asked for once. */
    pageLoaded = false;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    get hubMode() { return (this.hubStatus && this.hubStatus.mode) || ''; }
    get isSetupMode() { return this.hubMode === 'setup'; }
    get gated() { return SANDBOX_MODES.includes(this.hubMode) || (this.isSetupMode && !IS_ADMIN); }
    get showPage() { return this.statusRead && !this.gated; }
    get canSwitchSandbox() { return !!IS_ADMIN; }
    /** Production not set up: the wizard alone, until the hub and the Git connection are saved (or the admin hides it). */
    get showRest() {
        const live = this.setupStatus;
        return !(this.isSetupMode && this.showWizard && !this.editing && !(live && live.needsSetup === false));
    }

    /** Reads the hub status once, then loads the page unless only the gate shows. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            })
            .finally(() => {
                this.statusRead = true;
                this.loadPageOnce();
            });
    }

    loadPageOnce() {
        if (this.gated || this.pageLoaded) {
            return;
        }
        this.pageLoaded = true;
        this.readSetupStatus();
        this.load();
    }

    /** The gate turned the sandbox override on or off: show what the new status allows. */
    handleStatusChange(event) {
        this.hubStatus = event.detail;
        this.loadPageOnce();
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

    // Edit in place (board HubPipelineSections): every section is read-only; Edit turns only that section into a form,
    // with Cancel / Save inside it. One section at a time.
    /** What is being edited: git, slack, bp, new (Register an org), or org:<Id>:<signin|approval|bp|slack>; undefined when nothing. */
    editing;
    editError;
    saving = false;
    focusEdit = false;
    /** The org being edited as the page has it (undefined when registering a new one). */
    editOrg;
    /** Register an org goes Sign-in → Approval → (Back promote) → Slack: the org being walked through, after its first save. */
    flowOrgId;
    form = blankForm();
    bounced = false;
    /** The Approval rule's error under the rule cards ("Pick at least one kind of change."). */
    ruleError;
    bpForm = { whenValue: 'Manual', approval: false };
    gitForm = blankGit();
    slackForm = { enabled: false, signingSecret: '', botToken: '', events: [] };
    slackAdvanced = false;
    memberEdits = {};
    bpSwitch = false;
    /** saveBotToken said this org can't keep the token from the page: show the Setup path instead of the field. */
    tokenNote;
    /** RlySetupStatus.getSetupStatus: the first-run setup shows while the hub has no Git connection or no Hub org. */
    setupStatus;
    wizardOpen = false;
    // Per-org values and quality gates (RlyRepoSettings.read), read again when the repository or branch changes.
    repoSettings;
    repoLoading = false;
    repoKey;
    /** Which sections are open (remembered in this browser). */
    folds = readFolds();
    /** Connected orgs: the tab the user last picked (undefined: the tab with Stage 1). */
    orgTab = readTab();
    /** The tab to focus after an arrow key. */
    focusTab;
    /** The card just registered or saved: it lights up once. */
    flashId;
    /** The org whose window is open (read mode, or Edit for all its sections). */
    dialogOrgId;
    focusDialog = false;
    /** The card whose window just closed: the focus goes back to it. */
    focusTileId;
    /** The forms as they were when Edit or Register opened them (Escape asks before dropping changes). */
    formSnapshot;
    confirming = false;

    connectedCallback() {
        this.readHubStatus();
    }

    renderedCallback() {
        if (this.focusFiles) {
            const close = this.template.querySelector('.rr-files-close');
            if (close) {
                close.focus();
                this.focusFiles = false;
            }
        }
        if (this.focusDialog) {
            const close = this.template.querySelector('.rr-modal-close');
            if (close) {
                close.focus();
            }
            this.focusDialog = false;
        }
        if (this.focusTab) {
            const tab = this.template.querySelector('button[data-value="' + this.focusTab + '"]');
            if (tab) {
                tab.focus();
            }
            this.focusTab = undefined;
        }
        if (this.focusTileId) {
            const tile = this.template.querySelector('c-rly-org-tile[data-id="' + this.focusTileId + '"]');
            if (tile) {
                tile.focus();
            }
            this.focusTileId = undefined;
        }
        if (this.focusEdit) {
            // One try, right after Edit: the section's first field (or the first provider tile).
            const first = this.template.querySelector('.rr-edit .rr-first');
            if (first) {
                first.focus();
            }
            this.focusEdit = false;
        }
    }

    /** Opens the first-run setup when the hub isn't set up yet. A failed read shows the page as it is. */
    readSetupStatus() {
        getSetupStatus()
            .then((s) => {
                this.setupStatus = s;
                this.wizardOpen = !!(s && s.needsSetup);
            })
            .catch(() => {
                this.setupStatus = undefined;
            });
    }

    // ---------- first-run setup ----------

    get showWizard() { return this.isAdmin && this.wizardOpen; }
    get wizardLabel() { return this.wizardOpen ? 'Hide setup' : 'Set up ' + APP_NAME; }

    toggleWizard() {
        this.wizardOpen = !this.wizardOpen;
    }

    handleWizardClose() {
        this.wizardOpen = false;
        this.load();
    }

    handleWizardChanged() {
        this.load();
        this.refreshSetupStatus();
    }

    /** After a wizard step saves: whether setup is still needed (the rest of the page shows once it isn't). */
    refreshSetupStatus() {
        getSetupStatus()
            .then((s) => {
                this.setupStatus = s;
            })
            .catch(() => {
                this.setupStatus = undefined;
            });
    }

    handleWizardRegister() {
        if (!this.editing) {
            this.startAdd();
        }
    }

    handleWizardSlack() {
        if (!this.editing) {
            this.openSlackEdit();
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
                this.loadRepoSettings();
                this.openAttention();
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
    get noOrgs() { return !this.loading && this.orgs.length === 0 && this.editing !== NEW_ORG; }

    /** An org as its window shows it: its pills, and its sections (Sign-in, Approval or Back promote, Slack), read-only. */
    orgCard(o) {
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
            statusMessage: o.Status_Message__c || '',
            checkedText: o.Last_Checked__c ? 'Checked ' + new Date(o.Last_Checked__c).toLocaleString([], {
                month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not checked yet',
            messageCls: o.Status__c === 'Failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-info',
            checking: this.checkingId === o.Id,
            cantCheck: this.checkingId === o.Id || this.hubCopy,
            checkLabel: this.checkingId === o.Id ? 'Checking…' : 'Check connection',
            isDeveloper,
            isBackPromote,
            bp,
            sections: this.orgSections(o, { isDeveloper, isTarget, isBackPromote, ap, bp }),
            cantTest: !this.isAdmin || busy || this.slackBusy || this.hubCopy || !(o.Slack_Channel__c || '').trim(),
            showHubNote: isTarget && this.slackSetUp && !ap.slack && !!o.Slack_Post__c,
            showEvents: this.slackSetUp && !isDeveloper && (!!o.Slack_Post__c || ap.slack),
            showDevNote: this.slackSetUp && isDeveloper
        };
    }

    /** Some section of this org is being edited. */
    isEditingOrg(orgId) { return !!this.editing && this.editing.startsWith('org:' + orgId + ':'); }

    // ---------- sections that fold (board HubPipelineLayout) ----------

    /** The section being edited stays open and can't fold (chevron off until Cancel / Save). */
    isLocked(key) {
        return (key === 'git' && (this.isGitEditing || this.isBpEditing)) || (key === 'route' && this.editingRoute)
            || (key === 'slack' && this.isSlackEditing);
    }

    /** A section is open when the user left it open (or it needs attention), or while something in it is being edited. */
    isOpen(key) { return this.isLocked(key) || this.folds[key] === true; }

    handleFold(event) {
        const key = event.currentTarget.dataset.key;
        if (this.isLocked(key)) {
            return;
        }
        this.folds = { ...this.folds, [key]: !this.isOpen(key) };
        writeFolds(this.folds);
    }

    /** A section with a Failed / Not found pill or warnings opens on load, even if it was left closed (not remembered). */
    openAttention() {
        const need = {
            git: this.gitStatus === 'Failed' || this.filesPill === 'Not found' || !!this.pipeFilesError,
            route: this.hasWarnings,
            values: !!this.valuesError,
            gates: !!this.gatesError,
            slack: this.slackStatus.startsWith('Error')
        };
        const keys = Object.keys(need).filter((k) => need[k] && this.folds[k] !== true);
        if (keys.length) {
            const next = { ...this.folds };
            keys.forEach((k) => {
                next[k] = true;
            });
            this.folds = next;
        }
    }

    /** Each section's open state, chevron, one-line summary (shown while closed) and status pill. */
    get fold() {
        const list = [
            { key: 'git', title: '1 · Where the code lives', summary: this.gitSummary, pill: this.gitStatusText, pillCls: this.gitStatusCls },
            { key: 'route', title: '2 · Route', summary: this.routeSummary },
            { key: 'values', title: 'Per-org values', summary: this.valuesSummary, pill: this.missingText, pillCls: 'rr-pill rr-pill-wait' },
            { key: 'gates', title: 'Quality gates', summary: this.gatesSummary },
            { key: 'slack', title: 'Slack connection', summary: this.slackSummary, pill: this.slackStatus, pillCls: this.slackStatusCls },
            { key: 'orgs', title: 'Connected orgs', summary: this.orgsSummary }
        ];
        const out = {};
        list.forEach((s) => {
            const open = this.isOpen(s.key);
            out[s.key] = {
                title: s.title,
                summary: s.summary,
                pill: open ? '' : (s.pill || ''),
                pillCls: s.pillCls || 'rr-pill rr-pill-none',
                open,
                closed: !open,
                locked: this.isLocked(s.key),
                expanded: open ? 'true' : 'false',
                headCls: open ? 'rr-sh rr-sh-open' : 'rr-sh',
                foldLabel: (open ? 'Collapse ' : 'Expand ') + s.title
            };
        });
        return out;
    }

    get gitSummary() {
        if (!this.git) {
            return 'No Git connection yet';
        }
        const p = PROVIDERS.find((x) => x.value === this.git.Provider__c) || PROVIDERS[0];
        const parts = [p.label, this.git.Repository__c || 'no repository', this.gitStatus];
        if (this.backPromote) {
            parts.push('Back promote ' + (this.bpEnabled ? 'on' : 'off'));
        }
        return parts.join(' · ');
    }

    get routeSummary() {
        if (!this.hasRoute) {
            return 'No route yet';
        }
        const names = this.stages.map((s) => s.Name);
        const branches = this.stages.map((s) => s.Branch__c || 'no branch');
        if (this.developers.length) {
            names.unshift(this.developers.map((d) => d.Name).join(', '));
            branches.unshift(this.developers.map((d) => d.Branch__c || 'no branch').join(', '));
        }
        const bp = this.bpOrgs.length;
        return [names.join(' → '), 'branches ' + branches.join(' → '),
            bp ? countText(bp, 'back promote org') : 'no back promote orgs'].join(' · ');
    }

    /** The route orgs' cells without a value (the grey extra columns don't count). */
    get missingValues() {
        if (!this.repoOk) {
            return 0;
        }
        const cols = this.valueColumns.filter((c) => !c.cls);
        const keys = new Set(cols.map((c) => c.key));
        return this.valueRows.reduce((n, r) => n + r.cells.filter((c) => keys.has(c.key) && !c.has).length, 0);
    }
    get missingText() { return this.missingValues ? countText(this.missingValues, 'missing value') : ''; }

    /** "3 names · A, B, C · from main · read 10:41 AM", or why it wasn't read. */
    get valuesSummary() {
        if (!this.repoRead) {
            return 'Reading the repository…';
        }
        if (this.repoMessage || this.valuesError) {
            return this.repoMessage || this.valuesError;
        }
        const names = (this.repoSettings.values || []).map((v) => v.name);
        if (!names.length) {
            return 'No per-org values yet · ' + this.repoReadText;
        }
        return [countText(names.length, 'name'), names.join(', '), this.repoReadText].join(' · ');
    }

    /** "3 of 4 set · what each set gate says · from main". */
    get gatesSummary() {
        if (!this.repoRead) {
            return 'Reading the repository…';
        }
        if (this.repoMessage || this.gatesError) {
            return this.repoMessage || this.gatesError;
        }
        const gates = this.repoSettings.gates || [];
        if (!gates.length) {
            return 'No quality gates yet · Salesforce\'s own rules still apply';
        }
        const set = gates.filter((g) => g.isSet);
        return [set.length + ' of ' + gates.length + ' set', ...set.map((g) => g.text), this.gatesReadText].filter((v) => !!v).join(' · ');
    }

    get slackSummary() {
        return [
            'Slack ' + (this.slack.enabled ? 'on' : 'off'),
            this.tokenSaved ? 'bot token saved' : 'no bot token yet',
            this.approveInSlackReady ? 'Approve in Slack set up' : 'Approve in Slack not set up',
            this.approversText + ' approvers linked'
        ].join(' · ');
    }

    get orgsSummary() {
        if (!this.orgs.length) {
            return 'No orgs registered yet';
        }
        const connected = this.orgs.filter((o) => o.Status__c === 'Connected').length;
        const failed = this.orgs.filter((o) => o.Status__c === 'Failed').length;
        return countText(this.orgs.length, 'org') + ' · ' + connected + ' connected' + (failed ? ' · ' + failed + ' failed' : '');
    }
    get orgsCountText() { return countText(this.orgs.length, 'org'); }

    // ---------- Connected orgs: tabs by Salesforce environment, compact cards ----------

    /** The environment tab an org belongs to (Not set when it has none). */
    tabOf(o) { return o && ENVIRONMENT_LABELS[o.Environment__c] ? o.Environment__c : OTHER_TAB; }

    /** One compact card: name, role, sign-in, branch, "Approval: … · Code scan: …" (developer orgs: Raises into …), last checked. */
    orgTile(o) {
        let approvalText;
        if (o.Role__c === 'Developer') {
            const first = this.stages.find((s) => s.Role__c !== 'Hub') || this.stages[0];
            approvalText = first ? 'Raises into ' + (first.Branch__c || first.Name) : 'Raises releases';
        } else if (o.Role__c === BACK_PROMOTE) {
            const b = this.bpFor(o);
            const when = this.bpWhenOptions.find((w) => w.value === (b.whenValue || 'Manual'));
            approvalText = 'Back promote · ' + (when ? when.label : 'Manual');
        } else {
            approvalText = RULE_CARD_LABELS[ruleOf(o)] + ' · Code scan: ' + this.scanShort(o);
        }
        return {
            id: o.Id,
            name: o.Name,
            domain: o.My_Domain__c || '',
            rolePill: this.rolePill(o),
            roleCls: o.Role__c === 'Hub' ? 'rr-pill rr-pill-info' : 'rr-pill rr-pill-none',
            statusText: o.Status__c || 'Not checked',
            dotCls: DOT_CLS[o.Status__c] || 'rr-dot',
            branch: o.Branch__c || 'No branch',
            branchCls: o.Branch__c ? 'rr-mono' : 'rr-weak',
            approvalText,
            checkedText: o.Last_Checked__c ? 'Checked ' + new Date(o.Last_Checked__c).toLocaleString([], {
                month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : 'Not checked yet',
            openLabel: 'Open ' + o.Name + ' to see or edit it',
            flash: this.flashId === o.Id
        };
    }

    /** The org's code scan choice in a few words, for its compact card. */
    scanShort(o) {
        const choice = scanChoiceOf(o);
        if (choice === SCAN_ALWAYS) {
            return 'Always';
        }
        if (choice === SCAN_NEVER) {
            return 'Don\'t scan';
        }
        return 'Follows Git (' + (this.gitScanOn ? 'on' : 'off') + ')';
    }

    /** Every environment tab in the picklist's order (empty ones grey but clickable), then Not set only when an org has none. */
    get orgGroups() {
        const sorted = [...this.orgs].sort((a, b) => (ROLE_ORDER[a.Role__c] - ROLE_ORDER[b.Role__c])
            || (this.routeIndex(a) - this.routeIndex(b)) || a.Name.localeCompare(b.Name));
        const values = ENVIRONMENT_OPTIONS.map((e) => e.value);
        if (sorted.some((o) => this.tabOf(o) === OTHER_TAB)) {
            values.push(OTHER_TAB);
        }
        const active = this.orgTabValue;
        return values.map((v) => {
            const list = sorted.filter((o) => this.tabOf(o) === v);
            const name = ENVIRONMENT_LABELS[v] || OTHER_TAB;
            const selected = v === active;
            let cls = 'slds-tabs_default__item rr-tab';
            cls += selected ? ' slds-is-active' : '';
            cls += list.length ? '' : ' rr-tab-zero';
            return {
                value: v,
                name,
                count: list.length,
                cls,
                selected: selected ? 'true' : 'false',
                tabIndex: selected ? '0' : '-1',
                tabId: 'rr-tab-' + v,
                tiles: list.map((o) => this.orgTile(o))
            };
        });
    }

    /** The open tab: the user's last pick, else the tab with Stage 1, else the hub's, else the first that has orgs. */
    get orgTabValue() {
        const values = [...ENVIRONMENT_OPTIONS.map((e) => e.value), OTHER_TAB];
        if (this.orgTab && values.includes(this.orgTab) && (this.orgTab !== OTHER_TAB || this.orgs.some((o) => this.tabOf(o) === OTHER_TAB))) {
            return this.orgTab;
        }
        const firstStage = this.stages[0] && this.orgs.find((o) => o.Id === this.stages[0].Id);
        const lead = firstStage || this.orgs.find((o) => o.Role__c === 'Hub') || this.orgs[0];
        return lead ? this.tabOf(lead) : values[0];
    }
    get activeGroup() { return this.orgGroups.find((g) => g.selected === 'true') || { tiles: [], name: '', value: '' }; }
    get activeTabEmpty() { return this.activeGroup.tiles.length === 0; }
    get activeTabEmptyText() { return 'No orgs in ' + this.activeGroup.name + ' yet.'; }
    get activeTabId() { return this.activeGroup.tabId; }
    get registerTileHint() {
        const v = this.activeGroup.value;
        return v && v !== OTHER_TAB ? 'Opens with ' + this.activeGroup.name + ' chosen' : 'Choose its Salesforce environment';
    }

    pickTab(value) {
        this.orgTab = value;
        this.flashId = undefined;
        writeTab(value);
    }

    handleOrgTab(event) {
        this.pickTab(event.currentTarget.dataset.value);
    }

    /** Arrow keys, Home and End move between the tabs (and select them), as SLDS tabs do. */
    handleTabKey(event) {
        const values = this.orgGroups.map((g) => g.value);
        const i = values.indexOf(this.orgTabValue);
        const moves = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: values.length - 1 };
        if (!(event.key in moves)) {
            return;
        }
        event.preventDefault();
        const j = (moves[event.key] + values.length) % values.length;
        this.pickTab(values[j]);
        this.focusTab = values[j];
    }

    // ---------- the org window (read mode; Edit turns every section into a form) ----------

    openOrgDialog(event) {
        const id = event.detail && event.detail.id;
        if (!id || this.editing) {
            return;
        }
        this.dialogOrgId = id;
        this.flashId = undefined;
        this.focusDialog = true;
    }

    /** The window shows: registering an org (one step at a time), or a saved org (read mode or editing all of it). */
    get modalOpen() { return this.inFlow || (!!this.dialogOrgId && !!this.dialogOrg); }
    get modalEditing() { return this.inFlow || this.editingKind === ALL_SECTIONS; }
    get modalReading() { return !this.modalEditing; }
    get modalEditAll() { return this.editingKind === ALL_SECTIONS; }
    get dialogOrg() {
        const o = this.orgs.find((x) => x.Id === this.dialogOrgId);
        return o ? this.orgCard(o) : null;
    }
    get modalTitle() {
        if (this.inFlow) {
            return 'Register an org';
        }
        const name = this.dialogOrg ? this.dialogOrg.Name : this.formOrgName;
        return this.modalEditAll ? 'Edit ' + name : name;
    }
    /** "Full Copy sandbox · branch sit · Checked Nov 1, 9:58 AM" (in Edit: "… · saved values shown"). */
    get modalSub() {
        const o = this.dialogOrg;
        if (this.inFlow || !o) {
            return '';
        }
        const parts = [ENVIRONMENT_LABELS[o.Environment__c] || 'Salesforce environment not set', 'branch ' + (o.Branch__c || 'not set')];
        parts.push(this.modalEditAll ? 'saved values shown' : o.checkedText);
        return parts.join(' · ');
    }
    get showModalPills() { return !this.inFlow && !!this.dialogOrg; }
    get dialogHasSlack() { return !!this.dialogOrg && this.slackSetUp; }
    get modalCantTest() { return !this.dialogOrg || this.dialogOrg.cantCheck || this.modalEditing; }
    get modalFootNote() {
        if (this.modalEditAll) {
            return 'Saves all sections together. Changing Sign-in tests it again.';
        }
        return this.editNote;
    }

    /** Register an org: the steps as chips (1 Sign-in · 2 Approval · 3 Slack), the one being done in blue. */
    get flowSteps() {
        const at = this.flowIndex;
        return this.flowKinds.map((k, i) => ({
            key: k,
            label: (i + 1) + ' ' + SECTION_TITLES[k],
            cls: i === at ? 'rr-stp rr-stp-on' : 'rr-stp',
            current: i === at ? 'step' : 'false'
        }));
    }

    /** The forms in the window: the register step being done, or every section of the org (they follow the Role chosen). */
    get formSections() {
        const kinds = this.modalEditAll ? this.flowKindsFor(this.form.Role__c) : [this.editingKind];
        return kinds.map((kind, i) => ({
            key: 'form-' + kind,
            kind,
            title: SECTION_TITLES[kind],
            cls: 'rr-msect rr-edit' + (i === 0 ? ' rr-msect-first' : ''),
            isSignin: kind === 'signin',
            isApproval: kind === 'approval',
            isBp: kind === 'bp',
            isSlack: kind === 'slack'
        }));
    }

    /** Edit in the org window: every section becomes a form, with one Cancel / Save. */
    handleDialogEdit() {
        if (this.editLocked || !this.dialogOrgId) {
            return;
        }
        this.beginSection(this.dialogOrgId, ALL_SECTIONS);
    }

    /** What the forms hold now, to tell whether anything was changed. */
    formState() { return JSON.stringify({ f: this.form, b: this.bpForm }); }
    get formDirty() { return this.modalEditing && this.formState() !== this.formSnapshot; }

    /** Resolves true when the window may drop what is typed: nothing changed, or the user says to discard it. */
    askDiscard() {
        if (!this.formDirty) {
            return Promise.resolve(true);
        }
        this.confirming = true;
        return LightningConfirm.open({
            label: 'Discard changes?',
            message: 'You changed ' + this.formOrgName + '. Discard the changes?',
            theme: 'warning'
        }).then((ok) => ok === true).catch(() => false).finally(() => {
            this.confirming = false;
        });
    }

    /** ×: closes the window (asks first when something typed would be lost); the focus goes back to the org's card. */
    handleModalClose() {
        if (this.saving || this.confirming) {
            return;
        }
        this.askDiscard().then((ok) => {
            if (ok) {
                this.closeModal();
            }
        });
    }

    /** Close: a form being filled is dropped; the focus goes back to the org's card. */
    closeModal() {
        if (this.saving) {
            return;
        }
        if (this.modalEditing) {
            this.endEdit();
        }
        this.focusTileId = this.dialogOrgId;
        this.dialogOrgId = undefined;
    }

    /** Escape = Cancel: in Edit back to read mode, otherwise the window closes; asks first when changes would be lost. */
    handleModalKey(event) {
        if (event.key !== 'Escape') {
            return;
        }
        event.stopPropagation();
        if (this.saving || this.confirming) {
            return;
        }
        this.askDiscard().then((ok) => {
            if (!ok) {
                return;
            }
            if (this.modalEditAll) {
                this.endEdit();
            } else {
                this.closeModal();
            }
        });
    }

    /** Saves every section of the org in one go: saveOrg with all its fields, then its back promote settings when it has them. */
    saveOrgAll() {
        if (!this.editValid() || !this.ruleValid()) {
            return;
        }
        const payload = this.orgPayload();
        const check = this.signInChanged(payload);
        const name = payload.Name || 'Org';
        const withBp = this.formIsBackPromote && this.bpIsAdmin;
        this.saving = true;
        this.editError = undefined;
        saveOrg({ orgJson: JSON.stringify(payload) })
            .then((id) => {
                const orgId = payload.Id || id;
                if (!withBp) {
                    return orgId;
                }
                const settings = { orgId, whenValue: this.bpForm.whenValue, approval: this.bpForm.approval };
                return saveBackPromoteOrg({ settingsJson: JSON.stringify(settings) }).then(() => orgId);
            })
            .then((orgId) => {
                this.saving = false;
                return this.finishEdit(name + ': saved').then(() => {
                    this.showOrgCard(orgId);
                    return check && orgId ? this.runCheck(orgId) : null;
                });
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    /** The card's sections: Sign-in; Approval (stages and the hub) or Back promote (back promote orgs); Slack once it's set up. */
    sectionKinds(c) {
        const kinds = ['signin'];
        if (c.isTarget) {
            kinds.push('approval');
        }
        if (c.isBackPromote && c.bp && this.bpIsAdmin) {
            kinds.push('bp');
        }
        if (this.slackSetUp) {
            kinds.push('slack');
        }
        return kinds;
    }

    /** The org window's sections, read-only (Edit in the window turns them all into forms). */
    orgSections(o, c) {
        return this.sectionKinds(c).map((kind, i) => {
            const title = SECTION_TITLES[kind];
            return {
                key: 'org:' + o.Id + ':' + kind, kind, orgId: o.Id, title,
                cls: 'rr-msect' + (i === 0 ? ' rr-msect-first' : ''),
                isSignin: kind === 'signin',
                isApproval: kind === 'approval',
                isBp: kind === 'bp',
                isSlack: kind === 'slack',
                facts: this.sectionFacts(o, kind, c),
                ariaLabel: o.Name + ': ' + title
            };
        });
    }

    sectionFacts(o, kind, c) {
        if (kind === 'signin') {
            return this.orgFacts(o);
        }
        if (kind === 'approval') {
            return this.approvalFacts(o, c.ap);
        }
        if (kind === 'bp') {
            return this.bpSectionFacts(c.bp);
        }
        return this.orgSlackFacts(o, c.isDeveloper);
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

    /** The Approval section, as text. */
    approvalFacts(o, ap) {
        const where = [];
        if (ap.sf || !(this.slackAvailable && ap.slack)) {
            where.push('Salesforce');
        }
        if (this.slackAvailable && ap.slack) {
            where.push('Slack');
        }
        const list = [
            fact('rule', 'Approval rule', ruleText(o), { wide: true }),
            fact('in', 'Approve in', where.join(' or ')),
            fact('scan', 'Code scan', this.scanText(o))
        ];
        if (this.showGitReview) {
            list.push(flag('git', this.gitProviderName.trim() + ' reviewers', ap.git));
        }
        list.push(flag('two', 'Hotfixes need 2 approvers', o.Hotfix_Two_Approvers__c === true,
            o.Hotfix_Two_Approvers__c === true ? 'Two different approvers, and the person who raised the hotfix can\'t approve it.' : ''));
        return list;
    }

    // ---------- Per-org values and Quality gates (read-only, from the repository) ----------

    /** Reads .relay/values.json and .relay/gates.json once per repository and branch. */
    loadRepoSettings() {
        const g = this.git;
        const key = g ? [g.Provider__c, g.Repository__c, g.Pipeline_Branch__c].join('|') : null;
        if (!g || this.repoLoading || key === this.repoKey) {
            return;
        }
        this.repoKey = key;
        this.repoLoading = true;
        readRepoSettings()
            .then((r) => {
                this.repoSettings = r;
            })
            .catch((e) => {
                this.repoSettings = { message: errorText(e), values: [], environments: [], gates: [] };
            })
            .finally(() => {
                this.repoLoading = false;
                this.openAttention();
            });
    }

    get showRepoCards() { return this.hasGit; }
    get placeholderSample() { return '{{relay:NAME}}'; }
    get repoBranch() { return (this.repoSettings && this.repoSettings.branch) || (this.git && this.git.Pipeline_Branch__c) || ''; }
    get repoReadText() {
        if (this.repoLoading || !this.repoSettings) {
            return 'Reading ' + (this.repoBranch || 'the repository') + '…';
        }
        const at = this.repoSettings.readAt ? new Date(this.repoSettings.readAt) : null;
        const time = at ? at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
        return 'from ' + this.repoBranch + (time ? ' · read ' + time : '');
    }
    get gatesReadText() { return this.repoBranch ? 'from ' + this.repoBranch : ''; }
    get valuesFileUrl() { return repoFileUrl(this.git, this.repoBranch, VALUES_PATH); }
    get gatesFileUrl() { return repoFileUrl(this.git, this.repoBranch, GATES_PATH); }
    get repoRead() { return !!this.repoSettings && !this.repoLoading; }
    get repoMessage() { return this.repoRead ? this.repoSettings.message : null; }
    get repoOk() { return this.repoRead && !this.repoSettings.message; }
    get valuesError() { return this.repoOk ? this.repoSettings.valuesError : null; }
    get gatesError() { return this.repoOk ? this.repoSettings.gatesError : null; }
    get hasValues() { return this.repoOk && (this.repoSettings.values || []).length > 0; }
    get valuesEmpty() { return this.repoOk && !this.valuesError && !this.hasValues; }
    get hasGates() { return this.repoOk && (this.repoSettings.gates || []).length > 0; }
    get gatesEmpty() { return this.repoOk && !this.gatesError && !this.hasGates; }

    /** The orgs in route order (developer orgs, the stages and the hub, then back promote orgs), with their Git environment. */
    get routeOrgsForValues() {
        const byId = new Map(this.orgs.map((o) => [o.Id, o]));
        const pick = (o) => byId.get(o.Id) || o;
        const bp = this.orgs.filter((o) => o.Role__c === BACK_PROMOTE).sort((a, b) => a.Name.localeCompare(b.Name));
        return [...this.developers.map(pick), ...this.stages.map(pick), ...bp];
    }

    /** Columns: each org on the route, then a grey column for each environment in the file that no org on the route uses. */
    get valueColumns() {
        const cols = this.routeOrgsForValues.map((o) => ({
            key: 'o-' + o.Id, label: o.Name, env: (o.Git_Environment__c || '').trim(), title: o.Git_Environment__c ? 'Git environment ' + o.Git_Environment__c : 'No Git environment', cls: '', cellCls: 'rr-mono rr-break'
        }));
        const used = new Set(cols.map((c) => c.env));
        ((this.repoSettings && this.repoSettings.environments) || []).filter((e) => !used.has(e)).forEach((e) => {
            cols.push({ key: 'e-' + e, label: e, env: e, title: 'Not on the route', cls: 'rr-weak', cellCls: 'rr-mono rr-break rr-weak' });
        });
        return cols;
    }

    get valueRows() {
        const cols = this.valueColumns;
        return ((this.repoSettings && this.repoSettings.values) || []).map((r) => {
            const by = r.byEnvironment || {};
            return {
                key: r.name,
                name: r.name,
                cells: cols.map((c) => {
                    const has = !!c.env && Object.prototype.hasOwnProperty.call(by, c.env);
                    return {
                        key: c.key,
                        has,
                        text: has ? shortValue(by[c.env]) : '— no value',
                        title: has ? by[c.env] : '',
                        cls: has ? c.cellCls : 'rr-weak rr-small'
                    };
                })
            };
        });
    }

    get gateRows() {
        return ((this.repoSettings && this.repoSettings.gates) || []).map((g) => ({ ...g, cls: READONLY_CLS }));
    }

    /** The Git connection's code scan switch (a connection saved before the switch existed scans). */
    get gitScanOn() { return !!this.git && this.git.Code_Scan__c !== false; }

    /** The org's code scan choice as one line: Follows the Git connection (on), Always or Don't scan. */
    scanText(o) {
        const choice = scanChoiceOf(o);
        if (choice === SCAN_ALWAYS) {
            return 'Always';
        }
        if (choice === SCAN_NEVER) {
            return 'Don\'t scan';
        }
        return 'Follows the Git connection (' + (this.gitScanOn ? 'on' : 'off') + ')';
    }

    /** A back promote org's Back promote section, as text. */
    bpSectionFacts(bp) {
        const when = this.bpWhenOptions.find((w) => w.value === bp.whenValue);
        return [
            fact('bpw', 'When', when ? when.label : bp.whenValue),
            flag('bpa', 'Approve before syncing', bp.approval, bp.approvalText)
        ];
    }

    /** The org's Slack section, as text. */
    orgSlackFacts(o, isDeveloper) {
        return [
            fact('ch', 'Channel', o.Slack_Channel__c, { mono: true, empty: 'Not set' }),
            flag('post', isDeveloper ? 'Also post here' : 'Post to Slack', !!o.Slack_Post__c)
        ];
    }

    /** The org's place on the route (stages in route order), so the cards follow the route. */
    routeIndex(o) {
        const i = this.stages.findIndex((s) => s.Id === o.Id);
        return i >= 0 ? i : this.stages.length;
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
    get gitCheckLabel() { return this.gitBusy ? 'Checking…' : 'Check connection'; }

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
            flag('scan', 'Code scan', scanOn, (scanOn ? 'On for every ' + (g.Provider__c === 'GitLab' ? 'merge request' : 'pull request') + '. ' : '') + SCAN_ORG_HINT)
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
                this.openAttention();
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
    /** How as radio cards (no bare radios). */
    get filesHowCards() {
        return this.filesHowOptions.map((o) => ({ value: o.value, label: o.label }));
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
    get editCantSave() { return this.saving || this.hubCopy; }
    /** Edit buttons: one section at a time, and nothing on a sandbox copy of the hub. */
    get editLocked() { return !!this.editing || this.editingRoute || this.hubCopy; }

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
    get bpHelpLead() { return 'Register an org with the role '; }
    get bpHelpTail() {
        return ', then choose when it gets ' + this.hubName + '\'s changes. Metadata only: users and records in that org stay as they are.';
    }
    get bpNoOrgs() { return this.bpOrgs.length === 0; }
    /** Back promote beside the Git connection (compact): when the orgs get the changes, and how many orgs. */
    get bpWhenText() {
        const whens = [...new Set(this.bpOrgs.map((b) => b.whenValue || 'Manual'))];
        if (!whens.length) {
            return '';
        }
        if (whens.length > 1) {
            return 'Set per org';
        }
        const w = this.bpWhenOptions.find((x) => x.value === whens[0]);
        return w ? w.label : whens[0];
    }
    get bpOnText() { return this.bpEnabled ? 'On' : 'Off'; }
    get bpCountText() { return this.bpOrgs.length + ' registered'; }
    get bpOrgNames() { return this.bpOrgs.map((b) => b.name).join(', '); }
    get bpCompactFacts() {
        return [
            fact('bpw', 'When', this.bpWhenText, { empty: 'When an admin clicks Sync now' }),
            fact('bpn', 'Back promote orgs', this.bpCountText, { hint: this.bpOrgNames })
        ];
    }
    get hasBackPromoteBox() { return !!this.backPromote; }
    get gitRowCls() { return this.hasBackPromoteBox ? 'rr-git-row' : 'rr-git-row rr-git-row-solo'; }

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
            offNote: this.bpEnabled ? '' : 'Back promote is off. Switch it on under Back promote, next to the Git connection, to sync this org.',
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
        if (!this.editing) {
            this.editingRoute = true;
        }
    }

    get routeCardCls() { return this.editingRoute ? 'rr-sec rr-card-edit' : 'rr-sec'; }

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
    /** Until Slack answers (Test), the card shows the checklist of what's done and what's next. */
    get slackNotSetUp() { return !this.slack.connected; }
    get slackConnectedView() { return !!this.slack.connected; }
    get slackStatus() { return this.slack.status || 'Not set up'; }
    get slackStatusCls() {
        if (this.slackStatus === 'Connected') {
            return 'rr-pill rr-pill-ok';
        }
        return this.slackStatus.startsWith('Error') ? 'rr-pill rr-pill-bad' : 'rr-pill rr-pill-none';
    }
    get slackTestLabel() { return this.slackTesting ? 'Checking…' : 'Check connection'; }
    /** The secret itself never comes to the page: only a masked hint of the saved one. */
    get slackSecretText() {
        const hint = this.slack.signingSecretHint;
        return hint ? 'Signing secret ' + hint.charAt(0).toLowerCase() + hint.slice(1) : 'No signing secret saved yet';
    }
    get slackSecretPlaceholder() { return this.slack.signingSecretHint ? this.slack.signingSecretHint + '. Leave blank to keep it.' : 'From Slack → Basic Information → Signing Secret'; }
    get approversText() { return (this.slack.approversLinked || 0) + ' of ' + (this.slack.approversTotal || 0); }
    get approversToggleLabel() { return this.showApprovers ? 'Hide approvers' : 'Show approvers'; }

    /** What the Slack connection card shows, as text. */
    get slackFacts() {
        const events = this.slack.events || [];
        return [
            flag('on', 'Slack', !!this.slack.enabled),
            fact('ws', 'Workspace', this.slack.workspace, { empty: 'Not connected yet' }),
            fact('tok', 'Bot token', this.tokenSaved ? 'Saved · kept by Salesforce, never shown' : '', { empty: 'Not saved yet', hint: this.tokenSavedText }),
            fact('ev', 'Send a message when a release is', events.join(' · '), { empty: 'No events', wide: true }),
            fact('site', 'Approve in Slack', this.approveInSlackReady ? 'Set up' : '', { empty: 'Not set up (optional)', hint: this.slackSecretText }),
            fact('ap', 'Approvers linked', this.approversText)
        ];
    }

    /** The masked end of the saved bot token, if saveBotToken / getSlack give one (the token never comes to the page). */
    get botTokenHint() { return this.slack.botTokenHint || ''; }
    /** A token is saved when Slack answers with it, or the hub has a masked hint of it. */
    get tokenSaved() { return !!(this.slack.connected || this.botTokenHint); }
    get approveInSlackReady() { return !!(this.slack.signingSecretHint && this.slack.actionsUrl); }
    get anyOrgChannel() { return this.orgs.some((o) => !!(o.Slack_Channel__c || '').trim()); }

    /** Before Slack is set up: what's done and what's next (board HubPipelineSections 4). */
    get slackChecklist() {
        const items = [
            { key: 'app', title: 'Slack app created', text: 'You do this in Slack (Guide → Set up → Slack).', done: this.tokenSaved },
            { key: 'tok', title: 'Bot token saved', text: 'Paste it with Edit → Bot token.', done: this.tokenSaved },
            { key: 'test', title: 'Check connection', text: 'Checks the token and shows your workspace name.', done: !!this.slack.connected },
            { key: 'ch', title: 'Pick a channel per org', text: 'Connected orgs → open the org → Edit → Slack.', done: this.anyOrgChannel }
        ];
        const next = items.findIndex((i) => !i.done);
        return items.map((i, n) => {
            let cls = 'rr-ci-n';
            if (i.done) {
                cls += ' rr-ci-done';
            } else if (n === next) {
                cls += ' rr-ci-next';
            }
            return { ...i, n: n + 1, cls, stateText: i.done ? 'Done' : 'To do' };
        });
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

    // ---------- edit in place ----------

    /** The kind of section being edited: git, slack, bp (the Back promote card), or an org section (signin, approval, bp, slack). */
    get editingKind() {
        if (this.editing === NEW_ORG) {
            return 'signin';
        }
        const parts = (this.editing || '').split(':');
        return parts[0] === 'org' ? parts[2] : parts[0];
    }
    get isGitEditing() { return this.editing === 'git'; }
    get gitViewing() { return !this.isGitEditing; }
    get isSlackEditing() { return this.editing === 'slack'; }
    get slackViewing() { return !this.isSlackEditing; }
    get isBpEditing() { return this.editing === 'bp'; }
    get bpViewing() { return !this.isBpEditing; }
    get gitCardCls() { return this.isGitEditing ? 'rr-sec rr-card-edit' : 'rr-sec'; }
    get gitBoxCls() { return this.isGitEditing ? 'rr-git-main rr-edit' : 'rr-git-main'; }
    get slackCardCls() { return this.isSlackEditing ? 'rr-sec rr-card-edit rr-edit' : 'rr-sec'; }
    get bpCardCls() { return this.isBpEditing ? 'rr-box rr-box-edit rr-edit' : 'rr-box'; }
    get isOrgEditing() { return this.editing === NEW_ORG || (this.editing || '').startsWith('org:'); }

    get saveLabel() {
        if (this.saving) {
            return 'Saving…';
        }
        if (this.isSlackEditing) {
            return 'Save and test';
        }
        if (!this.inFlow) {
            return 'Save';
        }
        if (this.editingKind === 'signin') {
            return 'Check connection and next';
        }
        return this.flowIsLast ? 'Save and finish' : 'Save and next';
    }
    /** The grey line beside Cancel / Save. */
    get editNote() {
        if (this.isGitEditing) {
            return 'Save tests the connection.';
        }
        if (this.isSlackEditing) {
            return 'Save then Test: shows the workspace name.';
        }
        if (this.editingKind === 'signin' || this.editingKind === ALL_SECTIONS) {
            return this.inFlow ? 'Next tests the sign-in.' : 'Save tests the sign-in again when it changes.';
        }
        return '';
    }
    get showSkip() { return this.inFlow && this.editingKind !== 'signin'; }

    // Register an org: Sign-in → Approval → (Back promote) → Slack, one section at a time.
    get inFlow() { return this.editing === NEW_ORG || (!!this.flowOrgId && this.isEditingOrg(this.flowOrgId)); }
    get flowKinds() { return this.flowKindsFor(this.form.Role__c); }
    get flowIndex() { return Math.max(0, this.flowKinds.indexOf(this.editingKind)); }
    get flowIsLast() { return this.flowIndex >= this.flowKinds.length - 1; }
    /** The sections a new org with this role is walked through (the same ones its card shows). */
    flowKindsFor(role) {
        const kinds = ['signin'];
        if (role !== 'Developer' && role !== BACK_PROMOTE) {
            kinds.push('approval');
        }
        if (role === BACK_PROMOTE && this.bpIsAdmin) {
            kinds.push('bp');
        }
        if (this.slackSetUp) {
            kinds.push('slack');
        }
        return kinds;
    }

    startEdit(key) {
        this.editing = key;
        this.editError = undefined;
        this.focusEdit = true;
        this.formSnapshot = this.formState();
    }

    /** Connected orgs shows the org's tab, and its card lights up once. */
    showOrgCard(orgId) {
        const o = this.orgs.find((x) => x.Id === orgId);
        if (o) {
            this.pickTab(this.tabOf(o));
            this.flashId = orgId;
        }
    }

    endEdit() {
        this.editing = undefined;
        this.editError = undefined;
        this.editOrg = undefined;
        this.flowOrgId = undefined;
        this.slackAdvanced = false;
        this.showApprovers = false;
    }

    handleEditCancel() {
        if (!this.saving) {
            this.endEdit();
        }
    }

    handleEditKey(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleEditCancel();
        }
    }

    /** Every required field in the section being edited filled in; shows the field errors when not. */
    editValid() {
        const fields = [...this.template.querySelectorAll('.rr-edit lightning-input, .rr-edit lightning-combobox')];
        return fields.reduce((ok, f) => f.reportValidity() && ok, true);
    }

    finishEdit(message) {
        this.endEdit();
        this.toast(message, 'success');
        return this.load();
    }

    handleEditSave() {
        if (this.isGitEditing) {
            this.saveGitEdit();
        } else if (this.isSlackEditing) {
            this.saveSlackEdit();
        } else if (this.isBpEditing) {
            this.saveBpEdit();
        } else if (this.editingKind === ALL_SECTIONS) {
            this.saveOrgAll();
        } else if (this.editingKind === 'bp') {
            this.saveBpOrg();
        } else {
            this.saveOrgSection();
        }
    }

    // ----- org sections -----

    /** Register an org (page header, or a tab's "+ Register an org" tile: that tab's environment comes chosen). */
    handleRegister(event) {
        const env = event && event.currentTarget && event.currentTarget.dataset ? event.currentTarget.dataset.env : undefined;
        this.startAdd(ENVIRONMENT_LABELS[env] ? env : undefined);
    }

    /** Opens the Register an org window at its first step (Sign-in), empty fields with grey hints. */
    startAdd(env) {
        if (this.editLocked) {
            return;
        }
        this.editOrg = undefined;
        this.flowOrgId = undefined;
        this.dialogOrgId = undefined;
        this.form = { ...blankForm(), Environment__c: env || null };
        this.bounced = false;
        this.ruleError = undefined;
        this.startEdit(NEW_ORG);
    }

    /** Opens one section of a saved org for editing, with its saved values. */
    beginSection(orgId, kind) {
        const o = this.orgs.find((x) => x.Id === orgId);
        if (!o) {
            return;
        }
        const ap = approvals(o);
        const b = this.bpFor(o);
        this.editOrg = o;
        this.form = {
            ...blankForm(), ...o, Consumer_Key__c: '',
            Approve_In_Salesforce__c: ap.sf || !(this.slackAvailable && ap.slack), Approve_In_Slack__c: ap.slack, Require_Git_Review__c: ap.git,
            Slack_Channel__c: o.Slack_Channel__c || '', Slack_Post__c: !!o.Slack_Post__c, Hotfix_Two_Approvers__c: o.Hotfix_Two_Approvers__c === true,
            Approval_Rule__c: ruleOf(o), approvalTypes: typesOf(o), Code_Scan__c: scanChoiceOf(o)
        };
        this.ruleError = undefined;
        this.bpForm = { whenValue: b.whenValue || 'Manual', approval: b.approval === true };
        this.bounced = false;
        this.startEdit('org:' + orgId + ':' + kind);
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
        const first = 'Invite the app to this channel first (/invite @YourApp). ';
        return first + (this.formIsDeveloper
            ? 'A release posts its card in the target\'s channel. A developer org can also get a copy, so the people working in ' + this.formOrgName + ' see their own releases.'
            : 'Releases into ' + this.formOrgName + ' post their card in this channel.');
    }
    get formChannelHint() {
        const slug = (this.form.Name || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
        return 'e.g. #release-' + (slug || 'name');
    }

    // Approval rule as radio cards (board HubPipelineSections 2): Always / Only when it contains… / Never.
    get formIsHub() { return this.form.Role__c === 'Hub'; }
    get formRuleSelected() { return this.form.Approval_Rule__c === RULE_SELECTED; }
    get formRuleCards() {
        const org = this.formOrgName;
        const help = {
            [RULE_ALWAYS]: 'Every release into ' + org + ' waits for an approver.',
            [RULE_SELECTED]: 'Only if the release has one of the chosen kinds of change.',
            [RULE_NEVER]: this.formIsHub ? 'Production always needs approval.' : 'Deploy when the scan, check-only deploy and tests pass.'
        };
        return APPROVAL_RULES.map((r) => ({
            value: r.value,
            label: RULE_CARD_LABELS[r.value],
            help: help[r.value],
            disabled: r.value === RULE_NEVER && this.formIsHub
        }));
    }
    get formRuleLabel() { return 'Approval rule for releases into ' + this.formOrgName; }

    // Code scan as radio cards: follow the Git connection, always scan, or don't scan (to move faster).
    get formScanLabel() { return 'Code scan for releases into ' + this.formOrgName; }
    get formScanValue() { return scanChoiceOf(this.form); }
    get formScanCards() {
        const org = this.formOrgName;
        const pr = this.git && this.git.Provider__c === 'GitLab' ? 'merge request' : 'pull request';
        return [
            { value: SCAN_FOLLOW, label: 'Follow the Git connection', help: 'Now ' + (this.gitScanOn ? 'on' : 'off') + ' for every ' + pr + '.' },
            { value: SCAN_ALWAYS, label: 'Always scan', help: 'Every release into ' + org + ' is scanned.' },
            { value: SCAN_NEVER, label: 'Don\'t scan', help: 'Releases into ' + org + ' skip the scan, to move faster.' }
        ];
    }

    handleScanChoice(event) {
        this.form = { ...this.form, Code_Scan__c: event.detail.value };
    }
    get formTypeChips() { return APPROVAL_TYPES; }
    get formTypesLabel() { return 'Kinds of change that need approval in ' + this.formOrgName; }

    handleRuleChoice(event) {
        this.form = { ...this.form, Approval_Rule__c: event.detail.value };
        this.ruleError = undefined;
    }

    handleRuleTypes(event) {
        this.form = { ...this.form, approvalTypes: event.detail.value };
        this.ruleError = undefined;
    }

    /** Selected_Types needs a chosen kind; the hub (production) can't be Never. */
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

    get bpFormGroupLabel() { return 'When ' + this.formOrgName + ' gets ' + this.hubName + '\'s changes'; }

    /** The masked hint of the saved consumer key (the key itself never comes to the page). */
    get savedKeyHint() { return this.form.Id ? this.keyHints[this.form.Id] : null; }
    get keyRequired() { return !this.savedKeyHint; }
    get keyPlaceholder() {
        const saved = this.savedKeyHint;
        return saved ? 'Saved (ends ••••' + saved.slice(-4) + '). Leave blank to keep it.' : 'From the External Client App';
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
        this.editError = undefined;
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
        if (!payload.Login_Type__c) {
            payload.Login_Type__c = loginFor(payload.My_Domain__c);
        }
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
            payload.Code_Scan__c = scanChoiceOf(f);
        }
        return payload;
    }

    /** A new org, a new consumer key or a changed sign-in field: test the sign-in after Save. */
    signInChanged(payload) {
        const before = this.editOrg;
        return !before || !!payload.Consumer_Key__c || SIGN_IN_FIELDS.some((k) => (payload[k] || null) !== (before[k] || null));
    }

    /** Saves the org section being edited (saveOrg takes the whole org; only this section's fields changed). */
    saveOrgSection() {
        const kind = this.editingKind;
        const ruleOk = kind !== 'approval' || this.ruleValid();
        if (!this.editValid() || !ruleOk) {
            return;
        }
        const payload = this.orgPayload();
        const flow = this.inFlow;
        const check = kind === 'signin' && this.signInChanged(payload);
        const name = payload.Name || 'Org';
        this.saving = true;
        this.editError = undefined;
        saveOrg({ orgJson: JSON.stringify(payload) })
            .then((id) => {
                const orgId = payload.Id || id;
                this.saving = false;
                if (flow) {
                    this.flowOrgId = orgId;
                    return this.load().then(() => this.flowAfterSave(orgId, kind));
                }
                return this.finishEdit(name + ': saved').then(() => (check && orgId ? this.runCheck(orgId) : null));
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    /** Register an org: after Sign-in, test it and go on only when it signs in; after the other sections, go on. */
    flowAfterSave(orgId, kind) {
        if (kind !== 'signin') {
            this.nextFlowStep(orgId, kind);
            return null;
        }
        return this.runCheck(orgId).then(() => {
            const o = this.orgs.find((x) => x.Id === orgId);
            if (o && o.Status__c === 'Connected') {
                this.nextFlowStep(orgId, kind);
                return;
            }
            this.beginSection(orgId, 'signin');
            this.editError = 'Saved, but the sign-in didn\'t work yet' + (o && o.Status_Message__c ? ': ' + o.Status_Message__c : '.')
                + ' Fix the details, then Check connection and next.';
        });
    }

    nextFlowStep(orgId, kind) {
        const o = this.orgs.find((x) => x.Id === orgId);
        const kinds = this.flowKindsFor(o ? o.Role__c : null);
        const next = kinds[kinds.indexOf(kind) + 1];
        if (o && next) {
            this.beginSection(orgId, next);
            return;
        }
        this.endEdit();
        this.toast((o ? o.Name : 'Org') + ' is registered', 'success');
        this.showOrgCard(orgId);
        this.focusTileId = orgId;
    }

    handleEditSkip() {
        if (this.flowOrgId && !this.saving) {
            this.nextFlowStep(this.flowOrgId, this.editingKind);
        }
    }

    /** A back promote org's Back promote section. */
    saveBpOrg() {
        const orgId = this.editOrg && this.editOrg.Id;
        const name = (this.editOrg && this.editOrg.Name) || 'Org';
        const flow = this.inFlow;
        const settings = { orgId, whenValue: this.bpForm.whenValue, approval: this.bpForm.approval };
        this.saving = true;
        this.editError = undefined;
        saveBackPromoteOrg({ settingsJson: JSON.stringify(settings) })
            .then(() => this.readBackPromote())
            .then((bp) => {
                this.backPromote = bp;
                this.saving = false;
                if (flow) {
                    this.nextFlowStep(orgId, 'bp');
                    return null;
                }
                return this.finishEdit(name + ': saved');
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Git connection -----

    openGitEdit() {
        if (this.editLocked) {
            return;
        }
        this.gitForm = this.git ? { ...blankGit(), ...this.git } : blankGit();
        this.startEdit('git');
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
    get gitRepoHint() { return 'e.g. ' + this.gitProvider.repo; }
    get gitCredHint() { return 'e.g. ' + this.gitProvider.cred; }
    get gitPipeHint() { return 'e.g. ' + this.gitProvider.pipe; }
    get scanOrgHint() { return SCAN_ORG_HINT; }
    get scanLabel() { return 'Code scan on every ' + (this.gitForm.Provider__c === 'GitLab' ? 'merge request' : 'pull request'); }

    pickProvider(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.gitForm.Provider__c) {
            return;
        }
        const before = this.gitProvider;
        const next = { ...this.gitForm, Provider__c: value };
        // The old provider's usual values go, so the new provider's hints show.
        if (next.Named_Credential__c === before.cred) {
            next.Named_Credential__c = '';
        }
        if (next.Pipeline__c === before.pipe) {
            next.Pipeline__c = '';
        }
        this.gitForm = next;
        this.editError = undefined;
    }

    handleGitField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }
        this.gitForm = { ...this.gitForm, [field]: value };
        this.editError = undefined;
    }

    saveGitEdit() {
        if (!this.editValid()) {
            return;
        }
        const f = this.gitForm;
        const payload = {
            Provider__c: f.Provider__c, Repository__c: (f.Repository__c || '').trim(), Named_Credential__c: (f.Named_Credential__c || '').trim(),
            Pipeline__c: (f.Pipeline__c || '').trim(), Pipeline_Branch__c: (f.Pipeline_Branch__c || '').trim(),
            Source_Path__c: (f.Source_Path__c || '').trim(), Code_Scan__c: f.Code_Scan__c !== false
        };
        this.saving = true;
        this.editError = undefined;
        saveGit({ gitJson: JSON.stringify(payload) })
            .then(() => {
                this.saving = false;
                // The provider or branch may have changed: read the pipeline files' versions again.
                this.pipeFiles = undefined;
                return this.finishEdit('Git connection saved').then(() => this.runGitCheck());
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Slack connection -----

    openSlackEdit() {
        if (this.editLocked) {
            return;
        }
        this.slackForm = { enabled: !!this.slack.enabled, signingSecret: '', botToken: '', events: [...(this.slack.events || [])] };
        this.memberEdits = {};
        this.slackAdvanced = false;
        this.showApprovers = false;
        this.startEdit('slack');
    }

    /** The bot token field's grey hint: the saved token's masked end, or an example. */
    get tokenPlaceholder() {
        const saved = this.tokenSavedText;
        return saved ? saved + '. Paste a new one to replace it.' : 'e.g. xoxb-…';
    }
    get tokenSavedText() {
        const h = this.botTokenHint;
        if (!h) {
            return '';
        }
        return h.startsWith('Saved') ? h : 'Saved (' + h + ')';
    }
    /** The token can be saved from this page unless saveBotToken said it can't in this org. */
    get showTokenField() { return !this.tokenNote; }
    get showTokenSetup() { return !this.showTokenField; }
    get tokenSetupText() { return (this.tokenNote ? this.tokenNote + ' ' : '') + TOKEN_SETUP_TEXT; }
    get tokenSetupUrl() { return TOKEN_SETUP_URL; }
    get slackAdvancedIcon() { return this.slackAdvanced ? 'utility:chevrondown' : 'utility:chevronright'; }
    get slackAdvancedExpanded() { return this.slackAdvanced ? 'true' : 'false'; }
    get linkApproversLabel() { return this.showApprovers ? 'Hide Slack member IDs' : 'Link Slack member IDs'; }
    get hasActionsUrl() { return !!this.slack.actionsUrl; }

    toggleSlackAdvanced() {
        this.slackAdvanced = !this.slackAdvanced;
    }

    handleSlackEnabled(event) {
        const enabled = event.target.checked;
        // Switched on with no events chosen: every event, as the hub does.
        const events = enabled && this.slackForm.events.length === 0 ? [...(this.slack.allEvents || [])] : this.slackForm.events;
        this.slackForm = { ...this.slackForm, enabled, events };
        this.editError = undefined;
    }

    handleSlackSecret(event) {
        this.slackForm = { ...this.slackForm, signingSecret: event.target.value };
        this.editError = undefined;
    }

    handleBotToken(event) {
        this.slackForm = { ...this.slackForm, botToken: event.target.value };
        this.editError = undefined;
    }

    handleSlackEvents(event) {
        this.slackForm = { ...this.slackForm, events: event.detail.value };
    }

    handleMemberInput(event) {
        this.memberEdits = { ...this.memberEdits, [event.target.dataset.id]: event.target.value };
    }

    handleCopyUrl() {
        const url = this.slack.actionsUrl;
        if (url && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(url)
                .then(() => this.toast('Interactivity URL copied', 'success'))
                .catch(() => this.toast('Select the URL and copy it.', 'info'));
        } else {
            this.toast('Select the URL and copy it.', 'info');
        }
    }

    /**
     * Sends a pasted bot token to RlySlackController.saveBotToken (it goes to the credential store; it never comes back).
     * Resolves true when saved; false when this org can't keep it from the page: saveBotToken then answers with an error
     * that says to set it in Setup, and the card shows that with the Setup path.
     */
    sendBotToken(token) {
        return saveBotToken({ token })
            .then((sl) => {
                if (sl) {
                    this.applySlack(sl);
                }
                this.tokenNote = undefined;
                return true;
            })
            .catch((e) => {
                this.tokenNote = errorText(e);
                return false;
            });
    }

    /** Saves the bot token (when one was pasted), the Slack settings, each changed approver member ID; then tests Slack. */
    saveSlackEdit() {
        const secret = (this.slackForm.signingSecret || '').trim();
        const token = (this.slackForm.botToken || '').trim();
        if (/\s/.test(secret)) {
            this.editError = 'The signing secret has no spaces: copy it again from the Slack app (Basic Information).';
            return;
        }
        if (token && (!token.startsWith(BOT_TOKEN_PREFIX) || /\s/.test(token))) {
            this.editError = 'A bot token starts with xoxb- and has no spaces: copy the Bot User OAuth Token again (Slack app → OAuth & Permissions).';
            return;
        }
        const settings = { enabled: this.slackForm.enabled, events: this.slackForm.events, signingSecret: secret };
        const members = (this.slack.approvers || [])
            .filter((a) => this.memberEdits[a.userId] !== undefined && this.memberEdits[a.userId].trim() !== (a.slackMemberId || ''))
            .map((a) => ({ userId: a.userId, memberId: this.memberEdits[a.userId].trim() }));
        const enabled = this.slackForm.enabled;
        let tokenKept = true;
        this.saving = true;
        this.editError = undefined;
        (token ? this.sendBotToken(token) : Promise.resolve(true))
            .then((kept) => {
                tokenKept = kept;
                return saveSlack({ settingsJson: JSON.stringify(settings) });
            })
            .then((sl) => {
                this.applySlack(sl);
                return members.reduce((p, m) => p.then(() => saveSlackMember(m)).then((s2) => this.applySlack(s2)), Promise.resolve());
            })
            .then(() => {
                this.saving = false;
                this.memberEdits = {};
                this.endEdit();
                if (tokenKept) {
                    this.toast('Slack settings saved', 'success');
                } else {
                    this.toast('Slack settings saved. The bot token goes in Setup: see the Slack connection card.', 'warning');
                }
                return this.load().then(() => (enabled ? this.runSlack(testSlack(), 'check') : null));
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.saving = false;
            });
    }

    // ----- Back promote switch -----

    openBpEdit() {
        if (this.editLocked) {
            return;
        }
        this.bpSwitch = this.bpEnabled;
        this.startEdit('bp');
    }

    handleBpSwitch(event) {
        this.bpSwitch = event.target.checked;
    }

    saveBpEdit() {
        this.saving = true;
        this.editError = undefined;
        setBackPromote({ state: this.bpSwitch ? 'on' : 'off' })
            .then((bp) => {
                this.backPromote = bp;
                this.saving = false;
                return this.finishEdit('Back promote ' + (bp && bp.enabled ? 'on' : 'off'));
            })
            .catch((e) => {
                this.editError = errorText(e);
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
    get remoteSite() { return (this.isOrgEditing && this.form.My_Domain__c) || 'https://<that org>.my.salesforce.com'; }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: APP_NAME, message, variant }));
    }
}
