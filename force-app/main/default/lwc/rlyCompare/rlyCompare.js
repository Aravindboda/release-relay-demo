import { LightningElement, api } from 'lwc';
import startCompare from '@salesforce/apex/RlyCompareController.startCompare';
import checkCompare from '@salesforce/apex/RlyCompareController.checkCompare';
import startPipelinePart from '@salesforce/apex/RlyCompareController.startPipelinePart';
import stagePipelinePart from '@salesforce/apex/RlyCompareController.stagePipelinePart';
import runPipelineCompare from '@salesforce/apex/RlyCompareController.runPipelineCompare';
import checkPipelineCompare from '@salesforce/apex/RlyCompareController.checkPipelineCompare';
import pipelineCompareFile from '@salesforce/apex/RlyCompareController.pipelineCompareFile';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';
import { errorText, plural, clearSearchBox } from 'c/rlyShared';

/** Most components the hub compares; more go to the pipeline. */
const HUB_CAP = 50;
/** Components per part in the hub (one small retrieve each) and per part sent to the pipeline. */
const PART_SIZE = 5;
const PIPELINE_PART_SIZE = 10;
/** Deletions read from the branch per part (no retrieve). */
const DELETE_PART_SIZE = 10;
/** Parts running at once. */
const AT_ONCE = 3;
/** The list shows its search box from this many components (or while a search is typed). */
const SEARCH_FROM = 7;
/** Statuses from RlyCompareController (RlyCompareFiles). */
const CHANGED = 'changed';
const SAME = 'same';
const ADDED = 'new';
const REMOVED = 'deleted';
const UNSUPPORTED = 'unsupported';
const PENDING = 'pending';
/** Build 50: types compare leaves out (large files); the page links to the file on the branch instead. */
const LEFT_OUT_TYPES = new Set(['StaticResource', 'Profile']);
const LEFT_OUT = 'Not compared: open it in Git.';
const isLeftOut = (key) => LEFT_OUT_TYPES.has(key.substring(0, key.indexOf(':')));
/** A part's (and its components') phase. */
const WAITING = 'waiting';
const RUNNING = 'running';
const READY = 'ready';
const ERROR = 'error';
/** Chip per status (Changed blue, New green, Deleted red, Same and Not available grey) and per phase. */
const CHIPS = {
    [CHANGED]: { label: 'Changed', cls: 'rr-pill rr-pill-info' },
    [ADDED]: { label: 'New in this release', cls: 'rr-pill rr-pill-ok' },
    [SAME]: { label: 'Same', cls: 'rr-pill rr-pill-none' },
    [REMOVED]: { label: 'Deleted', cls: 'rr-pill rr-pill-bad' },
    [UNSUPPORTED]: { label: 'Not available', cls: 'rr-pill rr-pill-none' }
};
const PHASE_CHIPS = {
    [WAITING]: { label: 'Waiting', cls: 'rr-pill rr-pill-none' },
    [RUNNING]: { label: 'Comparing', cls: 'rr-pill rr-pill-run' },
    [ERROR]: { label: 'Couldn’t read', cls: 'rr-pill rr-pill-bad' }
};
const CHECKING = { label: 'Checking…', cls: 'rr-pill rr-pill-wait' };
const TOO_LARGE_CHIP = { label: 'Too large', cls: 'rr-pill rr-pill-wait' };
const FLOW_STATUS = { Active: 'Active', Draft: 'Draft', InvalidDraft: 'Invalid draft', Obsolete: 'Obsolete' };
const FLOW_CLS = { Active: 'rr-pill rr-pill-info', Draft: 'rr-pill rr-pill-wait', InvalidDraft: 'rr-pill rr-pill-bad', Obsolete: 'rr-pill rr-pill-none' };
/** A part that fails with one of these is split into single components and tried again. */
const SPLIT_ON = /too large|heap|limit|timed? ?out|time limit/i;

/** A file's status from its two sides, as RlyCompareParts.statusOf (exact, line endings ignored). */
function statusOf(left, right) {
    if (left === null || left === undefined) {
        return right === null || right === undefined ? SAME : ADDED;
    }
    if (right === null || right === undefined) {
        return REMOVED;
    }
    return left.replace(/\r\n/g, '\n') === right.replace(/\r\n/g, '\n') ? SAME : CHANGED;
}

