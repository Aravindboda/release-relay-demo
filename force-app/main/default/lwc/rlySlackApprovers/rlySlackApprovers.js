import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import loadWindow from '@salesforce/apex/RlySlackApprovers.load';
import checkScopes from '@salesforce/apex/RlySlackApprovers.checkScopes';
import searchUsers from '@salesforce/apex/RlySlackApprovers.searchUsers';
import addApprovers from '@salesforce/apex/RlySlackApprovers.addApprovers';
import matchPass from '@salesforce/apex/RlySlackApprovers.matchPass';
import finishMatch from '@salesforce/apex/RlySlackApprovers.finishMatch';
import setMember from '@salesforce/apex/RlySlackApprovers.setMember';
import fixRow from '@salesforce/apex/RlySlackApprovers.fixRow';
import unlinkApprover from '@salesforce/apex/RlySlackApprovers.unlink';
import removeApprover from '@salesforce/apex/RlySlackApprovers.removeApprover';
import { searchTerm, matchesSearch, highlightParts } from 'c/rlyListSearch';

/** How approvers are matched, as the window says it. */
const MATCH_LABELS = { SSO: 'SSO Federation ID', Email: 'Email', Manual: 'Manual only' };
/** The filter chips (Needs attention shortens to Attention on a narrow screen). */
const CHIPS = [
    { key: 'all', label: 'All', short: 'All' },
    { key: 'notLinked', label: 'Not linked', short: 'Not linked' },
    { key: 'linked', label: 'Linked', short: 'Linked' },
    { key: 'attention', label: 'Needs attention', short: 'Attention' }
];
/** The inline fix each reason offers. */
const FIXES = {
    notFound: { label: 'Set ID', action: 'set' },
    fedEmpty: { label: 'Set ID', action: 'set' },
    fedNotEmail: { label: 'Set ID', action: 'set' },
    notLinked: { label: 'Set ID', action: 'set' },
    used: { label: 'Move link here', action: 'move' },
    pick: { label: 'Pick this one', action: 'pick' },
    changed: { label: 'Use SSO result', action: 'use' }
};
const MEMBER_ID = /^[UW][A-Z0-9]{2,19}$/;
/** Searching people waits this long after typing stops. */
const SEARCH_WAIT_MS = 300;
/** New rows stay highlighted this long. */
const FLASH_MS = 4000;

function errorText(e) {
    if (e && e.body && e.body.message) {
        return e.body.message;
    }
    return (e && e.message) || 'Something went wrong.';
}

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

/** "Today, 10:12 AM" for today, otherwise "Oct 28, 2026". */
function whenText(value) {
    if (!value) {
        return '';
    }
    const d = new Date(value);
    const now = new Date();
    if (d.toDateString() === now.toDateString()) {
        return 'Today, ' + d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    }
    return d.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
}

function shortName(name) {
    const parts = String(name || '').trim().split(/\s+/);
    return parts.length > 1 ? parts[0].charAt(0) + '. ' + parts[parts.length - 1] : parts[0] || '';
}

/**
 * Slack approvers window (board HubSlackApprovers 3–5, 7): every approver (RLY_Approver or RLY_Admin) and the Slack
 * account they approve from. Chips, search, fixed columns with a pinned header, row actions, Add approvers (assigns
 * RLY_Approver, then matches the new people), and Match now (passes of up to 50 Slack lookups, one Apex call each,
 * looped here; a 429 waits for Slack's Retry-After). Fires "close" and "changed" (after anything was saved).
 */
export default class RlySlackApprovers extends LightningElement {
    /** The window's data (RlySlackApprovers.load). */
    win;
    loading = true;
    error;
    chip = 'all';
    term = '';
    /** The approver whose Slack ID is being typed (Set ID by hand). */
    editId;
    editValue = '';
    editError;
    busyId;
    /** The message bar over the list: { text, detail, tone }. */
    banner;
    /** Rows added just now (highlighted for a few seconds). */
    flashIds = [];
    /** The live scope check (RlySlackApprovers.checkScopes). */
    scopes;
    // Add approvers picker
    adding = false;
    pickTerm = '';
    candidates = [];
    picked = {};
    searching = false;
    addBusy = false;
    searchTimer;
    searchSeq = 0;
    // Match now
    matching = false;
    stopAfterPass = false;
    run;
    waitTimer;
    flashTimer;
    changed = false;

