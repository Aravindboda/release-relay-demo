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
const RELEASES_TAB = 'RLY_My_Releases';
const BRANCH_OK = 'Synced';
/** RLY_Release_Event__c.Event_Type__c: the History card's title and icon per event (board HubApprovalFlowsEvidence 3). */
const EVENT_LOOK = {
    Raised: { title: 'Raised', icon: 'utility:add', cls: 'rr-tli rr-c-raise' },
    Pull_Request: { title: 'Pull request opened', icon: 'utility:merge', cls: 'rr-tli rr-c-git' },
    Scan: { title: 'Code scan', icon: 'utility:check', cls: 'rr-tli rr-c-scan' },
    Validation: { title: 'Check-only deploy', icon: 'utility:check', cls: 'rr-tli rr-c-val' },
    Approved: { title: 'Approved', icon: 'utility:approval', cls: 'rr-tli rr-c-appr' },
    Rejected: { title: 'Rejected', icon: 'utility:close', cls: 'rr-tli rr-c-fail' },
    Auto_Approved: { title: 'Approved automatically', icon: 'utility:settings', cls: 'rr-tli rr-c-auto' },
    Deployed: { title: 'Deployed', icon: 'utility:upload', cls: 'rr-tli rr-c-dep' },
    Deploy_Failed: { title: 'Deploy failed', icon: 'utility:error', cls: 'rr-tli rr-c-fail' },
    Manual_Step: { title: 'Manual step done', icon: 'utility:task', cls: 'rr-tli rr-c-man' },
    Flow_Activated: { title: 'Flow activated', icon: 'utility:flow', cls: 'rr-tli rr-c-flow' },
    Merged_Back: { title: 'Merged back', icon: 'utility:merge', cls: 'rr-tli rr-c-git' },
    Promoted: { title: 'Promoted', icon: 'utility:forward', cls: 'rr-tli rr-c-git' },
    Back_Promoted: { title: 'Back promoted', icon: 'utility:back', cls: 'rr-tli rr-c-git' },
    Comment: { title: 'Comment', icon: 'utility:comments', cls: 'rr-tli rr-c-git' }
};
/** Types whose title names the org: "Deployed to <org>", "Approved for <org>"… */
const EVENT_ORG_WORD = { Approved: ' for ', Rejected: ' for ', Deployed: ' to ', Deploy_Failed: ' in ', Validation: ' in ', Manual_Step: ' in ', Flow_Activated: ' in ', Auto_Approved: ' for ' };
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
     * RlyHubGuard.getHubStatus: whether this org is a sandbox copy of the hub. The tab around this view shows the banner;
     * here the actions are disabled.
     */
    hubStatus;

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
        if (value) {
            this.load();
        }
    }

    connectedCallback() {
        this.readHubStatus();
    }

    disconnectedCallback() {
        this.stop();
    }

    /** Reads the hub status once. A failed read disables nothing: the server refuses the actions anyway. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
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
    /** Header pill: Detail.manualOpen, the manual steps still open for this release. */
    get manualOpenText() {
        const n = Number(this.detail && this.detail.manualOpen) || 0;
        return n ? n + (n === 1 ? ' manual step open' : ' manual steps open') : '';
    }
    get hotfixReason() { return this.isHotfix ? (this.detail.hotfixReason || '') : ''; }
    /** The header pill: Detail.phase (for example Resolving conflicts), else the status. */
    get phase() { return (this.detail && this.detail.phase) || this.rel.Status__c; }
    get phaseCls() { return pillCls(this.phase); }
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
        return PATH.map((p, i) => {
            let state = 'todo';
            if (i < pos.index) {
                state = 'done';
            } else if (i === pos.index) {
                state = pos.failed ? 'lost' : 'current';
            }
            return {
                ...p,
                label: p.key === 'pr' ? this.crLabel : p.label,
                cls: 'rr-path-item rr-path-' + state,
                current: i === pos.index ? 'step' : null,
                stateText: { done: 'Done', lost: 'Failed', current: 'Current', todo: 'Not yet' }[state]
            };
        });
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
        const backPromote = this.backPromoteStep();
        if (backPromote) {
            steps.push(backPromote);
        }
        return steps.map((st, i) => this.decorate(st, i));
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
            return 'Code scan is off for this repository.';
        }
        if (r.Scan_Status__c === 'Pending') {
            return r.PR_Number__c ? 'Salesforce Code Analyzer is running…' : '';
        }
        if (scan.message && !scan.total) {
            return scan.message;
        }
        if (scan.total) {
            return scan.total + ' finding' + (scan.total === 1 ? '' : 's') + ', ' + (scan.blocking || 0) + ' at '
                + (scan.thresholdLabel || 'High') + ' or above' + (scan.blocking ? ' (blocking)' : ': below the bar, so they don\'t block');
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
            + (val.mergedWith ? ' · merged with ' + r.Target_Branch__c + ' at ' + String(val.mergedWith).substring(0, 7) : '');
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

    get violations() {
        return (this.scan.violations || []).slice(0, 100).map((v, i) => ({
            key: 'v' + i, ...v, sevCls: SEVERITY_CLS[v.severityLabel] || 'rr-pill rr-pill-none',
            where: (v.file || '').split('/').pop() + (v.line ? ':' + v.line : '')
        }));
    }
    get hasViolations() { return this.violations.length > 0; }

    get problems() {
        const out = [];
        [['Validation', this.validation], ['Deploy', this.deploy]].forEach(([label, r]) => {
            (r.componentErrors || []).forEach((c, i) => out.push({ key: label + 'c' + i, label, what: c.type + ' ' + c.name + (c.line ? ':' + c.line : ''), message: c.problem }));
            (r.testFailures || []).forEach((t, i) => out.push({ key: label + 't' + i, label, what: t.name + '.' + t.method, message: t.message }));
            (r.coverageWarnings || []).forEach((w, i) => out.push({ key: label + 'w' + i, label, what: w.name || 'Coverage', message: w.message }));
        });
        return out;
    }
    get hasProblems() { return this.problems.length > 0; }

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
        return list.map((c) => ({ key: 'c' + c.id, id: c.id, name: c.name, title: c.title, isHotfix: c.isHotfix === true, href: this.releaseHref(c.id) }));
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

    // ---------- history (Detail.events, oldest first) ----------

    get events() {
        const list = this.detail && Array.isArray(this.detail.events) ? [...this.detail.events] : [];
        list.sort((a, b) => new Date(a.occurredOn || 0) - new Date(b.occurredOn || 0));
        let lastDay = '';
        return list.map((e, i) => {
            const look = EVENT_LOOK[e.eventType] || EVENT_LOOK.Comment;
            const day = dayOf(e.occurredOn);
            const whenText = day === lastDay ? timeOnly(e.occurredOn) : when(e.occurredOn);
            lastDay = day;
            const orgWord = EVENT_ORG_WORD[e.eventType];
            const checked = CHECK_EVENTS.includes(e.eventType);
            const failed = checked && /fail|error|block/i.test(e.detail || '');
            const ref = e.reference || '';
            return {
                key: e.id || 'e' + i,
                title: e.title || this.eventTitle(e, look, failed) + (orgWord && e.orgName ? orgWord + e.orgName : ''),
                icon: look.icon,
                cls: failed ? 'rr-tli rr-c-fail' : look.cls,
                who: [e.actorName, e.via].filter(Boolean).join(' · '),
                whenText,
                detail: e.detail || '',
                refLink: /^https?:\/\//i.test(ref) ? ref : '',
                refText: /^https?:\/\//i.test(ref) ? '' : ref
            };
        });
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
        lines.push('Components: ' + this.items.length + this.componentBreakdown);
        if (this.hasDeletions) {
            lines.push('Deletes: ' + this.deletions.map((x) => x.name).join(', '));
        }
        lines.push('Scan: ' + this.scanLabel.toLowerCase() + (this.scanSummary ? ', ' + this.scanSummary : '') + ' · Tests: ' + this.testsText);
        lines.push('Validation: ' + this.validationLabel.toLowerCase() + (this.validation.testsRun ? ', ' + this.validation.testsRun + ' tests run' : ''));
        lines.push('Approval: ' + this.approvalSummary);
        lines.push('Status: ' + this.phase + (r.Merge_Commit__c ? ' · merge ' + r.Merge_Commit__c.substring(0, 7) : ''));
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
