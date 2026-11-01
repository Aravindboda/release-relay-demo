import { LightningElement, api } from 'lwc';
import { MAX_LINES, toLines, diffTexts, parsePatch, foldOps, splitRows, unifiedRows, countOps } from './diffEngine';

// The diff of the last inputs, per component (kept outside the reactive fields so rendering never writes state).
const CACHE = new WeakMap();

/**
 * One file compared line by line: the target's copy (left) against the source's (right), or a GitHub patch.
 * Side by side (each side scrolls sideways on its own) or unified; long unchanged runs are folded; changed
 * characters are marked; the browser does the diff. Slot "subheader" sits under the header (file picker, versions).
 */
export default class RlyDiffView extends LightningElement {
    @api title;
    @api leftLabel;
    @api rightLabel;
    @api left;
    @api right;
    @api patch;
    /** Optional link in the header, for example the file in the pull request ("Open in GitHub ↗"). */
    @api linkUrl;
    @api linkLabel;

    viewMode;
    expanded = {};
    lastSource;

    @api
    get mode() {
        return this.viewMode || 'split';
    }
    set mode(value) {
        this.viewMode = value === 'unified' ? 'unified' : 'split';
    }

    // ---------- the diff ----------

    get model() {
        const cached = CACHE.get(this);
        if (cached && cached.left === this.left && cached.right === this.right && cached.patch === this.patch) {
            return cached.model;
        }
        const model = this.build();
        CACHE.set(this, { left: this.left, right: this.right, patch: this.patch, model });
        return model;
    }

    build() {
        if (this.patch) {
            const p = parsePatch(this.patch);
            return { ops: p.ops, isNew: p.isNew, isDeleted: p.isDeleted, tooLarge: false, fromPatch: true };
        }
        const a = toLines(this.left);
        const b = toLines(this.right);
        if (a.length > MAX_LINES || b.length > MAX_LINES) {
            return { ops: [], tooLarge: true, leftCount: a.length, rightCount: b.length };
        }
        const ops = diffTexts(this.left, this.right);
        return { ops, isNew: a.length === 0 && b.length > 0, isDeleted: b.length === 0 && a.length > 0, tooLarge: false, empty: a.length === 0 && b.length === 0 };
    }

    get counts() {
        return countOps(this.model.ops);
    }

    get shownOps() {
        // a new set of texts starts with every fold closed
        const source = this.model;
        const opened = this.lastSource === source ? this.expanded : {};
        return foldOps(source.ops, opened);
    }

    // ---------- header ----------

    get addedText() {
        return '+' + this.counts.added.toLocaleString();
    }

    get removedText() {
        return '−' + this.counts.removed.toLocaleString();
    }

    get showAdded() {
        return this.showCounts && this.counts.added > 0;
    }

    get showRemoved() {
        return this.showCounts && this.counts.removed > 0;
    }

    get countsLabel() {
        return this.counts.added + ' lines added, ' + this.counts.removed + ' lines removed';
    }

    get showCounts() {
        return this.hasLines;
    }

    get isSplit() {
        return this.mode === 'split';
    }

    get splitCls() {
        return this.isSplit ? 'rr-seg-btn rr-seg-on' : 'rr-seg-btn';
    }

    get unifiedCls() {
        return this.isSplit ? 'rr-seg-btn' : 'rr-seg-btn rr-seg-on';
    }

    get splitPressed() {
        return String(this.isSplit);
    }

    get unifiedPressed() {
        return String(!this.isSplit);
    }

    get leftName() {
        return this.leftLabel || 'the target';
    }

    get rightName() {
        return this.rightLabel || 'the source';
    }

    // ---------- states ----------

    get hasLines() {
        return !this.model.tooLarge && this.model.ops.length > 0 && !this.noDifferences;
    }

    get isNew() {
        return this.hasLines && this.model.isNew;
    }

    get isDeleted() {
        return this.hasLines && this.model.isDeleted;
    }

    get newText() {
        const n = this.counts.added;
        return 'Not in ' + this.leftName + ' yet: ' + (n === 1 ? 'its 1 line is added.' : 'all ' + n.toLocaleString() + ' lines are added.');
    }

    get deletedText() {
        return 'Removed from ' + this.leftName + ' when this release deploys.';
    }

    get tooLarge() {
        return this.model.tooLarge;
    }

    get tooLargeText() {
        const m = this.model;
        const lines = (n) => n.toLocaleString() + (n === 1 ? ' line' : ' lines');
        return 'Too large to compare here (' + lines(m.rightCount) + ' in ' + this.rightName + ', ' + lines(m.leftCount) + ' in ' + this.leftName + ').';
    }

    get noDifferences() {
        const m = this.model;
        return !m.tooLarge && !m.fromPatch && !m.empty && m.ops.length > 0 && this.counts.added === 0 && this.counts.removed === 0;
    }

    get sameText() {
        return 'No differences: ' + this.rightName + ' and ' + this.leftName + ' have the same file.';
    }

    get isEmpty() {
        const m = this.model;
        return !m.tooLarge && (m.empty || m.ops.length === 0);
    }

    get emptyText() {
        return this.model.fromPatch ? 'No line changes in this file.' : 'Nothing to compare: the file is empty on both sides.';
    }

    // ---------- rows ----------

    get splitRowsShown() {
        return splitRows(this.shownOps);
    }

    get unifiedRowsShown() {
        return unifiedRows(this.shownOps);
    }

    // ---------- actions ----------

    showSplit() {
        this.viewMode = 'split';
    }

    showUnified() {
        this.viewMode = 'unified';
    }

    openFold(event) {
        const id = event.currentTarget.dataset.id;
        const source = this.model;
        const opened = this.lastSource === source ? this.expanded : {};
        this.lastSource = source;
        this.expanded = Object.assign({}, opened, { [id]: true });
    }
}