    connectedCallback() {
        this.refresh().then(() => {
            if (this.isAdmin) {
                this.runScopeCheck();
            }
        });
    }

    disconnectedCallback() {
        // Leaving stops after the pass that is running; what is saved stays saved.
        this.stopAfterPass = true;
        clearTimeout(this.waitTimer);
        clearTimeout(this.searchTimer);
        clearTimeout(this.flashTimer);
    }

    refresh() {
        this.loading = true;
        return loadWindow()
            .then((w) => {
                this.win = w;
                this.error = undefined;
            })
            .catch((e) => {
                this.error = errorText(e);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    runScopeCheck() {
        return checkScopes()
            .then((s) => {
                this.scopes = s;
            })
            .catch(() => {
                this.scopes = undefined;
            });
    }

    // ---------- header ----------

    get isAdmin() { return !!(this.win && this.win.isAdmin); }
    get matchBy() { return (this.win && this.win.matchBy) || 'SSO'; }
    get isManual() { return this.matchBy === 'Manual'; }
    get matchLabel() { return MATCH_LABELS[this.matchBy] || this.matchBy; }
    get showMatchNow() { return this.isAdmin && !this.isManual; }
    get matchLabelLead() { return this.isManual ? 'Matching: ' : 'Matching by '; }
    get lastMatchText() {
        if (!this.win || !this.win.lastMatch || this.isManual) {
            return '';
        }
        return ' · last matched ' + whenText(this.win.lastMatch).replace('Today, ', 'today ') + (this.win.lastMatchBy ? ' by ' + this.win.lastMatchBy : '');
    }
    /** Why Slack can't be asked: the live scope check when it ran, else what the hub saved. */
    get slackProblem() {
        if (this.win && this.win.slackProblem && this.win.slackProblem.startsWith('Connect')) {
            return this.win.slackProblem;
        }
        if (this.scopes && !this.scopes.problem && this.scopes.items && this.scopes.items.length) {
            return this.scopes.missingText || null;
        }
        return this.win ? this.win.slackProblem : null;
    }
    get problemText() {
        const p = this.slackProblem;
        if (!p) {
            return '';
        }
        return p.startsWith('Connect') ? 'Slack off or no bot token: ' + p + ' Match now is off; the list, Add and Remove still work.'
            : p + ' Match now is off until then. Adding approvers still works; they\'re matched later.';
    }
    get matchDisabled() { return this.matching || !!this.slackProblem || this.total === 0; }
    get matchButtonLabel() { return this.matching ? 'Matching…' : 'Match now'; }

    // ---------- rows ----------

    get rows() { return (this.win && this.win.rows) || []; }
    get total() { return this.rows.length; }
    get hasRows() { return this.total > 0; }
    get noRows() { return !this.loading && !this.error && this.total === 0; }

    counts() {
        const c = { all: this.total, notLinked: 0, linked: 0, attention: 0 };
        this.rows.forEach((r) => {
            c[r.memberId ? 'linked' : 'notLinked'] += 1;
            c.attention += r.reasonCode ? 1 : 0;
        });
        return c;
    }

    get chips() {
        const c = this.counts();
        return CHIPS.map((x) => ({
            ...x,
            count: c[x.key],
            pressed: this.chip === x.key ? 'true' : 'false',
            cls: 'rr-chip' + (this.chip === x.key ? ' rr-chip-on' : '') + (x.key === 'attention' && c.attention ? ' rr-chip-warn' : '')
        }));
    }

    inChip(r) {
        switch (this.chip) {
            case 'linked': return !!r.memberId;
            case 'notLinked': return !r.memberId;
            case 'attention': return !!r.reasonCode;
            default: return true;
        }
    }

    get shownRows() {
        const t = this.term;
        return this.rows
            .filter((r) => this.inChip(r) && matchesSearch([r.name, r.username, r.federationId, r.memberId], t))
            .map((r) => this.view(r));
    }

    view(r) {
        const t = this.term;
        const fix = r.reasonCode ? FIXES[r.reasonCode] : null;
        const editing = this.editId === r.userId;
        const linked = !!r.memberId;
        const by = linked ? (r.linkedBy || '') : '';
        let onText = linked ? whenText(r.linkedOn) : '–';
        if (linked && r.linkedBy === 'Admin' && r.linkedByName) {
            onText = (r.linkedOn ? new Date(r.linkedOn).toLocaleDateString([], { month: 'short', day: 'numeric' }) : '') + ' · ' + shortName(r.linkedByName);
        }
        const flash = this.flashIds.includes(r.userId);
        return {
            ...r,
            key: r.userId,
            nameParts: highlightParts(r.name, t),
            userParts: highlightParts(r.username, t),
            fedParts: highlightParts(r.federationId || '', t),
            memberParts: highlightParts(r.memberId || '', t),
            fedEmpty: this.isAdmin && !r.federationId,
            showFed: this.isAdmin && !!r.federationId,
            linked,
            showReason: !!r.reasonCode && !linked,
            showChanged: r.reasonCode === 'changed',
            reasonLine: r.reasonText + (r.reasonDetail ? ' · ' + r.reasonDetail : ''),
            byText: by || '–',
            byCls: by ? 'rr-by rr-by-' + by.toLowerCase() : 'rr-weak',
            hasBy: !!by,
            onText,
            rowCls: 'rr-arow' + (r.reasonCode ? ' rr-arow-warn' : '') + (flash ? ' rr-arow-new' : '') + (editing ? ' rr-arow-edit' : ''),
            canAct: this.isAdmin && !editing,
            fixLabel: fix ? fix.label : '',
            fixAction: fix ? fix.action : '',
            hasFix: this.isAdmin && !!fix && !editing,
            showKeep: this.isAdmin && r.reasonCode === 'changed' && !editing,
            busy: this.busyId === r.userId,
            editing,
            menuLabel: 'Actions for ' + r.name,
            unlinkLabel: linked ? 'Unlink' : 'Unlink (not linked)',
            unlinkOff: !linked,
            removeOff: !!r.removeNote,
            removeLabel: r.removeNote ? 'Remove approver (' + r.removeNote + ')' : 'Remove approver',
            narrowLine: [linked ? r.memberId : r.reasonText, linked ? onText : '', r.access].filter((x) => !!x).join(' · '),
            narrowFed: (this.isAdmin ? (r.federationId || 'no Federation ID') : r.username)
        };
    }

    get shownCount() { return this.shownRows.length; }
    get noMatch() { return this.hasRows && this.shownCount === 0; }
    get noMatchText() { return this.term ? 'No approvers match ‘' + this.term + '’.' : 'No approvers in this view.'; }
    get countLine() { return this.shownCount + ' of ' + this.total + ' · needs attention first'; }
    get showFedColumn() { return this.isAdmin; }
    get searchHint() { return this.isAdmin ? 'Search name, username, Federation ID or Slack ID' : 'Search name, username or Slack ID'; }
    get narrowFooter() { return plural(this.total, 'approver', 'approvers') + (this.total > 8 ? ' · scroll for more' : ''); }

    handleSearch(event) {
        this.term = searchTerm(event.detail && event.detail.value);
    }

    clearSearch() {
        const box = this.template.querySelector('c-rly-search-box');
        if (box) {
            box.clear();
        }
        this.term = '';
        this.chip = 'all';
    }

    handleChip(event) {
        this.chip = event.currentTarget.dataset.key;
    }

    // ---------- row actions ----------

    handleFix(event) {
        const id = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;
        const row = this.rows.find((r) => r.userId === id);
        if (!row) {
            return;
        }
        if (action === 'set') {
            this.openEditor(row);
        } else if (action === 'move') {
            const holder = (row.reasonDetail || '').replace(/^by /, '') || 'the other user';
            this.confirmThen('Move the Slack link?', 'Slack gives ' + row.name + '\'s Federation ID a Slack ID that is linked to '
                + holder + '. Move it from ' + holder + ' to ' + row.name + '? ' + holder + ' is unlinked.', 'warning')
                .then((ok) => (ok ? this.save(id, fixRow({ userId: id, fix: 'move' })) : null));
        } else {
            this.save(id, fixRow({ userId: id, fix: action }));
        }
    }

    handleKeep(event) {
        const id = event.currentTarget.dataset.id;
        this.save(id, fixRow({ userId: id, fix: 'keep' }));
    }

    handleMenu(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.userId === id);
        const what = event.detail.value;
        if (!row) {
            return;
        }
        if (what === 'set') {
            this.openEditor(row);
        } else if (what === 'unlink') {
            this.confirmThen('Unlink ' + row.name + '?', 'Clears ' + row.memberId + '. ' + row.name
                + ' stays an approver; Approve in Slack asks them to link again.', 'warning')
                .then((ok) => (ok ? this.save(id, unlinkApprover({ userId: id })) : null));
        } else if (what === 'remove') {
            this.confirmThen('Remove ' + row.name + ' as an approver?', 'Unassigns RLY_Approver. Their Slack link is kept but does nothing.', 'error')
                .then((ok) => (ok ? this.save(id, removeApprover({ userId: id })) : null));
        }
    }

    confirmThen(label, message, theme) {
        return LightningConfirm.open({ label, message, theme }).catch(() => false);
    }

    /** Runs a row change; the window comes back with what was done. */
    save(id, call) {
        this.busyId = id;
        return call
            .then((w) => {
                this.win = w;
                this.changed = true;
                this.banner = { text: w.message || 'Saved.', tone: 'ok' };
                this.fireChanged();
                return true;
            })
            .catch((e) => {
                this.banner = { text: errorText(e), tone: 'bad' };
                return false;
            })
            .finally(() => {
                this.busyId = undefined;
            });
    }

    // ---------- Set ID by hand ----------

    openEditor(row) {
        this.editId = row.userId;
        this.editValue = row.memberId || '';
        this.editError = undefined;
    }

    get editRow() { return this.rows.find((r) => r.userId === this.editId); }
    get editLabel() { return this.editRow ? 'Slack member ID for ' + this.editRow.name : 'Slack member ID'; }
    get editSaving() { return !!this.editId && this.busyId === this.editId; }
    get editSaveLabel() { return this.editSaving ? 'Checking…' : 'Save'; }

    handleEditInput(event) {
        this.editValue = event.target.value;
        this.editError = undefined;
    }

    handleEditKey(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.cancelEdit();
        } else if (event.key === 'Enter') {
            this.saveEdit();
        }
    }

    cancelEdit() {
        this.editId = undefined;
        this.editError = undefined;
    }

    saveEdit() {
        const value = (this.editValue || '').trim().toUpperCase();
        if (!MEMBER_ID.test(value)) {
            this.editError = 'Member IDs start with U or W.';
            return;
        }
        const id = this.editId;
        this.busyId = id;
        setMember({ userId: id, memberId: value })
            .then((w) => {
                this.win = w;
                this.editId = undefined;
                this.banner = { text: w.message, tone: 'ok' };
                this.fireChanged();
            })
            .catch((e) => {
                this.editError = errorText(e);
            })
            .finally(() => {
                this.busyId = undefined;
            });
    }

    // ---------- Match now ----------

    get showRun() { return !!this.run; }
    get runDone() { return !!(this.run && this.run.done); }
    get runRunning() { return !!(this.run && !this.run.done); }
    get runTitle() { return this.runDone ? (this.run.problem ? 'Match stopped' : 'Match done') : 'Matching…'; }
    get runSummary() {
        const r = this.run;
        if (!r) {
            return '';
        }
        return r.same + ' linked · ' + r.changed + ' changed · ' + plural(r.misses.length, 'needs attention', 'need attention');
    }
    get runProgress() {
        const r = this.run;
        if (!r) {
            return '';
        }
        return 'Pass ' + (r.passes.length + 1) + ' · ' + r.looked + ' of ' + r.total + ' looked up';
    }
    get runWait() { return this.run ? this.run.waitText : ''; }
    get runProblem() { return this.run ? this.run.problem : ''; }
    get runPasses() { return this.run ? this.run.passes : []; }
    get runMisses() { return this.run ? this.run.misses.slice(0, 20) : []; }
    get runHasMisses() { return !!(this.run && this.run.misses.length); }
    get runShowLabel() { return 'Show the ' + (this.run ? this.run.misses.length : 0); }
    get runFoot() {
        const r = this.run;
        if (!r || !r.done) {
            return 'Leaving or closing stops after this pass; what\'s saved stays saved.';
        }
        const secs = Math.max(1, Math.round((Date.now() - r.started) / 1000));
        return plural(r.total, 'approver', 'approvers') + ' · ' + plural(r.passes.length, 'pass', 'passes') + ' · ' + secs
            + ' s. Links set by an admin or by the approver (Self) are never overwritten; a different Slack ID for them shows as “changed in Slack” in Needs attention instead.';
    }

    handleMatchNow() {
        this.banner = undefined;
        this.startMatch(null);
    }

    /** Runs passes until done; ids: the people just added, or null for everyone. Resolves with the run. */
    startMatch(ids) {
        this.matching = true;
        this.stopAfterPass = false;
        this.run = { passes: [], same: 0, changed: 0, looked: 0, total: 0, misses: [], waitText: '', problem: '', done: false, started: Date.now() };
        return this.nextPass(ids, 0);
    }

    nextPass(ids, offset) {
        if (this.stopAfterPass) {
            return this.endMatch();
        }
        return matchPass({ userIds: ids, offset })
            .then((p) => {
                const r = this.run;
                r.total = p.total;
                r.looked += p.looked;
                r.same += p.same;
                r.changed += p.changed;
                r.misses = [...r.misses, ...(p.misses || []).map((m) => ({ key: m.userId + '-' + r.passes.length, name: m.name, reason: m.reason }))];
                r.passes = [...r.passes, {
                    key: 'p' + r.passes.length,
                    title: 'Pass ' + (r.passes.length + 1),
                    text: p.looked + ' looked up · ' + p.same + ' same · ' + p.changed + ' new · ' + p.notLinked + ' not linked',
                    state: p.retryAfter ? 'Waiting' : 'Done'
                }];
                r.waitText = '';
                this.run = { ...r };
                if (p.problem) {
                    this.run = { ...this.run, problem: p.problem };
                    return this.endMatch();
                }
                if (p.retryAfter) {
                    this.run = { ...this.run, waitText: 'Slack is busy, carrying on in ' + p.retryAfter + ' s' };
                    return this.pause(p.retryAfter).then(() => this.nextPass(ids, p.nextOffset));
                }
                if (p.nextOffset !== null && p.nextOffset !== undefined) {
                    return this.nextPass(ids, p.nextOffset);
                }
                return this.endMatch();
            })
            .catch((e) => {
                this.run = { ...this.run, problem: errorText(e) };
                return this.endMatch();
            });
    }

    pause(seconds) {
        return new Promise((resolve) => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.waitTimer = setTimeout(resolve, seconds * 1000);
        });
    }

