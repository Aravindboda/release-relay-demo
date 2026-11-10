import { LightningElement, api } from 'lwc';
import listProfiles from '@salesforce/apex/RlyProfileAccessController.profiles';
import readAccess from '@salesforce/apex/RlyProfileAccessController.readAccess';
import listNames from '@salesforce/apex/RlyProfileAccessController.names';
import { errorText } from 'c/rlyShared';
import { SECTIONS, sectionOf, rowId, valueKey, rowsFor, switched, startValues, describe } from 'c/rlyAccessRows';

const MAX_PROFILES = 20;
const MATCHES_SHOWN = 12;
const PICKS_SHOWN = 40;
const ON = 'true';

/**
 * New Release, step Profile access (build 58): pick profiles, then set the access each one gets for the release's
 * components (and any added here). Only rows set here are sent; the developer org's values show as grey hints and
 * the target's as words. Fires "accesschange" with { state, profileAccess } after every change, so the release
 * builder keeps the state across steps and sends profileAccess with the raise.
 */
export default class RlyProfileAccess extends LightningElement {
    /** The developer org. */
    @api orgId;
    /** The developer org's name. */
    @api sourceName;
    /** The release's components ({ type, name }). */
    @api components = [];
    /** Read only while the release is raised. */
    @api disabled = false;
    /** The state this step had last time (restored when the step opens again). */
    @api
    get state() { return this._state; }
    set state(value) { this._state = value; }

    allProfiles = [];
    profilesLoading = true;
    profileError;
    search = '';
    picked = [];
    active;
    extraRows = [];
    sends = {};
    source = {};
    target = {};
    notes = [];
    usage = {};
    targetName;
    reading = 0;
    addSection = '';
    addObject = '';
    pickSearch = '';
    picks = [];
    picksLoading = false;
    addError = '';
    pickCache = {};
    _state;

    connectedCallback() {
        const s = this._state;
        if (s) {
            Object.assign(this, { picked: s.picked || [], active: s.active, extraRows: s.extraRows || [], sends: s.sends || {},
                source: s.source || {}, target: s.target || {}, notes: s.notes || [], usage: s.usage || {}, targetName: s.targetName });
        }
        this.loadProfiles();
    }

    async loadProfiles() {
        this.profilesLoading = true;
        try {
            this.allProfiles = await listProfiles({ orgId: this.orgId });
        } catch (e) {
            this.profileError = errorText(e);
        } finally {
            this.profilesLoading = false;
        }
    }

    // ---------- rows ----------

    get componentRows() { return rowsFor(this.components); }

    get allRows() {
        const seen = new Set();
        return this.componentRows.map((r) => ({ ...r, added: false })).concat(this.extraRows.map((r) => ({ ...r, added: true })))
            .filter((r) => {
                const id = rowId(r.section, r.key);
                if (seen.has(id)) {
                    return false;
                }
                seen.add(id);
                return true;
            });
    }

    get hasRows() { return this.allRows.length > 0; }
    get noRowsText() {
        return 'Nothing in this release needs profile access. Use Add access for system permissions, custom settings or components already in the target.';
    }

    // ---------- profiles ----------

    /** A label two profiles share shows with its file name: Authenticated Website (Authenticated Website%2E). */
    get duplicateLabels() {
        const seen = new Set();
        const twice = new Set();
        (this.allProfiles || []).forEach((p) => (seen.has(p.label) ? twice.add(p.label) : seen.add(p.label)));
        return twice;
    }

    shownLabel(p) {
        return this.duplicateLabels.has(p.label) ? p.label + ' (' + p.profile + ')' : p.label;
    }

    get pickedChips() {
        return this.picked.map((p) => ({ ...p, shown: this.shownLabel(p), cls: 'rr-chip' + (p.profile === this.active ? ' rr-sel' : ''),
            pressed: p.profile === this.active ? 'true' : 'false', count: this.countFor(p.profile) }));
    }
    get hasPicked() { return this.picked.length > 0; }

