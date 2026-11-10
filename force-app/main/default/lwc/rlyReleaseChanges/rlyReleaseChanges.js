import { LightningElement, api } from 'lwc';
import files from '@salesforce/apex/RlyPullRequestFiles.files';
import filesPage from '@salesforce/apex/RlyPullRequestFiles.filesPage';
import filePatch from '@salesforce/apex/RlyPullRequestFiles.filePatch';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';
import { errorText, clearSearchBox } from 'c/rlyShared';

const BLOCKS = 5;
/** The list shows its search box from this many files (or while a search is typed). */
const SEARCH_FROM = 7;
const STATUS_CLS = {
    modified: 'rr-pill rr-pill-info',
    changed: 'rr-pill rr-pill-info',
    added: 'rr-pill rr-pill-ok',
    copied: 'rr-pill rr-pill-ok',
    removed: 'rr-pill rr-pill-bad'
};

function plural(n, word) {
    return n.toLocaleString() + ' ' + word + (n === 1 ? '' : 's');
}

// GitHub-style bar: five blocks shared between added (green) and removed (red) lines.
function bar(added, removed) {
    const total = added + removed;
    const green = total === 0 ? 0 : Math.round((added / total) * BLOCKS);
    const out = [];
    for (let i = 0; i < BLOCKS; i++) {
        let cls = 'rr-blk';
        if (total > 0) {
            cls += i < green ? ' rr-blk-add' : ' rr-blk-del';
        }
        out.push({ key: 'b' + i, cls });
    }
    return out;
}

/**
 * The Changes tab of the release page: the files of the release's pull request as GitHub shows them, and a wide dialog
 * that steps through their diffs (rlyDiffView, from each file's patch). Build 37: the files come a page at a time
 * without their patches (the next page is read as soon as one arrives, so the list fills in), and a file's patch is
 * read when it's opened, then kept.
 */
export default class RlyReleaseChanges extends LightningElement {
    @api releaseId;
    /** The pull request's button label, for example "Pull request #42" (shown when the provider isn't GitHub). */
    @api prLabel;
    @api prUrl;

