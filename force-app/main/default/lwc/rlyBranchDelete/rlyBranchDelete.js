import { LightningElement, api } from 'lwc';
import branchPlan from '@salesforce/apex/RlyChangePartsController.branchPlan';
import deletionPart from '@salesforce/apex/RlyChangePartsController.deletionPart';
import presentNames from '@salesforce/apex/RlyChangePartsController.presentNames';
import presentFields from '@salesforce/apex/RlyChangePartsController.presentFields';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';
import { PARALLEL, PAGE, MAX_CHOSEN, presenceKey, words, runPool, folderTypesOf, componentsOf, typeCounts } from './branchHelpers';

const STILL = 'in';
const GONE = 'out';
const UNKNOWN = 'unknown';
const CHECKING = 'checking';

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

/**
 * Delete from the branch (build 37.1, board "Delete from the branch"): everything on the target's branch, read a part at
 * a time (RlyChangePartsController.branchPlan / deletionPart, PARALLEL at once, each part tried once more, then listed
 * with Try again), each type checked in the developer org (presentNames, custom fields a page at a time through the
 * Tooling API when needed) to tag a component Still in <org> or Not in <org>. Types on the left, components on the
 * right with search, All / Chosen, a Delete chip each (no checkboxes); components a deploy can't delete (Salesforce's
 * own, settings, managed packages…) are greyed with the reason, components already in the release say In release.
 * Fires add ({ items: [{ type, name, stillIn }] }) and close.
 */
export default class RlyBranchDelete extends LightningElement {
    /** The developer org (RLY_Org__c Id). */
    @api sourceOrgId;
    /** The developer org's name. */
    @api sourceName;
    /** The target org's name. */
    @api targetName;
    /** The target's branch. */
    @api targetBranch;
    /** Type:Name of what the release has already (added or deleted). */
    @api takenKeys = [];

    plan;
    keyLists = new Map();
    blockedList = [];
    components = [];
    presence = new Map();
    presenceState = new Map();
    failedParts = [];
    failedTypes = [];
    chosen = new Set();
    typeFilter = 'all';
    view = 'all';
    term = '';
    shown = PAGE;
    reading = true;
    checking = false;
    partsDone = 0;
    typesDone = 0;
    typesTotal = 0;
    truncated = false;
    error;
    started = false;
    closed = false;

    connectedCallback() {
        if (!this.started) {
            this.started = true;
            this.start();
        }
    }

    async start() {
        try {
            this.plan = await branchPlan({ orgId: this.sourceOrgId, targetBranch: this.targetBranch });
            this.truncated = !!this.plan.truncated;
            await runPool((this.plan.parts || []).map((p) => () => this.readPart(p, 0)), PARALLEL);
            this.refresh();
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.reading = false;
        }
        await this.checkOrg(this.typesToCheck());
    }

    /** One part of the branch; tried once more, then listed with Try again. */
    readPart(part, attempt) {
        const json = JSON.stringify({ ...part, rules: this.plan.rules, namespace: this.plan.namespace });
        return deletionPart({ orgId: this.sourceOrgId, partJson: json })
            .then((r) => {
                this.keyLists.set(part.id, r.keys || []);
                this.blockedList = [...this.blockedList, ...(r.blocked || [])];
                this.truncated = this.truncated || r.truncated;
                this.failedParts = this.failedParts.filter((f) => f.part.id !== part.id);
                this.partsDone += 1;
            })
            .catch((e) => {
                if (attempt < 1 && !this.closed) {
                    return this.readPart(part, attempt + 1);
                }
                this.partsDone += 1;
                this.failedParts = [...this.failedParts.filter((f) => f.part.id !== part.id), { key: 'part|' + part.id, part, reason: errorText(e) }];
                return undefined;
            });
    }

    refresh() {
        this.components = componentsOf([...this.keyLists.values()], this.blockedList);
    }

    /** The types to look up in the org: those with a component a deploy can delete, not checked yet, not in folders. */
    typesToCheck() {
        const folders = folderTypesOf(this.plan && this.plan.rules);
        const types = new Set();
        this.components.forEach((c) => {
            if (!c.blocked && !folders.has(c.type) && !this.presenceState.has(c.type)) {
                types.add(c.type);
            }
        });
        return [...types];
    }

    async checkOrg(types) {
        if (!types.length || this.closed) {
            return;
        }
        this.checking = true;
        this.typesTotal += types.length;
        types.forEach((t) => this.presenceState.set(t, CHECKING));
        this.presenceState = new Map(this.presenceState);
        await runPool(types.map((t) => () => this.readType(t, 0)), PARALLEL);
        this.checking = false;
    }

    /** One type in the org; tried once more, custom fields then a page at a time, then listed with Try again. */
    readType(type, attempt) {
        return presentNames({ orgId: this.sourceOrgId, type })
            .then((p) => this.keepPresence(type, p.names || []))
            .catch((e) => {
                if (attempt < 1 && !this.closed) {
                    return this.readType(type, attempt + 1);
                }
                if (type === 'CustomField') {
                    return this.readFieldPages(null, []).catch((e2) => this.failType(type, e2));
                }
                return this.failType(type, e);
            });
    }