function chunks(list, size) {
    const out = [];
    for (let i = 0; i < list.length; i += size) {
        out.push(list.slice(i, i + size));
    }
    return out;
}

/** A file too large for the hub (its reason points at the pipeline). */
function isTooLarge(f) {
    return f.status === UNSUPPORTED && /too large/i.test(f.reason || '');
}

/** One line of a unified diff, with its class. */
function patchLine(text, i) {
    let cls = 'rr-pl';
    if (text.startsWith('+') && !text.startsWith('+++')) {
        cls += ' rr-pl-add';
    } else if (text.startsWith('-') && !text.startsWith('---')) {
        cls += ' rr-pl-del';
    } else if (text.startsWith('@@')) {
        cls += ' rr-pl-hunk';
    }
    return { key: 'l' + i, text: text || ' ', cls };
}

/**
 * Compare before raising (board HubCompare, build 36): a wide modal with the release's components on the left (a chip
 * each) and the selected file in c-rly-diff-view on the right: the target branch's copy (left) against the developer
 * org's copy now (right). Nothing is changed in either place. Fires close.
 *
 * In the hub the components are split into parts of PART_SIZE (deletions DELETE_PART_SIZE), up to AT_ONCE at a time:
 * each part is one small retrieve (startCompare) and its checks (checkCompare, every 2 seconds with a CSS countdown, no
 * timers), so no call reads a big zip. Rows show Waiting / Comparing / their status as their part finishes, the first
 * ready component opens by itself, and a part that fails is split into single components (when it was too large) or
 * offers Try again on its own rows. More than HUB_CAP components, or files too large for the hub, can be compared in
 * the pipeline: the parts' zips go to the results branch and the pipeline compares them with Git (RlyComparePipeline);
 * a file's copies are read when it's opened.
 */
export default class RlyCompare extends LightningElement {
    /** The developer org (RLY_Org__c Id). */
    @api sourceOrgId;
    /** The developer org's name. */
    @api sourceName;
    /** The target org's name. */
    @api targetName;
    /** The target org's branch. */
    @api targetBranch;
    /** [{ type, name, deleted, typeLabel }] in list order. */
    @api items = [];
    /** Type:Name of the component to open first (blank: the first). */
    @api startKey;
    /** RlyChangesController.flowVersions results by flow name, from Review (source org). */
    @api flowInfo = {};

    components = [];
    parts = [];
    selectedKey;
    selectedPath;
    userPicked = false;
    readAt;
    targetFlows = [];
    problems = [];
    error;
    started = false;
    closed = false;
    partSeq = 0;
    /** Compare in the pipeline: null in the hub. */
    pipe = null;
    pipeCycle = 0;
    pipeWaiting = false;
    fileLoading = false;
    fileError;

    connectedCallback() {
        if (!this.started) {
            this.started = true;
            this.startHub();
        }
    }

    // ---------- the hub: parts ----------

    startHub() {
        const items = (this.items || []).slice(0, HUB_CAP);
        this.components = items.map((i) => this.row(i));
        const start = this.startKey && this.components.find((c) => c.key === this.startKey);
        this.selectedKey = start ? start.key : (this.components[0] && this.components[0].key);
        const brought = this.components.filter((c) => !c.item.deleted).map((c) => c.key);
        const deleted = this.components.filter((c) => c.item.deleted).map((c) => c.key);
        this.parts = chunks(brought, PART_SIZE).map((keys) => this.newPart(keys, []))
            .concat(chunks(deleted, DELETE_PART_SIZE).map((keys) => this.newPart([], keys)));
        this.pump();
    }

    row(item) {
        return { key: item.type + ':' + item.name, item, status: undefined, reason: undefined, files: [], part: null, phase: WAITING };
    }

    newPart(keys, deleted) {
        this.partSeq += 1;
        const id = 'p' + this.partSeq;
        const own = new Set(keys.concat(deleted));
        this.components = this.components.map((c) => (own.has(c.key) ? { ...c, part: id, phase: WAITING, error: undefined } : c));
        return { id, keys, deleted, phase: WAITING, job: null, cycle: 0, waiting: false, error: undefined };
    }

    /** Starts waiting parts while fewer than AT_ONCE run. */
    pump() {
        if (this.closed || this.pipe) {
            return;
        }
        let running = this.parts.filter((p) => p.phase === RUNNING).length;
        for (const p of this.parts) {
            if (running >= AT_ONCE) {
                break;
            }
            if (p.phase === WAITING) {
                running += 1;
                this.runPart(p.id);
            }
        }
    }

