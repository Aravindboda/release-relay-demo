import { LightningElement, api } from 'lwc';
import refreshRelease from '@salesforce/apex/RlyReleasesController.refreshRelease';
import bypassScan from '@salesforce/apex/RlyReleasesController.bypassScan';
import checkAgain from '@salesforce/apex/RlyReleasesController.checkAgain';
import approve from '@salesforce/apex/RlyReleasesController.approve';
import reject from '@salesforce/apex/RlyReleasesController.reject';

const POLL_SECONDS = 30;
const GOOD = ['Deployed', 'Ready for approval'];
const BAD = ['Checks failed', 'Deploy failed', 'Failed', 'Rejected'];
const RUNNING = ['Retrieving', 'Workflow running', 'Validating', 'Deploying'];
const SEVERITY_CLS = { Critical: 'rr-pill rr-pill-bad', High: 'rr-pill rr-pill-bad', Moderate: 'rr-pill rr-pill-wait', Low: 'rr-pill rr-pill-none', Info: 'rr-pill rr-pill-none' };

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
    if (GOOD.includes(status) || status === 'Passed' || status === 'Approved' || status === 'Merged') {
        return 'rr-pill rr-pill-ok';
    }
    if (BAD.includes(status) || status === 'Failed' || status === 'Error') {
        return 'rr-pill rr-pill-bad';
    }
    if (RUNNING.includes(status) || status === 'Pending' || status === 'Deploying') {
        return 'rr-pill rr-pill-wait';
    }
    return 'rr-pill rr-pill-none';
}

function when(value) {
    return value ? new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
}

export default class RlyReleaseView extends LightningElement {
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
    showItems = false;

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

