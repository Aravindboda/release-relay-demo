import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import readBoard from '@salesforce/apex/RlyRunMonitorController.readBoard';
import readOlder from '@salesforce/apex/RlyRunMonitorController.readOlder';
import { searchTerm, matchesSearch } from 'c/rlyListSearch';
import { errorText, sameDay, clock, shortDate, toDate, isGated, fitPageToWindow } from 'c/rlyShared';

/** A run is queued or in progress: the board is read again every 10 s. */
const FAST_SECONDS = 10;
/** Nothing is going: every 30 s. */
const SLOW_SECONDS = 30;
const RELEASES_TAB = 'RLY_My_Releases';
const ACTIVE = ['Queued', 'In progress'];
const STATUS = {
    Queued: { label: 'Queued', cls: 'rr-badge rr-b-q', tone: 'run' },
    'In progress': { label: 'Running', cls: 'rr-badge rr-b-run', tone: 'run' },
    Succeeded: { label: 'Succeeded', cls: 'rr-badge rr-b-ok', tone: 'ok' },
    Failed: { label: 'Failed', cls: 'rr-badge rr-b-bad', tone: 'bad' },
    Cancelled: { label: 'Cancelled', cls: 'rr-badge rr-b-q', tone: 'none' }
};
const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'running', label: 'Running' },
    { value: 'failed', label: 'Failed' },
    { value: 'succeeded', label: 'Succeeded' }
];
const FILTER_STATUSES = { running: ACTIVE, failed: ['Failed'], succeeded: ['Succeeded'] };
const BRANCH_DOT = { running: 'rr-dot rr-d-run', failed: 'rr-dot rr-d-bad', ok: 'rr-dot rr-d-ok', warn: 'rr-dot rr-d-warn', idle: 'rr-dot rr-d-idle' };
const BRANCH_BADGE = { running: 'rr-badge rr-b-run', failed: 'rr-badge rr-b-bad', ok: 'rr-badge rr-b-ok', warn: 'rr-badge rr-b-warn', idle: 'rr-badge rr-b-q' };
/** A release's status as a colour, for branches with no pipeline run yet. */
const RELEASE_TONE = {
    'Checks failed': 'failed', Conflict: 'failed', Rejected: 'failed', Failed: 'failed', 'Deploy failed': 'failed',
    'Ready for approval': 'warn', 'Waiting for approval': 'warn', 'Needs a second approver': 'warn', 'Waiting for window': 'warn',
    Approved: 'ok', Deployed: 'ok', Merged: 'ok'
};
/** Space kept under the page inside the tab (the :host bottom padding plus a little air). */
const PAGE_BOTTOM_GAP = 30;
/** The page never gets shorter than this; below it the browser scrolls the tab. */
const PAGE_MIN_HEIGHT = 480;
const STEP_ICON = {
    success: { cls: 'rr-ic rr-ic-ok', mark: '✓' },
    failure: { cls: 'rr-ic rr-ic-bad', mark: '!' },
    cancelled: { cls: 'rr-ic rr-ic-skip', mark: '–' },
    skipped: { cls: 'rr-ic rr-ic-skip', mark: '' }
};
const SEGMENT_CLS = { done: 'rr-seg rr-seg-done', run: 'rr-seg rr-seg-run', failed: 'rr-seg rr-seg-bad', none: 'rr-seg' };

/** "9:12:04 PM". */
function clockSeconds(value) {
    const d = toDate(value);
    return d ? d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' }) : '';
}

/** "9:12 PM" today, else "Nov 5, 9:12 PM". */
function started(value) {
    const d = toDate(value);
    if (!d) {
        return '';
    }
    return sameDay(d, new Date()) ? clock(d) : d.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ', ' + clock(d);
}

/** "45s", "4m 10s", "1h 02m". */
function durationText(seconds) {
    if (seconds === null || seconds === undefined || isNaN(Number(seconds))) {
        return '';
    }
    const s = Math.max(0, Math.round(Number(seconds)));
    if (s < 60) {
        return s + 's';
    }
    const m = Math.floor(s / 60);
    if (m < 60) {
        return m + 'm ' + String(s % 60).padStart(2, '0') + 's';
    }
    return Math.floor(m / 60) + 'h ' + String(m % 60).padStart(2, '0') + 'm';
}

