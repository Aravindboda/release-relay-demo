import { LightningElement, api } from 'lwc';
import readFiles from '@salesforce/apex/RlyFileEdit.files';
import readFile from '@salesforce/apex/RlyFileEdit.readFile';
import saveFile from '@salesforce/apex/RlyFileEdit.saveFile';
import startCompare from '@salesforce/apex/RlyCompareController.startCompare';
import checkCompare from '@salesforce/apex/RlyCompareController.checkCompare';
import { errorText } from 'c/rlyShared';

/** Most lines a read-only column draws; the editor always has the whole file. */
const MAX_LINES = 2000;
/** Most checks of the source org's retrieve (2 s apart) before giving up. */
const MAX_CHECKS = 60;

/** "A", "A and B", "A, B and C". */
function names(list) {
    if (list.length <= 1) {
        return list.join('');
    }
    return list.slice(0, -1).join(', ') + ' and ' + list[list.length - 1];
}

/** The namespaces a line references (ns__Name, or ns.Class at the start of a value). */
function refsIn(line, known) {
    return known.filter((ns) => new RegExp('(\\b' + ns + '__\\w)|(>\\s*' + ns + '\\.\\w)', 'i').test(line));
}

/**
 * Edit a file (build 55, board "Package-aware releases" e), opened from the release page. Every file of an open
 * release: the source org's copy (read as Compare reads it: a small retrieve, checked every 2 seconds with a CSS
 * countdown, no timers), the target branch's copy and what will be deployed (the release branch's copy, editable).
 * Lines that reference a package are marked with the namespace and whether the target org gets them. Save edit commits
 * the file to the release branch (RlyFileEdit.saveFile): History says "Edited by <you>: <file>" and the checks run
 * again. Only the person who raised the release or an admin, while it is open and no run is going.
 */
export default class RlyFileEdit extends LightningElement {
    @api releaseId;

    view;
    error;
    loading = false;
    saving = false;
    selectedKey;
    texts = [];
    selectedPath;
    draft;
    editing = false;
    mode = 'side';
    orgTexts = {};
    orgState = 'idle';
    orgError;
    job;
    cycle = 0;
    checks = 0;

    connectedCallback() {
        readFiles({ releaseId: this.releaseId }).then((v) => {
            this.view = v;
            const first = (v.items || []).find((i) => i.editable);
            if (first) {
                this.open(first.key);
            }
        }).catch((e) => { this.error = errorText(e); });
    }

    // ---------- what is open ----------

    get title() { return 'Edit a file' + (this.view ? ' · ' + this.view.releaseName : ''); }
    get items() {
        return ((this.view && this.view.items) || []).map((i) => ({
            ...i, label: i.name + ' (' + i.type + ')',
            cls: 'rr-fe-item' + (i.key === this.selectedKey ? ' rr-fe-item-on' : '') + (i.editable ? '' : ' rr-fe-item-off'),
            current: i.key === this.selectedKey ? 'true' : 'false',
            disabled: !i.editable || this.saving
        }));
    }
    get selectedItem() { return ((this.view && this.view.items) || []).find((i) => i.key === this.selectedKey); }
    get fileTabs() {
        return this.texts.map((t) => ({ key: 'f-' + t.path, path: t.path, label: t.path.split('/').pop(),
            cls: 'rr-fe-tab' + (t.path === this.selectedPath ? ' rr-fe-tab-on' : ''), pressed: t.path === this.selectedPath ? 'true' : 'false' }));
    }
    get hasTabs() { return this.texts.length > 1; }
    get file() { return this.texts.find((t) => t.path === this.selectedPath); }
    get fileReason() { return this.file && this.file.reason; }
    get isDirty() { return !!this.file && this.draft !== undefined && this.draft !== (this.file.release || ''); }
    get canEdit() { return !!this.view && this.view.canEdit === true && !!this.file && !this.file.reason; }
    get whyNot() { return this.view && !this.view.canEdit ? this.view.whyNot : ''; }
    get cantSave() { return !this.canEdit || !this.isDirty || this.saving; }
    get saveLabel() { return this.saving ? 'Saving…' : 'Save edit'; }
    get statusText() {
        if (!this.file) {
            return '';
        }
        const t = this.file;
        if (t.release === null || t.release === undefined) {
            return 'Not on the release branch';
        }
        if (t.target === null || t.target === undefined) {
            return 'New in this release';
        }
        return t.release.replace(/\r\n/g, '\n') === t.target.replace(/\r\n/g, '\n') ? 'Same as the target' : 'Changed';
    }

