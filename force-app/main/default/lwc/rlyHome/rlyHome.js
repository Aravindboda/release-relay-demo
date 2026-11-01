import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import readHome from '@salesforce/apex/RlyHomeController.read';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import { searchTerm, matchesSearch, highlightParts } from 'c/rlyListSearch';

/** Modes of RlyHubGuard.getHubStatus in which the tab shows only the org gate. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];
/** Under this width (board HubHome D) the page stacks and the tables collapse to two-line rows. */
const NARROW_QUERY = '(max-width: 899px)';

const TAB = {
    releases: 'RLY_My_Releases',
    approvals: 'RLY_Approvals',
    promote: 'RLY_Promote',
    pipeline: 'RLY_Pipeline',
    builder: 'RLY_New_Release'
};

/** RLY_Release_Event__c.Event_Type__c: the activity's words, icon, tone (G green, R red, B blue, A amber, N grey) and chips. */
const EVENT_LOOK = {
    Raised: { label: 'Raised', icon: 'utility:arrowup', tone: 'B' },
    Pull_Request: { label: 'Pull request opened', icon: 'utility:merge', tone: 'N' },
    Scan: { label: 'Scan passed', failLabel: 'Scan failed', icon: 'utility:check', tone: 'G', check: true },
    Validation: { label: 'Validation passed', failLabel: 'Validation failed', icon: 'utility:check', tone: 'G', check: true },
    Approved: { label: 'Approved', icon: 'utility:check', tone: 'B', approval: true },
    Auto_Approved: { label: 'Auto-approved', icon: 'utility:check', tone: 'B', approval: true },
    Rejected: { label: 'Rejected', icon: 'utility:close', tone: 'R', approval: true },
    Deployed: { label: 'Deployed', icon: 'utility:check', tone: 'G', deploy: true },
    Deploy_Failed: { label: 'Deploy failed', icon: 'utility:close', tone: 'R', deploy: true, failure: true },
    Manual_Step: { label: 'Manual step done', icon: 'utility:task', tone: 'A' },
    Flow_Activated: { label: 'Flow activated', failLabel: 'Flow activation failed', icon: 'utility:play', tone: 'G', check: true },
    Merged_Back: { label: 'Merged back', icon: 'utility:merge', tone: 'B' },
    Promoted: { label: 'Promoted', icon: 'utility:forward', tone: 'B' },
    Back_Promoted: { label: 'Back promoted', icon: 'utility:back', tone: 'B' },
    Rolled_Back: { label: 'Rolled back', icon: 'utility:undo', tone: 'N', rollback: true },
    Rollback_Failed: { label: 'Rollback failed', icon: 'utility:undo', tone: 'R', rollback: true, failure: true },
    Comment: { label: 'Comment', icon: 'utility:comments', tone: 'N' }
};
const ACTIVITY_CHIPS = [
    { id: 'all', label: 'All' },
    { id: 'deploys', label: 'Deploys' },
    { id: 'approvals', label: 'Approvals' },
    { id: 'failures', label: 'Failures' },
    { id: 'rollbacks', label: 'Rollbacks' }
];
/** Needs you: what each role's group says when it has nothing (board HubHome B). */
const GROUP_EMPTY = {
    approvals: { title: 'Nothing waiting for your approval.', text: 'Releases you can approve show up here.' },
    steps: { title: 'No manual steps to do.', text: 'Steps for approved and deployed releases show up here.' },
    mine: { title: 'All your releases are moving.', text: 'to raise one.', link: 'New release' }
};
const PILL = { info: 'rr-pill rr-pill-info', wait: 'rr-pill rr-pill-wait', bad: 'rr-pill rr-pill-bad', hot: 'rr-pill rr-pill-bad' };
const DOT = { ok: 'rr-dot rr-dot-ok', wait: 'rr-dot rr-dot-wait', bad: 'rr-dot rr-dot-bad', none: 'rr-dot rr-dot-none' };
const MINUTE = 60000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
/** The chart's drawing area in the SVG viewBox (0 0 420 170). */
const CHART = { left: 30, step: 48, bar: 16, top: 20, bottom: 140 };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function clock(d) {
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function shortDate(d) {
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

/** "Yesterday" when the date is the day before today. */
function isYesterday(d, now) {
    const y = new Date(now.getTime());
    y.setDate(y.getDate() - 1);
    return sameDay(d, y);
}

/** "40 min ago", "3 h ago", "Yesterday 4:52 PM", "Oct 31, 5:20 PM" (board HubHome, Recent activity). */
function agoText(value, now = new Date()) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    const diff = now.getTime() - d.getTime();
    if (sameDay(d, now) && diff < HOUR) {
        return diff < MINUTE ? 'Just now' : Math.floor(diff / MINUTE) + ' min ago';
    }
    if (sameDay(d, now)) {
        return Math.floor(diff / HOUR) + ' h ago';
    }
    return (isYesterday(d, now) ? 'Yesterday' : shortDate(d) + ',') + ' ' + clock(d);
}

/** The narrow layout's "When": "40 min", "3 h", "Yest.", "Oct 31". */
function shortAgo(value, now = new Date()) {
    const full = agoText(value, now);
    if (full.endsWith(' ago')) {
        return full.slice(0, -4);
    }
    if (full.startsWith('Yesterday')) {
        return 'Yest.';
    }
    return full.split(',')[0];
}

/** "40 min", "3 h", "1 day", "3 days" (narrow: "1 d"). */
function sinceText(value, compact, now = new Date()) {
    if (!value) {
        return '';
    }
    const diff = Math.max(0, now.getTime() - new Date(value).getTime());
    if (diff < HOUR) {
        return Math.max(1, Math.floor(diff / MINUTE)) + ' min';
    }
    if (diff < DAY) {
        return Math.floor(diff / HOUR) + ' h';
    }
    const days = Math.floor(diff / DAY);
    return compact ? days + ' d' : plural(days, 'day', 'days');
}

/** "Today 9:12 AM", "Yesterday 4:40 PM", "Oct 30, 6:05 PM" (route cards). */
function dayAndTime(value, now = new Date()) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    if (sameDay(d, now)) {
        return 'Today ' + clock(d);
    }
    return (isYesterday(d, now) ? 'Yesterday' : shortDate(d) + ',') + ' ' + clock(d);
}

