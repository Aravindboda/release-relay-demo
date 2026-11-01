import APP_NAME from '@salesforce/label/c.RLY_App_Name';
import { LightningElement } from 'lwc';
import getPromote from '@salesforce/apex/RlyPromoteController.getPromote';
import promote from '@salesforce/apex/RlyPromoteController.promote';
import getSteps from '@salesforce/apex/RlyManualStepController.getSteps';
import getHubStatus from '@salesforce/apex/RlyHubGuard.getHubStatus';

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

/**
 * The Promote tab (boards HubPromoteProd and HubHotfixBackPromote, 3): per stage, the releases deployed there and not yet
 * promoted, hotfixes first. Tick what goes to the next stop; a hotfix can go on its own. Promote raises one Promotion
 * release that runs the usual checks and approval into the next stop.
 */
export default class RlyPromote extends LightningElement {
    /** RlyHubGuard.getHubStatus: whether this org is a sandbox copy of the hub (then a banner, and the actions are off). */
    hubStatus;
    get hubCopy() { return !!(this.hubStatus && this.hubStatus.isHubCopy); }
    get hubCopyMessage() { return this.hubCopy ? this.hubStatus.message : ''; }

    /** Reads the hub status once. A failed read shows nothing: the server refuses the actions anyway. */
    readHubStatus() {
        getHubStatus()
            .then((status) => {
                this.hubStatus = status;
            })
            .catch(() => {
                this.hubStatus = undefined;
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
    busyStage;
    promotedId;
    /** releaseId → its manual steps (StepRow, in sequence), read for releases with Ready.manualSteps. */
    stepsByRelease = {};

    connectedCallback() {
        this.readHubStatus();
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

    /** Hotfixes waiting are ticked on their own (they go first); with no hotfix, everything waiting is ticked. */
    defaultPicks() {
        const picks = {};
        this.stages.forEach((s) => {
            const ready = s.ready || [];
            const hot = ready.filter((r) => r.isHotfix);
            picks[s.stageId] = (hot.length ? hot : ready).map((r) => r.id);
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
            ? 'You can see what is waiting. Approvers and admins promote it.' : '';
    }

    get stageViews() {
        return this.stages.map((s) => this.stageView(s));
    }

    stageView(s) {
        const ready = s.ready || [];
        const picked = new Set(this.picks[s.stageId] || []);
        const chosen = ready.filter((r) => picked.has(r.id));
        const onlyHotfixes = chosen.length > 0 && chosen.every((r) => r.isHotfix);
        const tests = [...new Set(chosen.flatMap((r) => r.tests || []))];
        const components = chosen.reduce((n, r) => n + (r.componentCount || 0), 0);
        const deletions = chosen.reduce((n, r) => n + (Number(r.deletionCount) || 0), 0);
        const busy = this.busyStage === s.stageId;
        const locked = !this.canPromote || busy;
        const title = this.titles[s.stageId] !== undefined ? this.titles[s.stageId] : this.suggestTitle(s, chosen, onlyHotfixes);
        const others = ready.length - chosen.length;
        const manual = this.manualFor(chosen, s.nextName);
        return {
            key: 'st-' + s.stageId,
            stageId: s.stageId,
            stageName: s.stageName,
            nextName: s.nextName,
            nextBranch: s.nextBranch,
            nextText: s.nextName + (s.nextBranch ? ' · ' + s.nextBranch : ''),
            routeLabel: s.stageName + ' to ' + s.nextName,
            listLabel: 'Releases deployed to ' + s.stageName,
            subText: 'Releases deployed to ' + s.stageName + ' and not yet in ' + s.nextName,
            empty: ready.length === 0,
            emptyText: 'Nothing deployed to ' + s.stageName + ' is waiting to be promoted.',
            locked,
            allChecked: ready.length > 0 && chosen.length === ready.length,
            rows: ready.map((r) => {
                const on = picked.has(r.id);
                return {
                    id: r.id,
                    name: r.name,
                    title: r.title,
                    isHotfix: r.isHotfix === true,
                    reason: r.isHotfix ? r.hotfixReason : '',
                    stays: !on && chosen.length > 0,
                    checked: on,
                    selLabel: 'Promote ' + r.name,
                    raisedBy: r.raisedBy || '',
                    deployedText: when(r.deployedOn),
                    testsText: (r.tests || []).length ? r.tests.join(', ') : 'None',
                    deletesText: Number(r.deletionCount) ? 'Deletes ' + r.deletionCount : '',
                    rowCls: on ? 'rr-row-on' : (r.isHotfix ? 'rr-row-hot' : '')
                };
            }),
            orderNote: 'Hotfixes are listed first, then the oldest deploy to ' + s.stageName + '. Changes are promoted in that order.',
            bundleTitle: onlyHotfixes ? 'Promote the hotfix alone' : 'Bundle into one ' + s.nextName + ' release',
            countText: plural(chosen.length, 'release', 'releases'),
            componentText: ' · ' + plural(components, 'component', 'components') + (deletions ? ' · ' + plural(deletions, 'deletion', 'deletions') : ''),
            testsLead: tests.length ? 'Tests in ' + s.nextName + ': ' : 'No test classes carried: ',
            testsList: tests.join(', '),
            testsTail: tests.length ? ' (RunSpecifiedTests, 75% each)' : 'deploys run without tests (NoTestRun) unless the target requires them.',
            aloneNote: onlyHotfixes && others > 0
                ? 'Only the hotfix\'s changes go to ' + s.nextName + '. Other work waiting in ' + s.stageName + ' isn\'t included.' : '',
            approvalNote: chosen.some((r) => r.isHotfix)
                ? ' A hotfix can need a 2nd approver into ' + s.nextName + ', and the person who raised it can\'t approve it.' : '',
            hasManual: manual.count > 0,
            manualTitle: 'Manual steps in ' + s.nextName + ', in this order · ' + manual.count,
            manualSteps: manual.list,
            manualNote: 'The promotion carries them in deploy order. ' + s.nextName + '\'s deploy waits for its before deploy steps.',
            title,
            branchText: 'promote/rel-…',
            error: this.errors[s.stageId],
            barText: plural(chosen.length, 'release', 'releases') + ' selected · ' + plural(tests.length, 'test class', 'test classes'),
            buttonLabel: this.buttonLabel(s, chosen, onlyHotfixes, busy),
            cantPromote: locked || this.hubCopy || chosen.length === 0 || !(title || '').trim()
        };
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
