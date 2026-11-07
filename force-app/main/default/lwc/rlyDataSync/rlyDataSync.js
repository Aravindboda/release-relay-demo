import { LightningElement } from 'lwc';
import board from '@salesforce/apex/RlyDataController.board';
import saveSet from '@salesforce/apex/RlyDataController.saveSet';
import removeSet from '@salesforce/apex/RlyDataController.removeSet';
import startRun from '@salesforce/apex/RlyDataController.startRun';
import exportPart from '@salesforce/apex/RlyDataController.exportPart';
import runExported from '@salesforce/apex/RlyDataController.runExported';
import readRun from '@salesforce/apex/RlyDataController.readRun';
import loadRun from '@salesforce/apex/RlyDataController.loadRun';
import { definitionOf, editorOf, statusPill, countsText, DIRECTIONS } from './dataHelpers';

/** Parts of a developer org's export sent at once (one object each). */
const AT_ONCE = 2;

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

/**
 * The Data view of the Sync status tab (board: Data sets · up and down, build 43). Left: the data sets (admins add and
 * edit them). Right: start a run (Send up, Copy down; Refill for an org refreshed since its last load), the latest runs
 * with their dry-run counts per object, and Load once a person may allow it (an approver who didn't start it for Send
 * up, an admin for Copy down). A developer org's records are sent from the page in pages of up to 2,000 (RlyDataRuns
 * exportPart), two objects at once; running runs are read again every 5 seconds with a CSS countdown (no timers).
 */
export default class RlyDataSync extends LightningElement {
    data;
    error;
    busy = false;
    selectedSetId;
    direction = 'Down';
    sourceOrgId;
    targetOrgId;
    mask = true;
    releaseName = '';
    openRunId;
    details = {};
    exportState;
    editor;
    tickCycle = 0;
    ticking = false;

    connectedCallback() {
        this.refresh();
    }

    async refresh() {
        try {
            this.data = await board();
            this.error = undefined;
            if (!this.selectedSetId && this.data.sets.length) {
                this.selectedSetId = this.data.sets[0].id;
            }
            this.direction = this.data.isAdmin ? this.direction : 'Up';
            this.tickIfRunning();
        } catch (e) {
            this.error = errorText(e);
        }
    }

    // ---------- data sets ----------

    get loaded() { return !!this.data; }
    get isAdmin() { return !!this.data && this.data.isAdmin; }
    get sets() {
        return (this.data ? this.data.sets : []).map((s) => ({ ...s, cls: 'rr-set' + (s.id === this.selectedSetId ? ' rr-set-on' : ''),
            sub: s.problem ? s.problem : s.objectCount + (s.objectCount === 1 ? ' object' : ' objects') }));
    }
    get hasSets() { return this.sets.length > 0; }
    get selectedSet() { return this.data && this.data.sets.find((s) => s.id === this.selectedSetId); }
    get selectedObjects() {
        const s = this.selectedSet;
        const d = s ? definitionOf(s.definition) : null;
        return d ? d.objects.map((o, i) => ({
            key: o.objectName + i, order: i + 1, objectName: o.objectName, filter: o.filter || 'all records',
            matchKey: (o.matchKey || []).join(' + '), parents: Object.keys(o.parents || {}).map((f) => f + ' → ' + o.parents[f]).join(', ') || '—',
            masks: Object.keys(o.masks || {}).join(', ') || '—'
        })) : [];
    }
    get bypassText() {
        const s = this.selectedSet;
        const d = s ? definitionOf(s.definition) : null;
        if (!d || !d.bypass || !d.bypass.kind) {
            return 'No trigger bypass: objects whose triggers fire are flagged on the dry run.';
        }
        return d.bypass.kind === 'setting' ? 'Trigger bypass: custom setting ' + d.bypass.name + '.' + d.bypass.field + ' (on for the pipeline’s user during the load).'
            : 'Trigger bypass: permission set ' + d.bypass.name + ' (assigned to the pipeline’s user during the load).';
    }
    pickSet(event) {
        this.selectedSetId = event.currentTarget.dataset.id;
    }

