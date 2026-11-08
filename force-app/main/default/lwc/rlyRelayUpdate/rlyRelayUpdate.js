import { LightningElement } from 'lwc';
import readState from '@salesforce/apex/RlyRelayUpdateController.state';
import prepareUpdate from '@salesforce/apex/RlyRelayUpdateController.prepare';
import startUpdateStep from '@salesforce/apex/RlyRelayUpdateController.start';
import refreshUpdate from '@salesforce/apex/RlyRelayUpdateController.refresh';
import { errorText } from 'c/rlyShared';

const ORDER = ['test-check', 'test-install', 'prod-check', 'prod-install'];
const PROD_TARGET = 'release-relay-hub';
const PILLS = {
    Running: 'rr-pill rr-pill-run',
    Passed: 'rr-pill rr-pill-ok',
    Installed: 'rr-pill rr-pill-ok',
    Failed: 'rr-pill rr-pill-bad'
};
const STATUS_TEXT = { Running: 'Running', Passed: 'Passed', Installed: 'Installed', Failed: 'Failed' };

function when(value) {
    if (!value) {
        return '';
    }
    try {
        return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })
            .format(new Date(value));
    } catch {
        return String(value);
    }
}

function httpsOnly(url) {
    return typeof url === 'string' && url.startsWith('https://') ? url : null;
}

/**
 * Pipeline tab → Advanced (build 51): Install Release Relay update, for admins only (no one else sees the card).
 * The admin names the update branch (the build's zip in .relay-inbox/), a title and the stage to test in, then runs
 * four steps in order with toggle chips: the test org's check, its install, production's check, production's install.
 * Each step opens only after the one before it passed. The hub starts every run (signed), and reads each result
 * from the signed result files; while a step runs, the card checks again every 30 seconds (a CSS animation, no timers).
 */