    loading = false;
    error;
    data;
    /** Reading more pages after the first. */
    more = false;
    moreError;
    /** Patches read so far, by file name. */
    patches = {};
    patchLoading = false;
    patchError;
    openIndex = -1;
    focusClose = false;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.focusClose) {
            const btn = this.template.querySelector('.rr-close');
            if (btn) {
                btn.focus();
                this.focusClose = false;
            }
        }
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        this.patches = {};
        try {
            this.data = await files({ releaseId: this.releaseId });
            const d = this.data;
            const count = d && d.available ? (d.totalFiles || d.files.length) : null;
            this.dispatchEvent(new CustomEvent('loaded', { detail: { count } }));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
        this.readMore();
    }

    /** Reads the next pages one after another; a page that fails offers Try again. */
    async readMore() {
        this.moreError = undefined;
        await this.readNextPage();
    }

    // One page, then the next (each needs the page number the last one returned).
    async readNextPage() {
        if (!this.data || !this.data.available || !this.data.nextPage) {
            this.more = false;
            return;
        }
        this.more = true;
        try {
            const next = await filesPage({ releaseId: this.releaseId, pageNo: this.data.nextPage });
            this.data = { ...this.data, files: this.data.files.concat(next.files || []), nextPage: next.nextPage };
        } catch (e) {
            this.moreError = errorText(e);
            this.more = false;
            return;
        }
        await this.readNextPage();
    }

    get moreText() {
        const total = this.data && this.data.totalFiles;
        return 'Reading the files: ' + this.fileCount.toLocaleString() + (total ? ' of ' + Math.min(total, 3000).toLocaleString() : '') + '…';
    }

    /** The open file's patch, read once. */
    async readPatch() {
        const f = this.data && this.data.files[this.openIndex];
        if (!f || !f.hasPatch || this.patches[f.filename] || this.patchLoading) {
            return;
        }
        this.patchLoading = true;
        this.patchError = undefined;
        try {
            const got = await filePatch({ releaseId: this.releaseId, pageNo: f.pageNo, filename: f.filename });
            this.patches = { ...this.patches, [f.filename]: got };
        } catch (e) {
            this.patchError = errorText(e);
        } finally {
            this.patchLoading = false;
        }
    }

    // ---------- the list ----------

    get available() {
        return !!(this.data && this.data.available);
    }

    get unavailableText() {
        return this.data && !this.data.available ? this.data.message : null;
    }

    get provider() {
        return (this.data && this.data.provider) || 'GitHub';
    }

    get openLabel() {
        return 'Open in ' + this.provider + ' ↗';
    }

    get filesUrl() {
        return this.data ? this.data.filesUrl : null;
    }

    get fileCount() {
        return this.available ? this.data.files.length : 0;
    }

    /** All files, for the summary: the pull request's count when it has more than one page. */
    get allCount() {
        return this.available ? Math.max(this.data.totalFiles || 0, this.fileCount) : 0;
    }

    get hasFiles() {
        return this.fileCount > 0;
    }

    get changedText() {
        return plural(this.allCount, 'file') + ' changed';
    }

    get addedText() {
        return '+' + (this.data ? this.data.additions : 0).toLocaleString();
    }

    get removedText() {
        return '−' + (this.data ? this.data.deletions : 0).toLocaleString();
    }

    get intoText() {
        const d = this.data;
        return 'pull request #' + d.prNumber + (d.targetBranch ? ' into ' + d.targetBranch : '');
    }

    get truncatedText() {
        if (!this.available || !this.data.truncated) {
            return null;
        }
        const total = this.data.totalFiles;
        return 'GitHub lists the first 3,000 files' + (total ? ' of ' + total.toLocaleString() : '');
    }

    get rows() {
        if (!this.available) {
            return [];
        }
        return this.data.files.map((f, i) => {
            const path = f.filename || '';
            const cut = path.lastIndexOf('/');
            const on = i === this.openIndex;
            return {
                key: 'f' + i,
                index: String(i),
                name: cut >= 0 ? path.substring(cut + 1) : path,
                folder: cut >= 0 ? path.substring(0, cut) : '',
                fromText: f.previousFilename ? 'from ' + f.previousFilename : null,
                status: f.status,
                statusCls: STATUS_CLS[f.status] || 'rr-pill rr-pill-none',
                added: f.additions ? '+' + f.additions.toLocaleString() : null,
                removed: f.deletions ? '−' + f.deletions.toLocaleString() : null,
                countsLabel: f.additions + ' added, ' + f.deletions + ' removed',
                blocks: bar(f.additions || 0, f.deletions || 0),
                rowCls: on ? 'rr-pr rr-pr-on' : 'rr-pr',
                itemCls: on ? 'rr-mi rr-mi-on' : 'rr-mi',
                current: on ? 'true' : 'false'
            };
        });
    }

    // ---------- search (build 27) ----------

    /** The search text, normalised: filters the file list on the page (the dialog keeps every file). */
    term = '';

    get shownRows() {
        const q = this.term;
        return this.rows.filter((r) => matchesSearch([r.name, r.folder, r.status, r.fromText], q))
            .map((r) => ({ ...r, nameParts: highlightParts(r.name, q), folderParts: highlightParts(r.folder, q) }));
    }
    get showSearch() { return this.rows.length >= SEARCH_FROM || !!this.term; }
    get noMatch() { return !!this.term && this.shownRows.length === 0; }
    get noMatchText() { return 'No files match \u2018' + this.term + '\u2019.'; }
    get rowCount() { return this.rows.length; }
    get shownCount() { return this.shownRows.length; }

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
    }

    clearSearch() {
        clearSearchBox(this.template);
        this.term = '';
    }

    // ---------- the dialog ----------

    get isOpen() {
        return this.openIndex >= 0 && this.available && this.openIndex < this.data.files.length;
    }

    get current() {
        if (!this.isOpen) {
            return null;
        }
        const f = this.data.files[this.openIndex];
        const got = this.patches[f.filename];
        return got ? { ...f, patch: got.patch, note: got.note || f.note } : f;
    }

    get patchWaiting() {
        return !!(this.current && this.current.hasPatch && !this.current.patch && !this.patchError);
    }

    get patchNote() {
        return this.current && this.current.patch ? this.current.note : null;
    }

    get modalTitle() {
        return 'Changes · Pull request #' + this.data.prNumber;
    }

    get modalSub() {
        const d = this.data;
        const route = d.sourceName && d.targetName ? d.sourceName + ' → ' + d.targetName + ' · ' : '';
        return route + this.changedText + ' · ' + this.addedText + ' ' + this.removedText + ' · as ' + this.provider + ' shows them on the pull request';
    }

    get listHead() {
        return plural(this.fileCount, 'file');
    }

    get leftLabel() {
        const d = this.data;
        if (d.targetName && d.targetBranch) {
            return d.targetName + ' (' + d.targetBranch + ' branch)';
        }
        return d.targetName || d.targetBranch;
    }

    get rightLabel() {
        return this.data.sourceName;
    }

    get hasPatch() {
        return !!(this.current && this.current.patch);
    }

    get noteText() {
        return this.patchError || (this.current ? this.current.note : null);
    }

    get options() {
        return this.rows.map((r) => ({ key: r.key, value: r.index, label: r.name + ' (' + r.status + ')', selected: r.current === 'true' }));
    }

    openFile(event) {
        this.show(Number(event.currentTarget.dataset.index));
        this.focusClose = true;
    }

    pickFile(event) {
        this.show(Number(event.currentTarget.dataset.index));
    }

    pickFromSelect(event) {
        this.show(Number(event.target.value));
    }

    show(index) {
        this.openIndex = index;
        this.patchError = undefined;
        this.readPatch();
    }

    close() {
        this.openIndex = -1;
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        } else if ((event.key === 'ArrowDown' || event.key === 'ArrowUp') && event.target.tagName !== 'SELECT') {
            const step = event.key === 'ArrowDown' ? 1 : -1;
            const next = this.openIndex + step;
            if (next >= 0 && next < this.fileCount) {
                event.preventDefault();
                this.show(next);
            }
        }
    }
}