    newSet() {
        this.editor = editorOf(null);
    }
    editSet() {
        this.editor = editorOf(this.selectedSet);
    }
    closeEditor() {
        this.editor = undefined;
    }
    get editorObjects() {
        return this.editor ? this.editor.objects.map((o, i) => ({ ...o, index: i, label: 'Object ' + (i + 1) })) : [];
    }
    get editorBypassButtons() {
        const kind = this.editor ? this.editor.bypassKind : '';
        return [{ value: '', label: 'None' }, { value: 'setting', label: 'Custom setting' }, { value: 'permissionSet', label: 'Permission set' }]
            .map((b) => ({ ...b, cls: 'rr-seg' + (b.value === kind ? ' rr-seg-on' : ''), pressed: b.value === kind ? 'true' : 'false' }));
    }
    get editorIsSetting() { return !!this.editor && this.editor.bypassKind === 'setting'; }
    get editorHasBypass() { return !!this.editor && !!this.editor.bypassKind; }
    handleEditorField(event) {
        this.editor = { ...this.editor, [event.target.dataset.field]: event.detail.value };
    }
    handleBypassKind(event) {
        this.editor = { ...this.editor, bypassKind: event.currentTarget.dataset.value };
    }
    handleObjectField(event) {
        const i = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const objects = this.editor.objects.map((o, n) => (n === i ? { ...o, [field]: event.detail.value } : o));
        this.editor = { ...this.editor, objects };
    }
    addObject() {
        this.editor = { ...this.editor, objects: [...this.editor.objects, { objectName: '', fields: '', filter: '', matchKey: '', parents: '', masks: '' }] };
    }
    removeObject(event) {
        const i = Number(event.currentTarget.dataset.index);
        this.editor = { ...this.editor, objects: this.editor.objects.filter((o, n) => n !== i) };
    }
    async saveEditor() {
        this.busy = true;
        try {
            const id = await saveSet({ setJson: JSON.stringify({ id: this.editor.id, title: this.editor.title, description: this.editor.description,
                definition: JSON.stringify(this.editor.toDefinition()) }) });
            this.editor = undefined;
            this.selectedSetId = id;
            await this.refresh();
        } catch (e) {
            this.editor = { ...this.editor, error: errorText(e) };
        } finally {
            this.busy = false;
        }
    }
    async deleteSet() {
        this.busy = true;
        try {
            await removeSet({ setId: this.selectedSetId });
            this.selectedSetId = undefined;
            await this.refresh();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    // ---------- start a run ----------

    get directionButtons() {
        const allowed = this.isAdmin ? DIRECTIONS : DIRECTIONS.filter((d) => d.value === 'Up');
        return allowed.map((d) => ({ ...d, cls: 'rr-seg' + (d.value === this.direction ? ' rr-seg-on' : ''), pressed: d.value === this.direction ? 'true' : 'false' }));
    }
    get isUp() { return this.direction === 'Up'; }
    get sourceOptions() {
        return (this.data ? this.data.orgs : []).map((o) => ({ label: o.name + (o.canLoad ? '' : ' (sent by the hub)'), value: o.id }));
    }
    get targetOptions() {
        return (this.data ? this.data.orgs : []).filter((o) => o.canLoad).map((o) => ({ label: o.name, value: o.id }));
    }
    get refills() {
        return (this.data ? this.data.orgs : []).filter((o) => o.refillDue && this.isAdmin).map((o) => ({ ...o, key: o.id,
            text: o.name + ' was refreshed since its last data load.' }));
    }
    get maskHint() {
        return this.isUp ? 'Usually off when sending up.' : 'Emails, phones and names in the masked fields are replaced on the way down.';
    }
    get cantStart() {
        return this.busy || !this.selectedSet || !!this.selectedSet.problem || !this.sourceOrgId || !this.targetOrgId || this.sourceOrgId === this.targetOrgId;
    }
    handleDirection(event) {
        this.direction = event.currentTarget.dataset.value;
        this.mask = this.direction !== 'Up';
    }
    handleSource(event) { this.sourceOrgId = event.detail.value; }
    handleTarget(event) { this.targetOrgId = event.detail.value; }
    handleMask(event) { this.mask = event.target.checked; }
    handleRelease(event) { this.releaseName = event.detail.value; }

    refill(event) {
        const org = this.data.orgs.find((o) => o.id === event.currentTarget.dataset.id);
        const last = this.data.runs.find((r) => r.runId === org.lastRunId);
        this.direction = 'Refill';
        this.mask = true;
        this.targetOrgId = org.id;
        if (last) {
            this.selectedSetId = last.dataSetId || this.selectedSetId;
            this.sourceOrgId = last.sourceOrgId;
        }
    }

    async start() {
        this.busy = true;
        this.error = undefined;
        try {
            const s = await startRun({ requestJson: JSON.stringify({ dataSetId: this.selectedSetId, sourceOrgId: this.sourceOrgId,
                targetOrgId: this.targetOrgId, direction: this.direction, mask: this.mask, releaseName: this.releaseName }) });
            if (s.next === 'export') {
                await this.sendRecords(s);
            }
            this.openRunId = s.runId;
            await this.refresh();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
            this.exportState = undefined;
        }
    }

    /** A developer org: every object's pages, AT_ONCE objects at a time, then the dry run. */
    async sendRecords(s) {
        const total = s.queries.length;
        let next = 0;
        let sent = 0;
        let records = 0;
        this.exportState = 'Sending ' + total + ' objects’ records to Git…';
        const worker = async () => {
            while (next < total) {
                const index = next;
                next += 1;
                let cursor = null;
                let page = 1;
                do {
                    // eslint-disable-next-line no-await-in-loop
                    const p = await exportPart({ partJson: JSON.stringify({ runId: s.runId, index, pageNo: page, cursor }) });
                    records += p.count;
                    cursor = p.nextCursor;
                    page += 1;
                } while (cursor);
                sent += 1;
                this.exportState = 'Sent ' + sent + ' of ' + total + ' objects (' + records + ' records)…';
            }
        };
        const workers = [];
        for (let i = 0; i < Math.min(AT_ONCE, total); i++) {
            workers.push(worker());
        }
        await Promise.all(workers);
        await runExported({ runId: s.runId });
    }

    // ---------- runs ----------

    get runs() {
        const me = this.data ? this.data.userId : null;
        return (this.data ? this.data.runs : []).map((r) => {
            const pill = statusPill(r.status);
            const canLoad = r.status === 'Ready' && (r.direction === 'Up' ? this.data.isApprover && r.requestedById !== me : this.isAdmin);
            const d = this.details[r.runId];
            return { ...r, key: r.runId, detailKey: r.runId + '-detail', pillLabel: pill.label, pillCls: pill.cls, countsText: countsText(r.counts),
                canLoad, open: this.openRunId === r.runId,
                loadLabel: r.direction === 'Up' ? 'Approve and load' : 'Load', detailRows: d ? d.objects.map((o) => ({ ...o, key: o.objectName,
                    dupText: o.duplicates.length ? o.duplicates.length + ' keys match twice: ' + o.duplicates.slice(0, 5).join(', ') : '',
                    missingText: o.missingKeys ? o.missingKeys + ' without a key' : '', errText: o.errors.slice(0, 3).join(' · ') })) : [],
                hint: r.direction === 'Up' && r.status === 'Ready' && r.requestedById === me ? 'An approver (not you) loads it.' : '' };
        });
    }
    get hasRuns() { return this.runs.length > 0; }

    async toggleRun(event) {
        const id = event.currentTarget.dataset.id;
        this.openRunId = this.openRunId === id ? undefined : id;
        if (this.openRunId) {
            await this.readOne(id);
        }
    }
    async readOne(id) {
        try {
            const v = await readRun({ runId: id });
            this.details = { ...this.details, [id]: v };
            const r = this.data.runs.find((x) => x.runId === id);
            if (r && v.status !== r.status) {
                await this.refresh();
            }
        } catch (e) {
            this.error = errorText(e);
        }
    }
    async load(event) {
        const id = event.currentTarget.dataset.id;
        this.busy = true;
        try {
            await loadRun({ runId: id });
            await this.refresh();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    /** Runs in Dry run or Loading: read again every 5 seconds (CSS countdown). */
    tickIfRunning() {
        this.ticking = (this.data ? this.data.runs : []).some((r) => r.status === 'Dry run' || r.status === 'Loading');
        if (this.ticking) {
            this.tickCycle += 1;
        }
    }
    get ticks() { return this.ticking ? [{ key: 't' + this.tickCycle }] : []; }
    async handleTick() {
        const running = (this.data ? this.data.runs : []).filter((r) => r.status === 'Dry run' || r.status === 'Loading');
        for (const r of running) {
            // eslint-disable-next-line no-await-in-loop
            await this.readOne(r.runId);
        }
        await this.refresh();
    }
}