    part(id) {
        return this.parts.find((p) => p.id === id);
    }

    setPart(id, values) {
        this.parts = this.parts.map((p) => (p.id === id ? { ...p, ...values } : p));
        if (values.phase) {
            this.components = this.components.map((c) => (c.part === id && c.phase !== READY ? { ...c, phase: values.phase, error: values.error } : c));
        }
    }

    async runPart(id) {
        const p = this.part(id);
        this.setPart(id, { phase: RUNNING, error: undefined });
        try {
            const retrieveId = p.keys.length ? await startCompare({ sourceOrgId: this.sourceOrgId, keys: p.keys }) : null;
            this.setPart(id, { job: { retrieveId, sourceOrgId: this.sourceOrgId, keys: p.keys, deleted: p.deleted, targetBranch: this.targetBranch } });
            await this.checkPart(id);
        } catch (e) {
            this.failPart(id, e);
        }
    }

    /** One check of a part; while its retrieve runs, counts down 2 seconds (CSS) and checks again. */
    async checkPart(id) {
        if (this.closed) {
            return;
        }
        const p = this.part(id);
        if (!p || p.phase !== RUNNING) {
            return;
        }
        this.setPart(id, { waiting: false });
        try {
            const r = await checkCompare({ jobJson: JSON.stringify(p.job) });
            if (!r.done) {
                this.setPart(id, { waiting: true, cycle: p.cycle + 1 });
                return;
            }
            this.applyResult(id, r);
            if (r.more) {
                await this.followUp(id);
            }
            this.setPart(id, { phase: READY });
            this.components = this.components.map((c) => (c.part === id ? { ...c, phase: READY } : c));
            this.openFirstReady();
            this.pump();
        } catch (e) {
            this.failPart(id, e);
        }
    }

    applyResult(id, r) {
        this.readAt = this.readAt || r.readAt;
        this.targetFlows = this.targetFlows.concat(r.targetFlows || []);
        this.problems = this.problems.concat(r.problems || []);
        const byKey = new Map((r.components || []).map((x) => [x.key, x]));
        this.components = this.components.map((c) => {
            const found = c.part === id && byKey.get(c.key);
            return found ? { ...c, status: found.status, reason: found.reason, files: found.files || [], gitUrl: found.gitUrl } : c;
        });
        if (this.selected && this.selected.part === id && !this.selectedPath) {
            this.pickFirstFile();
        }
    }

    /** Reads the part's files left pending and merges the branch's copies in. */
    async followUp(id) {
        const p = this.part(id);
        const pending = [];
        this.components.filter((c) => c.part === id).forEach((c) => c.files.forEach((f) => {
            if (f.status === PENDING) {
                pending.push(f.path);
            }
        }));
        if (!pending.length) {
            return;
        }
        const r = await checkCompare({ jobJson: JSON.stringify({ ...p.job, pendingPaths: pending }) });
        const byPath = new Map((r.fetched || []).map((f) => [f.path, f]));
        this.components = this.components.map((c) => {
            if (c.part !== id || !c.files.some((f) => byPath.has(f.path))) {
                return c;
            }
            const files = c.files.map((f) => {
                const got = byPath.get(f.path);
                if (!got || got.status === PENDING) {
                    return f;
                }
                if (got.status === UNSUPPORTED) {
                    return { ...f, right: null, status: UNSUPPORTED, reason: got.reason };
                }
                return { ...f, left: got.left, status: statusOf(got.left, f.right) };
            });
            const main = files[0];
            return { ...c, files, status: main.status, reason: c.reason || (main.status === UNSUPPORTED ? main.reason : undefined) };
        });
        if (r.more) {
            await this.followUp(id);
        }
    }

    /** A part failed: too large → its components are tried one by one; otherwise its rows offer Try again. */
    failPart(id, e) {
        const p = this.part(id);
        const message = errorText(e);
        if (p && p.keys.length + p.deleted.length > 1 && SPLIT_ON.test(message)) {
            const singles = p.keys.map((k) => this.newPart([k], [])).concat(p.deleted.map((k) => this.newPart([], [k])));
            this.parts = this.parts.filter((x) => x.id !== id).concat(singles);
        } else {
            this.setPart(id, { phase: ERROR, waiting: false, error: message });
        }
        this.pump();
    }