    get matches() {
        const term = this.search.trim().toLowerCase();
        const taken = new Set(this.picked.map((p) => p.profile));
        return (this.allProfiles || []).filter((p) => !taken.has(p.profile) && (!term || p.label.toLowerCase().includes(term)))
            .slice(0, MATCHES_SHOWN).map((p) => ({ ...p, shown: this.shownLabel(p) }));
    }
    get moreMatches() {
        const term = this.search.trim().toLowerCase();
        const n = (this.allProfiles || []).filter((p) => !term || p.label.toLowerCase().includes(term)).length - this.picked.length;
        return n > MATCHES_SHOWN ? 'Showing ' + MATCHES_SHOWN + ' of ' + n + ': search to narrow.' : '';
    }
    get atLimit() { return this.picked.length >= MAX_PROFILES; }

    handleSearch(event) {
        this.search = event.target.value || '';
    }

    pickProfile(event) {
        if (this.atLimit || this.disabled) {
            return;
        }
        const p = this.allProfiles.find((x) => x.profile === event.currentTarget.dataset.profile);
        if (!p) {
            return;
        }
        this.picked = [...this.picked, { profile: p.profile, label: p.label }];
        this.active = p.profile;
        this.emit();
        this.readFor([{ profile: p.profile, label: p.label }], this.allRows);
    }

    showProfile(event) {
        this.active = event.currentTarget.dataset.profile;
        this.emit();
    }

    dropProfile(event) {
        event.stopPropagation();
        const name = event.currentTarget.dataset.profile;
        this.picked = this.picked.filter((p) => p.profile !== name);
        const next = { ...this.sends };
        delete next[name];
        this.sends = next;
        if (this.active === name) {
            this.active = this.picked.length ? this.picked[0].profile : undefined;
        }
        this.emit();
    }

    get activeLabel() {
        const p = this.picked.find((x) => x.profile === this.active);
        return p ? p.label : '';
    }

    countFor(profile) {
        return Object.keys(this.sends[profile] || {}).length;
    }

    // ---------- reading ----------

    async readFor(profiles, rows) {
        if (!profiles.length || !rows.length) {
            return;
        }
        this.reading += 1;
        try {
            const a = await readAccess({ askJson: JSON.stringify({ orgId: this.orgId, profiles,
                rows: rows.map((r) => ({ section: r.section, key: r.key })) }) });
            this.source = { ...this.source, ...a.source.rows };
            this.target = { ...this.target, ...a.target.rows };
            this.targetName = a.targetName || this.targetName;
            this.notes = [...new Set([...this.notes, ...a.source.notes, ...a.target.notes])].slice(-8);
            this.usage = { source: this.usageOf(a.sourceName || this.sourceName, a.source),
                target: a.targetName ? this.usageOf(a.targetName, a.target) : this.usage.target };
        } catch (e) {
            this.notes = [...this.notes, errorText(e)].slice(-8);
        } finally {
            this.reading -= 1;
            this.emit();
        }
    }

    usageOf(name, values) {
        const calls = values.calls || 0;
        const daily = values.apiMax ? ' · ' + Number(values.apiUsed).toLocaleString() + ' of ' + Number(values.apiMax).toLocaleString()
            + ' daily API calls used' : '';
        return name + ': ' + calls + (calls === 1 ? ' call' : ' calls') + ' for this read' + daily;
    }

    get usageLines() {
        return [this.usage.source, this.usage.target].filter(Boolean).map((text, i) => ({ key: 'u' + i, text }));
    }
    get isReading() { return this.reading > 0; }
    get hasNotes() { return this.notes.length > 0; }
    get noteList() { return this.notes.map((text, i) => ({ key: 'n' + i, text })); }
    get targetHead() { return (this.targetName || 'Target') + ' now'; }

    // ---------- the grid ----------

