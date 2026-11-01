import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import readArchive from '@salesforce/apex/RlyArchiveController.readArchive';
import startRun from '@salesforce/apex/RlyArchiveController.startRun';
import runPass from '@salesforce/apex/RlyArchiveController.runPass';
import cancelRun from '@salesforce/apex/RlyArchiveController.cancelRun';
import { searchTerm, matchesSearch, highlightParts } from 'c/rlyListSearch';
import {
    KB_PER_RECORD, PASS_SIZE, DAY_MS, num, count, longDate, shortDate, clock, when, stamp, toDate,
    nightlyClock, mb, size, duration, errorText
} from 'c/rlyArchiveText';

/** Modes of RlyHubGuard.getHubStatus in which the tab shows only the org gate. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];
/** Under this width (board section 4) tiles stack two per row and the runs list keeps When, Releases and Status. */
const NARROW_QUERY = '(max-width: 480px)';
const PIPELINE_TAB = 'RLY_Pipeline';
const GUIDE_TAB = 'RLY_Relay_Guide';
const GUIDE_SECTION = 'setup-archive';
/** A pass also stops at this many records (release + children). */
const PASS_RECORDS = 4000;
/** The server stops a run after 25 passes (Partial); the page never asks for more than this. */
const MAX_PASSES = 30;
/** Focus and visibility changes re-read the numbers at most this often. */
const REREAD_GAP = 5000;
const NIGHTLY = 'Nightly';
const STATUS = {
    Succeeded: { cls: 'rr-chip-st rr-st-ok', short: 'OK' },
    Failed: { cls: 'rr-chip-st rr-st-bad', short: 'Failed' },
    Partial: { cls: 'rr-chip-st rr-st-part', short: 'Partial' },
    Cancelled: { cls: 'rr-chip-st rr-st-none', short: 'Cancelled' },
    Running: { cls: 'rr-chip-st rr-st-run', short: 'Running' }
};
const STATUS_CHIPS = ['Succeeded', 'Failed', 'Partial', 'Cancelled'];
const LINK_TIP = 'Opens the GitHub Actions run that made this call (its log has every pass). Failed: what was removed before the failure stays removed.';

/** "Oct 25 – Oct 31, 2023", or with both years when they differ. */
function rangeText(oldest, newest) {
    const a = toDate(oldest);
    const b = toDate(newest);
    if (!a && !b) {
        return '–';
    }
    if (!a || !b) {
        return longDate(a || b);
    }
    return a.getFullYear() === b.getFullYear() ? shortDate(a) + ' – ' + longDate(b) : longDate(a) + ' – ' + longDate(b);
}

/** "#4821" from a GitHub Actions run URL (…/actions/runs/4821), or ''. */
function runNumber(url) {
    const m = /\/runs\/(\d+)/.exec(String(url || ''));
    return m ? '#' + m[1] : '';
}

/** A round top for the chart's scale with 4 steps of 1, 2, 2.5 or 5 × 10^n. */
function niceTop(max) {
    const raw = Math.max(1, max) / 4;
    const pow = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= raw);
    return step * 4;
}

function parts(text, term) {
    return highlightParts(text, term);
}

export default class RlyArchive extends NavigationMixin(LightningElement) {
    /** RlyHubGuard.getHubStatus: outside the production hub this tab shows only rlyOrgGate. */
    hubStatus;
    statusRead = false;
    /** RlyArchiveController.readArchive. */
    archive;
    loading = false;
    error;
    updatedAt;
    lastRead = 0;
    narrow = false;
    media;
    mediaHandler;
    focusHandler;
    visibilityHandler;
    searchText = '';
    term = '';
    /** all, or one status (Failed, Succeeded, Partial, Cancelled). */
    filter = 'all';
    /** Narrow layout: the run whose details are open. */
    openRunId;

    // Run now window
    /** confirm, running, done, stopped, failed (undefined while closed). */
    modal;
    typedDays = '';
    passes = [];
    runId;
    runTotal = 0;
    runRemoved = 0;
    runRecords = 0;
    runRemaining = 0;
    runStatus;
    runMessage;
    runStartedAt;
    runEndedAt;
    cancelAsked = false;
    leaving = false;
    focusModal = false;
    focusRunNow = false;

    get appName() { return APP_NAME; }

    // ---------- loading ----------

    connectedCallback() {
        this.leaving = false;
        this.watchWidth();
        this.watchFocus();
        this.readHubStatus();
    }

