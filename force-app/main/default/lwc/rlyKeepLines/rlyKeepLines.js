import { LightningElement, api } from 'lwc';
import startCompare from '@salesforce/apex/RlyCompareController.startCompare';
import checkCompare from '@salesforce/apex/RlyCompareController.checkCompare';
import { missingItems, itemWords } from 'c/rlyXmlItems';
import { errorText } from 'c/rlyShared';

/** The types Review reads (the hub compares them; labels and profiles are left to the pipeline). */
const READ_TYPES = new Set(['Layout', 'PermissionSet', 'CustomField', 'GlobalValueSet', 'StandardValueSet']);
/** Most components one read takes (RlyCompareFiles.MAX_COMPONENTS). */
const MAX_READ = 25;
/** Wait between checks of the retrieve. */
const WAIT_MS = 2000;
const READING = 'reading';
const READY = 'ready';
const FAILED = 'failed';

/**
 * Review, build 60 (D40, board "D40 · Review: lines DEV1 doesn't have"): reads the developer org's copy and the target
 * branch's copy of the release's layouts, permission sets, fields and value sets (the compare calls, one small retrieve)
 * and lists every item the branch has that the developer org lacks: a layout field, a permission, a picklist value.
 * Each is kept (the default: it came from another release and was never put into the developer org) or taken out on
 * purpose. Fires keepchange { removeOnPurpose: [{ component, item }], kept, removed, state } on every change; state
 * comes back through the state property, so going to Profile access and back reads nothing again.
 */
export default class RlyKeepLines extends LightningElement {
    @api sourceOrgId;
    @api sourceName;
    @api targetBranch;
    @api disabled = false;

    phase;
    sig;
    rows = [];
    removed = new Set();
    message;
    waitKey = 0;
    waiting = false;
    job;
    readKeys = [];
    leftOver = 0;
    _items = [];
    _state;

    /** [{ type, name }] the release brings. */
    @api
    get items() { return this._items; }
    set items(value) {
        this._items = Array.isArray(value) ? value : [];
        if (this.isConnected) {
            this.read();
        }
    }

    /** What keepchange sent last (kept by the builder while the steps change). */
    @api
    get state() { return this._state; }
    set state(value) { this._state = value; }

    connectedCallback() {
        this.read();
    }

    get keys() {
        return this._items.filter((i) => READ_TYPES.has(i.type)).map((i) => i.type + ':' + i.name);
    }

    /** Starts reading when the components changed; a state for the same components is used as it is. */
    read() {
        const all = this.keys;
        const sig = all.join('\n');
        if (this.sig === sig) {
            return;
        }
        this.sig = sig;
        this.waiting = false;
        if (!all.length) {
            this.phase = undefined;
            this.rows = [];
            this.emit();
            return;
        }
        const st = this._state;
        if (st && st.sig === sig && st.phase === READY) {
            this.rows = st.rows;
            this.removed = new Set(st.removed);
            this.leftOver = st.leftOver || 0;
            this.phase = READY;
            return;
        }
        this.readKeys = all.slice(0, MAX_READ);
        this.leftOver = all.length - this.readKeys.length;
        this.phase = READING;
        this.rows = [];
        this.removed = new Set();
        this.message = undefined;
        this.start(sig);
    }

    async start(sig) {
        try {
            const retrieveId = await startCompare({ sourceOrgId: this.sourceOrgId, keys: this.readKeys });
            if (sig !== this.sig) {
                return;
            }
            this.job = { retrieveId, sourceOrgId: this.sourceOrgId, keys: this.readKeys, deleted: [], targetBranch: this.targetBranch };
            this.check(sig);
        } catch (e) {
            this.fail(e, sig);
        }
    }

    async check(sig) {
        try {
            const r = await checkCompare({ jobJson: JSON.stringify(this.job) });
            if (sig !== this.sig) {
                return;
            }
            if (!r.done) {
                this.waitAgain();
                return;
            }
            const components = r.components || [];
            const pending = this.pendingPaths(components);
            if (r.more && pending.length) {
                await this.fillPending(components, pending, sig);
            }
            if (sig === this.sig) {
                this.settle(components);
            }
        } catch (e) {
            this.fail(e, sig);
        }
    }

    pendingPaths(components) {
        const out = [];
        components.forEach((c) => (c.files || []).forEach((f) => {
            if (f.status === 'pending') {
                out.push(f.path);
            }
        }));
        return out;
    }

