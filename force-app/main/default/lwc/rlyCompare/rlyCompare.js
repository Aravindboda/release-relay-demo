import { LightningElement, api } from 'lwc';
import startCompare from '@salesforce/apex/RlyCompareController.startCompare';
import checkCompare from '@salesforce/apex/RlyCompareController.checkCompare';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';

/** The most components one compare takes (RlyCompareFiles.MAX_COMPONENTS). */
const MAX_COMPONENTS = 25;
/** The list shows its search box from this many components (or while a search is typed). */
const SEARCH_FROM = 7;
/** Statuses from RlyCompareController.checkCompare (RlyCompareFiles). */
const CHANGED = 'changed';
const SAME = 'same';
const ADDED = 'new';
const REMOVED = 'deleted';
const UNSUPPORTED = 'unsupported';
const PENDING = 'pending';
/** Chip per status (board HubCompare: Changed blue, New green, Deleted red, Same and Not available grey, Checking… amber). */
const CHIPS = {
    [CHANGED]: { label: 'Changed', cls: 'rr-pill rr-pill-info' },
    [ADDED]: { label: 'New in this release', cls: 'rr-pill rr-pill-ok' },
    [SAME]: { label: 'Same', cls: 'rr-pill rr-pill-none' },
    [REMOVED]: { label: 'Deleted', cls: 'rr-pill rr-pill-bad' },
    [UNSUPPORTED]: { label: 'Not available', cls: 'rr-pill rr-pill-none' }
};
const CHECKING = { label: 'Checking…', cls: 'rr-pill rr-pill-wait' };
const FLOW_STATUS = { Active: 'Active', Draft: 'Draft', InvalidDraft: 'Invalid draft', Obsolete: 'Obsolete' };
const FLOW_CLS = { Active: 'rr-pill rr-pill-info', Draft: 'rr-pill rr-pill-wait', InvalidDraft: 'rr-pill rr-pill-bad', Obsolete: 'rr-pill rr-pill-none' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

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

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

/**
 * Compare before raising (board HubCompare 2–3): a wide modal with the release's components on the left (a chip each)
 * and the selected file in c-rly-diff-view on the right: the target branch's copy (left) against the developer org's
 * copy now (right). RlyCompareController.startCompare retrieves the components, checkCompare is polled every 2 seconds
 * (a CSS countdown, no timers) until the files are read; a follow-up check reads the files left pending. Nothing is
 * changed in either place. Fires close.
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
    selectedKey;
    selectedPath;
    job;
    result;
    error;
    started = false;
    waiting = false;
    cycle = 0;

    connectedCallback() {
        this.components = this.compared.map((i) => ({ key: i.type + ':' + i.name, item: i, status: undefined, files: [] }));
        const start = this.startKey && this.components.find((c) => c.key === this.startKey);
        this.selectedKey = start ? start.key : (this.components[0] && this.components[0].key);
        if (!this.started) {
            this.started = true;
            this.begin();
        }
    }

    /** The components compared: the first MAX_COMPONENTS. */
    get compared() {
        return (this.items || []).slice(0, MAX_COMPONENTS);
    }
    get overCap() { return (this.items || []).length > MAX_COMPONENTS; }
    get overCapText() {
        return 'Compare takes ' + MAX_COMPONENTS + ' components at a time: the first ' + MAX_COMPONENTS + ' of ' + this.items.length + ' are here.';
    }

    // ---------- reading ----------

    async begin() {
        const keys = this.components.filter((c) => !c.item.deleted).map((c) => c.key);
        const deleted = this.components.filter((c) => c.item.deleted).map((c) => c.key);
        try {
            const retrieveId = keys.length ? await startCompare({ sourceOrgId: this.sourceOrgId, keys }) : null;
            this.job = { retrieveId, sourceOrgId: this.sourceOrgId, keys, deleted, targetBranch: this.targetBranch };
            await this.check();
        } catch (e) {
            this.error = errorText(e);
        }
    }

    /** One check; while the retrieve runs, counts down 2 seconds (CSS) and checks again. */
    async check() {
        this.waiting = false;
        try {
            const r = await checkCompare({ jobJson: JSON.stringify(this.job) });
            if (!r.done) {
                this.result = this.result || r;
                this.startCountdown();
                return;
            }
            this.result = r;
            this.components = this.components.map((c) => {
                const found = (r.components || []).find((x) => x.key === c.key);
                return found ? { ...c, status: found.status, reason: found.reason, files: found.files || [] } : c;
            });
            this.pickFirstFile();
            if (r.more) {
                await this.followUp();
            }
        } catch (e) {
            this.error = errorText(e);
        }
    }

    /** Reads the files left pending (one more check per budget's worth) and merges the branch's copies in. */
    async followUp() {
        const pending = [];
        this.components.forEach((c) => c.files.forEach((f) => {
            if (f.status === PENDING) {
                pending.push(f.path);
            }
        }));
        if (!pending.length) {
            return;
        }
        const r = await checkCompare({ jobJson: JSON.stringify({ ...this.job, pendingPaths: pending }) });
        const byPath = new Map((r.fetched || []).map((f) => [f.path, f]));
        this.components = this.components.map((c) => {
            if (!c.files.some((f) => byPath.has(f.path))) {
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
            await this.followUp();
        }
    }

    startCountdown() {
        this.cycle += 1;
        this.waiting = true;
    }
    get cycles() { return [{ key: 'c' + this.cycle }]; }

    /** The 2-second countdown ended: check again. */
    handleTick() {
        if (this.waiting) {
            this.check();
        }
    }

    // ---------- list ----------

    get countText() { return plural(this.components.length, 'component', 'components'); }
    get loaded() { return !!(this.result && this.result.done); }
    get loading() { return !this.loaded && !this.error; }

    get rows() {
        return this.components.map((c) => {
            const on = c.key === this.selectedKey;
            const chip = this.loaded && c.status && c.status !== PENDING ? CHIPS[c.status] || CHECKING : CHECKING;
            let sub = c.item.typeLabel;
            if (c.item.deleted) {
                sub += ' · Delete from ' + this.targetName;
            } else if (c.files.length) {
                sub += ' · ' + plural(c.files.length, 'file', 'files');
            }
            return {
                key: c.key, name: c.item.name, sub, chipLabel: chip.label, chipCls: chip.cls,
                why: this.loaded && c.status === UNSUPPORTED ? c.reason : '',
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
    get noMatchText() { return 'No components match \u2018' + this.term + '\u2019.'; }
    get rowCount() { return this.components.length; }
    get shownCount() { return this.shownRows.length; }

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
    }

    clearSearch() {
        const box = this.template.querySelector('c-rly-search-box');
        if (box) {
            box.clear();
        }
        this.term = '';
    }

    get pickOptions() { return this.components.map((c) => ({ label: c.item.name, value: c.key })); }

    pickComponent(event) {
        this.selectedKey = event.currentTarget.dataset.key;
        this.pickFirstFile();
    }
    handlePickChange(event) {
        this.selectedKey = event.detail.value;
        this.pickFirstFile();
    }
    pickFirstFile() {
        const c = this.selected;
        this.selectedPath = c && c.files.length ? c.files[0].path : undefined;
    }

    // ---------- right pane ----------

    get selected() { return this.components.find((c) => c.key === this.selectedKey); }
    get file() {
        const c = this.selected;
        return c ? c.files.find((f) => f.path === this.selectedPath) || c.files[0] : undefined;
    }
    get loadingTitle() { return 'Getting ' + this.sourceName + '\'s copy…'; }
    get loadingText() {
        const n = this.components.filter((c) => !c.item.deleted).length;
        return n
            ? 'Retrieving ' + plural(n, 'component', 'components') + ' from ' + this.sourceName + ', then reading the ' + this.targetBranch + ' branch. Usually under a minute.'
            : 'Reading the ' + this.targetBranch + ' branch.';
    }
    get showUnavailable() {
        const c = this.selected;
        return this.loaded && !!c && c.status === UNSUPPORTED && !c.files.some((f) => f.status !== UNSUPPORTED);
    }
    get unavailableName() { return this.selected ? this.selected.key.substring(this.selected.key.indexOf(':') + 1) : ''; }
    get unavailableReason() {
        const c = this.selected;
        return (c && (c.reason || (c.files[0] && c.files[0].reason))) || '';
    }
    get showFile() { return this.loaded && !this.showUnavailable && !!this.file; }
    get filePending() { return !!this.file && this.file.status === PENDING; }
    get fileUnsupported() { return !!this.file && this.file.status === UNSUPPORTED; }
    get fileDiff() { return this.showFile && !this.filePending && !this.fileUnsupported; }
    get fileReadingText() { return 'Reading the ' + this.targetBranch + ' branch…'; }
    get fileReason() { return this.file ? this.file.reason : ''; }
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
        return f && f.status !== PENDING ? CHIPS[f.status] || CHECKING : CHECKING;
    }
    get fileChipLabel() { return this.fileChip.label; }
    get fileChipCls() { return this.fileChip.cls; }
    pickFile(event) {
        this.selectedPath = event.currentTarget.dataset.path;
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
        const t = ((this.result && this.result.targetFlows) || []).find((x) => x.name === c.item.name);
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
        return this.loaded
            ? 'What ' + this.sourceName + ' has now against the ' + this.targetBranch + ' branch. Nothing is changed in either place.'
            : 'Getting the files…';
    }
    get readAt() { return this.result && this.result.readAt; }
    get readLabel() { return this.sourceName + ' read'; }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }
    close() {
        this.waiting = false;
        this.dispatchEvent(new CustomEvent('close'));
    }
}