    readFieldPages(cursor, names) {
        return presentFields({ orgId: this.sourceOrgId, cursor }).then((p) => {
            names.push(...(p.names || []));
            return p.nextCursor ? this.readFieldPages(p.nextCursor, names) : this.keepPresence('CustomField', names);
        });
    }

    keepPresence(type, names) {
        this.presence.set(type, new Set(names.map((n) => presenceKey(type, n))));
        this.presenceState = new Map(this.presenceState).set(type, 'done');
        this.failedTypes = this.failedTypes.filter((f) => f.type !== type);
        this.typesDone += 1;
    }

    failType(type, e) {
        this.presenceState = new Map(this.presenceState).set(type, UNKNOWN);
        this.failedTypes = [...this.failedTypes.filter((f) => f.type !== type), { key: 'type|' + type, type, reason: errorText(e) }];
        this.typesDone += 1;
    }

    /** Try again on a part of the branch or a type in the org. */
    async retry(event) {
        const [kind, id] = event.currentTarget.dataset.key.split('|');
        if (kind === 'part') {
            const failure = this.failedParts.find((f) => f.part.id === id);
            if (failure) {
                this.reading = true;
                await this.readPart(failure.part, 0);
                this.refresh();
                this.reading = false;
                await this.checkOrg(this.typesToCheck());
            }
            return;
        }
        this.presenceState = new Map(this.presenceState);
        this.presenceState.delete(id);
        this.failedTypes = this.failedTypes.filter((f) => f.type !== id);
        await this.checkOrg([id]);
    }

    // ---------- tags ----------

    whereIs(c) {
        const state = this.presenceState.get(c.type);
        if (state === CHECKING) {
            return CHECKING;
        }
        const names = this.presence.get(c.type);
        if (!names) {
            return UNKNOWN;
        }
        return names.has(presenceKey(c.type, c.name)) ? STILL : GONE;
    }

    get taken() { return new Set(this.takenKeys || []); }

    // ---------- list ----------

    get types() {
        const all = { key: 'all', label: 'All types', count: this.components.length };
        return [all, ...typeCounts(this.components).map((t) => ({ key: t.type, label: words(t.type), count: t.count }))]
            .map((t) => ({ ...t, cls: 'rr-ty' + (t.key === this.typeFilter ? ' rr-ty-on' : ''), pressed: t.key === this.typeFilter ? 'true' : 'false' }));
    }

    get filtered() {
        const q = this.term;
        return this.components.filter((c) => (this.typeFilter === 'all' || c.type === this.typeFilter)
            && (this.view === 'all' || this.chosen.has(c.key))
            && matchesSearch([c.name, c.type, words(c.type)], q));
    }

    get rows() {
        const taken = this.taken;
        return this.filtered.slice(0, this.shown).map((c) => {
            const inRelease = taken.has(c.key);
            const on = this.chosen.has(c.key);
            const where = c.blocked || inRelease ? null : this.whereIs(c);
            let tag = '';
            let tagCls = 'rr-pill rr-pill-none';
            if (c.blocked) {
                tag = 'Can’t be deleted';
            } else if (where === STILL) {
                tag = 'Still in ' + this.sourceName;
                tagCls = 'rr-pill rr-pill-wait';
            } else if (where === GONE) {
                tag = 'Not in ' + this.sourceName;
            } else if (where === CHECKING) {
                tag = 'Checking…';
            } else if (!inRelease) {
                tag = 'Not checked';
            }
            return {
                key: c.key, nameParts: highlightParts(c.name, this.term), typeLabel: words(c.type), tag, tagCls,
                hasTag: !!tag, reason: c.blocked, inRelease, canChoose: !c.blocked && !inRelease,
                chipCls: 'rr-chip' + (on ? ' rr-chip-on' : ''), pressed: on ? 'true' : 'false', chipLabel: on ? '✓ Delete' : 'Delete',
                chipAria: (on ? 'Don’t delete ' : 'Delete ') + c.name,
                rowCls: 'rr-row' + (c.blocked ? ' rr-row-grey' : '') + (on ? ' rr-row-on' : '')
            };
        });
    }

    get hasRows() { return this.rows.length > 0; }
    get hasMore() { return this.filtered.length > this.shown; }
    get moreText() { return 'Show more (' + (this.filtered.length - this.shown) + ' left)'; }
    showMore() { this.shown += PAGE; }
    get shownCount() { return this.filtered.length; }
    get totalCount() { return this.components.length; }
    get emptyText() {
        if (this.reading) {
            return 'Reading the ' + this.targetBranch + ' branch…';
        }
        if (this.view === 'chosen') {
            return 'Nothing chosen yet: press Delete on a component.';
        }
        return this.term ? 'No components match ‘' + this.term + '’.' : 'No components on the ' + this.targetBranch + ' branch.';
    }

