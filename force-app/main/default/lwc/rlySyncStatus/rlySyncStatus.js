import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import readBoard from '@salesforce/apex/RlySyncController.board';
import startOrgCheck from '@salesforce/apex/RlySyncController.startOrgCheck';
import runDeveloperCheck from '@salesforce/apex/RlySyncController.runDeveloperCheck';
import startRouteCheck from '@salesforce/apex/RlySyncController.startRouteCheck';
import readCheck from '@salesforce/apex/RlySyncController.readCheck';
import syncFile from '@salesforce/apex/RlySyncController.syncFile';
import readPackages from '@salesforce/apex/RlySyncController.readPackages';
import packageUsage from '@salesforce/apex/RlySyncController.packageUsage';
import backPromotePicked from '@salesforce/apex/RlySyncController.backPromotePicked';
import backPromoteAll from '@salesforce/apex/RlySyncController.backPromoteAll';
import pushToOrg from '@salesforce/apex/RlySyncController.pushToOrg';
import describeTypes from '@salesforce/apex/RlyChangesController.describeTypes';
import listChanges from '@salesforce/apex/RlyChangesController.listChanges';
import stagePipelinePart from '@salesforce/apex/RlyCompareController.stagePipelinePart';
import { searchTerm, matchesSearch, highlightParts } from 'c/rlyListSearch';
import { statusChip, pairKey, packageStatus, versionList, compareVersions } from './syncHelpers';
import { PartSending, listTypeChunks, partsOf } from 'c/rlyPartSending';
import { errorText, isGated, oneAfterAnother, fitPageToWindow } from 'c/rlyShared';

const PAGE_MIN_HEIGHT = 520;
const PAGE_BOTTOM_GAP = 24;
const NEW_RELEASE_TAB = 'RLY_New_Release';
const RELEASES_TAB = 'RLY_My_Releases';
/** Parts sending at once (a developer org's check). */
const VIEWS = [
    { value: 'org', label: 'Org vs branch' },
    { value: 'route', label: 'Down the route' },
    { value: 'packages', label: 'Installed packages' },
    { value: 'data', label: 'Data' }
];
const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'onlyInOrg', label: 'Only in org' },
    { value: 'onlyOnBranch', label: 'Only on branch' },
    { value: 'different', label: 'Different' }
];

/** The name split for highlighting the search text. */
function marked(text, q) {
    return highlightParts(text, q).map((p) => ({ ...p, cls: p.hit ? 'rr-hit' : '' }));
}

/**
 * Sync status (design board 2026-11-07): Org vs branch (each route org against its own branch), Down the route (each
 * branch against the one below it, with back promote of picked components) and Installed packages. Checks run in the
 * pipeline; the page reads them again on a CSS-animation countdown (no timers). A developer org is listed and sent in
 * parts from the page first (no async Apex).
 */
export default class RlySyncStatus extends NavigationMixin(PartSending(LightningElement)) {
    appName = APP_NAME;
    hubStatus;
    statusRead = false;
    board;
    loading = false;
    error;
    notice;
    view = 'org';
    selectedOrgId;
    /** syncId => RlySyncResult.View (with components / pairs once read). */
    checks = {};
    filter = 'all';
    typeFilter = 'all';
    term = '';
    picks = new Set();
    openKey;
    openPath;
    files = {};
    fileLoading = false;
    fileError;
    busy = false;
    pairIndex = 0;
    routePicks = new Set();
    usage;
    usageNs;
    usagePicks = new Set();
    usageLoading = false;
    /** Running checks and parts waiting: one countdown each. */
    waits = {};
    /** A developer org's check being sent: { syncId, orgId, types, parts, done, failed, message }. */
    sending;
    pageHeight;

