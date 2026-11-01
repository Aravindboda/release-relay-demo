import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveEvidence from '@salesforce/apex/RlyEvidenceController.saveEvidence';
import refreshRelease from '@salesforce/apex/RlyReleasesController.refreshRelease';
import bypassScan from '@salesforce/apex/RlyReleasesController.bypassScan';
import checkAgain from '@salesforce/apex/RlyReleasesController.checkAgain';
import approve from '@salesforce/apex/RlyReleasesController.approve';
import reject from '@salesforce/apex/RlyReleasesController.reject';
import resolveConflicts from '@salesforce/apex/RlyReleasesController.resolveConflicts';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';

/** Modes of RlyHubGuard.getHubStatus in which only the org gate shows. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];

const POLL_SECONDS = 30;
const RESOLVING = 'Resolving conflicts';
const GOOD = ['Deployed', 'Ready for approval'];
const BAD = ['Checks failed', 'Deploy failed', 'Failed', 'Rejected'];
const RUNNING = ['Retrieving', 'Workflow running', 'Validating', 'Deploying'];
const ENDED_BADLY = ['Failed', 'Deploy failed'];
const SYNC_STATE = {
    Synced: { label: 'Updated', cls: 'rr-pill rr-pill-ok' },
    Conflict: { label: 'Not updated', cls: 'rr-pill rr-pill-wait' },
    Missing: { label: 'Not found', cls: 'rr-pill rr-pill-wait' }
};
const SEVERITY_CLS = { Critical: 'rr-pill rr-pill-bad', High: 'rr-pill rr-pill-bad', Moderate: 'rr-pill rr-pill-wait', Low: 'rr-pill rr-pill-none', Info: 'rr-pill rr-pill-none' };
const SEVERITY_ORDER = ['Critical', 'High', 'Moderate', 'Low', 'Info'];
const STEP_PILL = {
    Done: 'rr-pill rr-pill-ok rr-sp',
    Running: 'rr-pill rr-pill-info rr-sp',
    Failed: 'rr-pill rr-pill-bad rr-sp',
    Warn: 'rr-pill rr-pill-wait rr-sp',
    Waiting: 'rr-pill rr-pill-none rr-sp'
};
const STEP_DOT = {
    Done: 'rr-dot rr-dot-done',
    Running: 'rr-dot rr-dot-running',
    Failed: 'rr-dot rr-dot-failed',
    Warn: 'rr-dot rr-dot-warn',
    Waiting: 'rr-dot'
};
const TYPE_LABEL = { Promotion: 'Promotion', Back_Promote: 'Back promote' };
/** A release with only manual steps (RLY_Release__c.Manual_Only__c): no Git or pipeline steps. */
const MANUAL_ONLY = 'Manual steps only';
const NOT_NEEDED = 'Not needed: manual steps only';
const NO_GIT_PATH = ['pr', 'checks'];
const RELEASES_TAB = 'RLY_My_Releases';
/** New Release: opened in append mode (state c__appendTo) to add changes to an open release. */
const BUILDER_TAB = 'RLY_New_Release';
const BRANCH_OK = 'Synced';
/** RLY_Release_Event__c.Event_Type__c: the History card's title and icon per event (board HubApprovalFlowsEvidence 3). */
const EVENT_LOOK = {
    Raised: { title: 'Raised', icon: 'utility:add' },
    Pull_Request: { title: 'Pull request opened', icon: 'utility:merge' },
    Scan: { title: 'Code scan', icon: 'utility:check' },
    Validation: { title: 'Check-only deploy', icon: 'utility:check' },
    Approved: { title: 'Approved', icon: 'utility:approval' },
    Rejected: { title: 'Rejected', icon: 'utility:close' },
    Auto_Approved: { title: 'Approved automatically', icon: 'utility:settings' },
    Deployed: { title: 'Deployed', icon: 'utility:upload' },
    Deploy_Failed: { title: 'Deploy failed', icon: 'utility:error' },
    Manual_Step: { title: 'Manual step done', icon: 'utility:task' },
    Flow_Activated: { title: 'Flow activated', icon: 'utility:flow' },
    Merged_Back: { title: 'Merged back', icon: 'utility:merge' },
    Promoted: { title: 'Promoted', icon: 'utility:forward' },
    Back_Promoted: { title: 'Back promoted', icon: 'utility:back' },
    Comment: { title: 'Comment', icon: 'utility:comments' },
    Rolled_Back: { title: 'Rolled back', icon: 'utility:undo' },
    Rollback_Failed: { title: 'Rollback failed', icon: 'utility:error' }
};
/** History dot colour per event type (anything else is blue): green done, red failed, amber rolled back or waiting. */
const EVENT_TONE = {
    Deployed: 'ok', Approved: 'ok', Auto_Approved: 'ok', Manual_Step: 'ok', Merged_Back: 'ok', Back_Promoted: 'ok',
    Scan: 'ok', Validation: 'ok', Flow_Activated: 'ok',
    Rejected: 'bad', Deploy_Failed: 'bad', Rollback_Failed: 'bad',
    Rolled_Back: 'wait'
};
/** Types whose title names the org: "Deployed to <org>", "Approved for <org>"… */
const EVENT_ORG_WORD = {
    Approved: ' for ', Rejected: ' for ', Deployed: ' to ', Deploy_Failed: ' in ', Validation: ' in ', Manual_Step: ' in ',
    Flow_Activated: ' in ', Auto_Approved: ' for ', Rolled_Back: ' in ', Rollback_Failed: ' in '
};
/** RLY_Release__c.Rollback_Status__c (RlyRollbackState): the header pill's tone per rollback state (board HubRollbackValuesGates 2). */
const ROLLBACK_PILL = { Running: 'rr-pill rr-pill-info', Rolled_Back: 'rr-pill rr-pill-wait', Failed: 'rr-pill rr-pill-bad' };
const ROLLED_BACK = 'Rolled_Back';
const ROLLBACK_RUNNING = 'Running';
/** Where .relay/gates.json failures come from when a result doesn't name the file. */
const GATES_FILE = '.relay/gates.json';
/** Events whose outcome (passed / failed) is in their detail line. */
const CHECK_EVENTS = ['Scan', 'Validation', 'Flow_Activated'];
/** RLY_Release__c.Flow_Actions__c / FlowChoice.choice → the Review step's label. */
const FLOW_CHOICE_LABEL = { Activate: 'Activate in each org', Inactive: 'Leave inactive: add a manual step to activate' };
const FLOW_ACTIVATED = 'Activated';
const FLOW_ALREADY = 'Already active';
const FLOW_FAILED = 'Failed';
const PATH = [
    { key: 'raised', label: 'Raised' },
    { key: 'pr', label: '' },
    { key: 'checks', label: 'Checks' },
    { key: 'approval', label: 'Approval' },
    { key: 'deploy', label: 'Deploy' }
];

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function parse(json) {
    if (!json) {
        return null;
    }
    try {
        return JSON.parse(json);
    } catch {
        return null;
    }
}

function pillCls(status) {
    if (status === RESOLVING) {
        return 'rr-pill rr-pill-info';
    }
    if (GOOD.includes(status) || status === 'Passed' || status === 'Approved' || status === 'Merged') {
        return 'rr-pill rr-pill-ok';
    }
    if (BAD.includes(status) || status === 'Failed' || status === 'Error') {
        return 'rr-pill rr-pill-bad';
    }
    if (RUNNING.includes(status) || status === 'Deploying' || status === 'Bypassed') {
        return 'rr-pill rr-pill-wait';
    }
    return 'rr-pill rr-pill-none';
}