    pickType(event) {
        this.typeFilter = event.currentTarget.dataset.key;
        this.shown = PAGE;
    }

    showAll() { this.view = 'all'; this.shown = PAGE; }
    showChosen() { this.view = 'chosen'; this.shown = PAGE; }
    get allCls() { return 'rr-seg' + (this.view === 'all' ? ' rr-seg-on' : ''); }
    get chosenCls() { return 'rr-seg' + (this.view === 'chosen' ? ' rr-seg-on' : ''); }
    get allPressed() { return this.view === 'all' ? 'true' : 'false'; }
    get chosenPressed() { return this.view === 'chosen' ? 'true' : 'false'; }
    get chosenTabLabel() { return 'Chosen (' + this.chosen.size + ')'; }

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
        this.shown = PAGE;
    }

    toggle(event) {
        const key = event.currentTarget.dataset.key;
        const next = new Set(this.chosen);
        if (next.has(key)) {
            next.delete(key);
        } else if (next.size < MAX_CHOSEN) {
            next.add(key);
        }
        this.chosen = next;
    }

    // ---------- progress, warnings, footer ----------

    get progressText() {
        const parts = (this.plan && this.plan.parts ? this.plan.parts.length : 0);
        const branch = this.reading
            ? 'Reading the ' + this.targetBranch + ' branch: ' + Math.min(this.partsDone, parts) + ' of ' + parts + ' parts'
            : 'Branch read · ' + plural(parts, 'part', 'parts');
        let org = '';
        if (this.checking) {
            org = ' · checking ' + this.sourceName + ': ' + Math.min(this.typesDone, this.typesTotal) + ' of ' + this.typesTotal + ' types';
        } else if (!this.reading && this.typesTotal) {
            org = ' · ' + this.sourceName + ' checked';
        }
        return branch + org;
    }
    get busy() { return this.reading || this.checking; }
    get barStyle() {
        const parts = this.plan && this.plan.parts ? this.plan.parts.length : 0;
        const total = parts + this.typesTotal;
        const done = Math.min(this.partsDone, parts) + Math.min(this.typesDone, this.typesTotal);
        return 'width:' + (total ? Math.round((done * 100) / total) : (this.reading ? 5 : 100)) + '%';
    }
    get truncatedText() { return 'GitHub cut a folder list short, so some components on the ' + this.targetBranch + ' branch may be missing.'; }
    get hasFailures() { return this.failedParts.length + this.failedTypes.length > 0; }
    get failureRows() {
        return [
            ...this.failedParts.map((f) => ({ key: f.key, text: 'Couldn’t read ' + f.part.label + ' on ' + this.targetBranch + ': ' + f.reason })),
            ...this.failedTypes.map((f) => ({ key: f.key, text: 'Couldn’t check ' + words(f.type) + ' in ' + this.sourceName + ': ' + f.reason }))
        ];
    }

    get chosenList() { return this.components.filter((c) => this.chosen.has(c.key)); }
    get stillChosen() { return this.chosenList.filter((c) => this.whereIs(c) === STILL); }
    get hasStillWarning() { return this.stillChosen.length > 0; }
    get stillWarning() {
        const still = this.stillChosen;
        const names = still.slice(0, 3).map((c) => c.name).join(', ') + (still.length > 3 ? ' and ' + (still.length - 3) + ' more' : '');
        return names + (still.length === 1 ? ' is' : ' are') + ' still in ' + this.sourceName + '. Delete '
            + (still.length === 1 ? 'it' : 'them') + ' there too, or a later release from ' + this.sourceName + ' can bring '
            + (still.length === 1 ? 'it' : 'them') + ' back.';
    }
    get footText() {
        const n = this.chosen.size;
        const still = this.stillChosen.length;
        return n + ' to delete' + (still ? ' \u00b7 ' + still + ' still in ' + this.sourceName : '');
    }
    get limitText() { return this.chosen.size >= MAX_CHOSEN ? 'At most ' + MAX_CHOSEN + ' deletions in one release.' : ''; }
    get noneChosen() { return this.chosen.size === 0; }
    get addLabel() { return 'Add ' + this.chosen.size + ' to the release'; }
    get heading() { return 'Delete from the ' + this.targetBranch + ' branch'; }
    get searchHint() { return 'Search the ' + this.targetBranch + ' branch'; }
    get intro() {
        return 'Everything on the ' + this.targetBranch + ' branch, read a folder at a time. Choose what this release deletes from '
            + this.targetName + ' (and from later stages when it’s promoted).';
    }

    add() {
        const items = this.chosenList.map((c) => ({ type: c.type, name: c.name, stillIn: this.whereIs(c) === STILL }));
        this.closed = true;
        this.dispatchEvent(new CustomEvent('add', { detail: { items } }));
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }

    close() {
        this.closed = true;
        this.dispatchEvent(new CustomEvent('close'));
    }
}