    disconnectedCallback() {
        this.stop();
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

    // ---------- header ----------

    get rel() { return this.detail ? this.detail.release : {}; }
    get statusCls() { return pillCls(this.rel.Status__c); }
    get route() { return this.detail ? this.detail.sourceName + ' → ' + this.detail.targetName + ' · ' + this.rel.Target_Branch__c : ''; }
    get raisedText() { return 'Raised by ' + (this.rel.CreatedBy ? this.rel.CreatedBy.Name : '') + ', ' + when(this.rel.CreatedDate); }
    get running() { return this.detail && this.detail.running; }
    get syncedText() {
        return this.rel.Last_Synced__c
            ? 'Last checked ' + new Date(this.rel.Last_Synced__c).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })
            : '';
    }
    get countdownText() {
        if (this.checking) {
            return 'Checking now…';
        }
        return this.running && this.nextAt
            ? 'Next check at ' + this.nextAt.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })
            : '';
    }
    get counting() { return !!this.nextAt && !this.checking; }
    /** One key per countdown, so a fresh bar (and a fresh animation) is drawn each time. */
    get cycles() { return [{ key: 'c' + this.cycle }]; }
    get prLabel() { return this.rel.PR_Number__c ? 'Pull request #' + this.rel.PR_Number__c : ''; }

    // ---------- timeline ----------

    get scan() { return parse(this.rel.Scan_Result__c) || {}; }
    get validation() { return parse(this.rel.Validation_Result__c) || {}; }
    get deploy() { return parse(this.rel.Deploy_Result__c) || {}; }

    get steps() {
        const r = this.rel;
        const s = r.Status__c;
        const collected = !['Retrieving'].includes(s) && !(s === 'Failed' && !r.Source_Branch__c);
        const scan = this.scan;
        const val = this.validation;
        const steps = [];
        steps.push({
            key: 'collect', title: 'Collected from ' + (this.detail ? this.detail.sourceName : ''),
            state: s === 'Retrieving' ? 'Running' : collected ? 'Done' : 'Failed',
            text: s === 'Retrieving' ? 'Retrieving the components with the Metadata API…' : (r.Component_Count__c || 0) + ' components'
        });
        steps.push({
            key: 'pr', title: 'Pull request',
            state: r.PR_Number__c ? 'Done' : s === 'Workflow running' ? 'Running' : collected && s === 'Failed' ? 'Failed' : 'Waiting',
            text: r.PR_Number__c ? '#' + r.PR_Number__c + ': ' + r.Source_Branch__c + ' → ' + r.Target_Branch__c
                : s === 'Workflow running' ? 'The pipeline is converting the files and opening the pull request…' : ''
        });
        let scanText = '';
        if (r.Scan_Status__c === 'Not configured') {
            scanText = 'Code scan is off for this repository.';
        } else if (r.Scan_Status__c === 'Pending') {
            scanText = r.PR_Number__c ? 'Salesforce Code Analyzer is running…' : '';
        } else if (scan.message && !scan.total) {
            scanText = scan.message;
        } else if (scan.total) {
            scanText = scan.total + ' finding' + (scan.total === 1 ? '' : 's') + ', ' + (scan.blocking || 0) + ' at '
                + (scan.thresholdLabel || 'High') + ' or above' + (scan.blocking ? ' (blocking)' : ': below the bar, so they don\'t block');
        } else if (r.Scan_Status__c === 'Passed') {
            scanText = 'No findings.';
        }
        if (r.Scan_Status__c === 'Bypassed') {
            scanText = 'Bypassed by ' + (r.Scan_Bypassed_By__r ? r.Scan_Bypassed_By__r.Name : '') + ': ' + r.Scan_Bypass_Reason__c;
        }
        steps.push({ key: 'scan', title: 'Code scan', state: this.checkState(r.Scan_Status__c, scan), text: scanText });
        let valText = '';
        if (r.Validation_Status__c === 'Pending') {
            valText = r.PR_Number__c ? 'Check-only deploy to ' + (this.detail ? this.detail.targetName : '') + ' with ' + this.testLevelText + '…' : '';
        } else if (r.Validation_Status__c === 'Not configured') {
            valText = 'The target has no Git environment: Git only.';
        } else if (val.status) {
            valText = (val.status === 'Passed' ? 'Check-only deploy passed' : val.message || val.status)
                + (val.testLevel ? ' · ' + val.testLevel + (val.testsRun ? ', ' + val.testsRun + ' tests run' : '') : '');
        }
        steps.push({ key: 'validate', title: 'Validation in ' + (this.detail ? this.detail.targetName : ''), state: this.checkState(r.Validation_Status__c, val), text: valText });
        steps.push({
            key: 'approval', title: 'Approval',
            state: r.Approval_Status__c === 'Approved' ? 'Done' : r.Approval_Status__c === 'Rejected' ? 'Failed' : s === 'Ready for approval' ? 'Running' : 'Waiting',
            text: r.Approval_Status__c === 'Approved' || r.Approval_Status__c === 'Rejected'
                ? r.Approval_Status__c + ' by ' + (r.Approved_By__r ? r.Approved_By__r.Name : '') + ', ' + when(r.Approved_On__c) + (r.Approval_Comment__c ? ': ' + r.Approval_Comment__c : '')
                : s === 'Ready for approval' ? 'Waiting for an approver.' : ''
        });
        const dep = this.deploy;
        steps.push({
            key: 'deploy', title: 'Merge and deploy to ' + (this.detail ? this.detail.targetName : ''),
            state: s === 'Deployed' ? 'Done' : s === 'Deploy failed' ? 'Failed' : s === 'Deploying' ? 'Running' : 'Waiting',
            text: s === 'Deployed' ? 'Deployed' + (r.Merge_Commit__c ? ' · merge ' + r.Merge_Commit__c.substring(0, 7) : '') + (dep.testsRun ? ' · ' + dep.testsRun + ' tests run' : '')
                : s === 'Deploying' ? 'Merging the pull request and deploying…' : s === 'Deploy failed' ? (r.Error_Message__c || dep.message || 'Failed') : ''
        });
        return steps.map((st, i) => ({
            ...st,
            num: i + 1,
            cls: 'rr-tl rr-tl-' + st.state.toLowerCase(),
            badge: st.state === 'Done' ? '✓' : st.state === 'Failed' ? '!' : st.state === 'Warn' ? '!' : String(i + 1),
            stateLabel: st.state === 'Running' ? 'In progress' : st.state === 'Waiting' ? ''
                : st.state === 'Warn' ? (st.key === 'scan' && this.rel.Scan_Status__c === 'Bypassed' ? 'Bypassed' : 'Passed with findings')
                : st.state
        }));
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

    get errorBanner() {
        const s = this.rel.Status__c;
        return this.rel.Error_Message__c && (s === 'Failed' || RUNNING.includes(s)) ? this.rel.Error_Message__c : null;
    }

    get items() {
        return (this.detail ? this.detail.items : []).map((i) => ({ key: i.Id, text: i.Metadata_Type__c + ': ' + i.Component_Name__c }));
    }
    get itemsLabel() { return (this.showItems ? 'Hide' : 'Show') + ' components (' + this.items.length + ')'; }
    toggleItems() { this.showItems = !this.showItems; }

    // ---------- actions ----------

    get isApprover() { return this.detail && this.detail.isApprover; }
    get canApprove() { return this.isApprover && this.rel.Status__c === 'Ready for approval'; }
    get canReject() { return this.isApprover && (this.rel.Status__c === 'Ready for approval' || this.rel.Status__c === 'Checks failed'); }
    get canBypass() {
        return this.isApprover && this.rel.Status__c === 'Checks failed'
            && (this.rel.Scan_Status__c === 'Failed' || this.rel.Scan_Status__c === 'Error');
    }
    get canCheckAgain() { return ['Checks failed', 'Ready for approval'].includes(this.rel.Status__c) && !!this.rel.PR_Number__c; }
    get hasActions() { return this.canApprove || this.canReject || this.canBypass || this.canCheckAgain; }
    get needsApproverNote() {
        return !this.isApprover && ['Ready for approval', 'Checks failed'].includes(this.rel.Status__c);
    }
    get validationBlocks() { return ['Failed', 'Error'].includes(this.rel.Validation_Status__c); }

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