    /** Try again on a component's part. */
    retryPart(event) {
        const id = event.currentTarget.dataset.part;
        this.setPart(id, { phase: WAITING, error: undefined, cycle: 0, waiting: false });
        this.pump();
    }

    get retryPartId() { return this.selected ? this.selected.part : undefined; }

    /** The first ready component opens by itself until the person picks one. */
    openFirstReady() {
        const sel = this.selected;
        if (this.userPicked || (sel && sel.phase === READY)) {
            return;
        }
        const first = this.components.find((c) => c.phase === READY);
        if (first) {
            this.selectedKey = first.key;
            this.pickFirstFile();
        }
    }

    /** One countdown per waiting part; the pipeline's run has its own. */
    get ticks() {
        const t = this.parts.filter((p) => p.waiting).map((p) => ({ key: p.id + '-' + p.cycle, part: p.id, cls: 'rr-tick-run' }));
        this.pipeTicks().forEach((x) => t.push(x));
        return t;
    }
    get hasTicks() { return this.ticks.length > 0; }

    /** A countdown ended: check its part (or the pipeline) again. */
    handleTick(event) {
        const id = event.currentTarget.dataset.part;
        if (id === 'pipe') {
            this.pipeTick();
            return;
        }
        if (id.startsWith('pipe:')) {
            this.handleSendTick(id.substring(5));
            return;
        }
        const p = this.part(id);
        if (p && p.waiting) {
            this.checkPart(id);
        }
    }

    // ---------- compare in the pipeline ----------

    get overCap() { return (this.items || []).length > HUB_CAP; }
    get showPipelineOffer() {
        return !this.pipe && (this.overCap || this.components.some((c) => c.phase === ERROR || c.files.some(isTooLarge)));
    }
    get pipelineOfferText() {
        const n = (this.items || []).length;
        if (this.overCap) {
            return 'This release has ' + n + ' components. The hub compares the first ' + HUB_CAP
                + '; compare all ' + n + ' in the pipeline (usually 1–2 minutes).';
        }
        return 'Some files are too large for the hub or couldn’t be read. Compare in the pipeline shows every file’s changes (usually 1–2 minutes).';
    }

    /** Starts Compare in the pipeline for every component of the release. */
    startPipeline() {
        const items = this.items || [];
        this.parts = [];
        this.components = items.map((i) => {
            const c = this.row(i);
            return isLeftOut(c.key) ? { ...c, status: UNSUPPORTED, reason: LEFT_OUT, phase: READY } : { ...c, phase: WAITING };
        });
        if (!this.components.some((c) => c.key === this.selectedKey)) {
            this.selectedKey = this.components[0] && this.components[0].key;
        }
        this.selectedPath = undefined;
        this.userPicked = false;
        const brought = this.components.filter((c) => !c.item.deleted && !isLeftOut(c.key)).map((c) => c.key);
        const pipe = {
            phase: 'sending', compareId: 'CMP-' + Date.now(), token: null, runUrl: null, message: null,
            parts: chunks(brought, PIPELINE_PART_SIZE).map((keys, i) => ({ id: 's' + (i + 1), keys, phase: WAITING, retrieveId: null, cycle: 0, waiting: false })),
            nextN: 1, files: {}
        };
        this.pipe = pipe;
        this.pumpSend();
    }

    pumpSend() {
        if (this.closed || !this.pipe || this.pipe.phase !== 'sending') {
            return;
        }
        const ps = this.pipe.parts;
        if (ps.length && ps.every((p) => p.phase === READY)) {
            this.runPipe();
            return;
        }
        if (!ps.length) {
            this.runPipe();
            return;
        }
        let running = ps.filter((p) => p.phase === RUNNING).length;
        ps.forEach((p) => {
            if (running < AT_ONCE && p.phase === WAITING) {
                running += 1;
                this.sendPart(p.id);
            }
        });
    }

    setSend(id, values) {
        this.pipe = { ...this.pipe, parts: this.pipe.parts.map((p) => (p.id === id ? { ...p, ...values } : p)) };
    }

    sendPartOf(id) {
        return this.pipe.parts.find((p) => p.id === id);
    }

    async sendPart(id) {
        const p = this.sendPartOf(id);
        const n = this.pipe.nextN;
        this.pipe = { ...this.pipe, nextN: n + 1 };
        this.setSend(id, { phase: RUNNING, n });
        try {
            const retrieveId = await startPipelinePart({ sourceOrgId: this.sourceOrgId, keys: p.keys });
            this.setSend(id, { retrieveId });
            await this.stagePart(id);
        } catch (e) {
            this.failSend(id, e);
        }
    }