export default class RlyRelayUpdate extends LightningElement {
    card;
    form = { branch: '', title: '', testOrgId: null };
    another = false;
    pickedKey;
    busy = false;
    error;
    tickCycle = 0;

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.apply(await readState());
        } catch (e) {
            this.error = errorText(e);
        }
    }

    apply(card) {
        this.card = card;
        const c = card && card.current;
        // An update prepared but not started (its start failed): its branch, title and org come back into the form.
        if (c && !this.another && !this.form.branch && !this.form.title && !c.steps.some((s) => !!s.status)) {
            this.form = { branch: c.branch || '', title: c.title || '', testOrgId: c.testOrgId || null };
        }
        this.schedulePoll();
    }

    // ---------- what is shown ----------

    get visible() { return !!this.card && this.card.visible === true; }
    get current() { return this.card ? this.card.current : null; }
    get supported() { return !!this.card && this.card.supported === true; }
    get notSupported() { return this.visible && !this.supported; }
    get notSupportedText() {
        return this.card && this.card.provider
            ? 'Install update works with GitHub or GitLab for now; this connection is ' + this.card.provider + '.'
            : 'Save the Git connection first (Connection and route).';
    }
    get notSigned() { return this.visible && this.card.signed !== true; }
    get running() { return !!this.current && this.current.running === true; }
    get stages() { return (this.card && this.card.stages) || []; }
    get hasStages() { return this.stages.length > 0; }
    get stageOptions() { return this.stages.map((s) => ({ value: s.value, label: s.label, help: s.help })); }
    get prodName() { return (this.card && this.card.prodName) || 'Production'; }

    get anyStarted() {
        return !!this.current && this.current.steps.some((s) => !!s.status);
    }

    get showForm() {
        return !this.running && (!this.current || this.another || !this.anyStarted);
    }

    get showAnother() { return !this.showForm && !this.running; }
    get showCancelAnother() { return this.another && !!this.current && this.anyStarted; }

    get subtitle() {
        if (this.showForm || !this.current) {
            return 'Check and install a new Release Relay build: the test org first, then production';
        }
        return this.current.title + ' · ' + this.current.branch;
    }

    get branchHint() {
        const repo = this.card && this.card.repository ? ' in ' + this.card.repository : '';
        return 'A branch' + repo + " with the build's zip in .relay-inbox/";
    }

    get testOrgName() {
        if (this.showForm) {
            const s = this.stages.find((x) => x.value === this.form.testOrgId);
            return s ? s.label : 'Test org';
        }
        return this.current.testOrgName;
    }

    get testInstallBranch() {
        const id = this.showForm ? this.form.testOrgId : this.current.testOrgId;
        const s = this.stages.find((x) => x.value === id);
        return s ? s.help : 'its install branch';
    }

    get testsText() {
        if (!this.current) {
            return '';
        }
        const from = this.current.testsFrom === 'zip' ? 'from the zip' : "from this org's Release Relay classes (the zip couldn't be read here)";
        return this.current.testsCount + ' test classes, ' + from;
    }

    // The four steps: the current update's, or the new one's while the form is shown.
    get stepList() {
        if (this.showForm) {
            const t = this.testOrgName;
            const p = this.prodName;
            return [t + ' check', t + ' install', p + ' check', p + ' install'].map((label, i) => ({
                key: ORDER[i], n: i + 1, label, status: null, startable: i === 0, retry: false, failures: []
            }));
        }
        return this.current.steps;
    }

    get selectedKey() {
        const list = this.stepList;
        const can = (s) => s.startable || s.retry;
        const picked = list.find((s) => s.key === this.pickedKey && can(s));
        if (picked) {
            return picked.key;
        }
        const first = list.find(can);
        if (first) {
            return first.key;
        }
        const run = list.find((s) => s.status === 'Running');
        return run ? run.key : null;
    }

    get selectedStep() {
        return this.stepList.find((s) => s.key === this.selectedKey) || null;
    }

    get stepChips() {
        const sel = this.selectedKey;
        return this.stepList.map((s, i) => {
            const usable = s.startable || s.retry;
            const isSel = s.key === sel;
            let cls = 'rr-chip';
            let mark = String(s.n);
            if (s.status === 'Passed' || s.status === 'Installed') {
                cls += ' rr-done';
                mark = '✓';
            } else if (s.status === 'Failed') {
                cls += ' rr-fail';
                mark = '!';
            } else if (s.status === 'Running') {
                cls += ' rr-run';
            }
            cls += isSel ? ' rr-sel' : '';
            cls += !usable && !isSel ? ' rr-off' : '';
            return {
                key: s.key,
                label: s.label,
                mark,
                cls,
                notFirst: i > 0,
                pressed: isSel ? 'true' : 'false',
                off: !usable || this.busy,
                statusText: STATUS_TEXT[s.status] || '',
                title: usable ? s.label : 'Opens once the step before it has passed'
            };
        });
    }

    get whatText() {
        const s = this.selectedStep;
        if (!s || s.status === 'Running') {
            return '';
        }
        const t = this.testOrgName;
        const p = this.prodName;
        switch (s.key) {
            case 'test-check':
                return 'Validates the update in ' + t + ', check only: the zip goes on a new branch from ' + this.testInstallBranch
                    + ', a pull request is opened and every test class runs. Nothing is installed yet.';
            case 'test-install':
                return 'Merges the ' + t + " check's pull request into " + this.testInstallBranch
                    + ' and quick deploys the validation that passed (no tests run again).';
            case 'prod-check':
                return 'Validates the same zip in ' + p + ', check only, on a new branch from ' + PROD_TARGET + ', with its own request id.';
            default:
                return 'Merges the ' + p + " check's pull request into " + PROD_TARGET + ' and quick deploys its validation: this installs the update in ' + p + '.';
        }
    }

    get rows() {
        if (this.showForm || !this.current) {
            return [];
        }
        return this.current.steps.filter((s) => !!s.status).map((s) => ({
            key: s.key,
            label: s.n + ' · ' + s.label,
            status: STATUS_TEXT[s.status] || s.status,
            pillCls: PILLS[s.status] || 'rr-pill rr-pill-none',
            requestId: s.requestId,
            runUrl: httpsOnly(s.runUrl),
            testsText: s.testsRun === null || s.testsRun === undefined ? '—' : String(s.testsRun),
            failText: s.status === 'Running' ? '—' : String((s.failures || []).length)
        }));
    }

    get hasRows() { return this.rows.length > 0; }

    // The failed step's message and failures (the newest failed one).
    get problem() {
        if (this.showForm || !this.current) {
            return null;
        }
        const failed = this.current.steps.filter((s) => s.status === 'Failed');
        const s = failed.length ? failed[failed.length - 1] : null;
        if (!s) {
            return null;
        }
        const failures = (s.failures || []).map((text, i) => ({ key: 'f' + i, text }));
        return { message: s.message || (failures.length ? failures.length + ' failure(s)' : 'The step failed.'), failures, hasFailures: failures.length > 0 };
    }

    get doneText() {
        return !this.showForm && this.current && this.current.installed
            ? this.current.title + ' is installed in ' + this.prodName + '. Reload the page to use it.' : '';
    }

    get pill() {
        if (this.showForm || !this.current) {
            return 'Not started';
        }
        if (this.current.installed) {
            return 'Installed';
        }
        const started = this.current.steps.filter((s) => !!s.status);
        const last = started[started.length - 1];
        return last.label + ' ' + (STATUS_TEXT[last.status] || '').toLowerCase();
    }

    get pillCls() {
        if (this.showForm || !this.current) {
            return 'rr-pill rr-pill-none';
        }
        if (this.current.installed) {
            return 'rr-pill rr-pill-ok';
        }
        const started = this.current.steps.filter((s) => !!s.status);
        return PILLS[started[started.length - 1].status] || 'rr-pill rr-pill-none';
    }

    get footText() {
        if (this.running) {
            const s = this.current.steps.find((x) => x.status === 'Running');
            return 'Started ' + when(s.startedAt) + (s.startedBy ? ' by ' + s.startedBy : '') + ' · checks again every 30 seconds';
        }
        if (this.showForm) {
            return 'Each step opens once the one before it has passed.';
        }
        const done = this.current.steps.filter((s) => s.finishedAt);
        return done.length ? 'Last result ' + when(done[done.length - 1].finishedAt) : '';
    }

    get formReady() {
        return !!(this.form.branch && this.form.branch.trim() && this.form.title && this.form.title.trim() && this.form.testOrgId);
    }

    get startLabel() {
        const s = this.selectedStep;
        if (!s) {
            return 'Start';
        }
        return s.status === 'Failed' ? 'Run ' + s.label + ' again' : 'Start ' + s.label;
    }

    get cantStart() {
        const s = this.selectedStep;
        if (this.busy || this.running || !this.supported || !s || !(s.startable || s.retry)) {
            return true;
        }
        return this.showForm && !this.formReady;
    }

    // ---------- form ----------

    handleBranch(event) { this.form = { ...this.form, branch: event.target.value }; }
    handleTitle(event) { this.form = { ...this.form, title: event.target.value }; }
    handleOrg(event) { this.form = { ...this.form, testOrgId: event.detail.value }; }

    pickStep(event) {
        this.pickedKey = event.currentTarget.dataset.key;
    }

    startAnother() {
        this.another = true;
        this.pickedKey = null;
        this.error = null;
        this.form = { branch: '', title: '', testOrgId: null };
    }

    cancelAnother() {
        this.another = false;
        this.error = null;
    }

    // ---------- actions ----------

    async startStep() {
        const s = this.selectedStep;
        if (!s || this.cantStart) {
            return;
        }
        this.busy = true;
        this.error = null;
        try {
            if (s.key === 'test-check') {
                await this.prepare(this.showForm ? this.form : {
                    branch: this.current.branch, title: this.current.title, testOrgId: this.current.testOrgId
                });
            }
            this.apply(await startUpdateStep({ stepKey: s.key }));
            this.another = false;
            this.pickedKey = null;
        } catch (e) {
            this.error = errorText(e);
            this.load();
        } finally {
            this.busy = false;
        }
    }

    // Reads the zip for its tests; when that can't be done here (a zip too large for the request), the org's own
    // Release Relay test classes are used instead.
    async prepare(f) {
        const form = { branch: (f.branch || '').trim(), title: (f.title || '').trim(), testOrgId: f.testOrgId };
        try {
            this.apply(await prepareUpdate({ form: { ...form, testsFrom: 'zip' } }));
        } catch {
            this.apply(await prepareUpdate({ form: { ...form, testsFrom: 'org' } }));
        }
    }

    async refreshNow() {
        this.busy = true;
        this.error = null;
        try {
            this.apply(await refreshUpdate());
        } catch (e) {
            this.error = errorText(e);
            this.schedulePoll();
        } finally {
            this.busy = false;
        }
    }

    // ---------- checking again (a CSS animation that ends after 30 seconds, no timers) ----------

    schedulePoll() {
        this.tickCycle = this.running ? this.tickCycle + 1 : 0;
    }

    // One hidden span per cycle while a step runs: a new key restarts its 30-second animation.
    get ticks() { return this.running && this.tickCycle > 0 ? [{ key: 'tick-' + this.tickCycle }] : []; }

    handleTick() {
        if (!this.running) {
            return;
        }
        if (this.busy) {
            this.schedulePoll();
            return;
        }
        this.refreshNow();
    }
}