/** An event's words, tone and chips: Scan, Validation and Flow_Activated failed when their detail says so. */
function eventView(e) {
    const look = EVENT_LOOK[e.eventType] || EVENT_LOOK.Comment;
    const failed = !!look.check && /fail|error|block/i.test(e.detail || '');
    let tone = failed ? 'R' : look.tone;
    if (e.eventType === 'Merged_Back' && /conflict|to review/i.test(e.detail || '')) {
        tone = 'A';
    }
    return {
        label: failed ? look.failLabel : look.label,
        icon: failed ? 'utility:close' : look.icon,
        tone,
        chips: {
            all: true,
            deploys: !!look.deploy,
            approvals: !!look.approval,
            failures: failed || !!look.failure,
            rollbacks: !!look.rollback
        }
    };
}

/** Greeting part of the day. */
function partOfDay(now) {
    const h = now.getHours();
    if (h < 12) {
        return 'morning';
    }
    return h < 18 ? 'afternoon' : 'evening';
}

/** Gridline step for the chart: 4 steps up to a round top. */
function chartScale(maxValue) {
    const step = Math.max(1, Math.ceil(maxValue / 4));
    return { step, top: step * 4 };
}

/**
 * The Home tab (board HubHome): the Release Relay app's landing page. One Apex call (RlyHomeController.read, saved
 * records only, no callouts) fills the header, the health line, the KPI tiles (each opens the right chip of Releases or
 * Approvals through page state c__filter), Needs you per role, the deploys chart, the route board and Recent activity.
 * The two lists search and filter in the browser (rlySearchBox, c/rlyListSearch) inside fixed-height scrolling cards.
 */
export default class RlyHome extends NavigationMixin(LightningElement) {
    /** RlyHubGuard.getHubStatus: outside the hub this tab shows only rlyOrgGate. */
    hubStatus;
    statusRead = false;
    home;
    loading = false;
    error;
    needsTerm = '';
    needsText = '';
    actTerm = '';
    actText = '';
    actChip = 'all';
    narrow = false;
    media;
    mediaHandler;

    get gated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    get showPage() { return this.statusRead && !this.gated; }
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    get hasHome() { return !!this.home; }

