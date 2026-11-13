import startPipelinePart from '@salesforce/apex/RlyCompareController.startPipelinePart';
import { errorText, partsToSend, withPart, partIn } from 'c/rlyShared';

/**
 * Sending a developer org's components to the pipeline in parts (build 57: one copy for Sync status and the Migration
 * tab). The listing chunks and parts, and a mixin with the part loop and its CSS countdowns (no timers).
 */

/** Types listed (and sent) on their own: big lists or big files. */
const HEAVY_TYPES = ['CustomField', 'ListView', 'RecordType', 'CompactLayout', 'WebLink', 'ValidationRule', 'FieldSet', 'BusinessProcess',
    'CustomLabel', 'StaticResource', 'Profile', 'ContentAsset', 'Document', 'ExperienceBundle', 'ApexClass', 'Flow', 'Layout'];
const TYPES_PER_CALL = 10;
const KEYS_PER_PART = 25;
const ALONE = ['StaticResource', 'Profile', 'ContentAsset', 'Document', 'ExperienceBundle'];
/** HTTP 409 on a part's commit is retried this many times (D27). */
const CLASH_RETRIES = 5;

/**
 * The types in listing calls: heavy types alone, the rest TYPES_PER_CALL at a time.
 * @param {string[]} types the metadata types
 * @returns {string[][]} the chunks
 */
export function listTypeChunks(types) {
    const out = [];
    const light = [];
    (types || []).forEach((t) => {
        if (HEAVY_TYPES.includes(t)) {
            out.push([t]);
        } else {
            light.push(t);
        }
    });
    for (let i = 0; i < light.length; i += TYPES_PER_CALL) {
        out.push(light.slice(i, i + TYPES_PER_CALL));
    }
    return out;
}

/**
 * The keys in parts to retrieve: static resources, profiles and documents alone, the rest KEYS_PER_PART at a time.
 * @param {string[]} keys Type:Name keys
 * @returns {string[][]} the parts
 */
export function partsOf(keys) {
    const out = [];
    let current = [];
    (keys || []).slice().sort().forEach((k) => {
        if (ALONE.includes(k.substring(0, k.indexOf(':')))) {
            out.push([k]);
            return;
        }
        if (current.length === KEYS_PER_PART) {
            out.push(current);
            current = [];
        }
        current.push(k);
    });
    if (current.length) {
        out.push(current);
    }
    return out;
}

/**
 * The part loop for a component that keeps `sending` ({ syncId, orgId, phase, parts }) and `waits` as its own fields,
 * and implements stageOnePart(part) (the server call that stages a retrieved part), finishDeveloper(), failSending(e, id)
 * and onWaitDone(id, wait) for its other countdowns. partsAtOnce can be overridden (3 by default).
 * @param {Function} Base the component's base class
 * @returns {Function} the class with the part loop
 */
export const PartSending = (Base) => class extends Base {
    get partsAtOnce() { return 3; }

    pumpParts() {
        const s = this.sending;
        if (!s || s.phase !== 'sending') {
            return;
        }
        const next = partsToSend(s, this.partsAtOnce);
        if (next.allReady) {
            this.finishDeveloper();
            return;
        }
        next.ids.forEach((id) => this.sendPart(id));
    }

    setPart(id, values) { this.sending = withPart(this.sending, id, values); }

    partOf(id) { return partIn(this.sending, id); }

    // A part of the send still running: a failed or finished send drops its parts, so late answers are ignored (build 52).
    isLive(id) { return !!this.partOf(id); }

    async sendPart(id) {
        const p = this.partOf(id);
        if (!p) {
            return;
        }
        const orgId = this.sending.orgId;
        this.setPart(id, { phase: 'running' });
        try {
            const retrieveId = await startPipelinePart({ sourceOrgId: orgId, keys: p.keys });
            if (!this.isLive(id)) {
                return;
            }
            this.setPart(id, { retrieveId });
            await this.stagePart(id);
        } catch (e) {
            this.failSending(e, id);
        }
    }

    async stagePart(id) {
        const p = this.partOf(id);
        if (!p) {
            return;
        }
        const s = this.sending;
        try {
            const st = await this.stageOnePart({ compareId: s.syncId, n: p.n, retrieveId: p.retrieveId, sourceOrgId: s.orgId });
            if (!this.isLive(id)) {
                return;
            }
            if (!st.done) {
                this.wait(id, 'part', 2);
                return;
            }
            this.setPart(id, { phase: 'ready' });
            this.pumpParts();
        } catch (e) {
            if (this.retryClash(e, id) || this.retryLostRetrieve(e, id)) {
                return;
            }
            this.failSending(e, id);
        }
    }

    // D36 (build 59): the org deletes a retrieve's result after a while (INVALID_LOCATOR), for example when the page
    // was in the background. The part starts a new retrieve once instead of failing the whole check.
    retryLostRetrieve(e, id) {
        const p = this.partOf(id);
        if (!p || p.restarted || !/INVALID_LOCATOR/.test(errorText(e))) {
            return false;
        }
        this.setPart(id, { restarted: true, retrieveId: undefined });
        this.sendPart(id);
        return true;
    }

    // D27 (build 57): parts are committed side by side, so the branch may move under one (HTTP 409, GitLab 400) even after the
    // server's own retries. The part is staged again a moment later (same retrieve) instead of failing the whole check.
    retryClash(e, id) {
        const p = this.partOf(id);
        // GitLab answers a moved branch with HTTP 400 "reference does not point to expected object" (build 61, D46).
        const clash = /HTTP 409|reference does not point to expected object/i.test(errorText(e));
        if (!p || !clash || (p.clashes || 0) >= CLASH_RETRIES) {
            return false;
        }
        this.setPart(id, { clashes: (p.clashes || 0) + 1 });
        this.wait(id, 'part', 2);
        return true;
    }

    // ---------- countdowns (CSS animation, no timers) ----------

    wait(id, kind, seconds = 5) {
        const prior = this.waits[id];
        this.waits = { ...this.waits, [id]: { kind, cycle: prior ? prior.cycle + 1 : 1, seconds } };
    }

    get ticks() {
        return Object.keys(this.waits).map((id) => {
            const w = this.waits[id];
            return { key: id + '-' + w.cycle, id, cls: 'rr-tick rr-tick-' + w.seconds };
        });
    }

    handleTick(event) {
        const id = event.currentTarget.dataset.id;
        const w = this.waits[id];
        if (!w) {
            return;
        }
        const rest = { ...this.waits };
        delete rest[id];
        this.waits = rest;
        if (w.kind === 'part') {
            this.stagePart(id);
        } else {
            this.onWaitDone(id, w);
        }
    }
};