/** "just now", "3m ago", "2h ago", "1d ago". */
function ago(value, nowMs) {
    const d = toDate(value);
    if (!d) {
        return '';
    }
    const m = Math.floor(Math.max(0, nowMs - d.getTime()) / 60000);
    if (m < 1) {
        return 'just now';
    }
    if (m < 60) {
        return m + 'm ago';
    }
    const h = Math.floor(m / 60);
    return h < 24 ? h + 'h ago' : Math.floor(h / 24) + 'd ago';
}

/** A run's seconds: what it took, or how long it has run so far. */
function runSeconds(run, nowMs) {
    if (run.durationSeconds !== null && run.durationSeconds !== undefined) {
        return run.durationSeconds;
    }
    const s = toDate(run.started);
    return s ? Math.round((nowMs - s.getTime()) / 1000) : null;
}

function statusOf(run) {
    return STATUS[run && run.status] || { label: (run && run.status) || '', cls: 'rr-badge rr-b-q', tone: 'none' };
}

/**
 * The lane's four-part bar: from the jobs the pipeline sent when the run ended (each part shows the job at its share
 * of the run), else from the status: queued none, running the first part, succeeded all, failed the last part red.
 * @param {object} run RlyRunMonitorViews.Run
 * @returns {Array} four { key, cls }
 */
function segments(run) {
    const steps = ((run && run.steps) || []).filter((s) => s.outcome !== 'skipped');
    let parts;
    if (steps.length && !ACTIVE.includes(run.status)) {
        parts = [0, 1, 2, 3].map((i) => {
            const o = steps[Math.floor((i * steps.length) / 4)].outcome;
            if (o === 'success') {
                return 'done';
            }
            return o === 'failure' ? 'failed' : 'none';
        });
    } else if (run && run.status === 'In progress') {
        parts = ['run', 'none', 'none', 'none'];
    } else if (run && run.status === 'Succeeded') {
        parts = ['done', 'done', 'done', 'done'];
    } else if (run && run.status === 'Failed') {
        parts = ['done', 'done', 'done', 'failed'];
    } else {
        parts = ['none', 'none', 'none', 'none'];
    }
    return parts.map((p, i) => ({ key: 's' + i, cls: SEGMENT_CLS[p] }));
}

function byNewest(a, b) {
    const x = toDate(a.started);
    const y = toDate(b.started);
    return (y ? y.getTime() : 0) - (x ? x.getTime() : 0);
}

/**
 * Pipeline Monitor (Release Relay tab RLY_Pipeline_Monitor, design board v2): read only, for every Release Relay user.
 * Reads RlyRunMonitorController.readBoard (the runs the Git pipeline posts to the hub, RLY_Pipeline_Run__c, with the
 * releases and the route's orgs) and shows four tiles, the Route (one lane per org, grouped as on the Pipeline tab),
 * Active branches and Runs (filters All, Running, Failed, Succeeded; Load older runs pages in 50 more with readOlder).
 * Each section has its own search and its own scroll. A run opens its details in a side panel (an overlay on narrow
 * screens). Refresh: the board is read again every 10 s while a run is queued or in progress and every 30 s otherwise,
 * paused while the browser tab is hidden and read at once when it is visible again. The countdown is a CSS animation of
 * one-second steps (no JavaScript timers): each step counts down, the end reads the board.
 */
export default class RlyPipelineMonitor extends NavigationMixin(LightningElement) {
    hubStatus;
    statusRead = false;
    board;
    error;
    loading = false;
    refreshing = false;
    repository;
    /** Older finished runs loaded with Load older runs (kept across refreshes). */
    olderRuns = [];
    olderHasMore;
    loadingOlder = false;
    routeTerm = '';
    branchTerm = '';
    runTerm = '';
    filter = 'all';
    selectedId;
    nowMs = Date.now();
    /** The countdown: seconds left, the cycle (a new animation element each cycle) and its length. */
    secondsLeft = 0;
    cycle = 0;
    cycleSeconds = SLOW_SECONDS;
    ticking = false;
    paused = false;
    visibilityHandler;