    get sections() {
        const profile = this.active;
        const mine = this.sends[profile] || {};
        return SECTIONS.map((s) => ({
            key: s.section,
            label: s.label,
            rows: this.allRows.filter((r) => r.section === s.section).map((r) => this.rowView(profile, s, r, mine[rowId(r.section, r.key)]))
        })).filter((s) => s.rows.length);
    }

    rowView(profile, s, r, sent) {
        const id = rowId(r.section, r.key);
        const known = this.source[valueKey(profile, r.section, r.key)];
        const view = {
            id,
            key: r.key,
            added: r.added,
            sent: !!sent,
            rowCls: 'rr-pa-row' + (sent ? ' rr-pa-on' : ''),
            targetText: describe(r.section, this.target[valueKey(profile, r.section, r.key)]),
            isText: !!s.text,
            textValue: sent && s.text ? sent[s.text] || '' : '',
            textHint: known && s.text && known[s.text] ? known[s.text] : (r.section === 'layoutAssignments' ? r.key.split('.')[0] + '-Layout name' : ''),
            chips: []
        };
        if (!s.text) {
            view.chips = s.values.map((v) => {
                const on = s.choice ? (sent ? sent[s.choice] === v.name : known && known[s.choice] === v.name)
                    : (sent ? sent[v.name] === ON : known && known[v.name] === ON);
                let cls = 'rr-chip rr-pa-chip';
                if (sent) {
                    cls += on ? ' rr-sel' : '';
                } else {
                    cls += on ? ' rr-pa-hint-on' : ' rr-pa-hint';
                }
                return { key: v.name, label: v.label, cls, pressed: sent && on ? 'true' : 'false' };
            });
        }
        return view;
    }

    get gridLabel() { return 'Profile access for ' + this.activeLabel; }
    get sentCount() {
        return Object.values(this.sends).reduce((n, rows) => n + Object.keys(rows).length, 0);
    }

    handleChip(event) {
        if (this.disabled) {
            return;
        }
        const { row, value } = event.currentTarget.dataset;
        const r = this.allRows.find((x) => rowId(x.section, x.key) === row);
        if (!r) {
            return;
        }
        const s = sectionOf(r.section);
        const mine = { ...(this.sends[this.active] || {}) };
        const current = mine[row] || startValues(r.section, this.source[valueKey(this.active, r.section, r.key)]);
        mine[row] = s.choice ? { ...current, [s.choice]: value } : switched(r.section, current, value);
        this.sends = { ...this.sends, [this.active]: mine };
        this.emit();
    }

    handleLayout(event) {
        const row = event.target.dataset.row;
        const value = (event.target.value || '').trim();
        const mine = { ...(this.sends[this.active] || {}) };
        if (value) {
            mine[row] = { layout: value };
        } else {
            delete mine[row];
        }
        this.sends = { ...this.sends, [this.active]: mine };
        this.emit();
    }

    clearRow(event) {
        const mine = { ...(this.sends[this.active] || {}) };
        delete mine[event.currentTarget.dataset.row];
        this.sends = { ...this.sends, [this.active]: mine };
        this.emit();
    }

    removeAdded(event) {
        const id = event.currentTarget.dataset.row;
        this.extraRows = this.extraRows.filter((r) => rowId(r.section, r.key) !== id);
        const next = {};
        Object.keys(this.sends).forEach((p) => {
            next[p] = { ...this.sends[p] };
            delete next[p][id];
        });
        this.sends = next;
        this.emit();
    }

    copySource() {
        const mine = { ...(this.sends[this.active] || {}) };
        this.allRows.forEach((r) => {
            const known = this.source[valueKey(this.active, r.section, r.key)];
            const start = known ? startValues(r.section, known) : null;
            if (start && Object.keys(start).length) {
                mine[rowId(r.section, r.key)] = start;
            }
        });
        this.sends = { ...this.sends, [this.active]: mine };
        this.emit();
    }

    clearProfile() {
        this.sends = { ...this.sends, [this.active]: {} };
        this.emit();
    }