    /** Files still pending: their branch copies, one follow-up check. */
    async fillPending(components, paths, sig) {
        const r = await checkCompare({ jobJson: JSON.stringify({ ...this.job, retrieveId: null, pendingPaths: paths }) });
        if (sig !== this.sig) {
            return;
        }
        const byPath = new Map((r.fetched || []).map((f) => [f.path, f]));
        components.forEach((c) => (c.files || []).forEach((f) => {
            const got = byPath.get(f.path);
            if (got && f.status === 'pending') {
                f.left = got.left;
            }
        }));
    }

    waitAgain() {
        this.waitKey += 1;
        this.waiting = true;
    }

    handleWaitDone() {
        this.waiting = false;
        this.check(this.sig);
    }

    settle(components) {
        const rows = [];
        components.forEach((c) => {
            const main = (c.files || [])[0];
            if (!main || main.left === null || main.left === undefined || main.right === null || main.right === undefined) {
                return;
            }
            const type = c.key.substring(0, c.key.indexOf(':'));
            const name = c.key.substring(c.key.indexOf(':') + 1);
            missingItems(type, main.left, main.right).forEach((i) => {
                rows.push({ key: c.key + '|' + i.id, component: c.key, item: i.id, name, words: itemWords(i.id) });
            });
        });
        this.rows = rows;
        this.phase = READY;
        this.emit();
    }

    fail(e, sig) {
        if (sig !== this.sig) {
            return;
        }
        this.phase = FAILED;
        this.message = errorText(e);
        this.rows = [];
        this.emit();
    }

    emit() {
        const removeOnPurpose = this.rows.filter((r) => this.removed.has(r.key)).map((r) => ({ component: r.component, item: r.item }));
        this._state = { sig: this.sig, phase: this.phase, rows: this.rows, removed: [...this.removed], leftOver: this.leftOver };
        this.dispatchEvent(new CustomEvent('keepchange', {
            detail: { removeOnPurpose, kept: this.rows.length - removeOnPurpose.length, removed: removeOnPurpose.length, state: this._state }
        }));
    }

    handleChoice(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.removed);
        if (event.currentTarget.dataset.value === 'remove') {
            next.add(key);
        } else {
            next.delete(key);
        }
        this.removed = next;
        this.emit();
    }

    get waits() { return this.waiting ? [{ key: 'w' + this.waitKey, ms: WAIT_MS }] : []; }
    get show() { return !!this.phase; }
    get isReading() { return this.phase === READING; }
    get isFailed() { return this.phase === FAILED; }
    get hasRows() { return this.phase === READY && this.rows.length > 0; }
    get source() { return this.sourceName || 'The developer org'; }
    get branch() { return this.targetBranch || 'target'; }
    get readingText() {
        const n = this.readKeys.length;
        return 'Reading ' + this.source + '\'s copy and the ' + this.branch + ' branch\'s copy of ' + n + (n === 1 ? ' component' : ' components')
            + ' to find lines ' + this.source + ' doesn\'t have…';
    }
    get failedText() {
        return 'Couldn\'t read the copies (' + (this.message || 'no answer') + '). You can raise anyway: the pipeline keeps every line the '
            + this.branch + ' branch has that ' + this.source + ' doesn\'t.';
    }
    get headline() {
        const n = this.rows.length;
        return this.source + ' doesn\'t have ' + n + (n === 1 ? ' line' : ' lines') + ' that the ' + this.branch + ' branch has';
    }
    get explain() {
        return 'They came from other releases (merged back from ' + this.branch + ') and were never put into ' + this.source
            + '. Release Relay keeps them, so this release only brings your changes. Tick Remove on purpose for a line you really took out.';
    }
    get leftOverText() {
        return this.leftOver ? 'Only the first ' + MAX_READ + ' components were read; the pipeline keeps the other ' + this.leftOver + '\'s lines too.' : '';
    }
    get lines() {
        return this.rows.map((r) => {
            const off = this.removed.has(r.key);
            return {
                ...r,
                keepCls: 'rr-tog' + (off ? '' : ' rr-tog-keep'),
                removeCls: 'rr-tog' + (off ? ' rr-tog-remove' : ''),
                keepPressed: off ? 'false' : 'true',
                removePressed: off ? 'true' : 'false',
                groupLabel: 'What this release does with ' + r.name + ' ' + r.words
            };
        });
    }
}
