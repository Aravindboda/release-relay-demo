import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import getPromote from '@salesforce/apex/RlyPromoteController.getPromote';
import promote from '@salesforce/apex/RlyPromoteController.promote';
import getSteps from '@salesforce/apex/RlyManualStepController.getSteps';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';
import { highlightParts, matchesSearch, searchTerm } from 'c/rlyListSearch';

/** Modes of RlyHubGuard.getHubStatus in which the tab shows only the org gate. */
const GATED_MODES = ['sandbox', 'copy', 'setup'];

/** A list shows its search box from this many rows (or while a search is typed). */
const SEARCH_FROM = 7;

const TIMING_LABEL = { Before_Deploy: 'Before deploy', After_Deploy: 'After deploy' };

function errorText(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}

function when(value) {
    return value ? new Date(value).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
}

function plural(n, one, many) {
    return n + ' ' + (n === 1 ? one : many);
}

function deployedAt(r) {
    return r.deployedOn ? new Date(r.deployedOn).getTime() : null;
}

function isLater(a, b) {
    const x = deployedAt(a);
    const y = deployedAt(b);
    return x !== null && y !== null && x > y;
}

function shortName(key) {
    return String(key).split(':').slice(1).join(':');
}

/** The release going that touches the component and was deployed to the stage last. */
function latestTouching(key, going) {
    let latest = null;
    going.forEach((r) => {
        if ((r.components || []).includes(key) && (!latest || isLater(r, latest))) {
            latest = r;
        }
    });
    return latest;
}

/** One unpicked release against what goes: carried (with the release and components), blocking, or neither. */
function judge(candidate, going) {
    const shared = [];
    let withRelease = null;
    for (const key of candidate.components || []) {
        const latest = latestTouching(key, going);
        if (latest && isLater(candidate, latest)) {
            return { block: { id: candidate.id, name: candidate.name, component: shortName(key), after: latest.name } };
        }
        if (latest) {
            shared.push(shortName(key));
            withRelease = withRelease || latest;
        }
    }
    return shared.length ? { carry: { withName: withRelease.name, components: [...new Set(shared)] } } : {};
}

/**
 * Mirrors RlyPromoteOverlap: the next stop gets each file as it is in the stage, so an unpicked release that changed
 * the same component (Type:Name, deletions included) goes too when it was deployed to the stage earlier, and blocks the
 * promotion when it was deployed later than every picked release touching that component. Carried releases count as
 * picked for the next round.
 */
function overlapOf(ready, pickedIds) {
    const going = ready.filter((r) => pickedIds.has(r.id));
    const carried = new Map();
    let blocked = null;
    let added = 1;
    while (added > 0 && !blocked) {
        added = 0;
        const goingIds = new Set(going.map((r) => r.id));
        for (const candidate of ready) {
            if (goingIds.has(candidate.id)) {
                continue;
            }
            const v = judge(candidate, going);
            if (v.block) {
                blocked = v.block;
                break;
            }
            if (v.carry) {
                going.push(candidate);
                carried.set(candidate.id, v.carry);
                added += 1;
            }
        }
    }
    return { carried, blocked };
}

/**
 * The Promote tab (boards HubPromoteProd and HubHotfixBackPromote, 3): per stage, the releases deployed there and not yet
 * promoted, hotfixes first. Tick what goes to the next stop; a hotfix can go on its own. Promote raises one Promotion
 * release that runs the usual checks and approval into the next stop.
 */