    async stagePart(id) {
        if (this.closed || !this.pipe) {
            return;
        }
        const p = this.sendPartOf(id);
        this.setSend(id, { waiting: false });
        try {
            const st = await stagePipelinePart({ partJson: JSON.stringify({ compareId: this.pipe.compareId, n: p.n, retrieveId: p.retrieveId, sourceOrgId: this.sourceOrgId }) });
            if (!st.done) {
                this.setSend(id, { waiting: true, cycle: p.cycle + 1 });
                return;
            }
            this.problems = this.problems.concat(st.problems || []);
            this.setSend(id, { phase: READY });
            this.pumpSend();
        } catch (e) {
            this.failSend(id, e);
        }
    }

    /** A part couldn't be sent: too large → one component at a time; otherwise the compare stops with the reason. */
    failSend(id, e) {
        const p = this.sendPartOf(id);
        const message = errorText(e);
        if (p.keys.length > 1 && SPLIT_ON.test(message)) {
            const singles = p.keys.map((k, i) => ({ id: id + '-' + (i + 1), keys: [k], phase: WAITING, retrieveId: null, cycle: 0, waiting: false }));
            this.pipe = { ...this.pipe, parts: this.pipe.parts.filter((x) => x.id !== id).concat(singles) };
            this.pumpSend();
            return;
        }
        this.pipe = { ...this.pipe, phase: 'failed', message: 'Sending the components to Git failed: ' + message };
    }

    async runPipe() {
        const compared = this.components.filter((c) => !isLeftOut(c.key));
        const keys = compared.filter((c) => !c.item.deleted).map((c) => c.key);
        const deleted = compared.filter((c) => c.item.deleted).map((c) => c.key);
        const notCompared = this.components.filter((c) => isLeftOut(c.key)).map((c) => c.key);
        if (!keys.length && !deleted.length) {
            this.pipe = { ...this.pipe, phase: 'done' };
            return;
        }
        try {
            const s = await runPipelineCompare({ jobJson: JSON.stringify({
                compareId: this.pipe.compareId, sourceOrgId: this.sourceOrgId, targetBranch: this.targetBranch,
                keys, deleted, parts: this.pipe.parts.length, notCompared }) });
            const urls = s.gitUrls || {};
            this.pipe = { ...this.pipe, phase: 'running', token: s.token };
            this.components = this.components.map((c) => (isLeftOut(c.key) ? { ...c, gitUrl: urls[c.key] } : { ...c, phase: RUNNING }));
            this.pipeCheck();
        } catch (e) {
            this.pipe = { ...this.pipe, phase: 'failed', message: errorText(e) };
        }
    }

    /** One check of the pipeline's result; while the run goes, counts down 5 seconds (CSS) and checks again. */
    async pipeCheck() {
        if (this.closed || !this.pipe || this.pipe.phase !== 'running') {
            return;
        }
        this.pipeWaiting = false;
        try {
            const r = await checkPipelineCompare({ compareId: this.pipe.compareId, token: this.pipe.token });
            this.pipe = { ...this.pipe, runUrl: r.runUrl || this.pipe.runUrl, runStatus: r.runStatus };
            if (!r.done) {
                this.pipeCycle += 1;
                this.pipeWaiting = true;
                return;
            }
            if (r.failed) {
                this.pipe = { ...this.pipe, phase: 'failed', message: r.message };
                return;
            }
            const byKey = new Map((r.components || []).map((x) => [x.key, x]));
            this.components = this.components.map((c) => {
                if (isLeftOut(c.key)) {
                    return c;
                }
                const found = byKey.get(c.key);
                return found ? { ...c, status: found.status, reason: found.reason, files: found.files || [], phase: READY }
                    : { ...c, status: UNSUPPORTED, reason: 'The pipeline didn’t return it.', files: [], phase: READY };
            });
            this.readAt = new Date().toISOString();
            this.pipe = { ...this.pipe, phase: 'done' };
            this.openFirstReady();
            this.pickFirstFile();
        } catch (e) {
            this.pipe = { ...this.pipe, phase: 'failed', message: errorText(e) };
        }
    }