    connectedCallback() {
        this.watchWidth();
        this.readHubStatus();
    }

    disconnectedCallback() {
        if (this.media && this.mediaHandler) {
            this.media.removeEventListener('change', this.mediaHandler);
        }
    }

    /** Narrow layout under 900px: tables collapse to release · text · when. */
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

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.home = await readHome();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
    }

    reload() {
        this.load();
    }

    // ---------- navigation ----------

    go(apiName, state) {
        const ref = { type: 'standard__navItemPage', attributes: { apiName } };
        if (state) {
            ref.state = state;
        }
        this[NavigationMixin.Navigate](ref);
    }

    openRelease(event) {
        const id = event.currentTarget.dataset.id;
        if (id) {
            this.go(TAB.releases, { c__release: id });
        }
    }

    openTile(event) {
        const tile = this.tiles.find((t) => t.key === event.currentTarget.dataset.key);
        if (tile && tile.tab) {
            this.go(tile.tab, tile.state);
        }
    }

    openNewRelease() { this.go(TAB.builder); }
    openPipeline() { this.go(TAB.pipeline); }
    openPromote() { this.go(TAB.promote); }
    openApprovals() { this.go(TAB.approvals); }
    openReleases() { this.go(TAB.releases, { c__filter: 'open' }); }
    openDeployed() { this.go(TAB.releases, { c__filter: 'deployed' }); }

    openStop(event) {
        const kind = event.currentTarget.dataset.kind;
        if (kind === 'stage') {
            this.openPromote();
        } else if (kind === 'hub') {
            this.openApprovals();
        } else {
            this.openReleases();
        }
    }

    // ---------- header ----------

    get kicker() { return 'Release Relay'; }

    get needCounts() {
        const counts = { approvals: 0, steps: 0, mine: 0 };
        const groups = (this.home && this.home.needs && this.home.needs.groups) || [];
        groups.forEach((g) => {
            counts[g.key] = (g.rows || []).length;
        });
        return counts;
    }

    get needTotal() {
        const c = this.needCounts;
        return c.approvals + c.steps + c.mine;
    }

    get greeting() {
        const name = this.home && this.home.firstName ? ', ' + this.home.firstName : '';
        return 'Good ' + partOfDay(new Date()) + name + '.';
    }

    get needsSomething() { return this.needTotal > 0; }

    get greetNeeds() {
        const n = this.needTotal;
        if (!n) {
            return 'Nothing needs you right now.';
        }
        return plural(n, 'thing needs you', 'things need you') + (this.narrow ? '.' : '');
    }

    get greetDetail() {
        if (this.narrow || !this.needTotal) {
            return '';
        }
        const c = this.needCounts;
        const parts = [];
        if (c.approvals) {
            parts.push(plural(c.approvals, 'approval', 'approvals'));
        }
        if (c.steps) {
            parts.push(plural(c.steps, 'manual step', 'manual steps'));
        }
        if (c.mine) {
            parts.push(c.mine + ' of your releases');
        }
        return ': ' + parts.join(', ') + '.';
    }

    // ---------- health ----------

    get health() { return (this.home && this.home.health) || { items: [], allOk: true, attention: 0 }; }
    get healthOk() { return !!this.health.allOk; }
    get healthItems() {
        return (this.health.items || []).map((i) => ({
            ...i,
            dot: DOT[i.tone] || DOT.none,
            cls: i.tone === 'wait' || i.tone === 'bad' ? 'rr-hs-item rr-hs-att' : 'rr-hs-item',
            text: i.label + ': ' + i.text
        }));
    }
    get healthSummary() {
        const n = this.health.attention || 0;
        return n ? plural(n, 'thing needs attention', 'things need attention') : 'All connections OK';
    }
    get healthSummaryDot() { return this.health.attention ? DOT.wait : DOT.ok; }
    get healthSummaryCls() { return this.health.attention ? 'rr-hs-item rr-hs-att' : 'rr-hs-item'; }
    get checkedText() {
        return this.health.checkedOn ? 'Checked ' + dayAndTime(this.health.checkedOn).replace(/^Today /, '') : '';
    }
    get isAdmin() { return !!(this.home && this.home.isAdmin); }

    // ---------- KPI tiles ----------

    get kpis() { return (this.home && this.home.kpis) || {}; }
    get isApprover() {
        const roles = (this.home && this.home.needs && this.home.needs.roles) || [];
        return roles.includes('approver');
    }
    get hubName() {
        const stops = (this.home && this.home.route && this.home.route.stops) || [];
        const hub = stops.find((s) => s.kind === 'hub');
        return hub ? hub.name : '';
    }

    get tiles() {
        const k = this.kpis;
        const open = k.openCount || 0;
        const waitingYou = k.waitingForYou || 0;
        const checks = k.checksFailed || 0;
        const deployed = k.deployedWeek || 0;
        const rollbacks = k.rollbacks || 0;
        const list = [
            {
                key: 'open', label: 'Open releases', value: open, tab: TAB.releases, state: { c__filter: 'open' }, tone: 'plain',
                sub: open ? (k.runningCount || 0) + ' running · ' + plural(k.hotfixCount || 0, 'hotfix', 'hotfixes') : 'Nothing running'
            },
            this.approver ? {
                key: 'waiting', label: 'Waiting for approval', value: waitingYou, unit: 'for you', tab: TAB.approvals,
                tone: waitingYou ? 'warn' : 'plain', sub: (k.waitingCount || 0) + ' in all'
            } : {
                key: 'waiting', label: 'Waiting for approval', value: k.waitingCount || 0, tab: TAB.approvals, tone: 'plain', sub: ''
            },
            {
                key: 'checks', label: 'Checks failed', value: checks, tab: TAB.releases, state: { c__filter: 'checks' },
                tone: checks ? 'alarm' : 'plain', sub: checks ? 'Yours: ' + (k.checksFailedYours || 0) : ''
            },
            {
                key: 'deployed', label: 'Deployed this week', value: deployed, tab: TAB.releases, state: { c__filter: 'deployed' },
                tone: deployed ? 'good' : 'plain', sub: deployed && this.hubName ? (k.deployedToHub || 0) + ' to ' + this.hubName : ''
            },
            {
                key: 'rollbacks', label: 'Rollbacks · 30 days', value: rollbacks, tab: TAB.releases, state: { c__filter: 'rolledback' },
                tone: 'plain', sub: rollbacks && k.lastRollbackName ? 'Last: ' + k.lastRollbackName + ', ' + shortDate(new Date(k.lastRollbackOn)) : ''
            }
        ];
        return list.map((t) => ({
            ...t,
            cls: 'rr-tile rr-tile-btn rr-tile-' + t.tone,
            hasUnit: !!t.unit,
            title: 'Open ' + t.label.toLowerCase()
        }));
    }
    get approver() { return this.isApprover; }

    get leadValue() {
        const d = this.kpis.leadDays;
        return d === null || d === undefined ? '–' : String(d);
    }
    get hasLead() { return this.kpis.leadDays !== null && this.kpis.leadDays !== undefined; }
    get leadSub() {
        return this.hasLead ? 'Average of ' + plural(this.kpis.leadCount || 0, 'release', 'releases') : 'No deploys yet';
    }

    // ---------- Needs you ----------

    get needsRoles() {
        const roles = (this.home && this.home.needs && this.home.needs.roles) || [];
        return roles.length ? 'Your roles: ' + roles.join(' · ') : '';
    }
    get needsTotal() { return this.needTotal; }
    get needsSearching() { return !!this.needsTerm; }

    get needGroups() {
        const term = this.needsTerm;
        const groups = (this.home && this.home.needs && this.home.needs.groups) || [];
        const compact = this.narrow;
        const out = [];
        groups.forEach((g) => {
            const all = g.rows || [];
            const hits = all.filter((r) => matchesSearch([r.releaseName, r.title, r.org, r.raisedBy], term));
            if (term && !hits.length) {
                return;
            }
            const empty = GROUP_EMPTY[g.key] || GROUP_EMPTY.approvals;
            out.push({
                key: g.key,
                label: g.label,
                count: term ? hits.length + ' of ' + all.length : String(all.length),
                isEmpty: !all.length,
                emptyTitle: empty.title,
                emptyText: empty.text,
                emptyLink: empty.link,
                rows: hits.map((r) => ({
                    ...r,
                    pillCls: PILL[r.tone] || PILL.info,
                    nameParts: highlightParts(r.releaseName, term),
                    titleParts: highlightParts(r.title, term),
                    orgParts: highlightParts(r.org, term),
                    byParts: highlightParts(r.raisedBy, term),
                    fullTitle: r.note ? r.title + ' · ' + r.note : r.title,
                    sinceText: sinceText(r.since, compact),
                    openLabel: 'Open ' + r.releaseName
                }))
            });
        });
        return out;
    }
    get needsShown() {
        return this.needGroups.reduce((n, g) => n + g.rows.length, 0);
    }
    get needsNoMatch() { return this.needsSearching && this.needGroups.length === 0; }
    get needsNoMatchText() { return 'No releases or steps match ‘' + this.needsText + '’.'; }
    handleNeedsSearch(event) {
        this.needsText = event.detail.value || '';
        this.needsTerm = searchTerm(this.needsText);
    }
    clearNeedsSearch() {
        const box = this.template.querySelector('c-rly-search-box[data-list="needs"]');
        if (box) {
            box.clear();
        }
    }

    // ---------- deploys chart ----------

    get weeks() { return (this.home && this.home.weeks) || []; }
    get chartTotals() {
        return this.weeks.reduce((t, w) => ({ deployed: t.deployed + (w.deployed || 0), failed: t.failed + (w.failed || 0) }),
            { deployed: 0, failed: 0 });
    }
    get hasDeploys() {
        const t = this.chartTotals;
        return t.deployed + t.failed > 0;
    }
    get chartDeployed() { return this.chartTotals.deployed; }
    get chartFailed() { return this.chartTotals.failed; }
    get chartSuccess() {
        const t = this.chartTotals;
        return t.deployed + t.failed ? Math.round((100 * t.deployed) / (t.deployed + t.failed)) + '%' : '–';
    }
    get chart() {
        const weeks = this.weeks;
        const max = weeks.reduce((m, w) => Math.max(m, w.deployed || 0, w.failed || 0), 0);
        const scale = chartScale(max);
        const height = CHART.bottom - CHART.top;
        const y = (v) => CHART.bottom - (v / scale.top) * height;
        const grid = [0, 1, 2, 3, 4].map((i) => ({
            key: 'g' + i, y: y(scale.step * i), labelY: y(scale.step * i) + 3, text: String(scale.step * i), base: i === 0
        }));
        let peak = -1;
        weeks.forEach((w, i) => {
            if ((w.deployed || 0) === max && max > 0) {
                peak = i;
            }
        });
        const bars = weeks.map((w, i) => {
            const x = CHART.left + i * CHART.step;
            const d = w.deployed || 0;
            const f = w.failed || 0;
            const start = new Date(w.weekStart + 'T00:00:00');
            const last = i === weeks.length - 1;
            const label = last ? 'This wk' : shortDate(start);
            return {
                key: 'w' + i,
                dx: x + 7, dy: y(d), dh: Math.max(0, CHART.bottom - y(d)),
                fx: x + 25, fy: y(f), fh: Math.max(0, CHART.bottom - y(f)),
                lx: x + 24, label, labelCls: last ? 'rr-chart-now' : 'rr-chart-wk',
                showPeak: i === peak, px: x + 15, py: y(d) - 4, peak: String(d),
                tip: (last ? 'This week' : 'Week of ' + shortDate(start)) + ': ' + d + ' deployed, ' + f + ' failed'
            };
        });
        return { grid, bars };
    }
    get weekByOrg() { return (this.home && this.home.weekByOrg) || []; }
    get hasWeekByOrg() { return this.weekByOrg.length > 0; }

    // ---------- route ----------

    get route() { return (this.home && this.home.route) || { stops: [] }; }
    get routeSet() { return !!this.route.isSet; }
    get showRoute() { return this.routeSet || this.isAdmin; }
    get routeSub() { return this.route.path ? this.route.path + ' · from the Pipeline route' : ''; }
    get stops() {
        const stops = this.route.stops || [];
        return stops.map((s, i) => {
            const isDev = s.kind === 'developer';
            const isStage = s.kind === 'stage';
            let countText = 'waiting for approval into ' + s.name;
            if (isDev) {
                countText = (s.count === 1 ? 'open release' : 'open releases') + ' raised from ' + (s.name.includes(' ') ? 'developer orgs' : s.name);
            } else if (isStage) {
                countText = 'ready to promote' + (s.nextName ? ' to ' + s.nextName : '') + (s.hotfixCount ? ' · ' + plural(s.hotfixCount, 'hotfix', 'hotfixes') : '');
            }
            const when = dayAndTime(s.lastOn);
            let meta = when;
            if (s.lastBy) {
                meta = when + ' · ' + (isDev ? '' : 'deployed by ') + s.lastBy;
            }
            return {
                ...s,
                cls: s.kind === 'hub' ? 'rr-stop rr-stop-hub' : 'rr-stop',
                dot: DOT[s.statusTone] || DOT.none,
                lastLabel: isDev ? 'Last raised from here' : 'Last deploy',
                hasLast: !!s.lastId,
                noLast: isDev ? 'Nothing raised yet' : 'Nothing deployed yet',
                lastText: s.lastName + (s.lastTitle ? ' · ' + s.lastTitle : ''),
                meta,
                countText,
                action: isDev ? 'Releases' : (isStage ? 'Promote' : 'Approvals'),
                actionVariant: isStage ? 'brand' : 'neutral',
                showArrow: i < stops.length - 1
            };
        });
    }

    // ---------- Recent activity ----------

    get activityAll() {
        return ((this.home && this.home.activity) || []).map((e) => {
            const v = eventView(e);
            return {
                ...e,
                view: v,
                who: e.actorName || e.via || '',
                eventText: v.label + (e.detail ? ' · ' + e.detail : '')
            };
        });
    }
    get hasActivity() { return this.activityAll.length > 0; }
    get chips() {
        const all = this.activityAll;
        return ACTIVITY_CHIPS.map((c) => {
            const on = c.id === this.actChip;
            return {
                ...c,
                count: all.filter((e) => e.view.chips[c.id]).length,
                cls: on ? 'rr-chip rr-chip-on' : 'rr-chip',
                pressed: on ? 'true' : 'false'
            };
        });
    }
    get chipRows() { return this.activityAll.filter((e) => e.view.chips[this.actChip]); }
    get actTotal() { return this.chipRows.length; }
    get activityRows() {
        const term = this.actTerm;
        const now = new Date();
        return this.chipRows
            .filter((e) => matchesSearch([e.releaseName, e.eventText, e.orgName, e.who], term))
            .map((e) => ({
                key: e.id,
                releaseId: e.releaseId,
                icon: e.view.icon,
                iconCls: 'rr-ic rr-ic-' + e.view.tone,
                iconAlt: e.view.label,
                nameParts: highlightParts(e.releaseName, term),
                labelParts: highlightParts(e.view.label, term),
                detailParts: highlightParts(e.detail ? ' · ' + e.detail : '', term),
                narrowDetailParts: highlightParts([e.detail, e.orgName].filter((x) => x).join(' · '), term),
                eventText: e.eventText,
                orgParts: highlightParts(e.orgName, term),
                orgName: e.orgName || '',
                whoParts: highlightParts(e.who, term),
                who: e.who,
                when: agoText(e.occurredOn, now),
                whenShort: shortAgo(e.occurredOn, now),
                openLabel: 'Open ' + e.releaseName
            }));
    }
    get actShown() { return this.activityRows.length; }
    get actNoMatch() { return this.actShown === 0 && this.hasActivity; }
    get actNoMatchText() {
        if (!this.actTerm) {
            return 'No events in this chip.';
        }
        const chip = ACTIVITY_CHIPS.find((c) => c.id === this.actChip);
        return 'No events match ‘' + this.actText + '’. Search looks at release, event, org and who' +
            (this.actChip === 'all' ? '.' : ' in ' + chip.label + '.');
    }
    get actSearching() { return !!this.actTerm; }
    handleActSearch(event) {
        this.actText = event.detail.value || '';
        this.actTerm = searchTerm(this.actText);
    }
    pickChip(event) {
        this.actChip = event.currentTarget.dataset.id;
    }
    clearActSearch() {
        const box = this.template.querySelector('c-rly-search-box[data-list="activity"]');
        if (box) {
            box.clear();
        }
    }
}
