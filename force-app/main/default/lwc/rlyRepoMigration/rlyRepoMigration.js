import { LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getMigration from '@salesforce/apex/RlyMigrationController.getMigration';
import startMigration from '@salesforce/apex/RlyMigrationController.startMigration';
import readCurrent from '@salesforce/apex/RlyMigrationController.readCurrent';
import saveTarget from '@salesforce/apex/RlyMigrationController.saveTarget';
import checkTargetRepository from '@salesforce/apex/RlyMigrationController.checkTargetRepository';
import chooseMethod from '@salesforce/apex/RlyMigrationController.chooseMethod';
import startRun from '@salesforce/apex/RlyMigrationController.startRun';
import refreshRun from '@salesforce/apex/RlyMigrationController.refreshRun';
import updatePipelineFiles from '@salesforce/apex/RlyMigrationController.updatePipelineFiles';
import checkNewConnection from '@salesforce/apex/RlyMigrationController.checkNewConnection';
import markItem from '@salesforce/apex/RlyMigrationOrgController.markItem';
import goToStep from '@salesforce/apex/RlyMigrationOrgController.goToStep';
import startOrgCheck from '@salesforce/apex/RlyMigrationOrgController.startOrgCheck';
import stageOrgPart from '@salesforce/apex/RlyMigrationOrgController.stageOrgPart';
import runOrgDeveloper from '@salesforce/apex/RlyMigrationOrgController.runOrgDeveloper';
import readOrgCheck from '@salesforce/apex/RlyMigrationOrgController.readOrgCheck';
import acceptDifferences from '@salesforce/apex/RlyMigrationOrgController.acceptDifferences';
import switchNow from '@salesforce/apex/RlyMigrationOrgController.switchNow';
import finishMigration from '@salesforce/apex/RlyMigrationOrgController.finishMigration';
import cancelMigration from '@salesforce/apex/RlyMigrationOrgController.cancelMigration';
import describeTypes from '@salesforce/apex/RlyChangesController.describeTypes';
import listChanges from '@salesforce/apex/RlyChangesController.listChanges';
import startPipelinePart from '@salesforce/apex/RlyCompareController.startPipelinePart';
import { listTypeChunks, partsOf, pillOf, shortSha, STEPS, PROVIDERS } from './migrationHelpers';
import { errorText, partsToSend, withPart, partIn } from 'c/rlyShared';

/** Parts of a developer org sent at once. */
const AT_ONCE = 2;

/**
 * The Migration tab (build 46, design board "Move to another provider"): moves the hub to another Git provider, all at
 * once. 1 Current → New (the active connection and what it holds; the new connection, with Check), 2 How (lift and shift,
 * the provider's own importer then verify, fresh start: only what works for the pair), 3 Dry run (required), 4 Run with
 * What moved and What didn't move, 5 New setup checklist, 6 each org against its new branch (developer orgs sent in parts,
 * as Sync status does), 7 Switch now, 8 Old setup checklist, then Finish → the Migration report (PDF). Done marks are
 * toggle chips. Running runs and checks are read again on a CSS-animation countdown (no timers).
 */
export default class RlyRepoMigration extends LightningElement {
    view;
    error;
    busy = false;
    form = { provider: '', repository: '', namedCredential: '', pipelineFile: '', pipelineBranch: '' };
    acceptReason = '';
    waits = {};
    sending;
    checkingAll = false;

    connectedCallback() {
        this.load();
    }

    async load() {
        await this.act(() => getMigration());
    }

    /** Runs an Apex action that returns the view; errors show on the page. */
    async act(call) {
        this.error = undefined;
        this.busy = true;
        try {
            const v = await call();
            if (v) {
                this.setView(v);
            }
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    setView(v) {
        this.view = v;
        if (v.target && !this.form.provider) {
            this.form = { provider: v.target.provider, repository: v.target.repository || '', namedCredential: v.target.namedCredential || '',
                pipelineFile: v.target.pipelineFile || '', pipelineBranch: v.target.pipelineBranch || '' };
        }
        this.acceptReason = (v.gate && v.gate.acceptReason) || this.acceptReason;
        if (v.run && v.run.running) {
            this.wait('run', 'run', 5);
        }
        (v.orgs || []).forEach((o) => {
            if (o.status === 'Running' && o.mode === 'drift') {
                this.wait('org:' + o.id, 'org', 5);
            }
        });
    }

    // ---------- the page ----------

    get loaded() { return !!this.view; }
    get isAdmin() { return !!(this.view && this.view.log && this.view.log.isAdmin); }
    get notAdmin() { return this.loaded && !this.isAdmin; }
    get hasMigration() { return this.isAdmin && !!this.view.id; }
    get noMigration() { return this.isAdmin && !this.view.id; }
    get current() { return (this.view && this.view.current) || {}; }
    get target() { return (this.view && this.view.target) || null; }
    get hasTarget() { return !!this.target; }
    get holds() { return (this.view && this.view.holds) || { branches: [], orgs: [], open: [] }; }
    get branchesText() { return (this.holds.branches || []).join(', ') + (this.holds.more ? ', …' : ''); }
    get hasOpen() { return (this.holds.open || []).length > 0; }
    get openCount() { return (this.holds.open || []).length; }
    get step() { return (this.view && this.view.step) || 1; }
    get statusText() { return this.view && this.view.status ? this.view.status : ''; }
    get isOpen() { return this.view && this.view.status === 'Open'; }
    get isSwitched() { return this.view && this.view.status === 'Switched'; }
    get isFinished() { return this.view && this.view.status === 'Finished'; }
    get cantCancel() { return this.busy || !this.isOpen; }
    get title() {
        const t = this.target;
        return 'Move from ' + (this.current.providerLabel || 'the current provider') + (t ? ' to ' + t.providerLabel : '');
    }

    // A step shows done (green) only when it actually completed, not because the wizard is past it (build 52).
    get steps() {
        const done = this.doneSteps;
        return STEPS.map((s) => {
            let cls = 'rr-step';
            cls += s.n === this.step ? ' rr-step-on' : (done.has(s.n) ? ' rr-step-done' : '');
            return { ...s, key: 's' + s.n, cls, current: s.n === this.step ? 'step' : 'false' };
        });
    }
    get doneSteps() {
        const v = this.view || {};
        const ok = (start) => ((v.gate && v.gate.conditions) || []).some((c) => c.ok && c.label && c.label.startsWith(start));
        const setup = v.setup || {};
        const newItems = setup.newItems || [];
        const done = new Set();
        const marks = [
            [1, !!this.target && this.target.status === 'Connected'],
            [2, !!this.method],
            [3, ok('Dry run passed')],
            [4, ok('Verified') || ok('The run copied')],
            [5, newItems.length > 0 && (setup.newDone || 0) >= newItems.length],
            [6, ok('Every org is in sync')],
            [7, !!this.isSwitched || !!this.isFinished],
            [8, !!this.isFinished]
        ];
        marks.forEach(([n, isDone]) => { if (isDone) { done.add(n); } });
        return done;
    }
    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isStep4() { return this.step === 4; }
    get isStep5() { return this.step === 5; }
    get isStep6() { return this.step === 6; }
    get isStep7() { return this.step === 7; }
    get isStep8() { return this.step === 8; }
    get cantBack() { return this.busy || this.step <= 1; }
    get cantNext() { return this.busy || this.step >= 8; }

    handleStep(event) {
        this.go(Number(event.currentTarget.dataset.n));
    }
    handleBack() { this.go(this.step - 1); }
    handleNext() { this.go(this.step + 1); }
    go(n) {
        this.act(() => goToStep({ migrationId: this.view.id, step: n }));
    }

    // ---------- start, cancel ----------

    handleStart() {
        this.act(() => startMigration());
    }

    async handleCancel() {
        const ok = await LightningConfirm.open({ label: 'Cancel this migration?', theme: 'warning',
            message: 'Nothing switches. The new connection stays, inactive; the copy in the new repository stays as it is.' });
        if (ok) {
            this.form = { provider: '', repository: '', namedCredential: '', pipelineFile: '', pipelineBranch: '' };
            this.act(() => cancelMigration({ migrationId: this.view.id }));
        }
    }

    // ---------- 1 · Current → New ----------

    get providerTiles() {
        return PROVIDERS.map((p) => {
            const isCurrent = p.value === this.current.provider;
            const on = p.value === this.form.provider;
            let cls = 'rr-tile';
            cls += on ? ' rr-tile-on' : '';
            cls += isCurrent ? ' rr-tile-off' : '';
            return { ...p, text: isCurrent ? p.label + ' (current)' : p.label, cls, off: isCurrent || !this.isOpen, pressed: on ? 'true' : 'false' };
        });
    }
    get hint() { return PROVIDERS.find((p) => p.value === this.form.provider) || PROVIDERS[0]; }
    get showForm() { return !!this.form.provider; }
    get cantSaveTarget() { return this.busy || !this.isOpen || !this.form.repository || !this.form.namedCredential || !this.form.pipelineBranch; }
    get cantCheckTarget() { return this.busy || !this.hasTarget; }
    get targetCheck() { return this.holds.targetCheck; }
    get targetCheckCls() { return this.targetCheck && this.targetCheck.startsWith('Reachable') ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad'; }

    handleProvider(event) {
        const value = event.currentTarget.dataset.value;
        const p = PROVIDERS.find((x) => x.value === value);
        this.form = { provider: value, repository: '', namedCredential: '', pipelineFile: '', pipelineBranch: '' };
        if (p && this.target && this.target.provider === value) {
            this.form = { provider: value, repository: this.target.repository || '', namedCredential: this.target.namedCredential || '',
                pipelineFile: this.target.pipelineFile || '', pipelineBranch: this.target.pipelineBranch || '' };
        }
    }
    handleField(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
    }
    handleSaveTarget() {
        const f = this.form;
        const json = JSON.stringify({ Provider__c: f.provider, Repository__c: f.repository, Named_Credential__c: f.namedCredential,
            Pipeline__c: f.pipelineFile, Pipeline_Branch__c: f.pipelineBranch });
        this.act(() => saveTarget({ migrationId: this.view.id, connectionJson: json }));
    }
    handleCheckTarget() {
        this.act(() => checkTargetRepository({ migrationId: this.view.id }));
    }
    handleReadCurrent() {
        this.act(() => readCurrent({ migrationId: this.view.id }));
    }

    // ---------- 2 · How ----------

    get methods() {
        const picked = this.view && this.view.choose ? this.view.choose.method : null;
        return ((this.view && this.view.choose && this.view.choose.methods) || []).map((m) => {
            let cls = 'rr-rcard';
            cls += m.key === picked ? ' rr-rcard-on' : '';
            cls += m.possible ? '' : ' rr-rcard-off';
            return { ...m, cls, checked: m.key === picked ? 'true' : 'false', off: !m.possible || !this.isOpen || this.busy,
                hasClicks: (m.clicks || []).length > 0, clickRows: (m.clicks || []).map((c, i) => ({ key: m.key + i, n: i + 1, text: c })) };
        });
    }
    handleMethod(event) {
        this.act(() => chooseMethod({ migrationId: this.view.id, method: event.currentTarget.dataset.key }));
    }

    // ---------- 3 · Dry run · 4 · Run ----------

    get run() { return (this.view && this.view.run) || {}; }
    get method() { return this.view && this.view.choose ? this.view.choose.method : null; }
    get isImporter() { return this.method === 'importer'; }
    get dry() { return this.run.dry; }
    get result() { return this.run.result; }
    get dryLabel() { return this.isImporter ? 'Verify the imported copy' : 'Start the dry run'; }
    get cantDry() { return this.busy || !this.isOpen || !this.method || this.run.running === true; }
    get cantRun() { return this.busy || !this.isOpen || this.isImporter || !this.dry || !this.dry.ready || this.run.running === true; }
    get runPill() { return pillOf(this.run.status); }
    get dryPill() { return this.dry ? pillOf(this.dry.ready ? 'Ready' : (this.dry.status === 'Failed' ? 'Failed' : 'Not ready')) : ''; }
    get dryReadyText() { return this.dry && this.dry.ready ? 'Ready' : 'Not ready'; }
    get dryNamed() {
        return ((this.dry && this.dry.named) || []).map((n) => ({ ...n, key: n.name,
            cls: n.inSource ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad', text: n.name + (n.inSource ? ' ✓' : ' missing') }));
    }
    get hasDryProblems() { return !!(this.dry && this.dry.problems && this.dry.problems.length); }
    get dryProblems() { return ((this.dry && this.dry.problems) || []).map((p, i) => ({ key: 'p' + i, text: p })); }
    get showProgress() { return this.run.kind === 'run' && this.result && this.result.status === 'In progress'; }
    get progress() { return (this.result && this.result.percent) || 0; }
    get tokenHint() { return this.view && this.view.setup ? this.view.setup.tokenHint : ''; }

    handleDry() {
        this.act(() => startRun({ migrationId: this.view.id, kind: 'dry' }));
    }
    async handleRun() {
        const ok = await LightningConfirm.open({ label: 'Start the run?', theme: 'warning',
            message: 'The migrate job pushes to ' + (this.target ? this.target.providerLabel + ' ' + this.target.repository : 'the new repository') + '.' });
        if (ok) {
            this.act(() => startRun({ migrationId: this.view.id, kind: 'run' }));
        }
    }

    // What moved
    get moved() { return (this.view && this.view.moved) || { rows: [], requests: [], stays: [] }; }
    get hasMoved() { return (this.moved.rows || []).length > 0; }
    get movedRows() {
        return (this.moved.rows || []).map((r) => ({ ...r, key: r.kind + ':' + r.name, src: shortSha(r.source), tgt: shortSha(r.target),
            markCls: r.match ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad', markText: r.match ? '✓' : '✗', hasUrl: !!r.url }));
    }
    get movedPill() { return this.moved.allMatch ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-warn'; }
    get hasMore() { return this.moved.more > 0; }
    get hasRequests() { return (this.moved.requests || []).length > 0; }
    get requests() { return (this.moved.requests || []).map((r) => ({ ...r, key: r.label })); }
    get stays() { return (this.moved.stays || []).map((s, i) => ({ key: 'st' + i, text: s })); }
    get sourceLabel() { return this.current.providerLabel || 'Current'; }
    get targetLabel() { return this.target ? this.target.providerLabel : 'New'; }

    // ---------- 5 · New setup · 8 · Old setup ----------

    itemsOf(items) {
        return (items || []).map((i) => ({ ...i, chipCls: i.done ? 'rr-chip rr-chip-on' : 'rr-chip', pressed: i.done ? 'true' : 'false',
            chipText: i.done ? 'Done ✓' : 'Done', byText: i.done && i.who ? i.who : '', hasAction: !!i.action,
            actionLabel: i.action === 'check' ? 'Check' : 'Run', off: this.busy }));
    }
    get newItems() { return this.itemsOf(this.view && this.view.setup ? this.view.setup.newItems : []); }
    get oldItems() { return this.itemsOf(this.view && this.view.setup ? this.view.setup.oldItems : []); }
    get newCount() { return (this.view.setup.newDone || 0) + ' of ' + this.newItems.length + ' done'; }
    get oldCount() { return (this.view.setup.oldDone || 0) + ' of ' + this.oldItems.length + ' done'; }
    get optionalNames() { return this.view && this.view.setup ? this.view.setup.optionalNames : ''; }

    handleChip(event) {
        const key = event.currentTarget.dataset.key;
        const on = event.currentTarget.getAttribute('aria-pressed') === 'true';
        this.act(() => markItem({ migrationId: this.view.id, key, value: on ? 'open' : 'done' }));
    }
    handleItemAction(event) {
        const action = event.currentTarget.dataset.action;
        const call = action === 'check' ? checkNewConnection : updatePipelineFiles;
        this.act(() => call({ migrationId: this.view.id }));
    }

    // ---------- 6 · Orgs in sync ----------

    get orgRows() {
        return ((this.view && this.view.orgs) || []).map((o) => {
            const sending = this.sending && this.sending.orgId === o.id;
            return { ...o, pill: pillOf(o.status), statusText: sending ? this.sendingText : o.status,
                buttonLabel: o.status === 'Not checked' ? 'Check' : 'Try again', off: this.busy || !this.isOpen || o.status === 'Running' || !!this.sending };
        });
    }
    get cantCheckAll() { return this.busy || !this.isOpen || !!this.sending || this.checkingAll; }
    get sendingText() {
        const s = this.sending;
        if (!s) {
            return '';
        }
        if (s.phase === 'listing') {
            return 'Listing… ' + s.listed;
        }
        const done = s.parts.filter((p) => p.phase === 'ready').length;
        return 'Sending part ' + Math.min(done + 1, s.parts.length) + ' of ' + s.parts.length;
    }

    handleOrgCheck(event) {
        this.checkOrg(event.currentTarget.dataset.id);
    }

    async handleCheckAll() {
        this.checkingAll = true;
        try {
            const ids = (this.view.orgs || []).filter((o) => o.status !== 'In sync').map((o) => o.id);
            await ids.reduce((prior, id) => prior.then(() => this.checkOrg(id)), Promise.resolve());
        } finally {
            this.checkingAll = false;
        }
    }

    async checkOrg(orgId) {
        this.error = undefined;
        this.busy = true;
        try {
            const s = await startOrgCheck({ migrationId: this.view.id, orgId });
            this.setView(await getMigration());
            if (s.mode === 'parts') {
                this.busy = false;
                await this.sendDeveloper(s.syncId, orgId);
            } else {
                this.wait('org:' + orgId, 'org', 5);
            }
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    // A developer org: list every component, send them in parts to the new repository, then start the compare.
    async sendDeveloper(syncId, orgId) {
        this.sending = { syncId, orgId, phase: 'listing', listed: 0, parts: [] };
        try {
            const t = await describeTypes({ orgId });
            const types = t.types || [];
            const keys = [];
            await listTypeChunks(types).reduce((prior, chunk) => prior.then(async () => {
                const found = await listChanges({ orgId, types: chunk, sinceIso: null });
                (found || []).filter((c) => !c.deleted).forEach((c) => keys.push(c.key));
                this.sending = { ...this.sending, listed: keys.length };
            }), Promise.resolve());
            if (!keys.length) {
                throw new Error('Nothing was listed in the org.');
            }
            const parts = partsOf(keys).map((k, i) => ({ id: syncId + '-' + (i + 1), n: i + 1, keys: k, phase: 'waiting', retrieveId: null }));
            this.sending = { ...this.sending, phase: 'sending', parts, types };
            this.pumpParts();
        } catch (e) {
            this.failSending(e);
        }
    }

    pumpParts() {
        const s = this.sending;
        if (!s || s.phase !== 'sending') {
            return;
        }
        const next = partsToSend(s, AT_ONCE);
        if (next.allReady) {
            this.finishDeveloper();
            return;
        }
        next.ids.forEach((id) => this.sendPart(id));
    }

    setPart(id, values) { this.sending = withPart(this.sending, id, values); }

    partOf(id) { return partIn(this.sending, id); }

    // A part of the send still running: a failed or finished send drops its parts, so late answers are ignored (build 52).
    isLive(id) { return !!this.partOf(id); }

    async sendPart(id) {
        const p = this.partOf(id);
        if (!p) {
            return;
        }
        const orgId = this.sending.orgId;
        this.setPart(id, { phase: 'running' });
        try {
            const retrieveId = await startPipelinePart({ sourceOrgId: orgId, keys: p.keys });
            if (!this.isLive(id)) {
                return;
            }
            this.setPart(id, { retrieveId });
            await this.stagePart(id);
        } catch (e) {
            this.failSending(e, id);
        }
    }

    async stagePart(id) {
        const p = this.partOf(id);
        if (!p) {
            return;
        }
        const s = this.sending;
        try {
            const part = { compareId: s.syncId, n: p.n, retrieveId: p.retrieveId, sourceOrgId: s.orgId };
            const st = await stageOrgPart({ migrationId: this.view.id, partJson: JSON.stringify(part) });
            if (!this.isLive(id)) {
                return;
            }
            if (!st.done) {
                this.wait(id, 'part', 2);
                return;
            }
            this.setPart(id, { phase: 'ready' });
            this.pumpParts();
        } catch (e) {
            this.failSending(e, id);
        }
    }

    async finishDeveloper() {
        const s = this.sending;
        this.sending = { ...s, phase: 'starting' };
        try {
            await runOrgDeveloper({ migrationId: this.view.id, runJson: JSON.stringify({ syncId: s.syncId, parts: s.parts.length, types: s.types }) });
            this.sending = undefined;
            this.wait('org:' + s.orgId, 'org', 5);
        } catch (e) {
            this.failSending(e);
        }
    }

    // The first error of a send is kept: once it failed, the parts still in flight end quietly (build 52).
    failSending(e, id) {
        if (!this.sending || (id && !this.isLive(id))) {
            return;
        }
        this.error = 'Sending the org\'s components failed: ' + errorText(e) + ' Try again.';
        this.sending = undefined;
    }

    /** The grey line while the hub sends a developer org's parts: the check is driven by this page. */
    get sendingHint() {
        return this.sending ? 'Keep this page open while the parts are sent.' : '';
    }

    handleReason(event) {
        this.acceptReason = event.target.value;
    }
    handleAccept() {
        this.act(() => acceptDifferences({ migrationId: this.view.id, reason: this.acceptReason }));
    }
    handleClearAccept() {
        this.acceptReason = '';
        this.act(() => acceptDifferences({ migrationId: this.view.id, reason: '' }));
    }
    get accepted() { return !!(this.view && this.view.gate && this.view.gate.acceptReason); }
    get acceptChipCls() { return this.accepted ? 'rr-chip rr-chip-on' : 'rr-chip'; }
    get acceptPressed() { return this.accepted ? 'true' : 'false'; }
    get acceptText() { return this.accepted ? 'Differences accepted ✓' : 'Accept the differences'; }
    get cantAccept() { return this.busy || !this.isOpen || !(this.acceptReason || '').trim(); }
    handleAcceptChip() {
        if (this.accepted) {
            this.handleClearAccept();
        } else {
            this.handleAccept();
        }
    }

    // ---------- 7 · Switch now ----------

    get conditions() {
        return ((this.view && this.view.gate && this.view.gate.conditions) || []).map((c, i) => ({ ...c, key: 'c' + i,
            pill: c.ok ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad', mark: c.ok ? '✓' : '✗' }));
    }
    get cantSwitch() { return this.busy || !(this.view && this.view.gate && this.view.gate.ready); }
    get switchLabel() { return 'Switch to ' + this.targetLabel + ' now'; }
    get switchedOn() { return this.view && this.view.gate ? this.view.gate.switchedOn : null; }

    async handleSwitch() {
        const ok = await LightningConfirm.open({ label: this.switchLabel + '?', theme: 'warning',
            message: this.targetLabel + ' becomes the active connection for everything: new releases start there. Old releases keep their own repository.' });
        if (ok) {
            this.act(() => switchNow({ migrationId: this.view.id }));
        }
    }

    // ---------- Finish ----------

    get cantFinish() { return this.busy || !this.isSwitched; }
    get reportUrl() { return this.view && this.view.log ? this.view.log.reportUrl : null; }
    handleFinish() {
        this.act(() => finishMigration({ migrationId: this.view.id }));
    }

    get events() {
        return ((this.view && this.view.log && this.view.log.events) || []).slice(0, 12).map((e, i) => ({ ...e, key: 'e' + i }));
    }
    get hasEvents() { return this.events.length > 0; }

    // ---------- countdowns (CSS animation, no timers) ----------

    wait(id, kind, seconds) {
        const prior = this.waits[id];
        this.waits = { ...this.waits, [id]: { kind, cycle: prior ? prior.cycle + 1 : 1, seconds } };
    }

    get ticks() {
        return Object.keys(this.waits).map((id) => {
            const w = this.waits[id];
            return { key: id + '-' + w.cycle, id, cls: 'rr-tick rr-tick-' + w.seconds };
        });
    }

    handleTick(event) {
        const id = event.currentTarget.dataset.id;
        const w = this.waits[id];
        if (!w) {
            return;
        }
        const rest = { ...this.waits };
        delete rest[id];
        this.waits = rest;
        if (w.kind === 'part') {
            this.stagePart(id);
        } else if (w.kind === 'run') {
            this.quiet(() => refreshRun({ migrationId: this.view.id }));
        } else {
            this.quiet(() => readOrgCheck({ migrationId: this.view.id, orgId: id.substring(4) }));
        }
    }

    // A background read: no spinner; a failure shows once.
    async quiet(call) {
        try {
            this.setView(await call());
        } catch (e) {
            this.error = errorText(e);
        }
    }
}