    pipeTicks() {
        const t = [];
        if (this.pipe) {
            this.pipe.parts.filter((p) => p.waiting).forEach((p) => t.push({ key: 'pipe-' + p.id + '-' + p.cycle, part: 'pipe:' + p.id, cls: 'rr-tick-run' }));
            if (this.pipeWaiting) {
                t.push({ key: 'pipe-run-' + this.pipeCycle, part: 'pipe', cls: 'rr-tick-run rr-tick-slow' });
            }
        }
        return t;
    }

    pipeTick() {
        if (this.pipeWaiting) {
            this.pipeCheck();
        }
    }

    /** A sending part's countdown (data-part pipe:<id>). */
    handleSendTick(id) {
        const p = this.pipe && this.sendPartOf(id);
        if (p && p.waiting) {
            this.stagePart(id);
        }
    }

    /** Opens a pipeline file: its copies are read once, then kept. */
    async loadPipelineFile(f) {
        if (!this.pipe || !f || !f.n || this.pipe.files[f.n] || this.fileLoading) {
            return;
        }
        this.fileLoading = true;
        this.fileError = undefined;
        try {
            const d = await pipelineCompareFile({ compareId: this.pipe.compareId, n: f.n });
            this.pipe = { ...this.pipe, files: { ...this.pipe.files, [f.n]: d } };
        } catch (e) {
            this.fileError = errorText(e);
        } finally {
            this.fileLoading = false;
        }
    }

    get pipeSending() { return !!this.pipe && this.pipe.phase === 'sending'; }
    get pipeRunning() { return !!this.pipe && this.pipe.phase === 'running'; }
    get pipeFailed() { return !!this.pipe && this.pipe.phase === 'failed'; }
    get pipeMessage() { return this.pipe ? this.pipe.message : ''; }
    get pipeRunUrl() { return this.pipe ? this.pipe.runUrl : null; }
    get pipeStatusText() {
        if (this.pipeSending) {
            const ps = this.pipe.parts;
            const sent = ps.filter((p) => p.phase === READY).length;
            return 'Sending ' + this.sourceName + '’s copy to Git: part ' + Math.min(sent + 1, Math.max(ps.length, 1)) + ' of ' + Math.max(ps.length, 1) + '.';
        }
        if (this.pipeRunning) {
            return this.pipe.runStatus === 'in_progress' ? 'The pipeline is comparing in Git…' : 'Waiting for the pipeline to start…';
        }
        return '';
    }

    // ---------- progress ----------

    get readyCount() { return this.components.filter((c) => c.phase === READY).length; }
    get progressText() { return this.readyCount + ' of ' + this.components.length + ' ready'; }
    get runningText() {
        if (this.pipe) {
            return this.pipeStatusText;
        }
        const n = this.parts.filter((p) => p.phase === RUNNING).length;
        const failed = this.parts.filter((p) => p.phase === ERROR).length;
        const bits = [];
        if (n) {
            bits.push(plural(n, 'part', 'parts') + ' running');
        }
        if (failed) {
            bits.push(plural(failed, 'part', 'parts') + ' couldn’t be read');
        }
        return bits.join(' · ');
    }
    get showProgress() { return this.readyCount < this.components.length || !!this.pipe && this.pipe.phase !== 'done'; }
    get barReadyStyle() { return 'width:' + this.pct(this.readyCount) + '%'; }
    get barRunStyle() {
        const n = this.components.filter((c) => c.phase === RUNNING).length;
        return 'width:' + this.pct(n) + '%';
    }
    pct(n) {
        return this.components.length ? Math.round((n * 100) / this.components.length) : 0;
    }

    // ---------- list ----------

    get countText() { return plural(this.components.length, 'component', 'components'); }

    chipOf(c) {
        if (c.phase !== READY) {
            return PHASE_CHIPS[c.phase] || CHECKING;
        }
        if (c.files.length && c.files.every(isTooLarge)) {
            return TOO_LARGE_CHIP;
        }
        return c.status && c.status !== PENDING ? CHIPS[c.status] || CHECKING : CHECKING;
    }