export default class RlyPromote extends LightningElement {
    /**
     * RlyHubGuard.getHubStatus: the org's mode (hub, setup, sandbox, copy). In a sandbox, a sandbox copy of the hub or a
     * production org not set up yet this tab shows only rlyOrgGate, and nothing else is loaded.
     */
    hubStatus;
    /** The status has been read, or failed to read (then the tab works as on the hub: the server refuses actions anyway). */
    statusRead = false;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }
    get gated() { return !!this.hubStatus && GATED_MODES.includes(this.hubStatus.mode); }
    get showPage() { return this.statusRead && !this.gated; }

    /** Reads the hub status once, then loads the page only on the hub. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
            })
            .finally(() => {
                this.statusRead = true;
                if (!this.gated) {
                    this.loadPage();
                }
            });
    }

    board;
    loading = false;
    error;
    /** stageId → ids ticked. */
    picks = {};
    /** stageId → title typed by the user (a suggestion is used until then). */
    titles = {};
    /** stageId → error from promote. */
    errors = {};
    /** The search text per stage, normalised (filters that stage's waiting releases on the page). */
    searches = {};
    busyStage;
    promotedId;
    /** releaseId → its manual steps (StepRow, in sequence), read for releases with Ready.manualSteps. */
    stepsByRelease = {};
    /** The stage whose "How promoting works" panel is open (one at a time), or undefined. */
    openRulesFor;
    /** After the next render: focus the open panel's heading (opened) or this stage's link (closed). */
    focusRulesFor;
    focusLinkFor;
    /** The tooltip on screen: { title, text, top, left }, or undefined. */
    tip;

    connectedCallback() {
        this.readHubStatus();
    }

    /** The promote board (on the hub only). */
    loadPage() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.board = await getPromote();
            this.picks = this.defaultPicks();
            this.titles = {};
            this.errors = {};
        } catch (e) {
            this.error = errorText(e);
        } finally {
            this.loading = false;
        }
        this.loadSteps();
    }

    /** The manual steps of the releases waiting (only those that have some), to list them in the bundle panel. */
    async loadSteps() {
        const ids = this.stages.flatMap((s) => (s.ready || []).filter((r) => Number(r.manualSteps) > 0).map((r) => r.id));
        const found = {};
        await Promise.all(ids.map(async (id) => {
            try {
                const board = await getSteps({ releaseId: id });
                found[id] = [...((board && board.steps) || [])].sort((a, b) => (Number(a.sequence) || 0) - (Number(b.sequence) || 0));
            } catch {
                found[id] = null;
            }
        }));
        this.stepsByRelease = found;
    }

    /**
     * The manual steps the promotion carries into the next stop, in deploy order (the releases in the order they are
     * promoted, then each step's sequence). Steps scoped to other orgs are left out.
     */
    manualFor(chosen, nextName) {
        let count = 0;
        const list = [];
        chosen.forEach((r) => {
            const steps = this.stepsByRelease[r.id];
            if (!Array.isArray(steps)) {
                count += Number(r.manualSteps) || 0;
                return;
            }
            steps.filter((st) => {
                const names = (st.orgScope || '').split(',').map((x) => x.trim()).filter((x) => x);
                return names.length === 0 || names.includes(nextName);
            }).forEach((st) => {
                list.push({
                    key: r.id + '-' + st.id,
                    title: st.title,
                    timingLabel: TIMING_LABEL[st.timing] || st.timing || '',
                    timingCls: 'rr-pill ' + (st.timing === 'Before_Deploy' ? 'rr-pill-wait' : 'rr-pill-info'),
                    fromRelease: st.fromRelease || r.name
                });
            });
        });
        count += list.length;
        return { count, list: list.map((x, i) => ({ ...x, no: i + 1 })) };
    }

    reload() {
        this.load();
    }

    /** Nothing is ticked when the tab opens: the user picks what goes. */
    defaultPicks() {
        const picks = {};
        this.stages.forEach((s) => {
            picks[s.stageId] = [];
        });
        return picks;
    }

    get kicker() { return APP_NAME + ' hub · Promote'; }
    get stages() { return (this.board && this.board.stages) || []; }
    get canPromote() { return !!(this.board && this.board.canPromote); }
    get isPicking() { return !this.promotedId; }
    get noStages() { return !!this.board && this.stages.length === 0; }
    get cantPromoteNote() {
        return this.board && !this.canPromote && this.stages.length
            ? 'Only approvers and admins can promote. You can see what\'s waiting.' : '';
    }

    /** The route for the panel's small picture: developer orgs, then each stage in order, then the last next stop. */
    get routeStops() {
        const stages = this.stages;
        if (!stages.length) {
            return [];
        }
        return [{ name: 'Developer org', dev: true }]
            .concat(stages.map((s) => ({ name: s.stageName, dev: false })))
            .concat([{ name: stages[stages.length - 1].nextName, dev: false }]);
    }

    get stageViews() {
        return this.stages.map((s) => this.stageView(s));
    }

    stageView(s) {
        const ready = s.ready || [];
        const picked = new Set(this.picks[s.stageId] || []);
        const picks = ready.filter((r) => picked.has(r.id));
        const overlap = overlapOf(ready, picked);
        // What goes: the picks and the older releases that changed the same components (carried).
        const chosen = ready.filter((r) => picked.has(r.id) || overlap.carried.has(r.id));
        const carriedRows = ready.filter((r) => overlap.carried.has(r.id));
        const onlyHotfixes = picks.length > 0 && chosen.every((r) => r.isHotfix);
        const tests = [...new Set(chosen.flatMap((r) => r.tests || []))];
        const components = chosen.reduce((n, r) => n + (r.componentCount || 0), 0);
        const deletions = chosen.reduce((n, r) => n + (Number(r.deletionCount) || 0), 0);
        const busy = this.busyStage === s.stageId;
        const locked = !this.canPromote || busy;
        const title = this.titles[s.stageId] !== undefined ? this.titles[s.stageId] : this.suggestTitle(s, picks, onlyHotfixes);
        const others = ready.length - chosen.length;
        const blocked = overlap.blocked;
        const manual = this.manualFor(chosen, s.nextName);
        const onlyManual = chosen.length > 0 && chosen.every((r) => r.manualOnly === true);
        const term = this.searches[s.stageId] || '';
        const found = ready.filter((r) => matchesSearch([r.name, r.title, r.raisedBy, r.hotfixReason, ...(r.tests || [])], term));
        const someManualOnly = !onlyManual && chosen.some((r) => r.manualOnly === true);
        return {
            key: 'st-' + s.stageId,
            stageId: s.stageId,
            stageName: s.stageName,
            nextName: s.nextName,
            nextBranch: s.nextBranch,
            nextText: s.nextName + (s.nextBranch ? ' · ' + s.nextBranch : ''),
            routeLabel: s.stageName + ' to ' + s.nextName,
            rulesOpen: this.openRulesFor === s.stageId,
            rulesExpanded: this.openRulesFor === s.stageId ? 'true' : 'false',
            rulesId: 'rr-rules-' + s.stageId,
            gridCls: this.openRulesFor === s.stageId ? 'rr-grid rr-grid-rules' : 'rr-grid',
            listLabel: 'Releases deployed to ' + s.stageName,
            subText: 'Releases deployed to ' + s.stageName + ' and not yet in ' + s.nextName,
            empty: ready.length === 0,
            emptyText: 'Nothing deployed to ' + s.stageName + ' is waiting to be promoted.',
            locked,
            allChecked: ready.length > 0 && picks.length === ready.length,
            showSearch: ready.length >= SEARCH_FROM || !!term,
            searchLabel: 'Search releases in ' + s.stageName,
            shownCount: found.length,
            totalCount: ready.length,
            noMatch: !!term && found.length === 0,
            noMatchText: 'No releases match \u2018' + term + '\u2019.',
            rows: found.map((r) => {
                const on = picked.has(r.id);
                const carry = overlap.carried.get(r.id);
                const blocks = !!blocked && blocked.id === r.id;
                return {
                    id: r.id,
                    name: r.name,
                    title: r.title,
                    nameParts: highlightParts(r.name, term),
                    titleParts: highlightParts(r.title, term),
                    isHotfix: r.isHotfix === true,
                    manualOnly: r.manualOnly === true,
                    reason: r.isHotfix ? r.hotfixReason : '',
                    stays: !on && !carry && !blocks && chosen.length > 0,
                    staysText: 'Stays in ' + s.stageName,
                    staysTip: 'Not ticked, and shares no component with what goes. It waits in ' + s.stageName + ' for a later promotion.',
                    carried: !!carry,
                    goesWith: carry ? 'Goes with ' + carry.withName + ' (' + carry.components.join(', ') + ')' : '',
                    goesTip: carry ? s.nextName + ' gets ' + carry.components.join(', ') + ' as it is in ' + s.stageName
                        + ', which includes this older change, so it goes too.' : '',
                    blockText: blocks ? 'Changed ' + blocked.component + ' after ' + blocked.after : '',
                    blockTip: blocks ? s.stageName + '\'s ' + blocked.component + ' already has this newer change, so ' + blocked.after
                        + ' can\'t go without it. Add it to promote.' : '',
                    rolledBackText: r.rolledBack ? 'Rolled back in ' + s.stageName : '',
                    rolledBackTip: r.rolledBack ? this.rolledBackTip(s, r) : '',
                    checked: on,
                    selLabel: 'Promote ' + r.name,
                    raisedBy: r.raisedBy || '',
                    deployedText: when(r.deployedOn),
                    testsText: (r.tests || []).length ? r.tests.join(', ') : 'None',
                    deletesText: Number(r.deletionCount) ? 'Deletes ' + r.deletionCount : '',
                    rowCls: this.rowCls(r, on, carry, blocks)
                };
            }),
            orderNote: 'Hotfixes are listed first, then the oldest deploy to ' + s.stageName + '. Changes are promoted in that order.',
            bundleTitle: onlyHotfixes ? 'Promote the hotfix alone' : 'Bundle into one ' + s.nextName + ' release',
            countText: plural(picks.length, 'release', 'releases'),
            stageRule: s.nextName + ' gets each file as it is in ' + s.stageName + '.',
            stageRuleTail: this.stageRuleTail(s, picks, carriedRows, blocked),
            hasCarried: carriedRows.length > 0,
            carriedText: carriedRows.map((r) => r.name).join(', '),
            alsoGoesTip: 'Older releases that changed the same component as one you ticked. ' + s.nextName + ' gets ' + s.stageName
                + '\'s version, which already has their changes, so they go too and are marked promoted with it.',
            carriedTail: ' (older ' + (carriedRows.length === 1 ? 'change' : 'changes') + ' to '
                + [...new Set(carriedRows.flatMap((r) => overlap.carried.get(r.id).components))].join(', ') + ' — ' + s.nextName + ' gets '
                + s.stageName + '\'s version, which includes ' + (carriedRows.length === 1 ? 'it' : 'them') + ')',
            blocked: !!blocked,
            blockedText: blocked ? blocked.name + ' changed ' + blocked.component + ' after ' + blocked.after + ': add it, or wait and promote them together.' : '',
            blockerId: blocked ? blocked.id : '',
            addBlockerLabel: blocked ? '+ Add ' + blocked.name : '',
            addTip: blocked ? 'Ticks ' + blocked.name + '. ' + s.stageName + '\'s ' + blocked.component + ' already has its change, so '
                + blocked.after + ' can\'t go without it.' : '',
            componentText: ' · ' + plural(components, 'component', 'components') + (deletions ? ' · ' + plural(deletions, 'deletion', 'deletions') : ''),
            testsLead: tests.length ? 'Tests in ' + s.nextName + ': ' : 'No test classes carried: ',
            testsList: tests.join(', '),
            testsTail: tests.length ? ' (RunSpecifiedTests, 75% each)' : 'deploys run without tests (NoTestRun) unless the target requires them.',
            aloneNote: onlyHotfixes && others > 0
                ? 'Only the hotfix\'s changes go to ' + s.nextName + '. Other work waiting in ' + s.stageName + ' isn\'t included.' : '',
            manualOnlyNote: this.manualOnlyNote(s, onlyManual, someManualOnly),
            approvalNote: chosen.some((r) => r.isHotfix)
                ? ' A hotfix can need a 2nd approver into ' + s.nextName + ', and the person who raised it can\'t approve it.' : '',
            hasManual: manual.count > 0,
            manualTitle: 'Manual steps in ' + s.nextName + ', in this order · ' + manual.count,
            manualSteps: manual.list,
            manualNote: 'The promotion carries them in deploy order. ' + s.nextName + '\'s deploy waits for its before deploy steps.',
            title,
            branchText: 'promote/rel-…',
            error: this.errors[s.stageId],
            barText: plural(picks.length, 'release', 'releases') + ' selected · ' + plural(tests.length, 'test class', 'test classes'),
            buttonLabel: this.buttonLabel(s, picks, onlyHotfixes, busy),
            cantPromote: locked || this.hubCopy || picks.length === 0 || !!blocked || !(title || '').trim()
        };
    }

    /**
     * The "Rolled back in <stage>" pill's tooltip: the stage is back to how it was before the release, but the release keeps
     * its status and Git still has the change, so it can still be picked and promoting it sends the change on.
     */
    rolledBackTip(s, r) {
        const rb = r.rolledBack || {};
        const on = rb.rolledOn ? ' on ' + when(rb.rolledOn) : '';
        const why = rb.why ? ' Why: ' + rb.why + '.' : '';
        return s.stageName + ' was put back the way it was before ' + r.name + on + '.' + why + ' The release keeps its status and Git still has '
            + 'the change, so promoting it sends the change on to ' + s.nextName + '. If it shouldn\'t go, leave it unticked and fix it with a new release.';
    }

    // ---------- How promoting works (side panel per card) ----------

    /** "How promoting works" on a card: opens its panel (closing any other), or closes it. */
    toggleRules(event) {
        const stageId = event.currentTarget.dataset.stage;
        if (this.openRulesFor === stageId) {
            this.openRulesFor = undefined;
            return;
        }
        this.openRulesFor = stageId;
        this.focusRulesFor = stageId;
    }

    /** ✕ or Esc in the panel: closes it and gives the focus back to the card's link. */
    closeRules(event) {
        const stageId = event.currentTarget.dataset.stage;
        this.openRulesFor = undefined;
        this.focusLinkFor = stageId;
    }

    renderedCallback() {
        if (this.focusRulesFor) {
            const panel = [...this.template.querySelectorAll('c-rly-promote-rules')].find((p) => p.dataset.stage === this.focusRulesFor);
            this.focusRulesFor = undefined;
            if (panel) {
                panel.focusHeading();
            }
        }
        if (this.focusLinkFor) {
            const link = [...this.template.querySelectorAll('button.rr-howlink')].find((b) => b.dataset.stage === this.focusLinkFor);
            this.focusLinkFor = undefined;
            if (link) {
                link.focus();
            }
        }
    }

    // ---------- tooltips on row labels, Also goes, + Add and Rolled back ----------

    get tipCls() { return this.tip ? 'rr-tip rr-tip-on' : 'rr-tip'; }
    get tipTitle() { return this.tip ? this.tip.title : ''; }
    get tipText() { return this.tip ? this.tip.text : ''; }
    get tipStyle() { return this.tip ? 'top:' + this.tip.top + 'px;left:' + this.tip.left + 'px' : ''; }

    /** Shows the label's reason under it (hover, focus, or a tap on touch screens). */
    showTip(event) {
        const el = event.currentTarget;
        if (!el || !el.dataset.tip) {
            return;
        }
        const rect = el.getBoundingClientRect();
        const width = window.innerWidth || 1024;
        this.tip = {
            title: el.dataset.tipTitle || '',
            text: el.dataset.tip,
            top: Math.round(rect.bottom + 6),
            left: Math.round(Math.max(8, Math.min(rect.left, width - 336)))
        };
    }

    hideTip() {
        this.tip = undefined;
    }

    /** Esc hides the tooltip. */
    tipKey(event) {
        if (event.key === 'Escape') {
            this.hideTip();
        }
    }

    /** Selected, carried (dashed box), blocking (red), a hotfix, or plain. */
    rowCls(r, on, carry, blocks) {
        if (blocks) {
            return 'rr-row-block';
        }
        if (carry) {
            return 'rr-row-carried';
        }
        if (on) {
            return 'rr-row-on';
        }
        return r.isHotfix ? 'rr-row-hot' : '';
    }

    /** The line after "<next> gets each file as it is in <stage>." */
    stageRuleTail(s, picks, carriedRows, blocked) {
        if (blocked) {
            return ' ' + s.stageName + '\'s ' + blocked.component + ' already has ' + blocked.name + '\'s change, so ' + blocked.after + ' can\'t go without it.';
        }
        if (carriedRows.length) {
            return ' The carried releases are marked promoted with ' + picks.map((r) => r.name).join(', ') + ' and leave this list.';
        }
        return picks.length ? '' : ' Tick the releases to promote. An older release that changed the same file goes too.';
    }

    /** "+ Add REL-00030": ticks the newer release that blocks the promotion. */
    addBlocker(event) {
        const stageId = event.currentTarget.dataset.stage;
        const id = event.currentTarget.dataset.id;
        this.setPicks(stageId, [...(this.picks[stageId] || []), id]);
    }

    /** What a promotion with releases that have only manual steps does: no pipeline run, or only the others' merge commits picked. */
    manualOnlyNote(s, onlyManual, someManualOnly) {
        if (onlyManual) {
            return 'Manual steps only: no pipeline run. The promotion goes straight to approval in ' + s.nextName
                + ' and is deployed when its manual steps there are done.';
        }
        return someManualOnly
            ? 'Releases with only manual steps carry no merge commit: only the others\' merge commits are picked; every release\'s manual steps go along in order.'
            : '';
    }

    /** "Promote hotfix to <next>" when only hotfixes are ticked, otherwise "Promote <n> releases to <next>". */
    buttonLabel(s, chosen, onlyHotfixes, busy) {
        if (busy) {
            return 'Promoting…';
        }
        if (onlyHotfixes) {
            return 'Promote ' + (chosen.length === 1 ? 'hotfix' : chosen.length + ' hotfixes') + ' to ' + s.nextName;
        }
        return 'Promote ' + plural(chosen.length, 'release', 'releases') + ' to ' + s.nextName;
    }

    /** The hotfix's own title when it goes alone, otherwise "Promote <n> releases to <next>". */
    suggestTitle(s, chosen, onlyHotfixes) {
        if (onlyHotfixes && chosen.length === 1) {
            return chosen[0].title || '';
        }
        return chosen.length ? 'Promote ' + plural(chosen.length, 'release', 'releases') + ' to ' + s.nextName : '';
    }

    handleCheck(event) {
        const stageId = event.target.dataset.stage;
        const id = event.target.dataset.id;
        const next = new Set(this.picks[stageId] || []);
        if (event.target.checked) {
            next.add(id);
        } else {
            next.delete(id);
        }
        this.setPicks(stageId, [...next]);
    }

    /** rlySearchBox above a stage's list: filters its waiting releases (picks stay picked). */
    handleStageSearch(event) {
        const stageId = event.currentTarget.dataset.stage;
        this.searches = { ...this.searches, [stageId]: searchTerm(event.detail && event.detail.value) };
    }

    /** "Clear search" in a stage's list. */
    clearStageSearch(event) {
        const stageId = event.currentTarget.dataset.stage;
        const box = [...this.template.querySelectorAll('c-rly-search-box')].find((b) => b.dataset.stage === stageId);
        if (box) {
            box.clear();
        }
        this.searches = { ...this.searches, [stageId]: '' };
    }

    handleCheckAll(event) {
        const stageId = event.target.dataset.stage;
        const s = this.stages.find((x) => x.stageId === stageId);
        this.setPicks(stageId, event.target.checked && s ? (s.ready || []).map((r) => r.id) : []);
    }

    /** Keeps the order the server gives (hotfixes first, oldest deploy first). */
    setPicks(stageId, ids) {
        const s = this.stages.find((x) => x.stageId === stageId);
        const wanted = new Set(ids);
        const ordered = s ? (s.ready || []).filter((r) => wanted.has(r.id)).map((r) => r.id) : ids;
        this.picks = { ...this.picks, [stageId]: ordered };
        this.errors = { ...this.errors, [stageId]: undefined };
    }

    handleTitle(event) {
        this.titles = { ...this.titles, [event.target.dataset.stage]: event.target.value };
    }

    async promote(event) {
        const stageId = event.currentTarget.dataset.stage;
        const view = this.stageViews.find((v) => v.stageId === stageId);
        if (!view || view.cantPromote) {
            return;
        }
        this.busyStage = stageId;
        this.errors = { ...this.errors, [stageId]: undefined };
        try {
            const request = { stageId, releaseIds: this.picks[stageId] || [], title: view.title.trim() };
            this.promotedId = await promote({ requestJson: JSON.stringify(request) });
        } catch (e) {
            this.errors = { ...this.errors, [stageId]: errorText(e) };
        } finally {
            this.busyStage = undefined;
        }
    }

    backToPromote() {
        this.promotedId = undefined;
        this.load();
    }
}