    async open(key) {
        this.selectedKey = key;
        this.loading = true;
        this.error = undefined;
        this.texts = [];
        this.selectedPath = undefined;
        this.editing = false;
        this.orgTexts = {};
        this.orgState = 'idle';
        this.job = undefined;
        try {
            this.texts = await readFile({ releaseId: this.releaseId, key });
            this.pick(this.texts[0] && this.texts[0].path);
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
        this.readOrg(key);
    }

    pick(path) {
        this.selectedPath = path;
        const t = this.file;
        this.draft = t ? t.release || '' : undefined;
        this.editing = false;
    }

    handleItem(event) {
        if (this.isDirty) {
            this.error = 'Save or discard the edit first.';
            return;
        }
        this.open(event.currentTarget.dataset.key);
    }

    handleTab(event) {
        if (this.isDirty) {
            this.error = 'Save or discard the edit first.';
            return;
        }
        this.pick(event.currentTarget.dataset.path);
    }

    // ---------- the source org's copy (as Compare reads it) ----------

    async readOrg(key) {
        const item = this.selectedItem;
        if (!this.view || !this.view.sourceReadable || !item || !item.comparable) {
            this.orgState = 'na';
            return;
        }
        this.orgState = 'reading';
        this.checks = 0;
        try {
            const retrieveId = await startCompare({ sourceOrgId: this.view.sourceOrgId, keys: [key] });
            if (!retrieveId || key !== this.selectedKey) {
                this.orgState = retrieveId ? this.orgState : 'na';
                return;
            }
            this.job = { retrieveId, sourceOrgId: this.view.sourceOrgId, keys: [key], deleted: [], targetBranch: this.view.targetBranch };
            this.cycle += 1;
        } catch (e) {
            this.orgState = 'error';
            this.orgError = errorText(e);
        }
    }

    /** One countdown while the retrieve runs; when it ends, check again. */
    get ticks() { return this.job && this.orgState === 'reading' ? [{ key: 't' + this.cycle }] : []; }

    async handleTick() {
        const job = this.job;
        if (!job) {
            return;
        }
        this.checks += 1;
        try {
            const r = await checkCompare({ jobJson: JSON.stringify(job) });
            if (job !== this.job) {
                return;
            }
            if (!r.done && this.checks < MAX_CHECKS) {
                this.cycle += 1;
                return;
            }
            const found = {};
            ((r.components && r.components[0] && r.components[0].files) || []).forEach((f) => { found[f.path] = f.right; });
            this.orgTexts = found;
            this.orgState = r.done ? 'done' : 'error';
            this.orgError = r.done ? undefined : 'The org took too long to answer.';
            this.job = undefined;
        } catch (e) {
            this.orgState = 'error';
            this.orgError = errorText(e);
            this.job = undefined;
        }
    }

    // ---------- the three columns ----------

    get known() {
        const out = new Set();
        ((this.view && this.view.packages) || []).forEach((o) => (o.has || []).forEach((ns) => out.add(ns)));
        return Array.from(out);
    }
    orgHas(name, ns) {
        const o = ((this.view && this.view.packages) || []).find((x) => x.name === name);
        return !o || !o.checked ? null : (o.has || []).includes(ns);
    }

    lines(text, side) {
        if (typeof text !== 'string') {
            return [];
        }
        const known = this.known;
        const all = text.replace(/\r\n/g, '\n').split('\n');
        const out = all.slice(0, MAX_LINES).map((l, i) => {
            const refs = known.length ? refsIn(l, known) : [];
            let tag = '';
            if (refs.length && side === 'deploy') {
                tag = refs.map((ns) => ns + (this.orgHas(this.view.targetName, ns) === false ? ' · left out' : ' · sent')).join(', ');
            }
            return { key: side + i, n: i + 1, text: l || ' ', tag, cls: 'rr-ln' + (refs.length ? ' rr-ln-pkg' : '') };
        });
        if (all.length > MAX_LINES) {
            out.push({ key: side + 'more', n: '…', text: (all.length - MAX_LINES) + ' more lines', tag: '', cls: 'rr-ln rr-ln-more' });
        }
        return out;
    }
    get orgLines() { return this.file ? this.lines(this.orgTexts[this.file.path], 'org') : []; }
    get targetLines() { return this.file ? this.lines(this.file.target, 'target') : []; }
    get deployLines() { return this.file ? this.lines(this.draft, 'deploy') : []; }
    get orgHeading() { return ((this.view && this.view.sourceName) || 'Source org') + ' (source org)'; }
    get targetHeading() { return ((this.view && this.view.targetBranch) || 'target') + ' branch (target)'; }
    get deployHeading() { return 'Will be deployed' + (this.canEdit ? ' (editable)' : ''); }
    get orgNote() {
        if (this.orgState === 'reading') {
            return 'Reading it from ' + this.view.sourceName + '…';
        }
        if (this.orgState === 'na') {
            return 'Not read here: ' + (this.view && this.view.sourceReadable ? 'Compare doesn\'t read this type.' : 'the release comes from a branch, not an org.');
        }
        if (this.orgState === 'error') {
            return 'Couldn\'t read it: ' + (this.orgError || '');
        }
        return this.orgState === 'done' && this.file && typeof this.orgTexts[this.file.path] !== 'string' ? 'Not in ' + this.view.sourceName + '.' : '';
    }
    get targetNote() { return this.file && typeof this.file.target !== 'string' ? 'Not on the ' + this.view.targetBranch + ' branch yet.' : ''; }

    /** "Marked lines belong to package arch: SIT and PROD get them, DEV1 doesn't." */
    get packageNote() {
        const text = this.draft || '';
        const found = this.known.filter((ns) => text.split('\n').some((l) => refsIn(l, [ns]).length > 0));
        return found.map((ns) => {
            const orgs = ((this.view && this.view.packages) || []).filter((o) => o.checked);
            const get = orgs.filter((o) => (o.has || []).includes(ns)).map((o) => o.name);
            const lack = orgs.filter((o) => !(o.has || []).includes(ns)).map((o) => o.name);
            return {
                key: 'pn-' + ns,
                text: 'Marked lines belong to package ' + ns + ': ' + (get.length ? names(get) + ' get them' : 'no org has it')
                    + (lack.length ? ', ' + names(lack) + (lack.length === 1 ? ' doesn\'t.' : ' don\'t.') : '.')
            };
        });
    }

    // ---------- views and editing ----------

    get isSide() { return this.mode === 'side'; }
    get sideCls() { return 'rr-seg' + (this.isSide ? ' rr-seg-on' : ''); }
    get diffCls() { return 'rr-seg' + (this.isSide ? '' : ' rr-seg-on'); }
    get sidePressed() { return this.isSide ? 'true' : 'false'; }
    get diffPressed() { return this.isSide ? 'false' : 'true'; }
    showSide() { this.mode = 'side'; }
    showDiff() { this.mode = 'diff'; }
    get diffTitle() { return this.file ? this.file.path : ''; }
    get diffLeft() { return this.file ? this.file.target || '' : ''; }

    get editLabel() { return this.editing ? 'Show marked lines' : 'Edit text'; }
    toggleEdit() { this.editing = !this.editing; }

    // D23 (build 56): a native textarea doesn't take value={draft} when it first renders, so it opened empty and saving
    // would have replaced the file with nothing. Fill it once each time it appears.
    renderedCallback() {
        const ta = this.template.querySelector('textarea.rr-fe-text');
        if (ta && !ta.dataset.filled) {
            ta.value = this.draft || '';
            ta.dataset.filled = 'yes';
        }
    }
    handleDraft(event) { this.draft = event.target.value; }
    discard() {
        this.draft = this.file ? this.file.release || '' : undefined;
        this.editing = false;
        this.error = undefined;
    }

    async save() {
        this.saving = true;
        this.error = undefined;
        try {
            const edit = { path: this.file.path, content: this.draft, expected: this.file.release || '' };
            const detail = await saveFile({ releaseId: this.releaseId, editJson: JSON.stringify(edit) });
            this.dispatchEvent(new CustomEvent('saved', { detail }));
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.saving = false;
        }
    }

    close() {
        this.job = undefined;
        this.dispatchEvent(new CustomEvent('close'));
    }
    handleKeydown(event) {
        if (event.key === 'Escape' && !this.isDirty) {
            this.close();
        }
    }
}