/** The Git provider, from Detail.gitProvider when the server sends it, else from the pull request's web address. */
function providerOf(detail, url) {
    if (detail && detail.gitProvider) {
        return detail.gitProvider;
    }
    const u = (url || '').toLowerCase();
    if (u.includes('github')) {
        return 'GitHub';
    }
    if (u.includes('gitlab')) {
        return 'GitLab';
    }
    if (u.includes('bitbucket')) {
        return 'Bitbucket';
    }
    if (u.includes('dev.azure.com') || u.includes('visualstudio.com')) {
        return 'Azure DevOps';
    }
    return null;
}

/** A metadata type for people: ApexClass → Apex Class, and Apex test class for the release's tests. */
function typeLabel(type, isTest) {
    if (type === 'ApexClass' && isTest) {
        return 'Apex test class';
    }
    return (type || '').replace(/([a-z])([A-Z])/g, '$1 $2');
}

function dayOf(value) {
    return value ? new Date(value).toDateString() : '';
}

function timeOnly(value) {
    return value ? new Date(value).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : '';
}

function when(value) {
    return value ? new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
}

/** The history dot's tone: red failed, amber rolled back or waiting (a conflict, a second approver), green done, blue other. */
function eventTone(e, failed) {
    const tone = failed ? 'bad' : EVENT_TONE[e.eventType] || 'info';
    if (tone === 'ok' && /waiting|conflict/i.test(e.detail || '')) {
        return 'wait';
    }
    return tone;
}

/** Where the release is on the path: the index of the current stop, and whether that stop failed. */
function pathPosition(r) {
    const s = r.Status__c;
    if (s === 'Deployed') {
        return { index: PATH.length, failed: false };
    }
    if (s === 'Deploying' || s === 'Deploy failed') {
        return { index: 4, failed: s === 'Deploy failed' };
    }
    if (s === 'Ready for approval' || s === 'Rejected') {
        return { index: 3, failed: s === 'Rejected' };
    }
    if (s === 'Validating' || s === 'Checks failed') {
        return { index: 2, failed: s === 'Checks failed' };
    }
    if (r.PR_Number__c) {
        return { index: 2, failed: s === 'Failed' };
    }
    if (s === 'Workflow running' || (s === 'Failed' && r.Source_Branch__c)) {
        return { index: 1, failed: s === 'Failed' };
    }
    return { index: 0, failed: s === 'Failed' };
}

export default class RlyReleaseView extends NavigationMixin(LightningElement) {
    _releaseId;
    detail;
    error;
    loading = false;
    busy = false;
    cycle = 0;
    nextAt;
    checking = false;
    comment = '';
    reason = '';

    /**
     * RlyHubGuard.getHubStatus: the org's mode. The tab around this view shows the gate or the banner; here the actions
     * are disabled outside the hub, and in a sandbox, a copy or an org not set up yet only the gate shows (nothing loads).
     */
    hubStatus;
    /** The status has been read, or failed to read (then the view works as on the hub). */
    statusRead = false;
    get gated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    get showPage() { return this.statusRead && !this.gated; }

    /** The app's name, from Custom Label RLY_App_Name. */
    get appName() { return APP_NAME; }
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    /** Busy, or a sandbox copy of the hub: the release's actions are disabled. */
    get actBusy() { return this.busy || this.hubCopy; }

    @api
    get releaseId() {
        return this._releaseId;
    }
    set releaseId(value) {
        this._releaseId = value;
        this.detail = undefined;
        this.lastRollback = undefined;
        if (value && this.statusRead && !this.gated) {
            this.load();
        }
    }

    connectedCallback() {
        this.readHubStatus();
    }

    disconnectedCallback() {
        this.stop();
    }