    // view models, rebuilt when the board, a search or the filter changes (not on every countdown step)
    laneGroups = [];
    laneCount = { shown: 0, total: 0 };
    branchRows = [];
    branchCount = { shown: 0, total: 0 };
    runRows = [];
    runCount = { shown: 0, total: 0 };

    get appName() { return APP_NAME; }

    connectedCallback() {
        this.visibilityHandler = () => this.handleVisibility();
        document.addEventListener('visibilitychange', this.visibilityHandler);
        this.resizeHandler = () => this.fitToWindow();
        window.addEventListener('resize', this.resizeHandler);
        this.readHubStatus();
    }

    disconnectedCallback() {
        this.stopCountdown();
        document.removeEventListener('visibilitychange', this.visibilityHandler);
        window.removeEventListener('resize', this.resizeHandler);
    }

    renderedCallback() {
        this.fitToWindow();
    }

    /** Sizes the page to the browser window: from its top edge to the bottom of the window, whatever the screen. */
    fitToWindow() {
        this.pageHeight = fitPageToWindow(this.template.querySelector('.rr-page'), this.pageHeight, PAGE_MIN_HEIGHT, PAGE_BOTTOM_GAP);
    }

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
                if (!this.gated) {
                    this.load();
                }
            });
    }

    get gated() { return isGated(this.hubStatus); }
    get showPage() { return this.statusRead && !this.gated; }
    get showSpinner() { return this.loading && !this.board; }

    // ---------- reading and the countdown ----------

    /** Reads the board, then counts down to the next read (10 s while a run is going, else 30 s). */
    async load() {
        this.stopCountdown();
        this.loading = !this.board;
        this.refreshing = true;
        try {
            const b = await readBoard({ repository: this.repository || null });
            this.board = b;
            this.repository = b.repository;
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
            this.refreshing = false;
        }
        this.nowMs = Date.now();
        this.rebuild();
        this.schedule();
    }

    schedule() {
        if (document.hidden) {
            this.paused = true;
            return;
        }
        this.paused = false;
        this.cycleSeconds = this.board && this.board.anyActive ? FAST_SECONDS : SLOW_SECONDS;
        this.secondsLeft = this.cycleSeconds;
        this.cycle += 1;
        this.ticking = true;
    }

    stopCountdown() {
        this.ticking = false;
    }

    /** One second of the countdown passed (an iteration of the tick animation). */
    handleTick() {
        if (!this.ticking) {
            return;
        }
        this.secondsLeft = Math.max(0, this.secondsLeft - 1);
    }

    /** The countdown ended: read the board again (unless the tab was hidden meanwhile). */
    handleTickEnd() {
        if (!this.ticking) {
            return;
        }
        this.ticking = false;
        if (document.hidden) {
            this.paused = true;
            return;
        }
        this.load();
    }

    /** Hidden tab: no reads (the countdown stops). Visible again: reads at once, then counts down as before. */
    handleVisibility() {
        if (!this.showPage) {
            return;
        }
        if (document.hidden) {
            if (this.ticking) {
                this.stopCountdown();
            }
            this.paused = true;
        } else if (this.paused) {
            this.paused = false;
            this.load();
        }
    }

    refresh() {
        if (!this.refreshing) {
            this.load();
        }
    }

    get cycles() { return this.ticking ? [{ key: 'c' + this.cycle }] : []; }
    get tickCls() { return this.cycleSeconds === FAST_SECONDS ? 'rr-tick rr-tick-fast' : 'rr-tick rr-tick-slow'; }
    get meterCls() { return this.cycleSeconds === FAST_SECONDS ? 'rr-meter-fill rr-meter-fast' : 'rr-meter-fill rr-meter-slow'; }
    get liveCls() { return this.error ? 'rr-live rr-live-bad' : (this.paused ? 'rr-live rr-live-off' : 'rr-live'); }
    get updatedText() {
        const when = this.board ? clockSeconds(this.board.readAt) : '';
        let next;
        if (this.refreshing) {
            next = 'updating…';
        } else if (this.paused) {
            next = 'paused while this tab is hidden';
        } else {
            next = 'next in ' + this.secondsLeft + 's';
        }
        return (when ? 'Updated ' + when + ' · ' : '') + next;
    }

    // ---------- repository ----------

    get repoOptions() {
        return ((this.board && this.board.repos) || []).map((r) => ({ label: r.repository, value: r.repository }));
    }
    get hasRepos() { return this.repoOptions.length > 0; }
    get repoDisabled() { return this.repoOptions.length < 2; }

    handleRepo(event) {
        this.repository = event.detail.value;
        this.olderRuns = [];
        this.olderHasMore = undefined;
        this.selectedId = undefined;
        this.load();
    }

    // ---------- tiles ----------

    get tiles() { return (this.board && this.board.tiles) || { running: 0, branches: 0, succeededToday: 0, failedToday: 0 }; }
    get showRunSpin() { return this.tiles.running > 0; }
    get failedTileCls() { return this.tiles.failedToday > 0 ? 'rr-card rr-tile rr-tile-bad' : 'rr-card rr-tile rr-tile-quiet'; }
    get failedTileHint() { return this.tiles.failedToday > 0 ? 'Failed today · click to show' : 'Failed today'; }

    showFailed() {
        this.filter = 'failed';
        this.buildRuns();
    }

    // ---------- view models ----------

    rebuild() {
        this.buildLanes();
        this.buildBranches();
        this.buildRuns();
    }

    /** Every run the page knows: the board's runs, the older pages and the lanes' runs (for the details panel). */
    get allRuns() {
        const map = new Map();
        const add = (r) => {
            if (r && r.id && !map.has(r.id)) {
                map.set(r.id, r);
            }
        };
        ((this.board && this.board.runs) || []).forEach(add);
        this.olderRuns.forEach(add);
        ((this.board && this.board.lanes) || []).forEach((l) => {
            add(l.run);
            add(l.lastRun);
        });
        return map;
    }

    buildLanes() {
        const lanes = (this.board && this.board.lanes) || [];
        const term = this.routeTerm;
        const groups = [];
        let shown = 0;
        lanes.forEach((l) => {
            const r = l.run;
            const last = l.lastRun;
            const values = [l.name, l.environment, l.roleText, r && r.branch, r && r.releaseName, r && r.actor, r && statusOf(r).label,
                r && r.step, last && last.releaseName];
            if (!matchesSearch(values, term)) {
                return;
            }
            let g = groups.find((x) => x.key === l.groupKey);
            if (!g) {
                g = { key: l.groupKey, label: l.groupLabel, lanes: [] };
                groups.push(g);
            }
            g.lanes.push(this.laneRow(l));
            shown += 1;
        });
        this.laneGroups = groups;
        this.laneCount = { shown, total: lanes.length };
    }

    laneRow(l) {
        const r = l.run;
        const row = { key: l.orgId, name: l.name, roleText: l.roleText, hasRun: !!r };
        if (r) {
            const st = statusOf(r);
            const parts = [r.releaseName, durationText(runSeconds(r, this.nowMs)), r.actor].filter((x) => x);
            return { ...row, runId: r.id, badge: st.label, badgeCls: st.cls, branch: r.branch || '', meta: parts.join(' · '),
                segments: segments(r), chipCls: 'rr-chip rr-chip-' + st.tone + (r.id === this.selectedId ? ' rr-chip-sel' : ''),
                title: 'Open the run details: ' + (r.step || st.label) };
        }
        const last = l.lastRun;
        const meta = last ? 'last run ' + shortDate(last.started) + (last.releaseName ? ' · ' + last.releaseName : '') : 'No run in the last 30 days';
        return { ...row, runId: last ? last.id : null, badge: 'No runs today', badgeCls: 'rr-badge rr-b-q', meta,
            chipCls: 'rr-chip rr-chip-idle', title: last ? 'Open the last run' : '' };
    }

    buildBranches() {
        const all = (this.board && this.board.branches) || [];
        const term = this.branchTerm;
        const rows = [];
        all.forEach((b) => {
            const pr = b.prNumber ? 'PR #' + b.prNumber + ' ' + (b.prState || 'open') : (b.releaseId ? 'No PR yet' : 'No PR');
            const values = [b.branch, pr, b.releaseName, b.stage, b.step];
            if (!matchesSearch(values, term)) {
                return;
            }
            const activity = b.lastActivity ? 'last activity ' + ago(b.lastActivity, this.nowMs) : '';
            const noRun = b.state === 'idle' && !b.runRecordId;
            // A release that needs attention (red or amber) shows its own status even after a green run, unless a run is
            // going right now.
            const releaseTone = RELEASE_TONE[b.releaseStatus];
            const useRelease = noRun || (b.state !== 'running' && (releaseTone === 'failed' || releaseTone === 'warn'));
            const tone = useRelease ? (releaseTone || (b.releaseStatus ? 'running' : 'idle')) : b.state;
            const stage = useRelease ? (b.releaseStatus || 'Waiting') : (b.stage || 'Waiting');
            rows.push({
                key: b.branch,
                branch: b.branch,
                meta: [pr, b.releaseName, activity].filter((x) => x).join(' · '),
                dotCls: BRANCH_DOT[tone] || BRANCH_DOT.idle,
                badge: stage,
                badgeCls: BRANCH_BADGE[tone] || BRANCH_BADGE.idle,
                runId: b.runRecordId,
                rowCls: b.runRecordId && b.runRecordId === this.selectedId ? 'rr-brl rr-brl-sel' : 'rr-brl',
                stateText: b.state
            });
        });
        this.branchRows = rows;
        this.branchCount = { shown: rows.length, total: all.length };
    }

    /** The loaded runs, each once, running first, then newest. */
    get loadedRuns() {
        const seen = new Set();
        const out = [];
        [...((this.board && this.board.runs) || []), ...this.olderRuns].forEach((r) => {
            if (!seen.has(r.id)) {
                seen.add(r.id);
                out.push(r);
            }
        });
        const active = out.filter((r) => ACTIVE.includes(r.status)).sort(byNewest);
        const rest = out.filter((r) => !ACTIVE.includes(r.status)).sort(byNewest);
        return [...active, ...rest];
    }

    buildRuns() {
        const loaded = this.loadedRuns;
        const term = this.runTerm;
        const statuses = FILTER_STATUSES[this.filter];
        const rows = [];
        loaded.forEach((r) => {
            const st = statusOf(r);
            if (statuses && !statuses.includes(r.status)) {
                return;
            }
            if (!matchesSearch([r.branch, r.releaseName, r.targetOrg, r.actor, r.step, st.label, r.runNumber], term)) {
                return;
            }
            rows.push({
                key: r.id,
                id: r.id,
                badge: st.label,
                badgeCls: st.cls,
                step: r.step || r.mode || '',
                branch: r.branch || '',
                targetOrg: r.targetOrg || '',
                releaseName: r.releaseName || '',
                releaseId: r.releaseId,
                hasRelease: !!r.releaseId,
                startedText: started(r.started),
                durationText: durationText(runSeconds(r, this.nowMs)),
                actor: r.actor || '',
                runUrl: r.runUrl,
                rowCls: r.id === this.selectedId ? 'rr-tr rr-tr-sel' : 'rr-tr'
            });
        });
        this.runRows = rows;
        this.runCount = { shown: rows.length, total: loaded.length };
    }

    // ---------- section headers, counts and empty states ----------

    countText(c) { return c.shown === c.total ? String(c.total) : c.shown + ' of ' + c.total; }
    get laneCountText() { return this.countText(this.laneCount); }
    get branchCountText() { return this.countText(this.branchCount); }
    get runCountText() { return this.countText(this.runCount); }
    get hasLanes() { return this.laneGroups.length > 0; }
    get hasBranches() { return this.branchRows.length > 0; }
    get showRunEmpty() { return this.runRows.length === 0; }
    get laneEmpty() {
        return this.laneCount.total ? 'No org matches your search.' : 'No orgs on the route yet. Register them on the Pipeline tab.';
    }
    get branchEmpty() {
        return this.branchCount.total ? 'No branch matches your search.' : 'No active branches: no open releases and no runs in the last 24 hours.';
    }
    get runEmpty() {
        if (this.runCount.total) {
            return this.filter === 'all' && !this.runTerm ? 'No runs.' : 'No run matches your search or filter.';
        }
        return 'No runs yet. Runs show here once the Git pipeline (version 20) posts them to Release Relay.';
    }

    get filterPills() {
        return FILTERS.map((f) => ({
            ...f,
            cls: f.value === this.filter ? 'rr-pill rr-pill-on' : 'rr-pill',
            pressed: f.value === this.filter ? 'true' : 'false'
        }));
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
        this.buildRuns();
    }

    handleRouteSearch(event) {
        this.routeTerm = searchTerm(event.detail.value);
        this.buildLanes();
    }

    handleBranchSearch(event) {
        this.branchTerm = searchTerm(event.detail.value);
        this.buildBranches();
    }

    handleRunSearch(event) {
        this.runTerm = searchTerm(event.detail.value);
        this.buildRuns();
    }

    // ---------- older runs ----------

    get hasMore() { return this.olderHasMore === undefined ? !!(this.board && this.board.hasMore) : this.olderHasMore; }
    get olderLabel() { return this.loadingOlder ? 'Loading…' : 'Load older runs'; }

    async loadOlder() {
        const finished = this.loadedRuns.filter((r) => !ACTIVE.includes(r.status) && r.started);
        const oldest = finished[finished.length - 1];
        if (!oldest || this.loadingOlder) {
            return;
        }
        this.loadingOlder = true;
        try {
            const page = await readOlder({ repository: this.repository || null, startedBefore: oldest.started, idBefore: oldest.id });
            this.olderRuns = [...this.olderRuns, ...((page && page.runs) || [])];
            this.olderHasMore = !!(page && page.hasMore);
            this.error = undefined;
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loadingOlder = false;
        }
        this.buildRuns();
    }

    // ---------- run details ----------

    get selected() { return this.selectedId ? this.allRuns.get(this.selectedId) : undefined; }
    get showDetails() { return !!this.selected; }
    get mainCls() { return this.showDetails ? 'rr-main rr-main-with-side' : 'rr-main'; }

    selectRun(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this.selectedId = id === this.selectedId ? undefined : id;
        this.rebuild();
    }

    selectRunKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.selectRun(event);
        }
    }

    closeDetails() {
        this.selectedId = undefined;
        this.rebuild();
    }

    get detail() {
        const r = this.selected;
        if (!r) {
            return {};
        }
        const st = statusOf(r);
        return {
            statusLabel: st.label,
            statusCls: 'rr-kv-status rr-tone-' + st.tone,
            release: r.releaseName ? r.releaseName + (r.releaseTitle ? ' · ' + r.releaseTitle : '') : '—',
            hasRelease: !!r.releaseId,
            releaseId: r.releaseId,
            releaseName: r.releaseName,
            step: (r.step || r.mode || '') + (r.targetOrg ? ' in ' + r.targetOrg : ''),
            branch: r.branch || '—',
            startedText: clockSeconds(r.started) + (r.started && !sameDay(new Date(r.started), new Date()) ? ', ' + shortDate(r.started) : '')
                + ' · ' + durationText(runSeconds(r, this.nowMs)),
            actor: r.actor || '—',
            runText: (r.runNumber ? '#' + r.runNumber : '—') + ' · attempt ' + (r.attempt || 1),
            steps: (r.steps || []).map((s, i) => {
                const icon = STEP_ICON[s.outcome] || STEP_ICON.skipped;
                return {
                    key: 'st' + i,
                    name: s.name,
                    iconCls: icon.cls,
                    mark: icon.mark,
                    nameCls: s.outcome === 'skipped' ? 'rr-st-name rr-weak' : 'rr-st-name',
                    meta: s.outcome === 'skipped' ? 'skipped' : durationText(s.seconds)
                };
            }),
            hasSteps: (r.steps || []).length > 0,
            noStepsText: ACTIVE.includes(r.status) ? 'The jobs and their outcomes show when the run ends.' : 'The pipeline sent no job list for this run.',
            failure: r.failure,
            runUrl: r.runUrl,
            openReleaseLabel: 'Open release ' + (r.releaseName || '') + ' →'
        };
    }

    // ---------- links ----------

    openRelease(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        event.stopPropagation();
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: RELEASES_TAB }, state: { c__release: id } });
    }

    stopClick(event) {
        event.stopPropagation();
    }
}