    connectedCallback() {
        this.resizeHandler = () => this.fitToWindow();
        window.addEventListener('resize', this.resizeHandler);
        getHubStatus()
            .then((s) => { this.hubStatus = s; })
            .catch(() => { this.hubStatus = undefined; })
            .finally(() => {
                this.statusRead = true;
                if (this.showPage) {
                    this.load();
                }
            });
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.resizeHandler);
        this.waits = {};
    }

    renderedCallback() {
        this.fitToWindow();
    }

    /** The page fills the window from its top edge down, whatever the screen. */
    fitToWindow() {
        this.pageHeight = fitPageToWindow(this.template.querySelector('.rr-page'), this.pageHeight, PAGE_MIN_HEIGHT, PAGE_BOTTOM_GAP);
    }

    get gated() { return isGated(this.hubStatus); }
    get showPage() { return this.statusRead && !this.gated; }

    load() {
        this.loading = true;
        return readBoard()
            .then((b) => {
                this.board = b;
                const checks = { ...this.checks };
                (b.orgs || []).forEach((o) => {
                    if (o.check && !checks[o.check.syncId]) {
                        checks[o.check.syncId] = o.check;
                    }
                    if (o.check && o.check.status === 'Running' && o.check.started) {
                        this.wait(o.check.syncId, 'check');
                    }
                });
                if (b.route) {
                    checks[b.route.syncId] = checks[b.route.syncId] || b.route;
                    if (b.route.status === 'Running') {
                        this.wait(b.route.syncId, 'check');
                    }
                }
                this.checks = checks;
                if (!this.selectedOrgId && b.orgs && b.orgs.length) {
                    this.selectOrg(b.orgs[0].orgId);
                }
            })
            .catch((e) => { this.error = errorText(e); })
            .finally(() => { this.loading = false; });
    }

    // ---------- views ----------

    get viewButtons() {
        return VIEWS.map((v) => ({ ...v, cls: 'rr-seg' + (v.value === this.view ? ' rr-seg-on' : ''), pressed: v.value === this.view ? 'true' : 'false' }));
    }
    get isOrgView() { return this.view === 'org'; }
    get isRouteView() { return this.view === 'route'; }
    get isPackagesView() { return this.view === 'packages'; }
    get isDataView() { return this.view === 'data'; }
    handleView(event) {
        this.view = event.currentTarget.dataset.value;
        this.openKey = undefined;
        if (this.view === 'route') {
            this.readRoute();
        }
    }
    get canPromote() { return !!this.board && this.board.canPromote; }

    // ---------- org vs branch ----------

    get orgCards() {
        return ((this.board && this.board.orgs) || []).map((o) => {
            const c = o.check ? this.checks[o.check.syncId] || o.check : null;
            const counts = (c && c.counts) || {};
            const total = (counts.onlyInOrg || 0) + (counts.onlyOnBranch || 0) + (counts.different || 0);
            let tag = { label: 'Not checked', cls: 'rr-pill rr-pill-none' };
            let big = '–';
            let bigCls = 'rr-big';
            if (this.sending && this.sending.orgId === o.orgId) {
                tag = { label: this.sendingText, cls: 'rr-pill rr-pill-run' };
                big = '…';
                bigCls += ' rr-big-run';
            } else if (c && c.status === 'Running' && !c.started) {
                tag = { label: 'Not finished', cls: 'rr-pill rr-pill-none' };
            } else if (c && c.status === 'Running') {
                tag = { label: 'Checking…', cls: 'rr-pill rr-pill-run' };
                big = '…';
                bigCls += ' rr-big-run';
            } else if (c && c.status === 'Failed') {
                tag = { label: 'Check failed', cls: 'rr-pill rr-pill-bad' };
            } else if (c && c.status === 'Succeeded') {
                tag = total === 0 ? { label: 'In sync', cls: 'rr-pill rr-pill-ok' } : { label: 'Out of sync', cls: 'rr-pill rr-pill-warn' };
                big = String(total);
                bigCls += total === 0 ? ' rr-big-ok' : ' rr-big-warn';
            }
            const detail = c && c.status === 'Succeeded' && total
                ? counts.onlyInOrg + ' only in org · ' + counts.onlyOnBranch + ' only on branch · ' + counts.different + ' different' : '';
            return {
                orgId: o.orgId, name: o.name, branch: o.branch, tagLabel: tag.label, tagCls: tag.cls, big, bigCls, detail,
                checked: c && c.checkedAt ? 'checked ' + new Date(c.checkedAt).toLocaleString() : 'never checked',
                runUrl: c ? c.runUrl : null, message: c && c.status === 'Failed' ? c.message : '',
                how: o.signIn ? 'read by the pipeline' : 'read by the hub, in parts',
                cls: 'rr-org' + (o.orgId === this.selectedOrgId ? ' rr-org-on' : ''),
                current: o.orgId === this.selectedOrgId ? 'true' : 'false',
                cantCheck: this.busy || !!this.sending || (!!c && c.status === 'Running' && c.started)
            };
        });
    }

    get selectedOrg() { return ((this.board && this.board.orgs) || []).find((o) => o.orgId === this.selectedOrgId); }
    get selectedCheck() {
        const o = this.selectedOrg;
        return o && o.check ? this.checks[o.check.syncId] || o.check : null;
    }
    get selectedName() { return this.selectedOrg ? this.selectedOrg.name : ''; }

    pickOrg(event) {
        this.selectOrg(event.currentTarget.dataset.id);
    }

    selectOrg(orgId) {
        this.selectedOrgId = orgId;
        this.picks = new Set();
        this.openKey = undefined;
        this.typeFilter = 'all';
        const c = this.selectedCheck;
        if (c && c.status === 'Succeeded' && !c.done) {
            this.refreshCheck(c.syncId);
        }
    }

    /** Check now on a card. */
    checkOrg(event) {
        event.stopPropagation();
        this.startOrg(event.currentTarget.dataset.id);
    }

    async startOrg(orgId) {
        this.error = undefined;
        this.busy = true;
        try {
            const s = await startOrgCheck({ orgId });
            await this.load();
            if (s.mode === 'parts') {
                await this.sendDeveloper(s.syncId, orgId);
            } else {
                this.wait(s.syncId, 'check');
            }
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    // A developer org: list every component (all time), send them in parts, then start the compare.
    async sendDeveloper(syncId, orgId) {
        this.sending = { syncId, orgId, phase: 'listing', listed: 0, parts: [], sent: 0 };
        try {
            const t = await describeTypes({ orgId });
            const types = t.types || [];
            const keys = [];
            const chunks = listTypeChunks(types);
            await oneAfterAnother(async (i) => {
                if (i >= chunks.length) {
                    return { done: true, state: i };
                }
                const found = await listChanges({ orgId, types: chunks[i], sinceIso: null });
                (found || []).filter((c) => !c.deleted).forEach((c) => keys.push(c.key));
                this.sending = { ...this.sending, listed: keys.length };
                return { done: false, state: i + 1 };
            }, 0);
            if (!keys.length) {
                throw new Error('Nothing was listed in the org.');
            }
            const parts = partsOf(keys).map((k, i) => ({ id: syncId + '-' + (i + 1), n: i + 1, keys: k, phase: 'waiting', retrieveId: null, cycle: 0 }));
            this.sending = { ...this.sending, phase: 'sending', parts, types };
            this.pumpParts();
        } catch (e) {
            this.sending = undefined;
            this.error = 'Checking the org failed: ' + errorText(e);
        }
    }

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

    async finishDeveloper() {
        const s = this.sending;
        this.sending = { ...s, phase: 'starting' };
        try {
            await runDeveloperCheck({ syncId: s.syncId, parts: s.parts.length, types: s.types });
            this.sending = undefined;
            await this.load();
            this.wait(s.syncId, 'check');
        } catch (e) {
            this.failSending(e);
        }
    }

    // The first error of a send is kept: once it failed, the parts still in flight end quietly (build 52).
    failSending(e, id) {
        if (!this.sending || (id && !this.isLive(id))) {
            return;
        }
        this.error = 'Sending the org\'s components failed: ' + errorText(e) + ' Check again to retry.';
        this.sending = undefined;
    }

    /** The grey line while the hub sends a developer org's parts: the check is driven by this page. */
    get sendingHint() {
        return this.sending ? 'Keep this page open while the parts are sent.' : '';
    }

    /** Reads a check again (its result once it's there). */
    async refreshCheck(syncId) {
        try {
            const read = await readCheck({ syncId });
            const v = { ...read, listAsked: true };
            this.checks = { ...this.checks, [syncId]: v };
            if (v.status === 'Running') {
                this.wait(syncId, 'check');
            } else if (this.board) {
                this.board = { ...this.board, orgs: this.board.orgs.map((o) => (o.check && o.check.syncId === syncId ? { ...o, check: v } : o)),
                    route: this.board.route && this.board.route.syncId === syncId ? v : this.board.route };
            }
        } catch (e) {
            this.error = errorText(e);
            if (this.checks[syncId]) {
                this.checks = { ...this.checks, [syncId]: { ...this.checks[syncId], listAsked: true } };
            }
        }
    }

    // ---------- the part loop's hooks (c/rlyPartSending) ----------

    stageOnePart(part) {
        return stagePipelinePart({ partJson: JSON.stringify(part) });
    }

    onWaitDone(id) {
        this.refreshCheck(id);
    }

    // ---------- the selected org's differences ----------

    get orgComponents() {
        const c = this.selectedCheck;
        return (c && c.components) || [];
    }
    // The board's checks are saved views (counts, no list: done is false); the list is read when the org is picked. The
    // panel follows the card: "In sync" only for a read result with nothing in it (build 52).
    get hasOrgResult() { return !!this.selectedCheck && this.selectedCheck.status === 'Succeeded' && this.selectedCheck.done === true; }
    get selectedTotal() {
        const counts = (this.selectedCheck && this.selectedCheck.counts) || {};
        return (counts.onlyInOrg || 0) + (counts.onlyOnBranch || 0) + (counts.different || 0);
    }
    get orgResultEmpty() { return this.hasOrgResult && this.orgComponents.length === 0 && this.selectedTotal === 0; }
    get orgUnread() { return !!this.selectedCheck && this.selectedCheck.status === 'Succeeded' && this.selectedCheck.done !== true; }
    get orgUnreadText() {
        const c = this.selectedCheck;
        const counts = (c && c.counts) || {};
        const total = this.selectedTotal;
        const summary = total === 0 ? 'In sync' : 'Out of sync · ' + (counts.onlyInOrg || 0) + ' only in org · ' + (counts.onlyOnBranch || 0)
            + ' only on branch · ' + (counts.different || 0) + ' different';
        return summary + (c && c.listAsked ? '. The list isn\'t on the results branch any more: Check now to read it again.' : '. Reading the list…');
    }
    get orgWaiting() {
        const c = this.selectedCheck;
        return (!!c && c.status === 'Running' && c.started) || (!!this.sending && this.sending.orgId === this.selectedOrgId);
    }
    get orgNever() { return (!this.selectedCheck || (this.selectedCheck.status === 'Running' && !this.selectedCheck.started)) && !this.orgWaiting; }
    get orgFailed() { return !!this.selectedCheck && this.selectedCheck.status === 'Failed'; }
    get orgFailMessage() { return this.orgFailed ? this.selectedCheck.message : ''; }
    get truncatedNote() { return this.selectedCheck && this.selectedCheck.truncated ? 'The pipeline lists the first 5,000 differences.' : ''; }

    get typeRows() {
        const counts = {};
        this.orgComponents.forEach((c) => { counts[c.type] = (counts[c.type] || 0) + 1; });
        const rows = [{ value: 'all', label: 'All types', count: this.orgComponents.length }];
        Object.keys(counts).sort().forEach((t) => rows.push({ value: t, label: t, count: counts[t] }));
        return rows.map((r) => ({ ...r, cls: 'rr-ty' + (r.value === this.typeFilter ? ' rr-ty-on' : ''), pressed: r.value === this.typeFilter ? 'true' : 'false' }));
    }
    pickType(event) { this.typeFilter = event.currentTarget.dataset.value; }

    get filterButtons() {
        const counts = (this.selectedCheck && this.selectedCheck.counts) || {};
        return FILTERS.map((f) => ({ ...f, label: f.value === 'all' ? f.label : f.label + ' ' + (counts[f.value] || 0),
            cls: 'rr-seg' + (f.value === this.filter ? ' rr-seg-on' : ''), pressed: f.value === this.filter ? 'true' : 'false' }));
    }
    handleFilter(event) { this.filter = event.currentTarget.dataset.value; }
    handleSearch(event) { this.term = searchTerm(event.detail && event.detail.value); }

    get orgRows() {
        const q = this.term;
        return this.orgComponents
            .filter((c) => (this.filter === 'all' || c.status === this.filter) && (this.typeFilter === 'all' || c.type === this.typeFilter))
            .filter((c) => matchesSearch([c.name, c.type, c.lastChangedBy], q))
            .slice(0, 1000)
            .map((c) => {
                const chip = statusChip(c.status, this.selectedName, '');
                const on = this.picks.has(c.key);
                return { key: c.key, name: c.name, type: c.type, nameParts: marked(c.name, q), chipLabel: chip.label, chipCls: chip.cls,
                    changed: c.lastChangedBy ? c.lastChangedBy + (c.lastChangedAt ? ' · ' + new Date(c.lastChangedAt).toLocaleDateString() : '') : (c.status === 'onlyOnBranch' ? 'in Git, not in ' + this.selectedName : ''),
                    pickCls: 'rr-chip' + (on ? ' rr-chip-on' : ''), pickLabel: on ? '✓' : 'Pick', pressed: on ? 'true' : 'false',
                    rowCls: 'rr-row' + (c.key === this.openKey ? ' rr-row-open' : '') };
            });
    }
    get orgShownCount() { return this.orgRows.length; }
    get orgTotal() { return this.orgComponents.length; }
    get noOrgMatch() { return this.hasOrgResult && this.orgComponents.length > 0 && this.orgRows.length === 0; }

    togglePick(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.picks);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.picks = next;
    }
    get pickCount() { return this.picks.size; }
    get noPicks() { return this.picks.size === 0 || this.busy; }
    get pickText() { return this.picks.size + ' picked'; }
    get cantPush() { return this.noPicks || !this.canPromote || !(this.selectedOrg && this.selectedOrg.signIn); }
    get pushHint() {
        if (!this.canPromote) {
            return 'Push to the org needs Release Relay Admin.';
        }
        return this.selectedOrg && !this.selectedOrg.signIn ? 'The pipeline can\'t deploy to a developer org.' : '';
    }

    /** Bring into the branch: New Release from the org with the picks selected (only-on-branch picks as deletions). */
    bringIntoBranch() {
        const picked = this.orgComponents.filter((c) => this.picks.has(c.key));
        this.openNewRelease({
            orgId: this.selectedOrgId,
            keys: picked.filter((c) => c.status !== 'onlyOnBranch').map((c) => c.key),
            deleted: picked.filter((c) => c.status === 'onlyOnBranch').map((c) => c.key)
        });
    }

    async pushPicked() {
        const picked = this.orgComponents.filter((c) => this.picks.has(c.key));
        await this.queueRelease(pushToOrg, { higherOrgId: this.selectedOrgId, keys: picked.map((c) => c.key), paths: this.pathsOf(picked) });
    }

    pathsOf(components) {
        const out = [];
        components.forEach((c) => (c.files || []).forEach((f) => { if (f.path && !out.includes(f.path)) { out.push(f.path); } }));
        return out;
    }

    // ---------- open a component (side-by-side) ----------

    openComponent(event) {
        const key = event.currentTarget.dataset.key;
        this.openKey = this.openKey === key ? undefined : key;
        const c = this.openComponentRow;
        this.openPath = c && c.files.length ? c.files[0].path : undefined;
        this.loadOpenFile();
    }
    closeComponent() { this.openKey = undefined; }

    get openComponentRow() {
        const list = this.isRouteView ? this.pairComponents : this.orgComponents;
        return list.find((c) => c.key === this.openKey);
    }
    get hasOpen() { return !!this.openComponentRow; }
    get openTitle() { return this.openComponentRow ? this.openComponentRow.name + ' · ' + this.openComponentRow.type : ''; }
    get openFiles() {
        const c = this.openComponentRow;
        return (c ? c.files : []).map((f) => ({ path: f.path, label: f.path.substring(f.path.lastIndexOf('/') + 1),
            cls: 'rr-fp' + (f.path === this.openPath ? ' rr-fp-on' : ''), pressed: f.path === this.openPath ? 'true' : 'false' }));
    }
    get hasFilePicker() { return this.openFiles.length > 1; }
    pickFile(event) {
        this.openPath = event.currentTarget.dataset.path;
        this.loadOpenFile();
    }
    get openFileRow() {
        const c = this.openComponentRow;
        return c ? c.files.find((f) => f.path === this.openPath) : undefined;
    }
    get openSyncId() {
        if (this.isRouteView) {
            return this.board && this.board.route ? this.board.route.syncId : null;
        }
        return this.selectedCheck ? this.selectedCheck.syncId : null;
    }
    async loadOpenFile() {
        const f = this.openFileRow;
        this.fileError = undefined;
        if (!f || !f.n) {
            return;
        }
        const key = this.openSyncId + '/' + f.n;
        if (this.files[key]) {
            return;
        }
        this.fileLoading = true;
        try {
            const d = await syncFile({ syncId: this.openSyncId, n: f.n });
            this.files = { ...this.files, [key]: d };
        } catch (e) {
            this.fileError = errorText(e);
        } finally {
            this.fileLoading = false;
        }
    }
    get openFile() {
        const f = this.openFileRow;
        return f && f.n ? this.files[this.openSyncId + '/' + f.n] : undefined;
    }
    get openReason() {
        const f = this.openFileRow;
        return f && !f.n ? (f.reason || 'Nothing to show for this file.') : '';
    }
    get showDiff() { return !!this.openFile && !this.openFile.patch; }
    get showPatch() { return !!this.openFile && !!this.openFile.patch; }
    get patchLines() {
        return this.showPatch ? this.openFile.patch.split('\n').slice(0, 20000).map((t, i) => ({ key: 'l' + i, text: t || ' ',
            cls: 'rr-pl' + (t.startsWith('+') && !t.startsWith('+++') ? ' rr-pl-add' : '') + (t.startsWith('-') && !t.startsWith('---') ? ' rr-pl-del' : '') + (t.startsWith('@@') ? ' rr-pl-hunk' : '') })) : [];
    }
    get leftText() { return (this.openFile && this.openFile.left) || ''; }
    get rightText() { return (this.openFile && this.openFile.right) || ''; }
    get leftLabel() {
        if (this.isRouteView) {
            return this.currentPair ? this.currentPair.higherBranch + ' branch' : '';
        }
        return this.selectedOrg ? this.selectedOrg.branch + ' branch' : '';
    }
    get rightLabel() {
        if (this.isRouteView) {
            return this.currentPair ? this.currentPair.lowerBranch + ' branch' : '';
        }
        return this.selectedName + ' org now';
    }
    get diffTitle() { return this.openPath || ''; }

    // ---------- down the route ----------

    get routeCheck() {
        const r = this.board && this.board.route;
        return r ? this.checks[r.syncId] || r : null;
    }
    readRoute() {
        const r = this.routeCheck;
        if (r && r.status === 'Succeeded' && !r.pairs) {
            this.refreshCheck(r.syncId);
        }
    }
    async checkRoute() {
        this.error = undefined;
        this.busy = true;
        try {
            const s = await startRouteCheck();
            await this.load();
            this.wait(s.syncId, 'check');
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }
    get routeRunning() { return !!this.routeCheck && this.routeCheck.status === 'Running'; }
    get routeFailed() { return !!this.routeCheck && this.routeCheck.status === 'Failed'; }
    get routeMessage() { return this.routeFailed ? this.routeCheck.message : ''; }
    get routeChecked() { return this.routeCheck && this.routeCheck.checkedAt ? 'Checked ' + new Date(this.routeCheck.checkedAt).toLocaleString() : 'Not checked yet'; }
    get routeRunUrl() { return this.routeCheck ? this.routeCheck.runUrl : null; }
    get cantCheckRoute() { return this.busy || this.routeRunning; }

    get resultPairs() { return (this.routeCheck && this.routeCheck.pairs) || []; }
    get lanePairs() {
        return ((this.board && this.board.pairs) || []).map((p, i) => {
            const r = this.resultPairs.find((x) => pairKey(x.higher, x.lower) === pairKey(p.higherBranch, p.lowerBranch));
            const count = r ? r.count : null;
            const on = i === this.pairIndex;
            let label = 'not checked';
            if (count === 0) {
                label = 'in step';
            } else if (count) {
                label = count + ' not in ' + p.lowerName;
            }
            return { ...p, index: i, key: p.higherId + '>' + p.lowerId, label,
                cls: 'rr-count' + (count === 0 ? ' rr-count-ok' : '') + (count ? ' rr-count-warn' : '') + (on ? ' rr-count-on' : ''),
                pressed: on ? 'true' : 'false' };
        });
    }
    pickPair(event) {
        this.pairIndex = Number(event.currentTarget.dataset.index);
        this.routePicks = new Set();
        this.openKey = undefined;
    }
    get currentPair() { return ((this.board && this.board.pairs) || [])[this.pairIndex]; }
    get pairTitle() {
        const p = this.currentPair;
        return p ? p.higherName + ' → ' + p.lowerName : '';
    }
    get pairResult() {
        const p = this.currentPair;
        return p ? this.resultPairs.find((x) => pairKey(x.higher, x.lower) === pairKey(p.higherBranch, p.lowerBranch)) : null;
    }
    get pairComponents() {
        const r = this.pairResult;
        return r ? r.components || [] : [];
    }
    // D21 (build 56): a pair the last check didn't cover (or no check yet) is "not checked", never "in step".
    get pairNotChecked() { return !this.routeRunning && !this.routeFailed && !this.pairResult; }
    get pairRows() {
        const q = this.term;
        const p = this.currentPair;
        return this.pairComponents.filter((c) => matchesSearch([c.name, c.type, c.cameFrom], q)).slice(0, 1000).map((c) => {
            const chip = statusChip(c.status, p ? p.lowerName : '', p ? p.higherName : '', c.lowerChangedToo);
            const on = this.routePicks.has(c.key);
            return { key: c.key, name: c.name, type: c.type, nameParts: marked(c.name, q), cameFrom: c.cameFrom || '',
                chipLabel: chip.label, chipCls: chip.cls, pickCls: 'rr-chip' + (on ? ' rr-chip-on' : ''), pickLabel: on ? '✓' : 'Pick',
                pressed: on ? 'true' : 'false', rowCls: 'rr-row rr-row-route' + (c.key === this.openKey ? ' rr-row-open' : '') };
        });
    }
    get pairEmpty() { return !!this.routeCheck && this.routeCheck.status === 'Succeeded' && !!this.pairResult && this.pairComponents.length === 0; }
    get pairCountText() { return this.pairComponents.length + ' on the ' + (this.currentPair ? this.currentPair.higherBranch : '') + ' branch that the ' + (this.currentPair ? this.currentPair.lowerBranch : '') + ' branch doesn\'t have'; }
    toggleRoutePick(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.routePicks);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.routePicks = next;
    }
    get routePickText() { return this.routePicks.size + ' picked · ' + this.pairTitle; }
    get cantBackPromotePicked() { return this.busy || !this.canPromote || this.routePicks.size === 0; }
    get cantBackPromoteAll() { return this.busy || !this.canPromote || !this.currentPair; }
    get allLabel() { return 'Back promote all ' + this.pairComponents.length; }
    get pickedLabel() { return 'Back promote ' + this.routePicks.size + ' picked'; }
    get branchOnlyNote() {
        const p = this.currentPair;
        return p && !p.lowerSignIn ? p.lowerName + ' is a developer org: back promote updates its branch only (the pipeline can\'t deploy to it).' : '';
    }
    get promoteHint() { return this.canPromote ? '' : 'Back promote needs Release Relay Admin.'; }

    async backPromotePickedNow() {
        const p = this.currentPair;
        const picked = this.pairComponents.filter((c) => this.routePicks.has(c.key));
        await this.queueRelease(backPromotePicked, { higherOrgId: p.higherId, lowerOrgId: p.lowerId, keys: picked.map((c) => c.key), paths: this.pathsOf(picked) });
    }

    async backPromoteAllNow() {
        const p = this.currentPair;
        this.busy = true;
        this.error = undefined;
        try {
            const id = await backPromoteAll({ higherOrgId: p.higherId, lowerOrgId: p.lowerId });
            this.openRelease(id);
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    async queueRelease(call, pick) {
        this.busy = true;
        this.error = undefined;
        try {
            const id = await call({ pickJson: JSON.stringify(pick) });
            this.openRelease(id);
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    openRelease(id) {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: RELEASES_TAB }, state: { c__release: id } });
    }

    // ---------- installed packages ----------

    get packages() { return this.board ? this.board.packages : null; }
    get packageOrgs() { return this.packages ? this.packages.orgs : ((this.board && this.board.orgs) || []).map((o) => o.name); }
    get packageHead() { return this.packageOrgs.map((n) => ({ key: n, name: n })); }
    get packageRows() {
        const p = this.packages;
        if (!p) {
            return [];
        }
        return p.packages.map((x) => {
            const status = packageStatus(x, p.orgs);
            return { key: x.namespace || x.name, name: x.name, namespace: x.namespace || '', versions: versionList(x, p.orgs),
                statusLabel: status.label, statusCls: status.cls, upgrade: status.upgrade, canUninstall: !!x.namespace };
        });
    }
    get packagesChecked() { return this.packages && this.packages.checkedAt ? 'Read ' + new Date(this.packages.checkedAt).toLocaleString() : 'Not read yet'; }
    get packageErrors() {
        const e = (this.packages && this.packages.errors) || {};
        return Object.keys(e).map((k) => ({ key: k, text: k + ': ' + e[k] }));
    }
    get noPackages() { return !!this.packages && this.packages.packages.length === 0; }

    async readPackagesNow() {
        this.busy = true;
        this.error = undefined;
        try {
            const p = await readPackages();
            this.board = { ...this.board, packages: p };
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    get developerOrgId() {
        const d = ((this.board && this.board.orgs) || []).find((o) => o.role === 'Developer');
        return d ? d.orgId : null;
    }

    /** Add upgrade step: New Release with a Managed package manual step (before deploy). */
    addUpgradeStep(event) {
        const x = this.packages.packages.find((p) => (p.namespace || p.name) === event.currentTarget.dataset.key);
        const latest = versionList(x, this.packages.orgs).map((v) => v.version).filter((v) => v !== '—').sort(compareVersions).pop();
        const behind = this.packages.orgs.filter((o) => x.versions[o] !== latest);
        this.openNewRelease({
            orgId: this.developerOrgId, keys: [], deleted: [], title: 'Upgrade ' + x.name + ' to ' + latest,
            steps: [{ title: ('Upgrade ' + x.name + ' to ' + latest).substring(0, 120), category: 'Managed_Package', timing: 'Before_Deploy',
                instructions: 'Upgrade the managed package ' + x.name + (x.namespace ? ' (' + x.namespace + ')' : '') + ' to version ' + latest
                    + ' in ' + behind.join(', ') + ' (Setup → Installed Packages, or the package\'s install link).', orgScope: '', backPromote: false }]
        });
    }

    async openUninstall(event) {
        const ns = event.currentTarget.dataset.key;
        this.usageNs = ns;
        this.usage = undefined;
        this.usageLoading = true;
        this.error = undefined;
        try {
            this.usage = await packageUsage({ orgId: null, namespace: ns });
            this.usagePicks = new Set(this.usage.uses.map((u) => u.key));
        } catch (e) {
            this.error = errorText(e);
            this.usageNs = undefined;
        } finally {
            this.usageLoading = false;
        }
    }
    closeUninstall() { this.usageNs = undefined; this.usage = undefined; }
    get showUninstall() { return !!this.usageNs; }
    get uninstallPackage() { return this.packages ? this.packages.packages.find((p) => p.namespace === this.usageNs) : null; }
    get uninstallTitle() { return this.uninstallPackage ? 'Uninstall ' + this.uninstallPackage.name + ' (' + this.usageNs + ')' : ''; }
    get usageRows() {
        return ((this.usage && this.usage.uses) || []).map((u) => {
            const on = this.usagePicks.has(u.key);
            return { ...u, pickCls: 'rr-chip' + (on ? ' rr-chip-on' : ''), pickLabel: on ? '✓' : 'Pick', pressed: on ? 'true' : 'false' };
        });
    }
    get usageNone() { return !!this.usage && this.usage.uses.length === 0; }
    get usageNote() { return this.usage ? this.usage.note : ''; }
    get usageOrg() { return this.usage ? this.usage.org : ''; }
    toggleUsage(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.usagePicks);
        if (next.has(key)) {
            next.delete(key);
        } else {
            next.add(key);
        }
        this.usagePicks = next;
    }
    get uninstallSummary() {
        const pkg = this.uninstallPackage;
        const where = pkg ? this.packages.orgs.filter((o) => pkg.versions[o]).join(', ') : '';
        return 'Release: deletions of the ' + this.usagePicks.size + ' picked (checks run as usual) + manual step "Uninstall ' + (pkg ? pkg.name : '') + ' in ' + where + '" (after deploy, proof per org).';
    }
    startUninstallRelease() {
        const pkg = this.uninstallPackage;
        const where = this.packages.orgs.filter((o) => pkg.versions[o]);
        this.openNewRelease({
            orgId: this.developerOrgId, keys: [], deleted: [...this.usagePicks], title: 'Uninstall ' + pkg.name,
            steps: [{ title: ('Uninstall ' + pkg.name).substring(0, 120), category: 'Managed_Package', timing: 'After_Deploy',
                instructions: 'Uninstall the managed package ' + pkg.name + ' (' + pkg.namespace + ') in ' + where.join(', ')
                    + ': Setup → Installed Packages → Uninstall. Salesforce refuses while your own metadata still uses it, so this runs after the deletions are deployed.',
                orgScope: '', backPromote: false }]
        });
    }

    /** Hands the picks to New Release (sessionStorage, read once there) and opens it. */
    openNewRelease(pick) {
        if (!pick.orgId) {
            this.error = 'Register a developer org first: releases are raised from one.';
            return;
        }
        try {
            window.sessionStorage.setItem('rlySyncPick', JSON.stringify(pick));
        } catch (e) {
            this.error = 'The browser didn\'t keep the picks: ' + errorText(e);
            return;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: NEW_RELEASE_TAB }, state: { c__syncPick: '1' } });
    }

    // ---------- page ----------

    get showSpinner() { return this.loading && !this.board; }
    dismissNotice() { this.notice = undefined; }
    refresh() { this.load(); }
}