    /** Reads the hub status once, then loads the release only on the hub. A failed read disables nothing. */
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
                if (!this.gated && this._releaseId) {
                    this.load();
                }
            });
    }

    /** Stops the countdown: the bar is removed, so its animation can't end and trigger a check. */
    stop() {
        this.nextAt = undefined;
    }

    /**
     * Starts the next countdown. The bar is a CSS animation of POLL_SECONDS (no JavaScript timers);
     * when it ends, handleCountdownEnd checks the status again.
     */
    startCountdown() {
        this.cycle += 1;
        this.nextAt = new Date(Date.now() + POLL_SECONDS * 1000);
    }

    handleCountdownEnd() {
        if (this.nextAt) {
            this.load();
        }
    }

    /** Reads the release's latest status (which moves it along), then counts down to the next check while it runs. */
    async load() {
        this.stop();
        if (!this._releaseId) {
            return;
        }
        this.loading = !this.detail;
        this.checking = true;
        try {
            this.detail = await refreshRelease({ releaseId: this._releaseId });
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
            this.checking = false;
        }
        if (this.detail && this.detail.running) {
            this.startCountdown();
        }
        this.dispatchEvent(new CustomEvent('changed', { detail: this.detail ? this.detail.release.Status__c : null }));
        this.tellRollback();
    }

    /** The rollback state moved (started, rolled back, failed): the list around this view reads its rows again. */
    tellRollback() {
        const state = this.detail && this.detail.rollbackState ? this.detail.rollbackState.status || '' : '';
        if (this.lastRollback !== undefined && state !== this.lastRollback) {
            this.dispatchEvent(new CustomEvent('rollbackchanged', { detail: state }));
        }
        this.lastRollback = state;
    }

    refresh() {
        this.load();
    }

    /** A manual step was added or ticked: read the release again (header pill, notice, a deploy the last step started). */
    handleStepsChange() {
        this.load();
    }

    // ---------- header ----------

    get rel() { return this.detail ? this.detail.release : {}; }
    get releaseType() { return (this.detail && this.detail.releaseType) || 'Release'; }
    /** Promotion or Back promote for those release types; nothing for an ordinary release. */
    get typeLabel() { return TYPE_LABEL[this.releaseType] || ''; }
    get eyebrow() { return (this.typeLabel || 'Release') + ' · ' + (this.rel.Name || ''); }
    get isHotfix() { return !!(this.detail && this.detail.isHotfix); }
    /** Manual steps only: no retrieve, Git branch, pull request, pipeline run, scan or validation. */
    get manualOnly() { return this.rel.Manual_Only__c === true; }
    get manualOnlyLabel() { return MANUAL_ONLY; }
    get notNeededText() { return NOT_NEEDED; }
    /** The route's branch, left out for a release with only manual steps. */
    get routeBranch() { return this.manualOnly ? '' : this.rel.Target_Branch__c; }
    /** Header pill: Detail.manualOpen, the manual steps still open for this release. */
    get manualOpenText() {
        const n = Number(this.detail && this.detail.manualOpen) || 0;
        return n ? n + (n === 1 ? ' manual step open' : ' manual steps open') : '';
    }
    get hotfixReason() { return this.isHotfix ? (this.detail.hotfixReason || '') : ''; }
    /** The header pill: Detail.phase (for example Resolving conflicts), else the status. */
    get phase() { return (this.detail && this.detail.phase) || this.rel.Status__c; }
    get phaseCls() { return pillCls(this.phase); }
    /** The header and Status pill: the latest rollback ("Rolled back in PROD") when there is one, else the phase. */
    get headPill() { return this.rollback.label || this.phase; }
    get headPillCls() { return this.rollback.label ? (ROLLBACK_PILL[this.rollback.status] || 'rr-pill rr-pill-none') : this.phaseCls; }
    get resolving() { return this.phase === RESOLVING; }
    get provider() { return providerOf(this.detail, this.rel.PR_URL__c); }
    /** Pull request, merge request (GitLab) or the neutral change request when the provider isn't known. */
    get crLabel() {
        const p = this.provider;
        if (p === 'GitLab') {
            return 'Merge request';
        }
        return p ? 'Pull request' : 'Change request';
    }
    get crWord() { return this.crLabel.toLowerCase(); }
    get prLabel() { return this.rel.PR_Number__c ? this.crLabel + ' #' + this.rel.PR_Number__c : this.crLabel; }
    get running() { return !!(this.detail && this.detail.running); }

    get pathSteps() {
        const pos = pathPosition(this.rel);
        const skip = this.manualOnly ? NO_GIT_PATH : [];
        return PATH.map((p, i) => {
            let state = 'todo';
            if (i < pos.index) {
                state = 'done';
            } else if (i === pos.index) {
                state = pos.failed ? 'lost' : 'current';
            }
            const rolledBack = p.key === 'deploy' && this.rollback.status === ROLLED_BACK;
            return {
                ...p,
                label: rolledBack ? 'Rolled back' : (p.key === 'pr' ? this.crLabel : p.label),
                cls: 'rr-path-item rr-path-' + (rolledBack ? 'rb' : state),
                current: i === pos.index ? 'step' : null,
                stateText: { done: 'Done', lost: 'Failed', current: 'Current', todo: 'Not yet' }[state]
            };
        }).filter((p) => !skip.includes(p.key));
    }

    // ---------- highlights ----------

    get raisedBy() { return this.rel.CreatedBy ? this.rel.CreatedBy.Name : ''; }
    get raisedOn() { return when(this.rel.CreatedDate); }
    get testsText() {
        const tests = this.detail && Array.isArray(this.detail.tests) ? this.detail.tests : [];
        return tests.length ? tests.join(', ') : 'None (no Apex)';
    }
    /** Where releases into the target org are approved, as Detail.approvedIn gives it (for example "Salesforce or Slack"). */
    get approvedInText() { return (this.detail && this.detail.approvedIn) || 'Salesforce'; }
    /** False when this release can't be approved in Salesforce (its target org approves from the Slack card). */
    get approveHere() { return !(this.detail && this.detail.approveHere === false); }

    // ---------- progress ----------

    get syncedText() {
        if (this.checking) {
            return 'Checking now…';
        }
        const last = this.rel.Last_Synced__c
            ? 'Last checked ' + new Date(this.rel.Last_Synced__c).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })
            : '';
        if (this.counting) {
            return last ? last + ' · next check in' : 'Next check in';
        }
        return last;
    }
    get counting() { return this.running && !!this.nextAt && !this.checking; }
    /** One key per countdown, so a fresh bar (and a fresh animation) is drawn each time. */
    get cycles() { return [{ key: 'c' + this.cycle }]; }

    get scan() { return parse(this.rel.Scan_Result__c) || {}; }
    get validation() { return parse(this.rel.Validation_Result__c) || {}; }
    get deploy() { return parse(this.rel.Deploy_Result__c) || {}; }
    get targetName() { return this.detail ? this.detail.targetName : ''; }

    get steps() {
        if (this.manualOnly) {
            return this.manualOnlySteps().map((st, i) => this.decorate(st, i));
        }
        const r = this.rel;
        const s = r.Status__c;
        const collected = !['Retrieving'].includes(s) && !(s === 'Failed' && !r.Source_Branch__c);
        const steps = [this.collectStep(collected), this.prStep(collected)];
        if (this.resolving) {
            steps.push({
                key: 'conflicts', title: 'Conflicts', state: 'Running', label: 'Resolving',
                text: 'Your choices' + this.conflictCountText + ' were committed. The pipeline is merging ' + (r.Target_Branch__c || 'the target') + ' and checking again…'
            });
            steps.push({ key: 'checks', title: 'Code scan and validation in ' + this.targetName, state: 'Waiting', text: 'Run again after the merge' });
        } else {
            steps.push({ key: 'scan', title: 'Code scan', state: this.checkState(r.Scan_Status__c, this.scan), text: this.scanText });
            const val = this.validation;
            steps.push({
                key: 'validate', title: 'Validation in ' + this.targetName, state: this.checkState(r.Validation_Status__c, val),
                text: this.validationText, conflict: val.status === 'Conflict'
            });
        }
        steps.push(this.approvalStep());
        steps.push(this.deployStep());
        this.backMergeSteps().forEach((st) => steps.push(st));
        const rollbackStep = this.rollbackStep();
        if (rollbackStep) {
            steps.push(rollbackStep);
        }
        const backPromote = this.backPromoteStep();
        if (backPromote) {
            steps.push(backPromote);
        }
        return steps.map((st, i) => this.decorate(st, i));
    }

    /** Manual steps only: one "Not needed" line for the Git and pipeline steps, the approval, then the manual steps as the deploy. */
    manualOnlySteps() {
        const steps = [
            { key: 'nogit', title: 'Retrieve, Git branch, ' + this.crWord + ', code scan and validation', state: 'Done', badge: '–', label: 'Not needed', pill: STEP_PILL.Waiting, text: NOT_NEEDED },
            this.approvalStep(),
            this.manualDeployStep()
        ];
        const backPromote = this.backPromoteStep();
        if (backPromote) {
            steps.push(backPromote);
        }
        return steps;
    }

    manualDeployStep() {
        const s = this.rel.Status__c;
        const open = Number(this.detail && this.detail.manualOpen) || 0;
        let state = 'Waiting';
        let text = (this.detail && this.detail.manualSummary) || '';
        if (s === 'Deployed') {
            state = 'Done';
            text = 'Every manual step in ' + this.targetName + ' is done';
        } else if (s === 'Deploying') {
            state = 'Running';
            text = 'The deployment team checks off ' + open + (open === 1 ? ' manual step' : ' manual steps') + ' in ' + this.targetName
                + ' (Manual steps below). It is deployed when all of them are done.';
        }
        return { key: 'deploy', title: 'Manual steps in ' + this.targetName, state, text, sync: [], hasSync: false };
    }

    decorate(st, i) {
        let label = st.label;
        if (!label) {
            label = this.stateLabel(st);
        }
        let badge = String(i + 1);
        if (st.state === 'Done') {
            badge = '✓';
        } else if (st.state === 'Failed' || st.state === 'Warn') {
            badge = '!';
        } else if (st.state === 'Running') {
            badge = '⟳';
        }
        if (st.badge) {
            badge = st.badge;
        }
        return {
            ...st,
            badge,
            dotCls: STEP_DOT[st.state] || STEP_DOT.Waiting,
            stateLabel: label,
            pillCls: st.pill || (st.conflict ? STEP_PILL.Warn : (STEP_PILL[st.state] || STEP_PILL.Waiting))
        };
    }

    stateLabel(st) {
        if (st.conflict) {
            return 'Conflict';
        }
        if (st.state === 'Running') {
            return 'In progress';
        }
        if (st.state === 'Waiting') {
            return '';
        }
        if (st.state === 'Warn') {
            return st.key === 'scan' && this.rel.Scan_Status__c === 'Bypassed' ? 'Bypassed' : 'Passed with findings';
        }
        return st.state;
    }

    collectStep(collected) {
        const s = this.rel.Status__c;
        let state = 'Failed';
        if (s === 'Retrieving') {
            state = 'Running';
        } else if (collected) {
            state = 'Done';
        }
        return {
            key: 'collect', title: 'Collected from ' + (this.detail ? this.detail.sourceName : ''), state,
            text: s === 'Retrieving' ? 'Retrieving the components with the Metadata API…' : (this.rel.Component_Count__c || 0) + ' components' + this.deletionsTail
        };
    }

    get deletionsTail() {
        const d = this.deletions.length;
        return d ? ' · ' + d + (d === 1 ? ' deletion' : ' deletions') : '';
    }

    prStep(collected) {
        const r = this.rel;
        const s = r.Status__c;
        let state = 'Waiting';
        let text = '';
        if (r.PR_Number__c) {
            state = 'Done';
            text = '#' + r.PR_Number__c + ': ' + r.Source_Branch__c + ' → ' + r.Target_Branch__c;
        } else if (s === 'Workflow running') {
            state = 'Running';
            text = 'The pipeline is converting the files and opening the ' + this.crWord + '…';
        } else if (collected && s === 'Failed') {
            state = 'Failed';
        }
        return { key: 'pr', title: this.crLabel, state, text };
    }

    get conflictCountText() {
        const n = Array.isArray(this.validation.conflicts) ? this.validation.conflicts.length : 0;
        return n ? ' for ' + n + ' file' + (n === 1 ? '' : 's') : '';
    }

    get scanText() {
        const r = this.rel;
        const scan = this.scan;
        if (r.Scan_Status__c === 'Bypassed') {
            return 'Bypassed by ' + (r.Scan_Bypassed_By__r ? r.Scan_Bypassed_By__r.Name : '') + ': ' + r.Scan_Bypass_Reason__c;
        }
        if (r.Scan_Status__c === 'Not configured') {
            // The target org's own choice (RlyScanRule: Off) names the org; following the connection's switch, the repository.
            const choice = r.Target_Org__r ? r.Target_Org__r.Code_Scan__c : null;
            return choice === 'Off' ? 'Code scan is off for ' + this.targetName + '.' : 'Code scan is off for this repository.';
        }
        if (r.Scan_Status__c === 'Pending') {
            return r.PR_Number__c ? 'Salesforce Code Analyzer is running…' : '';
        }
        if (scan.message && !scan.total) {
            return scan.message;
        }
        const gate = scan.gate && scan.gate.failAtPriority ? ' · gate: fails at priority ' + scan.gate.failAtPriority + ' or higher' : '';
        if (scan.gate && scan.gate.findings) {
            return scan.gate.findings + ' scan finding' + (scan.gate.findings === 1 ? '' : 's') + ' at priority ' + scan.gate.failAtPriority + ' or higher' + gate;
        }
        if (scan.total) {
            return scan.total + ' finding' + (scan.total === 1 ? '' : 's') + ', ' + (scan.blocking || 0) + ' at '
                + (scan.thresholdLabel || 'High') + ' or above' + (scan.blocking ? ' (blocking)' : ': below the bar, so they don\'t block') + gate;
        }
        return r.Scan_Status__c === 'Passed' ? 'No findings.' : '';
    }

    get validationText() {
        const r = this.rel;
        const val = this.validation;
        if (r.Validation_Status__c === 'Pending') {
            return r.PR_Number__c ? 'Check-only deploy to ' + this.targetName + ' with ' + this.testLevelText + '…' : '';
        }
        if (r.Validation_Status__c === 'Not configured') {
            return 'The target has no Git environment: Git only.';
        }
        if (!val.status) {
            return '';
        }
        return (val.status === 'Passed' ? 'Check-only deploy passed' : val.message || val.status)
            + (val.testLevel ? ' · ' + val.testLevel + (val.testsRun ? ', ' + val.testsRun + ' tests run' : '') : '')
            + (val.mergedWith ? ' · merged with ' + r.Target_Branch__c + ' at ' + String(val.mergedWith).substring(0, 7) : '')
            + this.valuesText(val);
    }

    /** Per-org values (.relay/values.json) the pipeline put in for the target: " · 2 per-org values filled in". */
    valuesText(result) {
        const n = result && result.values ? Number(result.values.replaced) || 0 : 0;
        return n ? ' · ' + n + (n === 1 ? ' per-org value' : ' per-org values') + ' filled in' : '';
    }

    approvalStep() {
        const r = this.rel;
        const s = r.Status__c;
        let state = 'Waiting';
        let text = '';
        if (s === 'Ready for approval' && this.needsSecondApprover) {
            // The first of two approvals: the release keeps waiting for someone else.
            state = 'Running';
            text = 'Approved by ' + this.firstApprover + '. Waiting for a second approver.';
        } else if (r.Approval_Status__c === 'Approved' && r.Approved_Via__c === 'Rule') {
            // The target org's approval rule said no approval was needed (RlyApprovalRules).
            return { key: 'approval', title: 'Approval', state: 'Done', label: 'Approved automatically', pill: STEP_PILL.Running, text: when(r.Approved_On__c), ...this.reasonLine };
        } else if (r.Approval_Status__c === 'Approved' || r.Approval_Status__c === 'Rejected') {
            state = r.Approval_Status__c === 'Approved' ? 'Done' : 'Failed';
            text = r.Approval_Status__c + ' by ' + (r.Approved_By__r ? r.Approved_By__r.Name : '') + this.secondApproverText + ', ' + when(r.Approved_On__c)
                + (r.Approved_Via__c ? ' in ' + r.Approved_Via__c : '') + (r.Approval_Comment__c ? ': ' + r.Approval_Comment__c : '');
        } else if (s === 'Ready for approval') {
            state = 'Running';
            text = this.approveHere ? 'Waiting for an approver.' : 'Waiting for approval in ' + this.approvedInText + '.';
        }
        return { key: 'approval', title: 'Approval', state, text, ...this.reasonLine };
    }

    /** Detail.approvalReason under the Approval step: "Needs approval: contains a Flow and a Profile", "Approved automatically: …". */
    get approvalReason() { return (this.detail && this.detail.approvalReason) || ''; }
    get reasonLine() {
        const reason = this.approvalReason;
        if (!reason) {
            return { reason: '' };
        }
        const auto = this.rel.Approved_Via__c === 'Rule' || /^Approved automatically/i.test(reason);
        return { reason, reasonCls: 'rr-msg rr-step-reason ' + (auto ? 'rr-msg-ok' : 'rr-msg-info') };
    }

    deployStep() {
        const r = this.rel;
        const s = r.Status__c;
        const dep = this.deploy;
        let state = 'Waiting';
        let text = '';
        if (s === 'Deployed') {
            state = 'Done';
            text = 'Deployed' + (r.Merge_Commit__c ? ' · merge ' + r.Merge_Commit__c.substring(0, 7) : '') + (dep.testsRun ? ' · ' + dep.testsRun + ' tests run' : '');
        } else if (s === 'Deploying') {
            state = 'Running';
            text = 'Merging the ' + this.crWord + ' and deploying…';
        } else if (s === 'Deploy failed') {
            state = 'Failed';
            text = r.Error_Message__c || dep.message || 'Failed';
        }
        if (s === 'Deployed' && this.secondApprover) {
            text += ' · 2 approvers';
        }
        // After a deploy to the hub the branches merged back are their own steps (backMergeSteps).
        const sync = this.backMerge.length ? [] : this.syncRows;
        return { key: 'deploy', title: 'Merge and deploy to ' + this.targetName, state, text, sync, hasSync: sync.length > 0, syncLabel: 'Developer branches' };
    }

    checkState(status, result) {
        if (status === 'Passed') {
            return result && result.total ? 'Warn' : 'Done';
        }
        if (status === 'Skipped' || status === 'Not configured') {
            return 'Done';
        }
        if (status === 'Bypassed') {
            return 'Warn';
        }
        if (status === 'Failed' || status === 'Error') {
            return 'Failed';
        }
        return this.rel.PR_Number__c ? 'Running' : 'Waiting';
    }

    get testLevelText() {
        const t = this.rel.Test_Classes__c;
        return t ? 'RunSpecifiedTests (' + t.split(',').join(', ') + ')' : 'NoTestRun';
    }

    // ---------- details ----------

    get scanLabel() { return this.rel.Scan_Status__c || 'Pending'; }
    get scanPillCls() { return pillCls(this.scanLabel); }
    /** Findings by severity, for example "2 Low". */
    get scanSummary() {
        const counts = {};
        (this.scan.violations || []).forEach((v) => {
            const sev = v.severityLabel || 'Info';
            counts[sev] = (counts[sev] || 0) + 1;
        });
        return SEVERITY_ORDER.filter((s) => counts[s]).map((s) => counts[s] + ' ' + s).join(', ');
    }
    get validationLabel() {
        if (this.resolving) {
            return 'Pending';
        }
        return this.validation.status === 'Conflict' ? 'Conflict' : (this.rel.Validation_Status__c || 'Pending');
    }
    get validationPillCls() { return this.validationLabel === 'Conflict' ? 'rr-pill rr-pill-wait' : pillCls(this.validationLabel); }

    get items() {
        const tests = this.detail && Array.isArray(this.detail.tests) ? this.detail.tests : [];
        return (this.detail && this.detail.items ? this.detail.items : []).map((i) => ({
            key: i.Id, dtKey: i.Id + 't', type: typeLabel(i.Metadata_Type__c, tests.includes(i.Component_Name__c)), name: i.Component_Name__c
        }));
    }
    get itemCount() {
        const d = this.deletions.length;
        return String(this.items.length) + (d ? ' · ' + d + (d === 1 ? ' deletion' : ' deletions') : '');
    }

    /** What the release removes from the target branch and org: Detail.deletions, as Type:Name. */
    get deletions() {
        const list = this.detail && Array.isArray(this.detail.deletions) ? this.detail.deletions : [];
        return list.map((d, i) => {
            const at = String(d).indexOf(':');
            const type = at > 0 ? String(d).slice(0, at) : '';
            return { key: 'd' + i, dtKey: 'd' + i + 't', type: type ? typeLabel(type, false) : '', name: at > 0 ? String(d).slice(at + 1) : String(d) };
        });
    }
    get hasDeletions() { return this.deletions.length > 0; }
    get deletesLabel() { return 'Deleted from ' + (this.targetName || 'the target'); }

    // ---------- results ----------

    /**
     * Findings with their priority (PMD 1 = most serious, the pipeline's severity). With a scan gate (scan.json gate,
     * .relay/gates.json) the findings that broke it get a red pill and the rest grey; without one, by severity.
     */
    get violations() {
        const gate = this.scan.gate && Number(this.scan.gate.failAtPriority);
        return (this.scan.violations || []).slice(0, 100).map((v, i) => {
            const priority = Number(v.severity) || '';
            let sevCls = SEVERITY_CLS[v.severityLabel] || 'rr-pill rr-pill-none';
            if (gate) {
                sevCls = priority && priority <= gate ? 'rr-pill rr-pill-bad' : 'rr-pill rr-pill-none';
            }
            return {
                key: 'v' + i, ...v, priority: priority || v.severityLabel || '', sevCls: sevCls + ' rr-prio',
                where: (v.file || '').split('/').pop() + (v.line ? ':' + v.line : '')
            };
        });
    }

    /** gates.failures of scan.json and validate.json (.relay/gates.json), shown as they are. */
    get gateFailures() {
        const out = [];
        [this.scan, this.validation].forEach((r, n) => {
            const g = r && r.gates;
            if (g && g.passed === false && Array.isArray(g.failures)) {
                g.failures.forEach((f, i) => out.push({ key: 'g' + n + '-' + i, text: String(f), file: g.file }));
            }
        });
        return out;
    }
    get hasGateFailures() { return this.gateFailures.length > 0; }
    get gatesFile() {
        const named = this.gateFailures.find((g) => g.file);
        return named ? named.file : GATES_FILE;
    }
    get hasViolations() { return this.violations.length > 0; }

    get problems() {
        const out = [];
        [['Validation', this.validation], ['Deploy', this.deploy], ['Rollback', this.rollbackResult]].forEach(([label, r]) => {
            (r.componentErrors || []).forEach((c, i) => out.push({ key: label + 'c' + i, label, what: c.type + ' ' + c.name + (c.line ? ':' + c.line : ''), message: c.problem }));
            (r.testFailures || []).forEach((t, i) => out.push({ key: label + 't' + i, label, what: t.name + '.' + t.method, message: t.message }));
            (r.coverageWarnings || []).forEach((w, i) => out.push({ key: label + 'w' + i, label, what: w.name || 'Coverage', message: w.message }));
        });
        return out;
    }
    get hasProblems() { return this.problems.length > 0; }

    /**
     * The files a promotion clashed on (raise.json conflicts, kept as Validation_Result__c raiseConflicts): the next
     * stop has a change to them that the stage doesn't. Listed under the message; no conflict editor.
     */
    get raiseConflicts() {
        const files = this.validation.raiseConflicts;
        return Array.isArray(files) ? files.map((f, i) => ({ key: 'rc' + i, path: typeof f === 'string' ? f : (f && f.file) || String(f) })) : [];
    }
    get hasRaiseConflicts() { return this.raiseConflicts.length > 0; }

    // ---------- add changes to an open release ----------

    /** Detail.canAppend: a normal release, Checks failed or Ready for approval, not approved, nothing running, raiser or admin. */
    get canAppend() { return !!(this.detail && this.detail.canAppend) && !this.running; }
    get appendLabel() { return 'Add changes from ' + ((this.detail && this.detail.sourceName) || 'the developer org'); }

    /** Opens New Release in append mode for this release (it starts at Select, with the release's components locked). */
    openAppend() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: BUILDER_TAB },
            state: { c__appendTo: this._releaseId }
        });
    }

    /** Error_Message__c whatever the status (for example a rejected release whose pull request couldn't be closed). */
    get errorBanner() {
        return this.rel.Error_Message__c || null;
    }
    get errorBannerCls() {
        return 'rr-msg rr-note ' + (ENDED_BADLY.includes(this.rel.Status__c) ? 'rr-msg-bad' : 'rr-msg-warn');
    }

    /** How each developer branch was updated from the target after the merge (merge.json sync). */
    get syncRows() {
        const target = this.rel.Target_Branch__c || 'the target';
        return (Array.isArray(this.deploy.sync) ? this.deploy.sync : []).map((b, i) => {
            const state = SYNC_STATE[b.status] || { label: b.status || 'Unknown', cls: 'rr-pill rr-pill-none' };
            const text = b.status === 'Synced'
                ? b.branch + ' updated from ' + target
                : b.branch + ' couldn\'t be updated from ' + target + (b.message ? ': ' + b.message : '')
                    + '. Merge it by hand so that ' + b.branch + ' starts from the latest ' + target + '.';
            return { key: 'sync' + i, label: state.label, cls: state.cls, text };
        });
    }

    // ---------- after a deploy to the hub: merged back down, back promote ----------

    /** Detail.backMerge: how each branch was updated from the hub's branch after the deploy (stage branches, then developer branches). */
    get backMerge() {
        return this.detail && Array.isArray(this.detail.backMerge) ? this.detail.backMerge : [];
    }

    /**
     * "Merged back to <stage branches>" and "Merged back to developer branches", each Done or "n to review" with a line per branch.
     * A branch's kind (Stage or Developer), when the server sends it, splits the list; without it the branches are one step.
     */
    backMergeSteps() {
        const list = this.backMerge;
        if (!list.length) {
            return [];
        }
        const hasKind = list.some((b) => b.kind);
        if (!hasKind) {
            return [this.mergeBackStep('mb-all', 'Merged back to ' + list.map((b) => b.branch).join(', '), list)];
        }
        const stages = list.filter((b) => b.kind === 'Stage');
        const devs = list.filter((b) => b.kind !== 'Stage');
        const out = [];
        if (stages.length) {
            out.push(this.mergeBackStep('mb-stages', 'Merged back to ' + stages.map((b) => b.branch).join(', '), stages));
        }
        if (devs.length) {
            out.push(this.mergeBackStep('mb-devs', 'Merged back to developer branches', devs));
        }
        return out;
    }

    mergeBackStep(key, title, branches) {
        const open = branches.filter((b) => b.status !== BRANCH_OK);
        const lines = branches.map((b, i) => {
            const ok = b.status === BRANCH_OK;
            let text = b.branch + ' updated from ' + (this.rel.Target_Branch__c || 'the target');
            if (!ok) {
                text = b.branch + (b.status === 'Missing' ? ': branch not found' : ': conflicts with work in progress')
                    + (b.message ? ' (' + b.message + ')' : '') + '. Merge it by hand so it starts from the latest ' + (this.rel.Target_Branch__c || 'target') + '.';
            }
            const state = SYNC_STATE[b.status] || { label: b.status || 'Unknown', cls: 'rr-pill rr-pill-none' };
            return { key: key + i, label: ok ? '✓' : state.label, cls: ok ? 'rr-pill rr-pill-ok' : state.cls, text };
        });
        return {
            key, title, state: 'Done', badge: '✓',
            label: open.length ? open.length + ' to review' : 'Done',
            pill: open.length ? STEP_PILL.Warn : STEP_PILL.Done,
            text: '', sync: lines, hasSync: true, syncLabel: title
        };
    }

    /** Detail.backPromote: Off, or what happened per back promote org (for example "Sent to an org: Deployed"). */
    backPromoteStep() {
        const value = this.detail && this.detail.backPromote;
        if (!value || this.rel.Status__c !== 'Deployed') {
            return null;
        }
        if (value === 'Off') {
            return { key: 'bp', title: 'Back promote', state: 'Waiting', badge: '→', label: 'Off', pill: STEP_PILL.Waiting, text: 'Not set up on the Pipeline tab' };
        }
        let state = 'Waiting';
        let label = 'Waiting';
        if (/Failed/.test(value)) {
            state = 'Failed';
            label = 'Failed';
        } else if (/Conflict/.test(value)) {
            state = 'Warn';
            label = 'To review';
        } else if (/Running|Deploying/.test(value)) {
            state = 'Running';
            label = 'In progress';
        } else if (/Deployed|Nothing to deploy/.test(value)) {
            state = 'Done';
            label = 'Done';
        }
        return { key: 'bp', title: 'Back promote', state, label, badge: state === 'Waiting' ? '→' : '', text: value };
    }

    // ---------- promotions, second approver ----------

    get carried() {
        const list = this.detail && Array.isArray(this.detail.carried) ? this.detail.carried : [];
        return list.map((c) => ({ key: 'c' + c.id, id: c.id, name: c.name, title: c.title, isHotfix: c.isHotfix === true, manualOnly: c.manualOnly === true, href: this.releaseHref(c.id) }));
    }
    get hasCarried() { return this.releaseType === 'Promotion' && this.carried.length > 0; }
    get promotedIn() {
        const d = this.detail;
        return d && d.promotedInId ? { id: d.promotedInId, name: d.promotedInName || 'the promotion', href: this.releaseHref(d.promotedInId) } : null;
    }

    releaseHref(releaseId) {
        return '/lightning/n/' + RELEASES_TAB + '?c__release=' + releaseId;
    }

    /** Opens another release (a carried one, or the promotion) on the Releases tab. */
    openRelease(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: RELEASES_TAB },
            state: { c__release: event.currentTarget.dataset.id }
        });
    }

    get needsSecondApprover() { return !!(this.detail && this.detail.needsSecondApprover); }
    get firstApprover() { return (this.detail && this.detail.firstApprover) || 'the first approver'; }
    get secondApprover() { return this.rel.Second_Approved_By__r ? this.rel.Second_Approved_By__r.Name : ''; }
    get secondApproverText() { return this.secondApprover ? ' and ' + this.secondApprover : ''; }
    /** Shown above the timeline unless the server's notice already says it. */
    get secondApproverNotice() {
        if (!this.needsSecondApprover || this.rel.Status__c !== 'Ready for approval') {
            return '';
        }
        const notice = (this.detail.notice || '').toLowerCase();
        if (notice.includes('second approver')) {
            return '';
        }
        return 'Approved by ' + this.firstApprover + '. Waiting for a second approver: someone else, not the person who raised it.';
    }

    // ---------- conflicts ----------

    get hasConflicts() {
        return !this.resolving && this.rel.Status__c === 'Checks failed' && this.validation.status === 'Conflict'
            && Array.isArray(this.validation.conflicts) && this.validation.conflicts.length > 0;
    }
    get canResolve() { return !!(this.detail && this.detail.canResolve && this.rel.PR_Number__c) && !this.hubCopy; }

    handleResolve(event) {
        this.act(resolveConflicts, { resolutionsJson: JSON.stringify({ resolutions: event.detail.resolutions }) });
    }

    // ---------- flows (Detail.flows: one FlowResult per org and flow, from Flow_Results__c) ----------

    /** The After deploy choice per flow, from RLY_Release__c.Flow_Actions__c ([{name, choice}]). */
    get flowActions() {
        const list = parse(this.rel.Flow_Actions__c);
        const out = {};
        (Array.isArray(list) ? list : []).forEach((f) => {
            if (f && f.name) {
                out[f.name] = f.choice;
            }
        });
        return out;
    }
    get flowResults() { return this.detail && Array.isArray(this.detail.flows) ? this.detail.flows : []; }

    /** One row per flow: its choice and "SIT v9 active · PROD failed: …" (board HubApprovalFlowsEvidence 3). */
    get flowRows() {
        const actions = this.flowActions;
        const byFlow = new Map();
        Object.keys(actions).forEach((name) => byFlow.set(name, []));
        this.flowResults.forEach((r) => {
            const name = r.flow || r.name;
            if (!byFlow.has(name)) {
                byFlow.set(name, []);
            }
            byFlow.get(name).push(r);
        });
        return [...byFlow.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([name, results]) => {
            const choice = actions[name] || (results[0] && results[0].choice) || 'Keep';
            const parts = results.map((r, i) => {
                const failed = r.status === FLOW_FAILED;
                let text = r.org + (r.version ? ' v' + r.version : '') + ' ';
                if (failed) {
                    text = r.org + ' failed' + (r.message ? ': “' + r.message + '”' : '');
                } else if (r.status === FLOW_ACTIVATED || r.status === FLOW_ALREADY) {
                    text += 'active';
                } else {
                    text += String(r.status || '').toLowerCase() + (r.message ? ' (' + r.message + ')' : '');
                }
                return { key: name + i, text, cls: failed ? 'rr-flow-bad' : '', sep: i > 0 };
            });
            return {
                key: name, name,
                choiceText: FLOW_CHOICE_LABEL[choice] || 'Keep as in ' + ((this.detail && this.detail.sourceName) || 'the developer org'),
                parts,
                waiting: !parts.length,
                waitText: choice === 'Activate' ? 'Activated after each deploy.' : 'Deployed as it is in ' + ((this.detail && this.detail.sourceName) || 'the developer org') + '.'
            };
        });
    }
    get hasFlows() { return this.flowRows.length > 0; }
    get flowActivatedText() {
        const n = this.flowResults.filter((r) => r.status === FLOW_ACTIVATED).length;
        return n ? n + ' activated' : '';
    }
    get flowFailedText() {
        const n = this.flowResults.filter((r) => r.status === FLOW_FAILED).length;
        return n ? n + ' failed' : '';
    }

    // ---------- history (Detail.events, newest first: a vertical path reading "this happened after that") ----------

    get events() {
        const list = this.detail && Array.isArray(this.detail.events) ? [...this.detail.events] : [];
        list.sort((a, b) => new Date(b.occurredOn || 0) - new Date(a.occurredOn || 0));
        let lastDay = '';
        return list.map((e, i) => {
            const look = EVENT_LOOK[e.eventType] || EVENT_LOOK.Comment;
            const day = dayOf(e.occurredOn);
            const whenText = day === lastDay ? timeOnly(e.occurredOn) : when(e.occurredOn);
            lastDay = day;
            const orgWord = EVENT_ORG_WORD[e.eventType];
            const failed = CHECK_EVENTS.includes(e.eventType) && /fail|error|block/i.test(e.detail || '');
            const ref = e.reference || '';
            return {
                key: e.id || 'e' + i,
                title: e.title || this.eventTitle(e, look, failed) + (orgWord && e.orgName ? orgWord + e.orgName : ''),
                icon: look.icon,
                cls: 'rr-vt-dot rr-vt-' + eventTone(e, failed),
                hasArrow: i < list.length - 1,
                who: [e.actorName, e.via].filter(Boolean).join(' · '),
                whenText,
                detail: e.detail || '',
                refLink: /^https?:\/\//i.test(ref) ? ref : '',
                refText: /^https?:\/\//i.test(ref) ? '' : ref
            };
        });
    }
    // ---------- Open org (admins and the deployment team; the hub is never listed) ----------

    /** RlyOrgLinks.OrgLink rows: the route's orgs with their login address (My Domain + "/"), empty for everyone else. */
    get orgLinks() {
        const links = this.detail && Array.isArray(this.detail.orgLinks) ? this.detail.orgLinks : [];
        return links.filter((l) => l && l.loginUrl).map((l) => ({
            ...l,
            menuLabel: 'Log in to ' + l.name,
            menuTitle: l.environment ? l.name + ' · ' + l.environment : l.name
        }));
    }
    get hasOrgLinks() { return this.orgLinks.length > 0; }
    /** Opens the chosen org's login page (or single sign-on) in a new window; no sign-in details, only its address. */
    openOrg(event) {
        const link = this.orgLinks.find((l) => l.orgId === event.detail.value);
        if (link) {
            window.open(link.loginUrl, '_blank', 'noopener,noreferrer');
        }
    }

    /** "Code scan passed", "Check-only deploy failed", "Flow activation failed": the event's line says which. */
    eventTitle(e, look, failed) {
        if (e.eventType === 'Flow_Activated') {
            return failed ? 'Flow activation failed' : look.title;
        }
        if (CHECK_EVENTS.includes(e.eventType)) {
            return look.title + (failed ? ' failed' : ' passed');
        }
        return look.title;
    }
    get hasEvents() { return this.events.length > 0; }
    get eventCountText() { const n = this.events.length; return n + (n === 1 ? ' event' : ' events'); }

    // ---------- evidence: PDF in the release's Files, plain-text summary ----------

    evidenceBusy = false;
    showSummary = false;
    get evidenceLabel() { return this.evidenceBusy ? 'Saving evidence…' : 'Download evidence (PDF)'; }

    /** RlyEvidenceController.saveEvidence: saves the PDF to the release's Files and returns its download address. */
    async downloadEvidence() {
        this.evidenceBusy = true;
        try {
            const res = await saveEvidence({ releaseId: this._releaseId });
            if (res && res.downloadUrl) {
                this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url: res.downloadUrl } });
            }
            this.toast('Evidence saved to the release\'s Files' + (res && res.title ? ': ' + res.title + '.pdf' : '.'), 'success');
        } catch (e) {
            this.toast(errorText(e), 'error');
        } finally {
            this.evidenceBusy = false;
        }
    }

    get summaryLabel() { return this.showSummary ? 'Hide summary' : 'Copy summary'; }

    /** A plain-text block for a change request. */
    get summaryText() {
        const r = this.rel;
        const d = this.detail || {};
        const lines = [(r.Name || '') + ' ' + (r.Title__c || '')];
        lines.push('Route: ' + d.sourceName + ' → ' + d.targetName + ' · raised by ' + this.raisedBy + ', ' + this.raisedOn);
        if (this.isHotfix) {
            lines.push('Hotfix: ' + this.hotfixReason);
        }
        if (this.manualOnly) {
            lines.push(MANUAL_ONLY + ': no components; Git branch, ' + this.crWord + ', scan and validation not needed');
        } else {
            lines.push('Components: ' + this.items.length + this.componentBreakdown);
            if (this.hasDeletions) {
                lines.push('Deletes: ' + this.deletions.map((x) => x.name).join(', '));
            }
            lines.push('Scan: ' + this.scanLabel.toLowerCase() + (this.scanSummary ? ', ' + this.scanSummary : '') + ' · Tests: ' + this.testsText);
            lines.push('Validation: ' + this.validationLabel.toLowerCase() + (this.validation.testsRun ? ', ' + this.validation.testsRun + ' tests run' : ''));
        }
        lines.push('Approval: ' + this.approvalSummary);
        lines.push('Status: ' + this.phase + (r.Merge_Commit__c ? ' · merge ' + r.Merge_Commit__c.substring(0, 7) : ''));
        if (this.rollback.label) {
            lines.push('Rollback: ' + this.rollback.label + ' by ' + (this.rollback.byName || '') + ', ' + when(this.rollback.rolledBackOn)
                + (this.rollback.reason ? ': ' + this.rollback.reason : ''));
        }
        this.flowRows.forEach((f) => lines.push('Flow ' + f.name + ': ' + (f.parts.length ? f.parts.map((p) => p.text).join(' · ') : f.choiceText)));
        if (d.manualSummary) {
            lines.push('Manual steps: ' + d.manualSummary);
        }
        if (r.PR_URL__c) {
            lines.push(this.crLabel + ': ' + r.PR_URL__c);
        }
        return lines.join('\n');
    }

    get componentBreakdown() {
        const counts = {};
        this.items.forEach((i) => {
            counts[i.type] = (counts[i.type] || 0) + 1;
        });
        const parts = Object.keys(counts).sort().map((t) => counts[t] + ' ' + t);
        return parts.length ? ' (' + parts.join(', ') + ')' : '';
    }

    get approvalSummary() {
        const r = this.rel;
        if (r.Approved_Via__c === 'Rule') {
            const reason = this.approvalReason.replace(/^Approved automatically:?\s*/i, '');
            return 'approved automatically (rule)' + (reason ? ': ' + reason : '');
        }
        if (r.Approval_Status__c === 'Approved' || r.Approval_Status__c === 'Rejected') {
            return r.Approval_Status__c.toLowerCase() + ' by ' + (r.Approved_By__r ? r.Approved_By__r.Name : '') + this.secondApproverText + ', '
                + when(r.Approved_On__c) + (r.Approved_Via__c ? ' (' + r.Approved_Via__c + ')' : '') + (r.Approval_Comment__c ? ': ' + r.Approval_Comment__c : '');
        }
        return this.approvalReason || 'not yet';
    }

    /** Copies the summary and shows it, so it can be selected by hand where the browser blocks the clipboard. */
    copySummary() {
        if (this.showSummary) {
            this.showSummary = false;
            return;
        }
        this.showSummary = true;
        const clip = typeof navigator !== 'undefined' ? navigator.clipboard : null;
        if (!clip || !clip.writeText) {
            this.toast('Select the summary below and copy it.', 'info');
            return;
        }
        clip.writeText(this.summaryText)
            .then(() => this.toast('Summary copied', 'success'))
            .catch(() => this.toast('Select the summary below and copy it.', 'info'));
    }

    get lowerLeft() { return this.hasFlows || this.showSummary; }
    get lowerCls() { return this.lowerLeft ? 'rr-cols rr-cols-even' : 'rr-one'; }
    get showLower() { return this.lowerLeft || this.hasEvents; }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: (this.rel.Name || 'Release'), message, variant }));
    }

    // ---------- roll back (board HubRollbackValuesGates, panels 1 and 2) ----------

    rollbackOpen = false;
    /** The rollback state the page last read (undefined before the first read). */
    lastRollback;

    /** Detail.rollbackState (RlyRollbackView.View): the latest rollback and whether this user may roll back. */
    get rollback() { return (this.detail && this.detail.rollbackState) || {}; }
    get rollbackResult() { return parse(this.rollback.resultJson) || {}; }
    /** Release Relay admins and the deployment team, on the hub, for a deployed release; hidden for everyone else. */
    get showRollback() { return this.rollback.canRollBack === true && !this.hubCopy; }
    get rollbackDisabled() { return this.rollback.busy === true || this.busy; }
    get rollbackTitle() { return this.rollbackDisabled ? 'A deploy or rollback is running' : 'Put an org back the way it was before this release'; }

    openRollback() {
        this.rollbackOpen = true;
    }

    closeRollback() {
        this.rollbackOpen = false;
    }

    /** The dialog started the rollback: read the release again, which follows the rollback until it ends. */
    rollbackStarted(event) {
        this.rollbackOpen = false;
        this.toast('Rolling back in ' + ((event.detail && event.detail.orgName) || 'the org') + '. Git is not changed.', 'success');
        this.load();
    }

    /** "PROD was rolled back on 1 Nov 14:20 by Ana. The prod branch in Git still has this release's changes: …" */
    get rolledBackNotice() {
        const rb = this.rollback;
        if (rb.status !== ROLLED_BACK) {
            return '';
        }
        const branch = this.rollbackResult.branch || '';
        return rb.orgName + ' was rolled back on ' + when(rb.rolledBackOn) + (rb.byName ? ' by ' + rb.byName : '') + '. The '
            + (branch ? branch + ' branch' : 'branch') + ' in Git still has this release\'s changes: raise a release to fix the branch.';
    }

    /** The Roll back <org> step: running, done (restored, removed) or failed (the errors are under Deployment errors). */
    rollbackStep() {
        const rb = this.rollback;
        if (!rb.status) {
            return null;
        }
        const res = this.rollbackResult;
        const tests = Array.isArray(res.tests) ? res.tests.length : 0;
        let state = 'Running';
        let label = 'Running';
        let text = 'Started ' + timeOnly(rb.rolledBackOn) + (rb.byName ? ' by ' + rb.byName : '') + ' · deploying the snapshot'
            + (tests ? ', running ' + tests + (tests === 1 ? ' test' : ' tests') : '');
        if (rb.status === ROLLED_BACK) {
            state = 'Done';
            label = 'Done';
            text = when(rb.rolledBackOn) + ' · restored ' + (res.restored || 0) + ', removed ' + (res.removed || 0)
                + (res.deployId ? ' · ' + res.deployId : '') + (res.testsRun ? ' · ' + res.testsRun + ' tests run' : '');
        } else if (rb.status !== ROLLBACK_RUNNING) {
            state = 'Failed';
            label = 'Failed';
            text = res.message || 'The rollback failed. The org is unchanged.';
        }
        return {
            key: 'rollback', title: 'Roll back ' + (rb.orgName || ''), state, label, badge: state === 'Running' ? '↺' : '',
            text, reason: rb.reason ? '“' + rb.reason + '”' : '', reasonCls: 'rr-small rr-weak', link: res.runUrl || '', linkLabel: 'Pipeline run'
        };
    }

    // ---------- actions ----------

    get isApprover() { return !!(this.detail && this.detail.isApprover); }
    get canApprove() { return this.isApprover && this.approveHere && this.rel.Status__c === 'Ready for approval'; }
    /** Ready for approval, but approved from the Slack card rather than here. */
    get approvedElsewhere() { return !this.approveHere && this.rel.Status__c === 'Ready for approval'; }
    get canReject() { return this.isApprover && (this.rel.Status__c === 'Ready for approval' || this.rel.Status__c === 'Checks failed'); }
    get canBypass() {
        return this.isApprover && this.rel.Status__c === 'Checks failed'
            && (this.rel.Scan_Status__c === 'Failed' || this.rel.Scan_Status__c === 'Error');
    }
    get canCheckAgain() { return ['Checks failed', 'Ready for approval'].includes(this.rel.Status__c) && !!this.rel.PR_Number__c; }
    get validationBlocks() { return ['Failed', 'Error'].includes(this.rel.Validation_Status__c); }
    get showDecision() { return !this.running && (this.canBypass || this.canReject); }

    /** While the checks run the bar shows the actions disabled; after that, the ones this user can take. */
    get waitingForChecks() { return this.running && ['Retrieving', 'Workflow running', 'Validating'].includes(this.rel.Status__c); }
    get showCheckAgain() { return this.waitingForChecks || this.canCheckAgain; }
    get showReject() { return (this.waitingForChecks && this.isApprover) || this.canReject; }
    get showApprove() { return (this.waitingForChecks && this.isApprover && this.approveHere) || this.canApprove; }
    get checkAgainDisabled() { return this.actBusy || !this.canCheckAgain; }
    get rejectDisabled() { return this.actBusy || !this.canReject; }
    get approveDisabled() { return this.actBusy || !this.canApprove; }
    get needsApproverNote() {
        return !this.isApprover && ['Ready for approval', 'Checks failed'].includes(this.rel.Status__c);
    }
    get footNote() {
        if (this.waitingForChecks) {
            return 'Actions show when the checks finish.';
        }
        if (this.approvedElsewhere) {
            return 'Approved from the Slack card.';
        }
        if (this.needsApproverNote) {
            return 'An approver approves or rejects it on the Approvals tab.';
        }
        if (this.needsSecondApprover && this.rel.Status__c === 'Ready for approval') {
            return 'A hotfix into ' + this.targetName + ' needs 2 approvers. The person who raised it can\'t approve it.';
        }
        return '';
    }
    get showFooter() { return this.showCheckAgain || this.showReject || this.showApprove || !!this.footNote; }

    handleComment(event) { this.comment = event.target.value; }
    handleReason(event) { this.reason = event.target.value; }

    async act(fn, args) {
        this.busy = true;
        this.error = undefined;
        try {
            this.detail = await fn({ releaseId: this._releaseId, ...args });
            this.comment = '';
            this.reason = '';
            if (this.detail.running) {
                this.load();
            }
            this.dispatchEvent(new CustomEvent('changed', { detail: this.detail.release.Status__c }));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    doApprove() { this.act(approve, { comment: this.comment }); }
    doReject() { this.act(reject, { comment: this.comment }); }
    doBypass() { this.act(bypassScan, { reason: this.reason }); }
    doCheckAgain() { this.act(checkAgain, {}); }
}