    endMatch() {
        return finishMatch()
            .then((w) => {
                this.win = w;
            })
            .catch(() => this.refresh())
            .then(() => {
                this.run = { ...this.run, done: true, waitText: '' };
                this.matching = false;
                this.fireChanged();
                return this.run;
            });
    }

    closeRun() {
        if (this.matching) {
            this.stopAfterPass = true;
            return;
        }
        this.run = undefined;
    }

    showMisses() {
        this.run = undefined;
        this.chip = 'attention';
    }

    // ---------- Add approvers ----------

    openAdd() {
        this.adding = true;
        this.pickTerm = '';
        this.candidates = [];
        this.picked = {};
    }

    closeAdd() {
        if (!this.addBusy) {
            this.adding = false;
        }
    }

    get pickedIds() { return Object.keys(this.picked); }
    get pickedCount() { return this.pickedIds.length; }
    get hasPicked() { return this.pickedCount > 0; }
    get pickedText() { return this.pickedIds.map((id) => this.picked[id]).join(', '); }
    get pickedHeader() { return this.pickedCount + ' selected'; }
    get addLabel() { return this.addBusy ? 'Adding…' : 'Add ' + this.pickedCount; }
    get addDisabled() { return this.addBusy || this.pickedCount === 0; }
    get hasCandidates() { return this.candidates.length > 0; }
    get pickNoneText() {
        if (this.pickTerm.trim().length < 2) {
            return 'Type at least 2 letters.';
        }
        return this.searching ? 'Searching…' : 'No active users match.';
    }
    get candidateRows() {
        return this.candidates.map((c) => {
            const on = !!this.picked[c.userId];
            const off = !!c.blocked;
            return {
                ...c,
                on,
                off,
                pressed: on ? 'true' : 'false',
                cls: 'rr-crow' + (on ? ' rr-crow-on' : '') + (off ? ' rr-crow-off' : ''),
                fedText: c.federationId || 'empty',
                fedCls: c.federationId ? '' : 'rr-weak rr-em',
                pickLabel: (on ? 'Selected: ' : 'Select ') + c.name,
                title: c.blocked || ''
            };
        });
    }