    get copyLabel() { return 'Copy ' + (this.sourceName || 'developer org') + ' values'; }

    // ---------- add access: picked from the developer org, never typed (build 58.1) ----------

    get sectionOptions() { return SECTIONS.map((s) => ({ label: s.label, value: s.section })); }
    get hasKind() { return !!this.addSection; }
    get pickPlaceholder() {
        if (this.addSection === 'fieldPermissions' && !this.addObject) {
            return 'Search objects, then pick a field';
        }
        return 'Search ' + (sectionOf(this.addSection) || { label: '' }).label.toLowerCase();
    }
    get inObject() { return this.addSection === 'fieldPermissions' && !!this.addObject; }
    get objectCrumb() { return this.addObject + ' fields'; }

    handleAddSection(event) {
        this.addSection = event.detail.value;
        this.addObject = '';
        this.pickSearch = '';
        this.addError = '';
        this.loadPicks();
    }

    handlePickSearch(event) {
        this.pickSearch = event.target.value || '';
    }

    async loadPicks() {
        const cacheKey = this.addSection + '|' + this.addObject;
        if (this.pickCache[cacheKey]) {
            this.picks = this.pickCache[cacheKey];
            return;
        }
        this.picks = [];
        this.picksLoading = true;
        try {
            const found = await listNames({ orgId: this.orgId, section: this.addSection, objectName: this.addObject || null });
            this.pickCache = { ...this.pickCache, [cacheKey]: found };
            this.picks = found;
        } catch (e) {
            this.addError = errorText(e);
        } finally {
            this.picksLoading = false;
        }
    }

    get pickMatches() {
        const term = this.pickSearch.trim().toLowerCase();
        const taken = new Set(this.allRows.map((r) => rowId(r.section, r.key)));
        return (this.picks || [])
            .filter((p) => p.opens || !taken.has(rowId(this.addSection, p.key)))
            .filter((p) => !term || p.key.toLowerCase().includes(term) || p.label.toLowerCase().includes(term))
            .slice(0, PICKS_SHOWN)
            .map((p) => ({ ...p, title: p.label === p.key ? p.key : p.label + ' · ' + p.key, icon: p.opens ? 'utility:chevronright' : 'utility:add' }));
    }
    get hasPickMatches() { return this.pickMatches.length > 0; }
    get pickCount() {
        const n = (this.picks || []).length;
        return n > PICKS_SHOWN ? 'Showing up to ' + PICKS_SHOWN + ' of ' + n + ': search to narrow.' : '';
    }
    get noPicks() { return this.hasKind && !this.picksLoading && !this.hasPickMatches; }

    choosePick(event) {
        const key = event.currentTarget.dataset.key;
        const p = (this.picks || []).find((x) => x.key === key);
        if (!p) {
            return;
        }
        if (p.opens) {
            this.addObject = p.key;
            this.pickSearch = '';
            this.loadPicks();
            return;
        }
        const row = { section: this.addSection, key: p.key };
        this.extraRows = [...this.extraRows, row];
        this.emit();
        this.readFor(this.picked, [row]);
    }

    backToObjects() {
        this.addObject = '';
        this.pickSearch = '';
        this.loadPicks();
    }

    // ---------- out ----------

    /** What the raise sends: each profile with its rows set here. */
    get profileAccess() {
        return this.picked.map((p) => ({
            profile: p.profile,
            label: p.label,
            rows: Object.entries(this.sends[p.profile] || {}).map(([id, values]) => ({
                section: id.split('|')[0], key: id.split('|').slice(1).join('|'), values
            }))
        })).filter((p) => p.rows.length);
    }

    emit() {
        const state = { picked: this.picked, active: this.active, extraRows: this.extraRows, sends: this.sends, source: this.source,
            target: this.target, notes: this.notes, usage: this.usage, targetName: this.targetName };
        this._state = state;
        this.dispatchEvent(new CustomEvent('accesschange', { detail: { state, profileAccess: this.profileAccess } }));
    }
}