    get rows() {
        return this.components.map((c) => {
            const on = c.key === this.selectedKey;
            const chip = this.chipOf(c);
            let sub = c.item.typeLabel;
            if (c.item.deleted) {
                sub += ' · Delete from ' + this.targetName;
            } else if (c.files.length) {
                sub += ' · ' + plural(c.files.length, 'file', 'files');
            }
            let why = '';
            if (c.phase === ERROR) {
                why = 'Try again on this part';
            } else if (c.phase === READY && c.status === UNSUPPORTED) {
                why = c.reason || '';
            } else if (c.phase === READY && c.files.some(isTooLarge)) {
                why = 'A file is too large for the hub';
            }
            return {
                key: c.key, name: c.item.name, sub, chipLabel: chip.label, chipCls: chip.cls, why,
                cls: 'rr-c-item' + (on ? ' rr-c-on' : ''), current: on ? 'true' : 'false'
            };
        });
    }
    /** The search text, normalised: filters the component list (the picker below 900px keeps them all). */
    term = '';

    get shownRows() {
        const q = this.term;
        return this.rows.filter((r) => matchesSearch([r.name, r.sub, r.chipLabel], q))
            .map((r) => ({ ...r, nameParts: highlightParts(r.name, q) }));
    }
    get showSearch() { return this.components.length >= SEARCH_FROM || !!this.term; }
    get noMatch() { return !!this.term && this.shownRows.length === 0; }
    get noMatchText() { return 'No components match ‘' + this.term + '’.'; }
    get rowCount() { return this.components.length; }
    get shownCount() { return this.shownRows.length; }

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
    }

    clearSearch() {
        clearSearchBox(this.template);
        this.term = '';
    }

    get pickOptions() { return this.components.map((c) => ({ label: c.item.name, value: c.key })); }

    pickComponent(event) {
        this.userPicked = true;
        this.selectedKey = event.currentTarget.dataset.key;
        this.pickFirstFile();
    }
    handlePickChange(event) {
        this.userPicked = true;
        this.selectedKey = event.detail.value;
        this.pickFirstFile();
    }
    pickFirstFile() {
        const c = this.selected;
        this.selectedPath = c && c.files.length ? c.files[0].path : undefined;
        this.loadPipelineFile(this.file);
    }

    // ---------- right pane ----------

    get selected() { return this.components.find((c) => c.key === this.selectedKey); }
    get selectedReady() { return !!this.selected && this.selected.phase === READY; }
    get selectedFailed() { return !!this.selected && this.selected.phase === ERROR && !this.pipe; }
    get selectedError() { return this.selected ? this.selected.error : ''; }
    get loading() { return !this.error && !this.pipeFailed && !this.selectedReady && !this.selectedFailed; }
    get file() {
        const c = this.selected;
        const f = c ? c.files.find((x) => x.path === this.selectedPath) || c.files[0] : undefined;
        if (f && this.pipe && f.n && this.pipe.files[f.n]) {
            return { ...f, ...this.pipe.files[f.n], status: f.status };
        }
        return f;
    }
    get loadingTitle() {
        const c = this.selected;
        const name = c ? c.item.name : '';
        if (this.pipe) {
            return this.pipeStatusText;
        }
        return c && c.phase === RUNNING ? 'Comparing ' + name + '…' : 'Waiting for ' + name + '…';
    }
    get loadingText() {
        if (this.pipe) {
            return 'Every component is compared in Git with the ' + this.targetBranch + ' branch; nothing is changed in either place.';
        }
        return 'Components are read a few at a time, so each one shows as soon as its part is ready.';
    }
    get showUnavailable() {
        const c = this.selected;
        return this.selectedReady && c.status === UNSUPPORTED && !c.files.some((f) => f.status !== UNSUPPORTED);
    }
    get unavailableName() { return this.selected ? this.selected.key.substring(this.selected.key.indexOf(':') + 1) : ''; }
    get unavailableReason() {
        const c = this.selected;
        return (c && (c.reason || (c.files[0] && c.files[0].reason))) || '';
    }
    /** A left-out component (static resource, profile): its file on the branch. */
    get unavailableUrl() { return (this.selected && this.selected.gitUrl) || ''; }
    get showFile() { return this.selectedReady && !this.showUnavailable && !!this.file; }
    get pipeFileWaiting() { return !!this.pipe && !!this.file && !!this.file.n && !this.pipe.files[this.file.n]; }
    get filePending() { return !!this.file && (this.file.status === PENDING || this.pipeFileWaiting); }
    get fileUnsupported() { return !!this.file && this.file.status === UNSUPPORTED; }
    get filePatch() { return !!this.file && !!this.file.patch; }
    get fileDiff() { return this.showFile && !this.filePending && !this.fileUnsupported && !this.filePatch; }
    get filePatchShown() { return this.showFile && !this.filePending && !this.fileUnsupported && this.filePatch; }
    get patchLines() { return this.filePatch ? this.file.patch.split('\n').slice(0, 20000).map(patchLine) : []; }
    get fileReadingText() { return this.pipe ? 'Reading the file from Git…' : 'Reading the ' + this.targetBranch + ' branch…'; }
    get fileReason() { return this.file ? this.file.reason : ''; }
    get fileTooLarge() { return !!this.file && isTooLarge(this.file) && !this.pipe; }
    get diffTitle() { return this.file ? this.file.path : ''; }
    get leftText() { return (this.file && this.file.left) || ''; }
    get rightText() { return (this.file && this.file.right) || ''; }
    get leftLabel() { return this.targetName + ' (' + this.targetBranch + ' branch)'; }
    get rightLabel() { return this.sourceName; }

    /** The file picker: only when the component has more than one file; each file with its own status. */
    get hasPicker() { return !!this.selected && this.selected.files.length > 1; }
    get pickerFiles() {
        const current = this.file;
        return (this.selected ? this.selected.files : []).map((f) => ({
            path: f.path,
            label: f.path.substring(f.path.lastIndexOf('/') + 1),
            cls: 'rr-fp' + (current && current.path === f.path ? ' rr-fp-on' : ''),
            pressed: current && current.path === f.path ? 'true' : 'false'
        }));
    }
    get fileChip() {
        const f = this.file;
        if (f && isTooLarge(f)) {
            return TOO_LARGE_CHIP;
        }
        return f && f.status !== PENDING ? CHIPS[f.status] || CHECKING : CHECKING;
    }
    get fileChipLabel() { return this.fileChip.label; }
    get fileChipCls() { return this.fileChip.cls; }
    pickFile(event) {
        this.selectedPath = event.currentTarget.dataset.path;
        this.loadPipelineFile(this.file);
    }
    get hasSubheader() { return this.hasPicker || !!this.flowLine; }

    /**
     * The flow's version line (board HubCompare 3) from Review's flow data and the target org's versions.
     * A Metadata API retrieve of a flow gives its ACTIVE version when it has one, so when the latest version is a newer
     * draft the line says the active one is what's compared.
     */
    get flowLine() {
        const c = this.selected;
        if (!c || c.item.type !== 'Flow' || c.item.deleted) {
            return undefined;
        }
        const f = (this.flowInfo || {})[c.item.name];
        if (!f || !f.latest) {
            return undefined;
        }
        const draftNewer = f.latestStatus !== 'Active' && !!f.active;
        const shown = draftNewer ? f.active : f.latest;
        const status = draftNewer ? 'Active' : f.latestStatus;
        const t = (this.targetFlows || []).find((x) => x.name === c.item.name);
        const tShown = t && (t.active || t.latest);
        const tStatus = t && (t.active ? 'Active' : t.latestStatus);
        return {
            source: 'Version ' + shown + ' · ' + (FLOW_STATUS[status] || status || 'Unknown'),
            sourceCls: FLOW_CLS[status] || 'rr-pill rr-pill-none',
            sourceWhere: 'in ' + this.sourceName,
            hasTarget: !!tShown,
            target: tShown ? 'Version ' + tShown + ' · ' + (FLOW_STATUS[tStatus] || tStatus || 'Unknown') : '',
            targetCls: FLOW_CLS[tStatus] || 'rr-pill rr-pill-none',
            targetWhere: 'in ' + this.targetName,
            note: draftNewer
                ? this.sourceName + ' copy is the active Version ' + f.active + '; Version ' + f.latest + ' · ' + (FLOW_STATUS[f.latestStatus] || f.latestStatus) + ' isn\'t compared.'
                : ''
        };
    }

    // ---------- frame ----------

    get heading() { return 'Compare with ' + this.targetName; }
    get intro() {
        const where = this.pipe ? ' (compared in the pipeline)' : '';
        return 'What ' + this.sourceName + ' has now against the ' + this.targetBranch + ' branch' + where + '. Nothing is changed in either place.';
    }
    get readLabel() { return this.sourceName + ' read'; }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }
    close() {
        this.closed = true;
        this.pipeWaiting = false;
        this.parts = this.parts.map((p) => ({ ...p, waiting: false }));
        this.dispatchEvent(new CustomEvent('close'));
    }
}