    handlePickSearch(event) {
        this.pickTerm = event.target.value || '';
        clearTimeout(this.searchTimer);
        const term = this.pickTerm.trim();
        if (term.length < 2) {
            this.candidates = [];
            return;
        }
        const seq = ++this.searchSeq;
        this.searching = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => {
            searchUsers({ term })
                .then((list) => {
                    if (seq === this.searchSeq) {
                        this.candidates = list || [];
                    }
                })
                .catch((e) => {
                    this.banner = { text: errorText(e), tone: 'bad' };
                })
                .finally(() => {
                    if (seq === this.searchSeq) {
                        this.searching = false;
                    }
                });
        }, SEARCH_WAIT_MS);
    }

    togglePick(event) {
        const id = event.currentTarget.dataset.id;
        const c = this.candidates.find((x) => x.userId === id);
        if (!c || c.blocked) {
            return;
        }
        const next = { ...this.picked };
        if (next[id]) {
            delete next[id];
        } else {
            next[id] = c.name;
        }
        this.picked = next;
    }

    clearPicked() {
        this.picked = {};
    }

    handleAdd() {
        const ids = this.pickedIds;
        this.addBusy = true;
        addApprovers({ userIds: ids })
            .then((res) => {
                const added = res.added || [];
                this.adding = false;
                this.flash(added);
                this.fireChanged();
                if (!added.length) {
                    this.banner = { text: 'Nobody was added.', detail: (res.problems || []).join(' '), tone: 'bad' };
                    return this.refresh();
                }
                if (res.manual || this.slackProblem) {
                    this.banner = { text: plural(added.length, 'added', 'added') + (res.manual ? ' · matching is manual only' : ' · not matched yet: ' + this.slackProblem),
                        detail: res.manual ? 'Set their IDs by hand, or they link themselves the first time they press Approve in Slack.' : 'Match now later picks them up.', tone: 'ok' };
                    return this.refresh();
                }
                return this.startMatch(added).then((run) => {
                    this.run = undefined;
                    this.banner = this.addBanner(added.length, run);
                });
            })
            .catch((e) => {
                this.banner = { text: errorText(e), tone: 'bad' };
            })
            .finally(() => {
                this.addBusy = false;
            });
    }

    addBanner(count, run) {
        const head = count + ' added';
        if (run.problem) {
            return { text: head + ' · not matched yet: ' + run.problem, detail: 'Match now later picks them up.', tone: 'ok' };
        }
        const linked = run.changed + run.same;
        const miss = run.misses[0];
        return {
            text: head + ' · ' + linked + ' linked by ' + this.matchLabel.replace(' Federation ID', '') + (run.misses.length ? ' · ' + run.misses.length + ' not linked' : ''),
            detail: miss ? miss.name + ': ' + miss.reason + '. Set the ID by hand, or they can link themselves the first time they press Approve in Slack.' : '',
            tone: 'ok'
        };
    }

    flash(ids) {
        this.flashIds = ids;
        clearTimeout(this.flashTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.flashTimer = setTimeout(() => {
            this.flashIds = [];
        }, FLASH_MS);
    }

    // ---------- window ----------

    get bannerCls() { return this.banner && this.banner.tone === 'bad' ? 'rr-banner rr-banner-bad' : 'rr-banner rr-banner-ok'; }
    get bannerIcon() { return this.banner && this.banner.tone === 'bad' ? 'utility:error' : 'utility:success'; }
    get bannerText() { return this.banner ? this.banner.text : ''; }
    get bannerDetail() { return this.banner ? this.banner.detail || '' : ''; }

    closeBanner() {
        this.banner = undefined;
    }

    fireChanged() {
        this.dispatchEvent(new CustomEvent('changed'));
    }

    handleClose() {
        this.stopAfterPass = true;
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleKey(event) {
        if (event.key !== 'Escape') {
            return;
        }
        event.stopPropagation();
        if (this.adding) {
            this.closeAdd();
        } else if (this.editId) {
            this.cancelEdit();
        } else if (this.run && !this.matching) {
            this.closeRun();
        } else {
            this.handleClose();
        }
    }

    /** Puts the focus in the window when it opens. */
    @api
    focus() {
        const close = this.template.querySelector('.rr-x');
        if (close) {
            close.focus();
        }
    }
}