    disconnectedCallback() {
        // A run in progress stops after the pass it is in (the loop sees this and cancels the run).
        this.leaving = true;
        if (this.media && this.mediaHandler) {
            this.media.removeEventListener('change', this.mediaHandler);
        }
        if (this.focusHandler) {
            window.removeEventListener('focus', this.focusHandler);
        }
        if (this.visibilityHandler) {
            document.removeEventListener('visibilitychange', this.visibilityHandler);
        }
    }

    renderedCallback() {
        if (this.focusModal) {
            const el = this.template.querySelector('.rr-modal-focus');
            if (el) {
                el.focus();
                this.focusModal = false;
            }
        }
        if (this.focusRunNow) {
            const btn = this.template.querySelector('.rr-run-now');
            if (btn) {
                btn.focus();
            }
            this.focusRunNow = false;
        }
    }

    watchWidth() {
        if (typeof window === 'undefined' || !window.matchMedia) {
            return;
        }
        this.media = window.matchMedia(NARROW_QUERY);
        this.narrow = this.media.matches;
        this.mediaHandler = (event) => {
            this.narrow = event.matches;
        };
        this.media.addEventListener('change', this.mediaHandler);
    }

    /** No constant polling: the numbers are read again when the tab comes back into view, and after each pass. */
    watchFocus() {
        if (typeof window === 'undefined' || typeof document === 'undefined') {
            return;
        }
        this.focusHandler = () => this.rereadSoon();
        this.visibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                this.rereadSoon();
            }
        };
        window.addEventListener('focus', this.focusHandler);
        document.addEventListener('visibilitychange', this.visibilityHandler);
    }

    rereadSoon() {
        if (!this.showPage || this.loading || this.modal === 'running' || Date.now() - this.lastRead < REREAD_GAP) {
            return;
        }
        this.load();
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
                if (!this.statusGated) {
                    this.load();
                }
            });
    }

    load() {
        this.loading = true;
        this.lastRead = Date.now();
        return readArchive()
            .then((a) => {
                this.archive = a;
                this.error = undefined;
                this.updatedAt = new Date();
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    /** Re-reads quietly (after each pass): a failed read keeps the numbers on screen. */
    reread() {
        this.lastRead = Date.now();
        return readArchive()
            .then((a) => {
                this.archive = a;
                this.updatedAt = new Date();
            })
            .catch(() => {});
    }

    // ---------- gate and access ----------

    get statusGated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    /** The org gate's status: the hub guard's, or readArchive's own mode when it isn't the hub. */
    get gateStatus() {
        if (this.statusGated) {
            return this.hubStatus;
        }
        const a = this.archive;
        if (a && a.mode && a.mode !== 'hub') {
            return { mode: a.mode, title: a.gateTitle, message: a.gateMessage };
        }
        return this.hubStatus;
    }
    get gated() {
        const a = this.archive;
        return this.statusGated || (!!a && !!a.mode && a.mode !== 'hub');
    }
    get showPage() { return this.statusRead && !this.gated; }
    get hasArchive() { return !!this.archive; }
    get canView() { return this.hasArchive && this.archive.canView === true; }
    get noAccess() { return this.hasArchive && this.archive.canView !== true; }
    get canRun() { return this.canView && this.archive.canRun === true; }
    get showApproverLine() { return this.canView && !this.canRun; }

    // ---------- header ----------

    get liveText() {
        if (this.narrow || !this.updatedAt) {
            return 'Live';
        }
        return 'Live · updated ' + clock(this.updatedAt);
    }
    get hasDays() { return this.hasArchive && this.archive.days !== null && this.archive.days !== undefined; }
    get days() { return this.hasDays ? this.archive.days : null; }
    get daysText() { return this.hasDays ? count(this.days, 'day', 'days') : ''; }
    get nightlyOn() { return this.hasDays && this.archive.nightly === true; }
    get eligible() { return this.hasArchive ? this.archive.eligibleReleases || 0 : 0; }
    get eligibleRecords() { return this.hasArchive ? this.archive.eligibleRecords || 0 : 0; }
    get cutoffText() { return this.hasArchive && this.archive.cutoffDate ? longDate(this.archive.cutoffDate) : ''; }
    get isRunning() { return this.modal === 'running' || (this.hasArchive && !!this.archive.running); }
    get runNowLabel() { return this.isRunning ? 'Running…' : 'Run now'; }
    get runNowDisabled() { return !!this.runNowReason; }
    /** Why Run now is off (also its tooltip), or ''. */
    get runNowReason() {
        if (this.isRunning) {
            return 'A run is going. A second run is refused until it ends.';
        }
        if (!this.hasDays) {
            return 'Set the number of days on the Pipeline tab first.';
        }
        if (this.eligible === 0) {
            return 'Disabled: nothing is eligible.';
        }
        return '';
    }
    get showRunNowReason() { return this.canRun && !!this.runNowReason && !this.isRunning; }
    get runningPill() { return this.hasArchive && !!this.archive.running && !this.canRun; }

    // ---------- tiles ----------

    get eligibleTileCls() {
        if (!this.hasDays) {
            return 'rr-tile';
        }
        return this.eligible > 0 ? 'rr-tile rr-tile-warn' : 'rr-tile rr-tile-good';
    }
    get eligibleValue() { return this.hasDays ? num(this.eligible) : '–'; }
    get eligibleRecordsText() { return num(this.eligibleRecords); }
    get eligibleSub() {
        if (!this.hasDays) {
            return 'No days set';
        }
        return this.narrow ? '' : ' records · finished before ' + this.cutoffText;
    }
    get showEligibleRecords() { return this.hasDays; }
    get eligibleNarrowSub() { return this.narrow && this.hasDays ? ' records' : ''; }
    get eligibleNextText() {
        const n = this.hasArchive ? this.archive.eligibleNext30 || 0 : 0;
        if (!this.hasDays || this.narrow) {
            return '';
        }
        return n ? num(n) + ' more in the next 30 days' : 'None more in the next 30 days';
    }
    get archivedValue() { return num(this.hasArchive ? this.archive.archivedReleases || 0 : 0); }
    get hasRuns() { return this.hasArchive && (this.archive.runCount || 0) > 0; }
    get archivedRecordsText() { return num(this.hasArchive ? this.archive.archivedRecords || 0 : 0); }
    get archivedSince() {
        if (!this.hasRuns || this.narrow) {
            return '';
        }
        const first = this.archive.firstRun ? 'since ' + longDate(this.archive.firstRun) + ' · ' : '';
        return first + count(this.archive.runCount, 'run', 'runs');
    }
    get freedValue() { return '≈ ' + mb(this.hasArchive ? this.archive.freedKB || 0 : 0); }
    get freedPerRecord() { return this.narrow ? KB_PER_RECORD + ' KB per record' : 'about ' + KB_PER_RECORD + ' KB per record'; }
    get freedMoreText() {
        if (!this.hasDays || !this.eligibleRecords || this.narrow) {
            return '';
        }
        return '≈ ' + mb(this.eligibleRecords * KB_PER_RECORD) + ' MB more if run now';
    }
    get lastRun() { return this.hasArchive ? this.archive.lastRun : null; }
    get lastRunWhen() { return this.lastRun ? when(this.lastRun.started) : 'No runs yet'; }
    get lastRunHow() { return this.lastRun ? this.lastRun.how : ''; }
    get lastRunBy() {
        if (!this.lastRun) {
            return '';
        }
        if (this.narrow) {
            return ' · ' + this.lastRun.status;
        }
        return ' · ' + (this.lastRun.how === NIGHTLY ? 'Git pipeline job' : this.lastRun.runBy || '');
    }
    get lastRunNums() {
        const r = this.lastRun;
        if (!r || this.narrow) {
            return '';
        }
        return count(r.releases || 0, 'release', 'releases') + ' · ' + count(r.records || 0, 'record', 'records') + ' · ' + r.status;
    }
    get settingValue() {
        if (!this.hasDays) {
            return 'Keep forever';
        }
        return this.narrow ? this.daysText + ' · nightly ' + (this.nightlyOn ? 'on' : 'off') : this.daysText;
    }
    get settingLead() {
        if (this.narrow) {
            return '';
        }
        if (!this.hasDays) {
            return 'No days set';
        }
        return this.nightlyOn ? 'Nightly on' : 'Nightly off';
    }
    get settingTail() {
        if (this.narrow || !this.hasDays) {
            return '';
        }
        return this.nightlyOn ? ' · next ' + nightlyClock() : ' · Run now only';
    }
    get settingLink() { return this.narrow ? 'Pipeline tab' : 'Change on the Pipeline tab'; }

    // ---------- empty states ----------

    get showNoDays() { return this.canView && !this.hasDays; }
    get showNothingEligible() { return this.canView && this.hasDays && this.eligible === 0 && !this.isRunning; }
    get nothingText() {
        return 'No finished release is older than ' + this.daysText + '.'
            + (this.nightlyOn ? ' The next nightly run is at ' + nightlyClock() + '.' : '');
    }
    /** With no days and no runs yet, only the tiles and the "Set retention" card show. */
    get showDetail() { return this.canView && (this.hasDays || this.hasRuns); }

    // ---------- nightly job ----------

    get health() { return (this.hasArchive && this.archive.health) || {}; }
    get missed() { return this.nightlyOn ? this.health.missedNights || 0 : 0; }
    get healthPill() {
        if (this.missed >= 2) {
            return 'Missed ' + this.missed + ' nights';
        }
        if (this.missed === 1) {
            return 'Missed last night';
        }
        if (!this.nightlyOn) {
            return 'Nightly off';
        }
        if (!this.health.lastCall) {
            return 'No calls yet';
        }
        return 'Called last night';
    }
    get healthPillCls() {
        if (this.missed >= 2) {
            return 'rr-pill rr-pill-bad';
        }
        if (this.missed === 1) {
            return 'rr-pill rr-pill-wait';
        }
        return this.nightlyOn && this.health.lastCall ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-none';
    }
    get healthSub() { return this.narrow ? '30 days' : 'Calls from the Git pipeline\'s scheduled job · last 30 days'; }
    get hRuns() { return num(this.health.runs || 0); }
    get hRunsSub() { return this.nightlyOn ? 'one per night' : 'nightly is off'; }
    get hSucceeded() { return num(this.health.succeeded || 0); }
    get hFailed() { return num(this.health.failed || 0); }
    get hPartial() { return num(this.health.partial || 0); }
    get hFailedCls() { return (this.health.failed || 0) > 0 ? 'rr-hl-cell rr-hl-red' : 'rr-hl-cell'; }
    get hSucceededLabel() { return this.narrow ? 'OK' : 'Succeeded'; }
    get hRunsLabel() { return this.narrow ? 'Runs' : 'Runs (30 days)'; }
    /** "Oct 12, Oct 29": the failed nightly runs in the last 30 days. */
    get hFailedDates() {
        if ((this.health.failed || 0) === 0) {
            return 'none';
        }
        const since = Date.now() - 30 * DAY_MS;
        const dates = this.runs
            .filter((r) => r.how === NIGHTLY && r.status === 'Failed' && toDate(r.started) && toDate(r.started).getTime() >= since)
            .map((r) => shortDate(r.started))
            .reverse();
        return dates.length > 3 ? dates.slice(-3).join(', ') + '…' : dates.join(', ');
    }
    get lastCallText() { return this.health.lastCall ? when(this.health.lastCall) : 'No call yet'; }
    get lastCallCls() { return this.missed > 0 ? 'rr-hl-v rr-hl-txt rr-amber' : 'rr-hl-v rr-hl-txt'; }
    /** "Last call skipped: nightly is off", or the nightly run that call made. */
    get lastCallSub() {
        const res = this.health.lastCallResult || '';
        if (/^skipped/i.test(res)) {
            return 'Last call ' + res.charAt(0).toLowerCase() + res.slice(1);
        }
        const run = this.runs.find((r) => r.how === NIGHTLY);
        if (run && this.health.lastCall) {
            return [run.name, count(run.passes || 0, 'pass', 'passes'), count(run.releases || 0, 'release', 'releases')].join(' · ');
        }
        return res;
    }
    get lastFailure() { return this.health.lastFailure || null; }
    get lastFailureTitle() { return this.lastFailure ? 'Last failure · ' + stamp(this.lastFailure.started) : 'Last failure'; }
    get lastFailureText() {
        if (!this.lastFailure) {
            return 'None.';
        }
        return (this.lastFailure.message || 'Failed.') + ' What was removed before it stays removed; the next run carries on.';
    }
    get lastFailureUrl() { return this.lastFailure ? this.lastFailure.pipelineUrl || '' : ''; }
    get lastFailureLink() { return 'Pipeline run ' + runNumber(this.lastFailureUrl) + ' ↗'; }
    get lastFailureCls() { return this.lastFailure ? 'rr-hl-s rr-wrap rr-red' : 'rr-hl-s rr-wrap'; }
    get narrowHealthLine() {
        const fail = this.lastFailure ? ' · last failure ' + shortDate(this.lastFailure.started) : '';
        return fail;
    }
    get lastCallNarrow() { return this.health.lastCall ? when(this.health.lastCall).replace(/^Today/, 'today').replace(/^Yesterday/, 'yesterday') : 'none yet'; }
    get showMissedBox() { return this.missed >= 2; }
    get showMissedLine() { return this.missed === 1; }
    get missedTitle() { return 'Missed the last ' + this.missed + ' nights'; }
    get missedSince() { return this.health.lastCall ? 'since ' + when(this.health.lastCall) : 'yet'; }
    get missedLine() {
        return 'Missed last night: the pipeline\'s scheduled job hasn\'t called ' + this.missedSince + '.';
    }

    // ---------- chart: releases archived per month ----------

    get months() { return (this.hasArchive && this.archive.months) || []; }
    get firstRunDate() { return this.hasArchive ? toDate(this.archive.firstRun) : null; }

    /** Before the first run a month shows "–" (no retention set yet). One month far above the others is cut to keep them readable. */
    get chart() {
        const list = this.months;
        const values = list.map((m) => m.releases || 0);
        const sorted = [...values].sort((a, b) => b - a);
        const top = sorted[0] || 0;
        const second = sorted[1] || 0;
        const cut = top > 0 && second > 0 && top > second * 3;
        const scale = niceTop(cut ? second * 1.2 : top);
        const first = this.firstRunDate;
        const now = new Date();
        const bars = list.map((m, i) => {
            const v = m.releases || 0;
            const before = !first || (m.year * 12 + m.month) < (first.getFullYear() * 12 + first.getMonth() + 1);
            const current = m.year === now.getFullYear() && m.month === now.getMonth() + 1;
            const isCut = cut && v === top;
            const pct = isCut ? 100 : Math.min(100, (v * 100) / scale);
            const dash = before && v === 0;
            const label = m.label || '';
            let cls = 'rr-bar';
            cls += current ? ' rr-bar-now' : '';
            cls += isCut ? ' rr-bar-cut' : '';
            return {
                key: m.year + '-' + m.month,
                value: dash ? '–' : num(v),
                valueCls: isCut ? 'rr-bar-v rr-bar-v-cut' : (dash ? 'rr-bar-v rr-weak' : 'rr-bar-v'),
                barCls: cls,
                barStyle: 'height:' + (v ? Math.max(pct, 1.5) : 0) + '%',
                label,
                letter: label.charAt(0),
                year: i === 0 || m.month === 1 ? String(m.year) : '',
                tip: label + ' ' + m.year + ': ' + (dash ? 'no retention set yet' : count(v, 'release', 'releases') + ' archived' + (current ? ' so far' : ''))
            };
        });
        const grid = [4, 3, 2, 1, 0].map((k) => ({ key: 'g' + k, text: num((scale * k) / 4), style: 'bottom:' + k * 25 + '%' }));
        const cutMonth = cut ? list[values.indexOf(top)] : null;
        const curr = list.find((m) => m.year === now.getFullYear() && m.month === now.getMonth() + 1);
        return {
            bars,
            grid,
            hasCut: !!cutMonth,
            cutLabel: cutMonth ? this.monthName(cutMonth) : '',
            cutShort: cutMonth ? cutMonth.label : '',
            cutValue: cutMonth ? num(top) : '',
            cutFirst: !!cutMonth && !!first && cutMonth.year === first.getFullYear() && cutMonth.month === first.getMonth() + 1,
            hasCurrent: !!curr,
            currentLabel: curr ? this.monthName(curr) : '',
            currentShort: curr ? curr.label : '',
            currentValue: curr ? num(curr.releases || 0) : '',
            hasDash: bars.some((b) => b.value === '–')
        };
    }
    get chartAria() {
        const list = this.months;
        if (!list.length) {
            return 'Releases archived per month';
        }
        const a = list[0];
        const b = list[list.length - 1];
        return 'Releases archived per month, ' + a.label + ' ' + a.year + ' to ' + b.label + ' ' + b.year;
    }
    get hasMonths() { return this.months.length > 0; }
    monthName(m) {
        return new Date(m.year, m.month - 1, 1).toLocaleDateString([], { month: 'long' });
    }
    get cutNote() { return this.chart.cutFirst ? ' (the first run)' : ''; }

    // ---------- how a run works ----------

    get howDays() { return this.hasDays ? this.daysText : 'the Retention days'; }
    get passSizeText() { return num(PASS_SIZE) + ' releases'; }

    // ---------- runs list ----------

    get runs() { return (this.hasArchive && this.archive.runs) || []; }
    get runTotalText() { return num(this.hasArchive ? this.archive.runCount || this.runs.length : 0); }
    get failedCount() { return this.runs.filter((r) => r.status === 'Failed').length; }

    handleSearch(event) {
        this.searchText = event.detail.value || '';
        this.term = searchTerm(this.searchText);
    }

    clearSearch() {
        const box = this.template.querySelector('c-rly-search-box');
        if (box) {
            box.clear();
        }
        this.searchText = '';
        this.term = '';
        this.filter = 'all';
    }

    pickFilter(event) {
        const value = event.currentTarget.dataset.value;
        this.filter = value === this.filter && value !== 'all' ? 'all' : value;
    }

    get filterChips() {
        return [
            { value: 'all', label: 'All', count: num(this.runs.length) },
            { value: 'Failed', label: 'Failed', count: num(this.failedCount) }
        ].map((c) => ({ ...c, cls: c.value === this.filter ? 'rr-chip rr-chip-on' : 'rr-chip', pressed: c.value === this.filter ? 'true' : 'false' }));
    }
    get statusChips() {
        return STATUS_CHIPS.map((s) => ({
            value: s,
            label: s,
            cls: STATUS[s].cls + ' rr-chip-btn' + (this.filter === s ? ' rr-chip-sel' : ''),
            pressed: this.filter === s ? 'true' : 'false',
            title: 'Show only ' + s + ' runs'
        }));
    }

    get filteredRuns() {
        const term = this.term;
        return this.runs.filter((r) => {
            if (this.filter !== 'all' && r.status !== this.filter) {
                return false;
            }
            const by = r.how === NIGHTLY ? 'Git pipeline job' : r.runBy;
            return matchesSearch([stamp(r.started), longDate(r.started), r.how, by, r.runBy, r.message, r.status, r.name], term);
        });
    }

    get shownRuns() {
        const term = this.term;
        return this.filteredRuns.map((r) => {
            const st = STATUS[r.status] || STATUS.Cancelled;
            const by = r.how === NIGHTLY ? 'Git pipeline job' : r.runBy || '';
            const open = this.openRunId === r.id;
            const whenText = stamp(r.started);
            return {
                key: r.id,
                id: r.id,
                whenText,
                whenParts: parts(whenText, term),
                how: r.how,
                howParts: parts(r.how, term),
                by,
                byParts: parts(by, term),
                byCls: r.how === NIGHTLY ? 'rr-weak' : '',
                releases: num(r.releases || 0),
                records: num(r.records || 0),
                freed: size(r.freedKB),
                freedCls: r.freedKB ? 'rr-r' : 'rr-r rr-weak',
                range: rangeText(r.oldest, r.newest),
                rangeCls: r.oldest || r.newest ? '' : 'rr-weak',
                status: r.status,
                statusShort: st.short,
                statusCls: st.cls,
                message: r.message || '',
                messageParts: parts(r.message || '', term),
                hasUrl: !!r.pipelineUrl,
                url: r.pipelineUrl,
                urlText: 'run ' + runNumber(r.pipelineUrl) + ' ↗',
                urlTip: LINK_TIP,
                sep: r.message && r.pipelineUrl ? ' · ' : '',
                open,
                expanded: open ? 'true' : 'false',
                rowLabel: 'Run of ' + whenText + ': show details',
                detailKey: r.id + '-d',
                detail: [
                    count(r.records || 0, 'record', 'records'),
                    size(r.freedKB) === '–' ? 'nothing freed' : size(r.freedKB) + ' freed',
                    rangeText(r.oldest, r.newest),
                    r.how === NIGHTLY ? 'Git pipeline job' : 'by ' + (r.runBy || '')
                ].join(' · ')
            };
        });
    }
    get runsShown() { return this.filteredRuns.length; }
    get runsTotal() { return this.runs.length; }
    get hasRunRows() { return this.runs.length > 0; }
    get runsNoMatch() { return this.hasRunRows && this.runsShown === 0; }
    get noRunsYet() { return !this.hasRunRows; }
    get runsFoot() {
        if (this.narrow) {
            return 'Tap a row for records, freed, dates and message';
        }
        const list = this.runs;
        if (!list.length) {
            return 'Newest first · one row per run.';
        }
        if (list.length >= 500) {
            return 'Newest first · the latest 500 runs';
        }
        const first = list[list.length - 1];
        const who = first.how === NIGHTLY ? 'Nightly' : 'Run now by ' + (first.runBy || 'someone');
        return 'Newest first · every run since retention was first set (' + longDate(first.started) + ': ' + who + ', '
            + count(first.releases || 0, 'release', 'releases') + ', ' + count(first.passes || 0, 'pass', 'passes') + ')';
    }

    toggleRun(event) {
        const id = event.currentTarget.dataset.id;
        this.openRunId = this.openRunId === id ? undefined : id;
    }

    // ---------- navigation ----------

    go(apiName, state) {
        const ref = { type: 'standard__navItemPage', attributes: { apiName } };
        if (state) {
            ref.state = state;
        }
        this[NavigationMixin.Navigate](ref);
    }

    openRetention() { this.go(PIPELINE_TAB, { c__section: 'retention' }); }
    openGuide() { this.go(GUIDE_TAB, { c__section: GUIDE_SECTION }); }

    scrollToRuns() {
        const list = this.template.querySelector('[data-id="runs"]');
        if (list && list.scrollIntoView) {
            list.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    // ---------- Run now: confirm → passes → done ----------

    get modalOpen() { return !!this.modal; }
    get isConfirm() { return this.modal === 'confirm'; }
    get isRunningModal() { return this.modal === 'running'; }
    get isFinished() { return this.modal === 'done' || this.modal === 'stopped' || this.modal === 'failed'; }
    get confirmReleases() { return count(this.eligible, 'finished release', 'finished releases'); }
    get confirmPasses() {
        const n = Math.max(1, Math.ceil(Math.max(this.eligible / PASS_SIZE, this.eligibleRecords / PASS_RECORDS)));
        return count(n, 'pass', 'passes') + ' of up to ' + num(PASS_SIZE) + ' releases';
    }
    get confirmFacts() {
        return 'About ' + num(this.eligibleRecords) + ' records · ≈ ' + mb(this.eligibleRecords * KB_PER_RECORD) + ' MB · '
            + this.confirmPasses + '. Keep this page open while it runs.';
    }
    get confirmCutoff() { return this.cutoffText ? ' (before ' + this.cutoffText + ')?' : '?'; }
    get confirmHint() { return 'e.g. ' + (this.hasDays ? this.days : 730); }
    get typedOk() { return this.hasDays && String(this.typedDays || '').trim() === String(this.days); }
    get runDisabled() { return !this.typedOk || this.isRunning; }

    openRunNow() {
        if (this.runNowDisabled || !this.canRun) {
            return;
        }
        this.typedDays = '';
        this.runMessage = undefined;
        this.modal = 'confirm';
        this.focusModal = true;
    }

    handleTyped(event) {
        this.typedDays = event.target.value;
    }

    handleConfirmKey(event) {
        if (event.key === 'Enter' && this.typedOk) {
            this.startArchive();
        }
    }

    handleModalKey(event) {
        if (event.key === 'Escape' && !this.isRunningModal) {
            event.stopPropagation();
            this.closeModal();
        }
    }

    closeModal() {
        if (this.isRunningModal) {
            return;
        }
        this.modal = undefined;
        this.focusRunNow = true;
        this.reread();
    }

    /** startRun, then one runPass call per pass until the server says done (or Cancel after this pass / leaving the page). */
    async startArchive() {
        if (!this.typedOk) {
            return;
        }
        const days = this.days;
        this.passes = [];
        this.runTotal = this.eligible;
        this.runRemoved = 0;
        this.runRecords = 0;
        this.runRemaining = this.eligible;
        this.runStatus = 'Running';
        this.runMessage = undefined;
        this.cancelAsked = false;
        this.runStartedAt = Date.now();
        this.runEndedAt = undefined;
        this.modal = 'running';
        let run;
        try {
            run = await startRun({ days });
        } catch (e) {
            this.finish('failed', 'Failed', errorText(e));
            return;
        }
        this.runId = run && run.id;
        if (!this.runId) {
            this.finish('failed', 'Failed', 'The run could not start.');
            return;
        }
        this.reread();
        for (let i = 0; i < MAX_PASSES; i++) {
            const n = this.passes.length + 1;
            this.passes = [...this.passes, { key: 'p' + n, label: 'Pass ' + n, text: 'Removing…', busy: true, pill: '', pillCls: '' }];
            let res;
            try {
                // eslint-disable-next-line no-await-in-loop
                res = await runPass({ runId: this.runId, days });
            } catch (e) {
                this.markPass(n, null, 'Failed');
                // eslint-disable-next-line no-await-in-loop
                await this.reread();
                this.finish('failed', 'Failed', errorText(e));
                return;
            }
            this.applyPass(n, res);
            // eslint-disable-next-line no-await-in-loop
            await this.reread();
            if (res.done) {
                const status = res.status || 'Succeeded';
                const state = status === 'Failed' ? 'failed' : (status === 'Cancelled' ? 'stopped' : 'done');
                this.finish(state, status, res.message);
                return;
            }
            if (this.cancelAsked || this.leaving) {
                try {
                    // eslint-disable-next-line no-await-in-loop
                    await cancelRun({ runId: this.runId });
                } catch (e) {
                    this.runMessage = errorText(e);
                }
                // eslint-disable-next-line no-await-in-loop
                await this.reread();
                this.finish('stopped', 'Cancelled', this.runMessage);
                return;
            }
        }
        this.finish('stopped', 'Partial', 'Stopped after ' + MAX_PASSES + ' passes; the next run carries on.');
    }

    applyPass(n, res) {
        this.runRemoved = res.totalReleases || 0;
        this.runRecords = res.totalRecords || 0;
        this.runRemaining = res.remaining || 0;
        this.runTotal = Math.max(this.runTotal, this.runRemoved + this.runRemaining);
        this.markPass(n, res, res.status === 'Failed' ? 'Failed' : 'Done');
        if (res.message) {
            this.runMessage = res.message;
        }
    }

    markPass(n, res, state) {
        this.passes = this.passes.map((p) => {
            if (p.key !== 'p' + n) {
                return p;
            }
            const text = res ? count(res.releases || 0, 'release', 'releases') + ' · ' + count(res.records || 0, 'record', 'records') : 'Nothing removed in this pass';
            return { ...p, text, busy: false, pill: state, pillCls: state === 'Done' ? 'rr-pill rr-pill-ok' : 'rr-pill rr-pill-bad' };
        });
    }

    finish(state, status, message) {
        this.runStatus = status;
        if (message) {
            this.runMessage = message;
        }
        this.runEndedAt = Date.now();
        this.passes = this.passes.filter((p) => !p.busy);
        this.modal = state;
        this.focusModal = true;
    }

    cancelAfterPass() {
        this.cancelAsked = true;
    }

    get cancelLabel() { return this.cancelAsked ? 'Stopping after this pass…' : 'Cancel after this pass'; }
    get passCount() { return this.passes.filter((p) => !p.busy).length; }
    get runLine() {
        const removed = num(this.runRemoved) + ' of ' + num(this.runTotal) + ' removed';
        if (this.modal === 'stopped' || this.modal === 'failed') {
            return 'Stopped after pass ' + this.passCount + ' · ' + removed;
        }
        if (this.isFinished) {
            return removed;
        }
        return (this.passCount ? 'Pass ' + this.passCount : 'Starting') + ' · ' + removed;
    }
    get progressStyle() {
        const pct = this.runTotal ? Math.min(100, Math.round((this.runRemoved * 100) / this.runTotal)) : (this.isFinished ? 100 : 0);
        return 'width:' + pct + '%';
    }
    get progressCls() { return this.modal === 'done' ? 'rr-prog rr-prog-done' : 'rr-prog'; }
    get elapsedText() { return duration((this.runEndedAt || Date.now()) - (this.runStartedAt || Date.now())); }
    get runSubLine() {
        return num(this.runRecords) + ' records removed · ≈ ' + mb(this.runRecords * KB_PER_RECORD) + ' MB freed · ' + this.elapsedText;
    }
    get modalTitle() {
        if (this.isConfirm) {
            return 'Archive now';
        }
        if (this.isRunningModal) {
            return 'Archiving…';
        }
        if (this.modal === 'failed') {
            return 'Archive failed';
        }
        return this.modal === 'stopped' ? 'Archive stopped' : 'Archive done';
    }
    get modalPill() {
        if (this.isRunningModal) {
            return 'Running';
        }
        if (this.modal === 'failed') {
            return 'Failed';
        }
        if (this.modal === 'stopped') {
            return 'Stopped';
        }
        if (this.modal === 'done') {
            return this.runStatus === 'Partial' ? 'Partial' : 'Done';
        }
        return '';
    }
    get modalPillCls() {
        const p = this.modalPill;
        if (p === 'Done') {
            return 'rr-pill rr-pill-ok';
        }
        if (p === 'Failed') {
            return 'rr-pill rr-pill-bad';
        }
        if (p === 'Partial' || p === 'Stopped') {
            return 'rr-pill rr-pill-wait';
        }
        return 'rr-pill rr-pill-info';
    }
    get closeDisabled() { return this.isRunningModal; }
    /** The finished run's row as read again (oldest – newest removed). */
    get doneRun() { return this.runs.find((r) => r.id === this.runId) || null; }
    get doneReleases() { return num(this.runRemoved); }
    get doneRecords() { return num(this.runRecords); }
    get doneFreed() { return '≈ ' + mb(this.runRecords * KB_PER_RECORD) + ' MB'; }
    get donePasses() { return this.passCount + ' · ' + this.elapsedText; }
    get doneRange() { return this.doneRun ? rangeText(this.doneRun.oldest, this.doneRun.newest) : '–'; }
    /** The server's message, for a run that stopped, failed or ended Partial (a clean finish needs none). */
    get showRunMessage() { return this.isFinished && !!this.runMessage && (this.modal !== 'done' || this.runStatus === 'Partial'); }
    get runMessageCls() { return this.modal === 'failed' ? 'rr-msg rr-msg-bad' : 'rr-msg rr-msg-wait'; }
    get finishedNote() {
        if (this.modal === 'failed') {
            return 'What was removed before the failure stays removed; the next run carries on.';
        }
        if (this.runStatus === 'Partial') {
            return 'The rest goes at the next run. Storage in Setup → Storage Usage can take a few hours to show the change.';
        }
        return 'Storage in Setup → Storage Usage can take a few hours to show the change.';
    }
}
